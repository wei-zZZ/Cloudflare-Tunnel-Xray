# Cloudflare-Tunnel-Xray
Cloudflare Tunnel + Xray 安全增强部署脚本 v2.1 # 新增：智能Cloudflare节点优选功能

============================================
# Cloudflare Tunnel + Xray 安全增强部署脚本
# 版本: 2.0
# 特性: 安全权限、文件校验、systemd服务、配置分离
============================================
安全增强版脚本核心改进



权限最小化 
创建专用系统用户/组运行服务，避免使用root。

文件校验 
下载二进制文件后验证SHA256哈希值，防止篡改。

安全目录 
使用标准Linux目录结构（/usr/local/bin, /var/log, /etc）。

可靠进程管理 
使用systemd服务管理，确保进程可靠启动停止。

配置与数据分离 
配置文件、数据、日志、临时文件分离存放。

错误处理 
关键步骤加入错误检查，失败时清晰提示并退出。

清理机制 
安装失败或卸载时自动清理残留文件。



📋 使用说明

1. 准备工作

```bash
# 下载脚本
curl -O https://example.com/secure_tunnel.sh

# 添加执行权限
chmod +x secure_tunnel.sh

# 更新文件哈希（重要！）
# 编辑脚本中的 FILE_HASHES 数组，填入从官方GitHub Release页面获取的最新哈希值
```

2. 快速安装

```bash
# 全自动安装
sudo ./secure_tunnel.sh install

# 或使用环境变量自定义
sudo PROTOCOL="vmess" ARGO_IP_VERSION="6" ./secure_tunnel.sh install
```

3. 手动授权步骤

安装后需要手动完成Cloudflare授权：

```bash
# 1. 登录Cloudflare（会打开浏览器）
sudo -u secure_tunnel cloudflared tunnel login

# 2. 创建隧道
sudo -u secure_tunnel cloudflared tunnel create 你的隧道名称

# 3. 绑定域名
sudo -u secure_tunnel cloudflared tunnel route dns 你的隧道名称 你的域名

# 4. 启动服务
sudo systemctl start secure-tunnel-argo
```

4. 查看连接信息

```bash
# 查看状态
sudo ./secure_tunnel.sh status

# 或直接查看配置文件
cat /etc/secure_tunnel/client-info.txt
```

🔒 安全最佳实践

1. 定期更新：
   ```bash
   # 更新文件哈希值
   # 从 https://github.com/XTLS/Xray-core/releases 获取最新哈希
   # 从 https://github.com/cloudflare/cloudflared/releases 获取最新哈希
   ```
2. 防火墙配置：
   ```bash
   # 只允许必要的端口
   ufw allow 22/tcp
   ufw allow 443/tcp
   ufw allow 80/tcp
   ufw enable
   ```
3. 监控日志：
   ```bash
   # 查看实时日志
   tail -f /var/log/secure_tunnel/xray-error.log
   journalctl -u secure-tunnel-xray -f
   ```
4. 定期备份配置：
   ```bash
   # 备份关键配置
   tar czf tunnel-backup-$(date +%Y%m%d).tar.gz /etc/secure_tunnel/
   ```
