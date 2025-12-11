🔐 Secure Tunnel Manager - 安全隧道管理工具


项目简介

这是一个自动化部署 Cloudflare Tunnel 与 Xray-core 的 Bash 脚本，能够快速搭建一个基于 Cloudflare Argo Tunnel 的安全代理隧道。该脚本实现了免端口暴露、自动 SSL 证书签发和 WebSocket 代理功能。

功能特性

✅ 一键安装 - 全自动部署 Xray-core 和 Cloudflare Tunnel

✅ 智能配置 - 自动生成 VLESS + WebSocket + TLS 配置

✅ 系统服务 - 自动创建 systemd 服务并配置开机自启

✅ 多架构支持 - 支持 x86_64 和 arm64 架构

✅ 配置管理 - 提供状态检查、重启、重新授权等管理功能

系统要求

操作系统: Ubuntu/Debian/CentOS 等主流 Linux 发行版

权限: Root 用户权限

网络: 可正常访问 GitHub 和 Cloudflare

Cloudflare 账户: 需要拥有一个域名并托管在 Cloudflare

🚀 快速开始

安装步骤：
1. 下载脚本
# 方法1：从GitHub下载
```bash

wget https://raw.githubusercontent.com/wei-zZZ/Cloudflare-Tunnel-Xray/4de04c8df4b70b224eb719d7a066c24a65173e3e/secure_tunnel.sh
```
# 方法2：克隆整个仓库
```bash
git clone https://github.com/wei-zZZ/Cloudflare-Tunnel-Xray.git
cd Cloudflare-Tunnel-Xray
```
2. 给脚本执行权限
```bash
chmod +x secure_tunnel.sh
```
3. 运行安装
```bash
sudo ./secure_tunnel.sh install
```
3. 按照提示操作
脚本将引导您完成以下步骤：

输入您的域名（如 tunnel.yourdomain.com）

设置隧道名称（默认：secure-tunnel）

授权 Cloudflare 账户

自动完成部署

详细使用方法
安装命令

# 完整安装
sudo ./secure_tunnel.sh install

# 查看服务状态
sudo ./secure_tunnel.sh status

# 重启服务
sudo ./secure_tunnel.sh restart

# 查看配置信息
sudo ./secure_tunnel.sh config

# 重新授权 Cloudflare
sudo ./secure_tunnel.sh auth

# 完全卸载
sudo ./secure_tunnel.sh uninstall

安装后配置
1. 客户端配置
2. 安装完成后，脚本会显示以下连接信息：

VLESS 链接: 可直接导入支持 VLESS 协议的客户端

Clash 配置: 适用于 Clash 客户端的 YAML 配置

手动配置参数:

地址: 您的域名

端口: 443 (TLS) 或 80 (非TLS)

UUID: 自动生成的唯一标识符

传输协议: WebSocket

路径: /生成的UUID

TLS: 启用

2. Cloudflare 配置检查
登录 Cloudflare 控制台

进入您的域名

检查 DNS 记录是否已自动添加

确认 SSL/TLS 设置为 "完全" 或 "灵活"

文件结构
text
```bash
/root/.cloudflared/
├── cert.pem             # Cloudflare 证书
└── *.json               # 隧道凭证文件

/etc/secure_tunnel/
├── tunnel.conf          # 隧道配置文件
├── xray.json           # Xray 配置文件
└── config.yaml         # Cloudflare Tunnel 配置

/var/log/secure_tunnel/
├── xray.log
├── xray-error.log
├── argo.log
└── argo-error.log

/usr/local/bin/
├── xray                # Xray 核心程序
└── cloudflared         # Cloudflare
```
Tunnel 客户端
服务管理
启动/停止服务
```bash
# 启动所有服务
systemctl start secure-tunnel-xray.service secure-tunnel-argo.service

# 停止所有服务
systemctl stop secure-tunnel-xray.service secure-tunnel-argo.service

# 查看服务状态
systemctl status secure-tunnel-xray.service secure-tunnel-argo.service

# 启用开机自启
systemctl enable secure-tunnel-xray.service secure-tunnel-argo.service
```
日志查看
```bash
# 查看 Xray 日志
journalctl -u secure-tunnel-xray.service -f

# 查看 Argo Tunnel 日志
journalctl -u secure-tunnel-argo.service -f

# 查看错误日志
tail -f /var/log/secure_tunnel/*error.log
```
故障排除
常见问题
授权失败

确保使用正确的 Cloudflare 账户

检查域名是否在 Cloudflare 托管

尝试重新授权：sudo ./secure_tunnel.sh auth

服务启动失败

检查日志：journalctl -u secure-tunnel-argo.service -n 50

确认证书是否存在：ls -la /root/.cloudflared/cert.pem

检查配置文件：sudo ./secure_tunnel.sh config

无法连接

等待 DNS 传播（可能需要几分钟）

检查 Cloudflare DNS 设置

验证客户端配置参数

证书问题

重新生成证书：删除 /root/.cloudflared/cert.pem 后重新授权

检查证书有效期

诊断命令
```bash
# 显示完整状态
sudo ./secure_tunnel.sh status

# 检查隧道状态
cloudflared tunnel list

# 检查进程运行状态
ps aux | grep -E "(xray|cloudflared)"

# 测试本地端口
curl -I http://localhost:10000
```
更新与维护
手动更新组件
```bash
# 更新 Xray
wget -O /tmp/xray.zip "最新版本下载链接"
unzip -o /tmp/xray.zip -d /tmp
mv /tmp/xray /usr/local/bin/
systemctl restart secure-tunnel-xray.service

# 更新 cloudflared
wget -O /usr/local/bin/cloudflared "最新版本下载链接"
chmod +x /usr/local/bin/cloudflared
systemctl restart secure-tunnel-argo.service
```
备份配置
```bash
# 备份重要文件
cp -r /etc/secure_tunnel ~/secure_tunnel_backup
cp -r /root/.cloudflared ~/cloudflared_backup
```
安全建议
定期更新

定期检查并更新 Xray 和 cloudflared 版本

关注安全公告

监控访问

定期检查服务日志

监控异常连接

备份配置

备份 /etc/secure_tunnel 目录

备份 /root/.cloudflared/cert.pem 文件

访问控制

使用强密码保护服务器

配置防火墙规则

免责声明
本项目仅为技术研究和学习用途，请遵守当地法律法规。使用者应对自己的行为负责，作者不对任何因使用本项目造成的直接或间接损失承担责任。

技术支持
如有问题，请：

查看本文档的故障排除部分

检查日志文件

确保按照步骤正确操作

版本历史
v4.3 - 修复配置文件解析错误

v4.0 - 支持无浏览器授权模式

v3.0 - 增加多架构支持和系统服务管理

注意: 请确保您有合法的使用场景，并遵守相关服务条款和法律法规。
