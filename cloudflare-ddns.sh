#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/cloudflare-ddns.env}"
API_BASE="https://api.cloudflare.com/client/v4"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    log "错误: $*" >&2
    exit 1
}

[[ -r "$CONFIG_FILE" ]] || die "无法读取配置文件: $CONFIG_FILE"

# shellcheck source=/dev/null
source "$CONFIG_FILE"

: "${CF_API_TOKEN:?配置中缺少 CF_API_TOKEN}"
: "${CF_ZONE_ID:?配置中缺少 CF_ZONE_ID}"
: "${CF_RECORD_NAME:?配置中缺少 CF_RECORD_NAME}"

IP_VERSION="${IP_VERSION:-4}"
CF_TTL="${CF_TTL:-1}"
CF_PROXIED="${CF_PROXIED:-false}"
CREATE_MISSING="${CREATE_MISSING:-true}"

for command_name in curl jq; do
    command -v "$command_name" >/dev/null 2>&1 || die "缺少依赖: $command_name"
done

[[ "$IP_VERSION" == "4" || "$IP_VERSION" == "6" || "$IP_VERSION" == "both" ]] || \
    die "IP_VERSION 只能是 4、6 或 both"
[[ "$CF_PROXIED" == "true" || "$CF_PROXIED" == "false" ]] || \
    die "CF_PROXIED 只能是 true 或 false"
[[ "$CREATE_MISSING" == "true" || "$CREATE_MISSING" == "false" ]] || \
    die "CREATE_MISSING 只能是 true 或 false"
[[ "$CF_TTL" =~ ^[0-9]+$ ]] || die "CF_TTL 必须是整数"
(( CF_TTL == 1 || (CF_TTL >= 60 && CF_TTL <= 86400) )) || \
    die "CF_TTL 必须是 1，或 60 到 86400 之间的秒数"

api_request() {
    local method="$1"
    local path="$2"
    local body="${3:-}"
    local response
    local -a args=(
        -sS
        --connect-timeout 10
        --max-time 30
        -X "$method"
        -H "Authorization: Bearer $CF_API_TOKEN"
        -H "Content-Type: application/json"
    )

    [[ -z "$body" ]] || args+=(--data "$body")

    if ! response="$(curl "${args[@]}" "$API_BASE$path")"; then
        die "Cloudflare API 请求失败: $method $path"
    fi

    if ! jq -e '.success == true' >/dev/null 2>&1 <<<"$response"; then
        jq -r '.errors[]? | "Cloudflare API 错误 \(.code): \(.message)"' <<<"$response" >&2
        return 1
    fi

    printf '%s\n' "$response"
}

public_ip() {
    local family="$1"
    local ip

    ip="$(
        curl "-$family" -fsS --connect-timeout 5 --max-time 15 \
            https://cloudflare.com/cdn-cgi/trace |
            sed -n 's/^ip=//p' |
            head -n 1
    )" || return 1

    if [[ "$family" == "4" ]]; then
        local -a octets
        IFS='.' read -r -a octets <<<"$ip"
        [[ "${#octets[@]}" -eq 4 ]] || return 1
        local octet
        for octet in "${octets[@]}"; do
            [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
            (( 10#$octet <= 255 )) || return 1
        done
    else
        [[ "$ip" == *:* && "$ip" =~ ^[0-9A-Fa-f:.]+$ && "${#ip}" -le 45 ]] || return 1
    fi

    printf '%s\n' "$ip"
}

sync_record() {
    local type="$1"
    local ip="$2"
    local encoded_name response count record_id old_ip old_ttl old_proxied body

    encoded_name="$(jq -rn --arg value "$CF_RECORD_NAME" '$value | @uri')"
    response="$(api_request GET "/zones/$CF_ZONE_ID/dns_records?type=$type&name=$encoded_name&per_page=100")"

    count="$(
        jq --arg type "$type" --arg name "$CF_RECORD_NAME" \
            '[.result[] | select(.type == $type and (.name | ascii_downcase) == ($name | ascii_downcase))] | length' \
            <<<"$response"
    )"

    if (( count > 1 )); then
        die "$CF_RECORD_NAME 存在多条 $type 记录，拒绝批量覆盖"
    fi

    body="$(
        jq -cn \
            --arg type "$type" \
            --arg name "$CF_RECORD_NAME" \
            --arg content "$ip" \
            --argjson ttl "$CF_TTL" \
            --argjson proxied "$CF_PROXIED" \
            '{type: $type, name: $name, content: $content, ttl: $ttl, proxied: $proxied}'
    )"

    if (( count == 0 )); then
        [[ "$CREATE_MISSING" == "true" ]] || die "$CF_RECORD_NAME 的 $type 记录不存在"
        api_request POST "/zones/$CF_ZONE_ID/dns_records" "$body" >/dev/null
        log "已创建 $type 记录: $CF_RECORD_NAME -> $ip"
        return
    fi

    record_id="$(jq -r --arg type "$type" --arg name "$CF_RECORD_NAME" \
        '.result[] | select(.type == $type and (.name | ascii_downcase) == ($name | ascii_downcase)) | .id' \
        <<<"$response")"
    old_ip="$(jq -r --arg id "$record_id" '.result[] | select(.id == $id) | .content' <<<"$response")"
    old_ttl="$(jq -r --arg id "$record_id" '.result[] | select(.id == $id) | .ttl' <<<"$response")"
    old_proxied="$(jq -r --arg id "$record_id" '.result[] | select(.id == $id) | .proxied' <<<"$response")"

    if [[ "$old_ip" == "$ip" && "$old_ttl" == "$CF_TTL" && "$old_proxied" == "$CF_PROXIED" ]]; then
        log "$type 记录未变化: $CF_RECORD_NAME -> $ip"
        return
    fi

    api_request PATCH "/zones/$CF_ZONE_ID/dns_records/$record_id" "$body" >/dev/null
    log "已更新 $type 记录: ${CF_RECORD_NAME}，$old_ip -> $ip"
}

run_family() {
    local family="$1"
    local type ip

    if [[ "$family" == "4" ]]; then
        type="A"
    else
        type="AAAA"
    fi

    if ! ip="$(public_ip "$family")"; then
        die "无法获取公网 IPv$family 地址"
    fi

    sync_record "$type" "$ip"
}

case "$IP_VERSION" in
    4) run_family 4 ;;
    6) run_family 6 ;;
    both)
        run_family 4
        run_family 6
        ;;
esac
