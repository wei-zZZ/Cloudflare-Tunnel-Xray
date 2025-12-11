Cloudflare Tunnel + Xray 一键安装脚本

📋 功能介绍
这是一个全自动的 Cloudflare Tunnel + Xray 安装脚本，主要功能包括：

🔧 核心功能
全自动安装：一键安装 Xray 和 cloudflared

Cloudflare 隧道：通过 Argo Tunnel 实现免端口转发

VLESS 协议：使用 VLESS + WebSocket + TLS 方案

多架构支持：支持 x86_64 和 ARM64 架构

系统服务：自动配置 systemd 服务，开机自启

故障恢复：服务崩溃后自动重启

⚡ 特点
无需公网 IP：通过 Cloudflare Tunnel 实现内网穿透

无需域名解析：自动配置 DNS 记录

无需端口开放：无需在防火墙开放端口

CDN 加速：享受 Cloudflare 全球 CDN 加速

自动重连：网络中断后自动重新连接

🚀 快速开始


一键安装（下载+授权+安装）

# 一条命令完成所有操作

curl -L https://raw.githubusercontent.com/wei-zZZ/Cloudflare-Tunnel-Xray/main/argox.sh -o argox.sh && chmod +x argox.sh && sudo ./argox.sh install
curl -L https://raw.githubusercontent.com/wei-zZZ/Cloudflare-Tunnel-Xray/main/argox.sh -o argox.sh && chmod +x argox.sh && sudo ./argox.sh menu
3. 静默安装（使用默认配置）

# 静默安装（无需交互）

sudo ./argox.sh -y

📝 安装流程
步骤 1：系统检查
脚本会自动检查：

Root 权限

必要工具（curl、unzip、wget）

系统架构

步骤 2：下载组件
自动下载：

Xray 核心（最新版本）

Cloudflared（最新版本）

使用多个备用源，确保下载成功

步骤 3：Cloudflare 授权
重要提示：此步骤需要浏览器操作

脚本会显示授权链接

复制链接到浏览器打开

选择你的域名并授权

授权成功后按回车继续

步骤 4：配置信息
输入以下信息：

域名：如 tunnel.yourdomain.com

隧道名称：默认 secure-tunnel

步骤 5：自动配置
脚本会自动：

创建 Cloudflare 隧道

绑定域名

生成 UUID 和配置

配置 Xray

设置 systemd 服务

步骤 6：启动服务
自动启动：

Xray 服务

Argo Tunnel 服务

🔍 管理命令
查看配置
bash
sudo ./secure_tunnel.sh config
查看服务状态
bash
sudo ./secure_tunnel.sh status
手动管理服务
bash
# 查看 Xray 状态
systemctl status secure-tunnel-xray.service

# 查看 Argo 隧道状态
systemctl status secure-tunnel-argo.service

# 重启服务
systemctl restart secure-tunnel-argo.service

# 停止服务
systemctl stop secure-tunnel-argo.service

# 启动服务
systemctl start secure-tunnel-argo.service

# 查看日志
tail -f /var/log/secure_tunnel/argo.log
tail -f /var/log/secure_tunnel/xray.log
📡 客户端配置
连接信息示例
安装完成后会显示类似以下信息：

text
🔗 域名: tunnel.yourdomain.com
🔑 UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
🚪 端口: 443 (TLS) / 80 (非TLS)
🛣️  路径: /xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

VLESS 链接:
vless://xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx@tunnel.yourdomain.com:443?encryption=none&security=tls&type=ws&host=tunnel.yourdomain.com&path=%2Fxxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx&sni=tunnel.yourdomain.com#安全隧道
支持的客户端
V2rayN（Windows）

Qv2ray（跨平台）

V2rayU（macOS）

v2rayNG（Android）

Shadowrocket（iOS）

🛠️ 故障排除
常见问题
1. 授权失败
bash
# 重新授权
rm -rf /root/.cloudflared
# 重新运行脚本
sudo ./secure_tunnel.sh install
2. 服务启动失败
bash
# 查看日志
journalctl -u secure-tunnel-argo.service -f
journalctl -u secure-tunnel-xray.service -f

