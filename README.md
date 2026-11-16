# Cloudflare VPS DDNS

这个 Bash 脚本定时获取 VPS 的公网 IPv4、IPv6 或两者，并把地址同步到 Cloudflare DNS 的 A、AAAA 记录。

脚本只在 IP、TTL 或代理状态发生变化时调用更新接口。DNS 记录不存在时，可按配置自动创建。

## 功能

- 支持 IPv4、IPv6 和双栈
- 支持根域名和子域名
- 支持 Cloudflare 代理状态和 TTL
- 记录不存在时可自动创建
- 相同配置不重复更新
- 提供 systemd timer 和 cron 两种定时方式
- API Token、Zone ID 与脚本分开保存

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `cloudflare-ddns.sh` | DDNS 主脚本 |
| `cloudflare-ddns.env.example` | 配置文件样例 |
| `cloudflare-ddns.service` | systemd 服务 |
| `cloudflare-ddns.timer` | 每五分钟运行一次的 systemd 定时器 |

## 使用条件

- 域名已经接入 Cloudflare DNS
- VPS 可以访问 `api.cloudflare.com` 和 `cloudflare.com`
- Bash 4 或更高版本
- `curl` 和 `jq`
- 使用 systemd 定时器时，系统需要运行 systemd

## 1. 安装依赖

Debian、Ubuntu：

```bash
sudo apt-get update
sudo apt-get install -y bash curl jq
```

RHEL、Rocky Linux、AlmaLinux、Fedora：

```bash
sudo dnf install -y bash curl jq
```

Alpine Linux：

```bash
sudo apk add bash curl jq
```

Alpine 默认不使用 systemd，可使用本文后面的 cron 配置。

## 2. 创建 Cloudflare API Token

1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)。
2. 打开用户菜单，进入 `My Profile`，选择 `API Tokens`。
3. 选择 `Create Token`。
4. 使用 `Edit zone DNS` 模板，或创建自定义 Token。
5. 权限设置为 `Zone / DNS / Edit`。
6. 在 `Zone Resources` 中选择 `Include / Specific zone / 你的域名`。
7. 创建 Token 并立即复制密钥。密钥只显示一次。

不要使用 Global API Key。不要把真实 Token 写进脚本、README 或 Git 仓库。

Cloudflare 官方说明：[创建 API Token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)。

## 3. 获取 Zone ID

1. 在 Cloudflare Dashboard 中打开需要更新的域名。
2. 进入域名的 `Overview` 页面。
3. 在页面下方的 `API` 区域复制 `Zone ID`。

Zone ID 通常是 32 个字符。不要把 Account ID 当成 Zone ID。Cloudflare 官方说明：[查找 Zone ID](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/)。

## 4. 下载和安装

在 VPS 上执行：

```bash
REPO_RAW="https://raw.githubusercontent.com/CodeManXposed/Cloudflare-ddns/main"

curl -fsSL "$REPO_RAW/cloudflare-ddns.sh" -o /tmp/cloudflare-ddns.sh
curl -fsSL "$REPO_RAW/cloudflare-ddns.env.example" -o /tmp/cloudflare-ddns.env

sudo install -m 0755 /tmp/cloudflare-ddns.sh /usr/local/sbin/cloudflare-ddns
sudo install -m 0600 /tmp/cloudflare-ddns.env /etc/cloudflare-ddns.env
```

确认权限：

```bash
ls -l /usr/local/sbin/cloudflare-ddns /etc/cloudflare-ddns.env
```

`/etc/cloudflare-ddns.env` 应只有 root 可以读写。

## 5. 填写配置

编辑配置文件：

```bash
sudo nano /etc/cloudflare-ddns.env
```

IPv4 子域名配置示例：

```bash
CF_API_TOKEN="替换为你的_API_Token"
CF_ZONE_ID="替换为你的_Zone_ID"
CF_RECORD_NAME="vps.example.com"

IP_VERSION="4"
CF_TTL="1"
CF_PROXIED="false"
CREATE_MISSING="true"
```

`CF_RECORD_NAME` 必须填写完整域名。根域名填写 `example.com`，不要填写 `@`；子域名填写 `vps.example.com`。

### 配置项

| 变量 | 是否必填 | 允许值 | 说明 |
| --- | --- | --- | --- |
| `CF_API_TOKEN` | 是 | Cloudflare API Token | 需要目标 Zone 的 DNS Edit 权限 |
| `CF_ZONE_ID` | 是 | Zone ID | 域名的 Zone ID，不是 Account ID |
| `CF_RECORD_NAME` | 是 | 完整域名 | 例如 `vps.example.com` 或 `example.com` |
| `IP_VERSION` | 否 | `4`、`6`、`both` | 默认 `4` |
| `CF_TTL` | 否 | `1` 或 `60` 到 `86400` | 默认 `1`，表示自动 TTL |
| `CF_PROXIED` | 否 | `true`、`false` | 默认 `false` |
| `CREATE_MISSING` | 否 | `true`、`false` | 默认 `true` |

