# Cloudflare VPS DDNS

这个 Bash 脚本把 VPS 当前公网 IPv4、IPv6 或两者同步到 Cloudflare DNS。它依赖 `curl` 和 `jq`，适用于使用 systemd 的常见 Linux 发行版。

## 1. 创建 API Token

在 Cloudflare 控制台创建 API Token：

- 权限选择 `Zone / DNS / Edit`
- Zone Resources 只选择要更新的域名
- 不要使用 Global API Key

从域名概览页复制 Zone ID。Token 密钥只会显示一次，不要把它写入脚本或提交到 Git。

## 2. 安装

在包含这些文件的目录中运行：

```bash
sudo install -m 0755 cloudflare-ddns.sh /usr/local/sbin/cloudflare-ddns
sudo install -m 0600 cloudflare-ddns.env.example /etc/cloudflare-ddns.env
sudo editor /etc/cloudflare-ddns.env

sudo install -m 0644 cloudflare-ddns.service /etc/systemd/system/cloudflare-ddns.service
sudo install -m 0644 cloudflare-ddns.timer /etc/systemd/system/cloudflare-ddns.timer
sudo systemctl daemon-reload
```

先手动测试：

```bash
sudo /usr/local/sbin/cloudflare-ddns
```

确认输出正常后启用定时器：

```bash
sudo systemctl enable --now cloudflare-ddns.timer
systemctl list-timers cloudflare-ddns.timer
```

查看最近日志：

```bash
journalctl -u cloudflare-ddns.service -n 50 --no-pager
```

## 使用 cron

不使用 systemd 时，可让 root 每五分钟执行一次：

```cron
*/5 * * * * /usr/local/sbin/cloudflare-ddns >>/var/log/cloudflare-ddns.log 2>&1
```

不要同时启用 cron 和 systemd timer。

## 配置说明

- `IP_VERSION=4` 更新 A 记录。
- `IP_VERSION=6` 更新 AAAA 记录。
- `IP_VERSION=both` 依次更新 A 和 AAAA 记录。VPS 必须同时具备可用的公网 IPv4 和 IPv6。
- `CF_PROXIED=true` 开启 Cloudflare 橙云代理。SSH、邮件等非 Cloudflare 支持的端口通常应设为 `false`。
- `CREATE_MISSING=true` 会在记录不存在时创建记录。

脚本通过 Cloudflare 的 `/cdn-cgi/trace` 获取当前出口地址。更新现有记录时会按配置同步 IP、TTL 和代理状态。若同一名称存在多条同类型记录，脚本会退出，避免覆盖轮询 DNS 配置。