# 检查配置文件
cat /etc/secure_tunnel/tunnel.conf
3. 连接超时
检查域名是否正确解析

检查 Cloudflare 代理状态（应为橙色云朵）

等待 DNS 传播（最长 72 小时）

4. 端口占用
bash
# 检查端口占用
ss -tulpn | grep :10000
# 如果端口被占用，修改 /etc/secure_tunnel/xray.json 中的端口
📁 文件结构
text
/etc/secure_tunnel/
├── tunnel.conf          # 配置文件
├── xray.json           # Xray 配置
└── config.yaml         # Cloudflared 配置

/var/lib/secure_tunnel/  # 数据目录
/var/log/secure_tunnel/  # 日志目录
├── argo.log            # Argo 隧道日志
├── argo-error.log      # Argo 错误日志
├── xray.log            # Xray 日志
└── xray-error.log      # Xray 错误日志

/usr/local/bin/
├── xray                # Xray 二进制
└── cloudflared         # Cloudflared 二进制

/etc/systemd/system/
├── secure-tunnel-xray.service   # Xray 服务
└── secure-tunnel-argo.service   # Argo 隧道服务
🔄 更新脚本
bash
# 重新下载脚本
curl -L https://raw.githubusercontent.com/your-repo/secure_tunnel.sh -o secure_tunnel.sh

# 更新权限
chmod +x secure_tunnel.sh

# 重新运行（配置会保留）
sudo ./secure_tunnel.sh install
🗑️ 卸载脚本
bash
# 停止服务
systemctl stop secure-tunnel-argo.service
systemctl stop secure-tunnel-xray.service

# 禁用服务
systemctl disable secure-tunnel-argo.service
systemctl disable secure-tunnel-xray.service

# 删除服务文件
rm -f /etc/systemd/system/secure-tunnel-*.service

# 删除配置文件
rm -rf /etc/secure_tunnel
rm -rf /var/lib/secure_tunnel
rm -rf /var/log/secure_tunnel

# 删除二进制文件（可选）
rm -f /usr/local/bin/xray
rm -f /usr/local/bin/cloudflared

# 删除用户
userdel secure_tunnel 2>/dev/null || true

# 重载 systemd
systemctl daemon-reload
📊 性能监控
查看资源使用
bash
# 查看进程
ps aux | grep -E "(xray|cloudflared)"

# 查看内存使用
top -p $(pgrep -d, -f "xray|cloudflared")

# 查看网络连接
ss -tulpn | grep -E "(xray|cloudflared)"
监控日志
bash
# 实时查看日志
tail -f /var/log/secure_tunnel/argo.log
tail -f /var/log/secure_tunnel/xray.log

# 查看错误日志
tail -f /var/log/secure_tunnel/argo-error.log
tail -f /var/log/secure_tunnel/xray-error.log
⚠️ 注意事项
域名要求

域名必须在 Cloudflare 管理

DNS 记录需由 Cloudflare 代理（橙色云朵）

建议使用子域名，如 tunnel.yourdomain.com

网络要求

服务器需要能访问互联网

需要能访问 GitHub（下载组件）

需要能访问 Cloudflare API

系统要求

Ubuntu/Debian 系统（推荐）

Root 权限

至少 512MB 内存

1GB 可用磁盘空间

安全建议

定期更新脚本和组件

监控日志文件

使用复杂 UUID

限制客户端访问

🆘 获取帮助
如果遇到问题，请检查：

是否完成 Cloudflare 授权

域名是否正确解析

服务是否正常运行

防火墙是否允许出站连接

如需进一步帮助，请提供：

操作系统版本

错误日志内容

执行步骤描述

📄 许可证
MIT License

👥 贡献
欢迎提交 Issue 和 Pull Request 来改进脚本。

🔔 更新日志
v5.1
优化安装流程

改进用户交互

增强错误处理

添加静默安装模式

v5.0
支持静默安装

优化授权流程

移除订阅服务器

精简代码结构

提示：安装前请确保已准备好 Cloudflare 账号和域名。
