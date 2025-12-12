Cloudflare Tunnel + Xray 安装脚本说明
简介
这是一个自动化的 Bash 脚本，用于在 Linux 服务器上部署 Cloudflare Tunnel 和 Xray (VLESS) 服务。通过 Cloudflare 的 Argo Tunnel 技术，您可以将本地服务安全地暴露到公网，无需公网 IP 和端口转发。

特性
✅ 全自动化安装配置

✅ 支持 x86_64 和 arm64 架构

✅ 自动下载最新版 Xray 和 cloudflared

✅ 交互式 Cloudflare 授权

✅ 自动创建隧道和 DNS 记录

✅ 系统服务管理 (systemd)

✅ 完整的卸载功能

✅ 静默安装模式

✅ 授权问题自动修复

系统要求
操作系统: Ubuntu/Debian/CentOS 等主流 Linux 发行版

权限: Root 权限

网络: 可以访问 GitHub 和 Cloudflare

内存: 至少 256MB RAM

安装前准备
一个域名（可以托管在 Cloudflare）

Cloudflare 账户

一台运行 Linux 的服务器

快速开始
1. 下载脚本
```
curl -sSL -o secure_tunnel.sh https://github.com/wei-zZZ/Cloudflare-Tunnel-Xray/blob/main/argox.sh
```
```
chmod +x secure_tunnel.sh
```
2. 运行脚本
```
sudo ./secure_tunnel.sh
```
3. 选择安装选项
脚本提供交互式菜单，选择 1) 安装 Secure Tunnel 开始安装。

详细安装步骤
步骤 1: 系统检查
脚本会自动检查：

Root 权限

必要的工具 (curl, unzip, wget)

系统架构 (自动选择正确的二进制版本)

步骤 2: Cloudflare 授权
重要: 这是最关键的一步！

脚本会运行 cloudflared tunnel login

您会看到一个 Cloudflare 登录链接

复制链接到浏览器打开

登录您的 Cloudflare 账户

选择您要使用的域名

点击 "Authorize" 授权

返回终端按回车继续

步骤 3: 配置信息
需要提供：

域名: 如 tunnel.yourdomain.com

隧道名称: 默认为 secure-tunnel

步骤 4: 组件安装
脚本会自动：

下载 Xray (VLESS/WS)

下载 cloudflared

安装到 /usr/local/bin/

步骤 5: 隧道创建
脚本会：

创建 Cloudflare Tunnel

生成 DNS 记录

保存隧道配置

步骤 6: Xray 配置
自动生成：

UUID (随机生成)

WS 路径 (使用 UUID)

本地监听端口 (10000)

步骤 7: 服务配置
创建两个 systemd 服务：
```
secure-tunnel-xray.service - Xray 服务

secure-tunnel-argo.service - Argo Tunnel 服务
```
步骤 8: 启动服务
启动所有服务并检查状态。

命令行参数
```
# 显示菜单（默认）
sudo ./secure_tunnel.sh

# 直接安装
sudo ./secure_tunnel.sh install

# 静默安装（使用默认值）
sudo ./secure_tunnel.sh -y
sudo ./secure_tunnel.sh --silent

# 查看状态
sudo ./secure_tunnel.sh status

# 查看配置
sudo ./secure_tunnel.sh config

# 修复授权问题
sudo ./secure_tunnel.sh fix-auth

# 卸载
sudo ./secure_tunnel.sh uninstall
```
静默安装模式
对于自动化部署，可以使用静默安装：

```
sudo ./secure_tunnel.sh -y
```
静默模式将使用默认值：

域名: tunnel.example.com

隧道名称: secure-tunnel

注意: 您需要在静默安装后手动修改配置。

连接信息
安装完成后，脚本会显示：

🔗 域名: 您配置的域名

🔑 UUID: 用于连接的身份验证

🛣️ 路径: /your-uuid

🔧 本地端口: 10000

VLESS 链接格式
```
vless://uuid@your-domain.com:443?encryption=none&security=tls&type=ws&host=your-domain.com&path=%2Fuuid&sni=your-domain.com#安全隧道
```
客户端配置
1. V2RayN / Qv2ray
地址: 您的域名

端口: 443

UUID: 安装时生成的 UUID

传输协议: WebSocket (WS)

路径: /您的UUID

TLS: 开启

