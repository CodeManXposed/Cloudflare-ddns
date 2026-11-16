#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="/usr/local/sbin/cloudflare-ddns"
UNINSTALL_PATH="/usr/local/sbin/cloudflare-ddns-uninstall"
CONFIG_PATH="/etc/cloudflare-ddns.env"
SERVICE_PATH="/etc/systemd/system/cloudflare-ddns.service"
TIMER_PATH="/etc/systemd/system/cloudflare-ddns.timer"
CRON_LOG_PATH="/var/log/cloudflare-ddns.log"

keep_config=false

usage() {
    cat <<'EOF'
用法: cloudflare-ddns-uninstall [--keep-config] [--help]

  --keep-config  保留 /etc/cloudflare-ddns.env
  --help         显示帮助
EOF
}

log() {
    printf '%s\n' "$*"
}

die() {
    printf '错误: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --keep-config)
            keep_config=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "未知参数: $1"
            ;;
    esac
    shift
done

(( EUID == 0 )) || die "请使用 root 权限运行，例如 sudo $UNINSTALL_PATH"

if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now cloudflare-ddns.timer >/dev/null 2>&1 || true
    systemctl stop cloudflare-ddns.service >/dev/null 2>&1 || true
fi

if command -v crontab >/dev/null 2>&1; then
    cron_current="$(mktemp)"
    cron_cleaned="$(mktemp)"
    trap 'rm -f "$cron_current" "$cron_cleaned"' EXIT

    if crontab -l >"$cron_current" 2>/dev/null; then
        sed '\|/usr/local/sbin/cloudflare-ddns\([[:space:]>;&|]\|$\)|d' \
            "$cron_current" >"$cron_cleaned"

        if ! cmp -s "$cron_current" "$cron_cleaned"; then
            if [[ -s "$cron_cleaned" ]]; then
                crontab "$cron_cleaned"
            else
                crontab -r
            fi
            log "已删除 Cloudflare DDNS 的 root cron 任务"
        fi
    fi
fi

rm -f "$SCRIPT_PATH" "$SERVICE_PATH" "$TIMER_PATH" "$CRON_LOG_PATH"

if [[ "$keep_config" == "true" ]]; then
    log "已保留配置文件: $CONFIG_PATH"
else
    rm -f "$CONFIG_PATH"
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed cloudflare-ddns.service cloudflare-ddns.timer >/dev/null 2>&1 || true
fi

rm -f "$UNINSTALL_PATH"

log "Cloudflare DDNS 已卸载"
log "Cloudflare DNS 中的 A、AAAA 记录未删除"
