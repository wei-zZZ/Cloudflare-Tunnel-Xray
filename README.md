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

✅一键恢复系统初始化 + 安装常用工具脚本：✅注意使用✅

```
curl -fsSL https://raw.githubusercontent.com/wei-zZZ/Cloudflare-Tunnel-Xray/main/recover.sh | bash
```
✅快速开始✅
```
curl -sSL -o secure_tunnel.sh https://raw.githubusercontent.com/wei-zZZ/Cloudflare-Tunnel-Xray/main/secure_tunnel.sh && chmod +x secure_tunnel.sh && sudo ./secure_tunnel.sh
```


1. 下载脚本
```
curl -sSL -o secure_tunnel.sh https://raw.githubusercontent.com/wei-zZZ/Cloudflare-Tunnel-Xray/main/secure_tunnel.sh
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