### IPv4、IPv6 和双栈

只更新 A 记录：

```bash
IP_VERSION="4"
```

只更新 AAAA 记录：

```bash
IP_VERSION="6"
```

同时更新相同域名的 A 和 AAAA 记录：

```bash
IP_VERSION="both"
```

使用 `both` 时，VPS 必须同时具备可用的公网 IPv4 和公网 IPv6。脚本先更新 A 记录，再更新 AAAA 记录。如果 IPv6 不可用，本次运行会以失败状态结束。

### 是否开启 Cloudflare 代理

网站使用 HTTP 或 HTTPS 时，可以设置：

```bash
CF_PROXIED="true"
CF_TTL="1"
```

SSH、邮件、数据库、游戏服务或其他非 Cloudflare 默认代理端口，应设置：

```bash
CF_PROXIED="false"
```

Cloudflare 默认不代理 SSH 的 22 端口。官方端口列表：[Cloudflare 代理端口](https://developers.cloudflare.com/fundamentals/reference/network-ports/)。

代理记录的 TTL 固定为 Auto。使用 `CF_PROXIED=true` 时把 `CF_TTL` 设为 `1`。Cloudflare 官方说明：[DNS TTL](https://developers.cloudflare.com/dns/manage-dns-records/reference/ttl/)。

## 6. 测试 Token 和公网 IP

检查 API Token 是否有效：

```bash
sudo bash -c '. /etc/cloudflare-ddns.env
curl -fsS "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CF_API_TOKEN" | jq'
```

成功响应中应包含：

```json
{
  "result": {
    "status": "active"
  },
  "success": true
}
```

检查 VPS 的公网 IPv4：

```bash
curl -4 -fsS https://cloudflare.com/cdn-cgi/trace | sed -n 's/^ip=//p'
```

检查公网 IPv6：

```bash
curl -6 -fsS https://cloudflare.com/cdn-cgi/trace | sed -n 's/^ip=//p'
```

IPv6 命令失败或返回的不是 IPv6 地址时，不要使用 `IP_VERSION=6` 或 `IP_VERSION=both`。

## 7. 手动运行

执行一次同步：

```bash
sudo /usr/local/sbin/cloudflare-ddns
```

首次运行可能显示：

```text
已创建 A 记录: vps.example.com -> 203.0.113.10
```

IP 改变后会显示：

```text
已更新 A 记录: vps.example.com，203.0.113.10 -> 198.51.100.20
```

配置和 IP 都没有变化时会显示：

```text
A 记录未变化: vps.example.com -> 198.51.100.20
```

先完成手动运行，再配置定时任务。

## 8. 使用 systemd timer

下载并安装 systemd 文件：

```bash
REPO_RAW="https://raw.githubusercontent.com/CodeManXposed/Cloudflare-ddns/main"

curl -fsSL "$REPO_RAW/cloudflare-ddns.service" -o /tmp/cloudflare-ddns.service
curl -fsSL "$REPO_RAW/cloudflare-ddns.timer" -o /tmp/cloudflare-ddns.timer

sudo install -m 0644 /tmp/cloudflare-ddns.service /etc/systemd/system/cloudflare-ddns.service
sudo install -m 0644 /tmp/cloudflare-ddns.timer /etc/systemd/system/cloudflare-ddns.timer
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflare-ddns.timer
```

定时器会在开机约 30 秒后首次运行，之后约每五分钟运行一次。配置包含最多 30 秒的随机延迟。

查看定时器状态和下次运行时间：

```bash
systemctl status cloudflare-ddns.timer --no-pager
systemctl list-timers --all cloudflare-ddns.timer
```

立即执行一次 systemd 服务：

```bash
sudo systemctl start cloudflare-ddns.service
```

查看最近日志：

```bash
journalctl -u cloudflare-ddns.service -n 50 --no-pager
```

持续查看日志：

```bash
journalctl -fu cloudflare-ddns.service
```

## 9. 使用 cron

不使用 systemd 时，编辑 root 的 crontab：

```bash
sudo crontab -e
```

加入下面一行，每五分钟运行一次：

```cron
*/5 * * * * /usr/local/sbin/cloudflare-ddns >>/var/log/cloudflare-ddns.log 2>&1
```

保存后检查：

```bash
sudo crontab -l
```

查看日志：

```bash
sudo tail -n 50 /var/log/cloudflare-ddns.log
```

不要同时启用 cron 和 systemd timer。

## 10. 验证 DNS 结果

安装 `dig` 后查询 Cloudflare 公共 DNS：

```bash
dig +short A vps.example.com @1.1.1.1
dig +short AAAA vps.example.com @1.1.1.1
```

当 `CF_PROXIED=false` 时，查询结果应是 VPS 的公网 IP。

当 `CF_PROXIED=true` 时，查询结果会是 Cloudflare Anycast 地址，不会直接显示 VPS 原始 IP。这是正常行为。代理状态说明：[Cloudflare Proxy status](https://developers.cloudflare.com/dns/proxy-status/)。

DNS 缓存可能导致本地查询短时间内仍显示旧结果。非代理记录的更新时间受 `CF_TTL` 和本地 DNS 缓存影响。

## 11. 常见问题

### 提示缺少 curl 或 jq

重新执行本文第 1 节对应发行版的安装命令，然后确认：

```bash
command -v bash curl jq
```

### Cloudflare API 返回认证或权限错误

检查以下项目：

- Token 状态为 `active`
- Token 权限是 `Zone / DNS / Edit`
- Token 的 Zone Resources 包含目标域名
- `CF_ZONE_ID` 来自目标域名，不是其他域名或 Account ID
- Token 前后没有多余空格或换行

### 无法获取公网 IPv6

先执行：

```bash
ip -6 address show scope global
curl -6 -fsS https://cloudflare.com/cdn-cgi/trace
```

没有全局 IPv6 地址或 IPv6 出站连接失败时，把 `IP_VERSION` 改为 `4`。

### 提示存在多条同类型记录

脚本发现同一个完整域名存在多条 A 或多条 AAAA 记录时会退出，避免破坏轮询 DNS。

在 Cloudflare DNS 页面删除重复记录，或为 DDNS 使用单独的子域名。脚本不会批量覆盖多条记录。

### 开启代理后 SSH 或其他端口无法连接

把配置改为：

```bash
CF_PROXIED="false"
```

再次运行脚本。Cloudflare 默认代理只处理指定的 HTTP 和 HTTPS 端口。

### systemd timer 没有运行

检查：

```bash
systemctl is-enabled cloudflare-ddns.timer
systemctl status cloudflare-ddns.timer --no-pager
journalctl -u cloudflare-ddns.timer -u cloudflare-ddns.service -n 100 --no-pager
```

重新加载并启动：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflare-ddns.timer
```

### DNS 查询显示 Cloudflare IP

`CF_PROXIED=true` 时，DNS 返回 Cloudflare Anycast 地址。若需要直接解析到 VPS 地址，把代理状态改为 `false` 后重新运行脚本。

## 12. 更新脚本

下载新版本并替换主脚本：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/CodeManXposed/Cloudflare-ddns/main/cloudflare-ddns.sh \
  -o /tmp/cloudflare-ddns.sh

sudo install -m 0755 /tmp/cloudflare-ddns.sh /usr/local/sbin/cloudflare-ddns
sudo /usr/local/sbin/cloudflare-ddns
```

更新 systemd 文件后需要执行：

```bash
sudo systemctl daemon-reload
sudo systemctl restart cloudflare-ddns.timer
```

## 13. 卸载

使用 systemd timer 时先停止并禁用：

```bash
sudo systemctl disable --now cloudflare-ddns.timer
```

删除安装的文件：

```bash
sudo rm -f /usr/local/sbin/cloudflare-ddns
sudo rm -f /etc/cloudflare-ddns.env
sudo rm -f /etc/systemd/system/cloudflare-ddns.service
sudo rm -f /etc/systemd/system/cloudflare-ddns.timer
sudo systemctl daemon-reload
```

使用 cron 时还需要执行 `sudo crontab -e`，删除对应的定时任务。

卸载脚本不会删除 Cloudflare 中已经创建的 DNS 记录。如需删除记录，请在 Cloudflare Dashboard 中手动处理。

## 工作方式和限制

每次运行时，脚本按以下顺序处理：

1. 从 `/etc/cloudflare-ddns.env` 读取配置。
2. 通过 Cloudflare `/cdn-cgi/trace` 获取当前出口 IP。
3. 按记录名和类型查询 Cloudflare DNS。
4. 记录不存在且 `CREATE_MISSING=true` 时创建记录。
5. IP、TTL 或代理状态变化时更新记录。
6. 配置没有变化时退出，不发送更新请求。

当前版本有以下限制：

- 一个配置文件只管理一个完整域名
- 双栈模式使用相同域名创建 A 和 AAAA 记录
- 不管理包含多条 A 或多条 AAAA 的轮询 DNS
- 不解决 NAT、运营商 CGNAT、防火墙或端口转发问题
- 公网 IP 获取和 DNS API 都依赖 Cloudflare 可访问

## 安全建议

- Token 只授予目标 Zone 的 DNS Edit 权限
- `/etc/cloudflare-ddns.env` 权限保持为 `0600`
- 不要把真实配置文件复制到 Web 目录或 Git 仓库
- 不要在终端截图、工单或聊天中公开 Token
- 怀疑 Token 泄露时，立即在 Cloudflare Dashboard 中吊销并重新创建

Cloudflare DNS API 参考：

- [查询 DNS 记录](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/list/)
- [创建 DNS 记录](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/create/)
- [更新 DNS 记录](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/edit/)