2. Clash
```
yaml
proxies:
  - name: "Cloudflare Tunnel"
    type: vless
    server: your-domain.com
    port: 443
    uuid: your-uuid-here
    network: ws
    tls: true
    servername: your-domain.com
    ws-opts:
      path: "/your-uuid"
      headers:
        Host: your-domain.com
        ```
管理命令
查看服务状态
```
sudo systemctl status secure-tunnel-xray.service
sudo systemctl status secure-tunnel-argo.service
```
重启服务
```
sudo systemctl restart secure-tunnel-argo.service
sudo systemctl restart secure-tunnel-xray.service
```
查看日志
```
# Xray 日志
journalctl -u secure-tunnel-xray.service -f

# Argo Tunnel 日志
journalctl -u secure-tunnel-argo.service -f

# 配置目录日志
tail -f /var/log/secure_tunnel/*
隧道管理
bash
# 查看所有隧道
/usr/local/bin/cloudflared tunnel list

# 删除隧道
/usr/local/bin/cloudflared tunnel delete <tunnel-name>
```
常见问题解决
1. 授权失败
症状: cloudflared tunnel login 不生成凭证文件

解决方案:

```
# 运行修复工具
sudo ./secure_tunnel.sh fix-auth

# 或手动步骤
rm -rf /root/.cloudflared
/usr/local/bin/cloudflared tunnel login
```
2. 服务启动失败
检查步骤:
```
查看日志: journalctl -u secure-tunnel-argo.service -n 50

检查证书: ls -la /root/.cloudflared/

检查配置: cat /etc/secure_tunnel/tunnel.conf
```
3. 无法连接
可能原因:

DNS 解析未生效 - 等待 1-5 分钟

隧道未启动 - 检查服务状态

UUID 不匹配 - 重新生成配置

4. 证书问题
```
# 重新下载最新 cloudflared
curl -L --output /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /usr/local/bin/cloudflared
文件结构
text
/etc/secure_tunnel/
├── tunnel.conf          # 主配置文件
├── xray.json           # Xray 配置
└── config.yaml         # Cloudflare Tunnel 配置

/var/log/secure_tunnel/
├── xray.log
├── xray-error.log
├── argo.log
└── argo-error.log

/root/.cloudflared/
├── cert.pem            # Cloudflare 证书
└── *.json              # 隧道凭证文件
```
卸载
```
sudo ./secure_tunnel.sh uninstall
```
会删除：

所有配置文件

系统服务

日志文件

可选择删除二进制文件和授权文件

注意事项
安全性
保护 UUID: UUID 相当于密码，不要泄露

定期更新: 建议每月更换一次 UUID

日志监控: 定期检查日志文件

防火墙: 确保本地防火墙允许 localhost 连接

性能
Cloudflare 限制: 注意 Cloudflare 的流量和连接数限制

服务器资源: Xray 消耗内存较小，但隧道服务需要稳定网络

DNS 缓存: 修改 DNS 后可能需要清除客户端缓存

网络
端口要求: 不需要开放任何公网端口

协议: 使用 WebSocket over TLS (443 端口)

CDN: 所有流量通过 Cloudflare CDN

故障排除
查看详细日志
```
# 查看完整日志
journalctl -u secure-tunnel-argo.service --no-pager

# 实时监控
journalctl -u secure-tunnel-argo.service -f

# 查看最后50条
journalctl -u secure-tunnel-argo.service -n 50
测试连接
bash
# 测试本地 Xray 服务
curl -v http://localhost:10000

# 测试隧道连接
curl -v https://your-domain.com/your-uuid
```
重新配置
```
# 备份配置
cp -r /etc/secure_tunnel /root/secure_tunnel_backup

# 重新安装
sudo ./secure_tunnel.sh uninstall
sudo ./secure_tunnel.sh install
```
更新脚本

# 重新下载最新脚本
```
curl -sSL -o secure_tunnel.sh https://github.com/wei-zZZ/Cloudflare-Tunnel-Xray/blob/main/argox.sh
```
```
chmod +x secure_tunnel.sh
```
# 重新安装（配置会保留）
```
sudo ./secure_tunnel.sh install
```
技术支持
GitHub: wei-zZZ/Cloudflare-Tunnel-Xray

问题报告: GitHub Issues

免责声明
本脚本仅供学习和研究使用，请遵守当地法律法规和 Cloudflare 服务条款。使用者需自行承担相关风险。

版本: 6.1
最后更新: $(date +%Y-%m-%d)
兼容性: Ubuntu 18.04+, Debian 9+, CentOS 7+