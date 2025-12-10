🔐 Secure Tunnel Manager - 安全隧道管理工具

📖 概述

Secure Tunnel Manager 是一个集成了 Cloudflare Tunnel 和 Xray 的安全代理解决方案，支持自动优选 Cloudflare 节点域名，提供稳定、快速、安全的网络隧道服务。

✨ 核心特性

特性 说明
智能域名优选 自动测试并选择延迟最低的 Cloudflare 节点
双重代理架构 Cloudflare Tunnel + Xray 双安全层
企业级安全 专用系统用户、文件哈希校验、最小权限原则
系统集成 完整的 systemd 服务管理
配置与数据分离 符合 Linux 标准的目录结构
缓存机制 优化结果缓存，避免重复测试
IPv4/IPv6 双栈 支持双协议栈测试和连接

📁 文件结构

```
/etc/secure_tunnel/              # 配置文件目录
├── xray.json                   # Xray 主配置文件
├── client-info.txt            # 客户端连接信息
└── optimized_domains.conf     # 优选域名配置

/var/lib/secure_tunnel/         # 数据目录
├── cache/                     # 优选域名缓存
└── xray.zip                   # 临时文件

/var/log/secure_tunnel/        # 日志目录
├── xray-access.log
├── xray-error.log
└── argo.log

/usr/local/bin/                # 二进制文件
├── xray
└── cloudflared
```

🚀 快速开始

1. 下载脚本
一键安装（包含域名优选）
```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/wei-zZZ/Cloudflare-Tunnel-Xray/main/secure_tunnel.sh)" -- install
```

# 或使用自定义参数
```bash
sudo PROTOCOL="vless" ARGO_IP_VERSION="6" ./secure_tunnel.sh install
```

3. 手动配置 Argo Tunnel
4. 
# 1. 登录 Cloudflare（会打开浏览器）
```bash
sudo -u secure_tunnel cloudflared tunnel login
```
# 2. 创建隧道
```bash
sudo -u secure_tunnel cloudflared tunnel create secure_tunnel
```
# 3. 绑定域名
```bash
sudo -u secure_tunnel cloudflared tunnel route dns secure_tunnel your-domain.com
```
# 4. 获取隧道 Token 并保存
```bash
sudo -u secure_tunnel cloudflared tunnel token secure_tunnel | sudo tee /etc/secure_tunnel/argo-token.txt
```

🎯 使用场景

场景一：个人科学上网

```bash
# 快速部署个人代理
sudo ./secure_tunnel.sh install

# 连接信息保存在：
cat /etc/secure_tunnel/client-info.txt

# 在客户端（如 v2rayN）导入 VLESS 链接即可使用
```

场景二：团队远程访问

```bash
# 部署企业级隧道
sudo TUNNEL_NAME="team-tunnel" ./secure_tunnel.sh install

# 团队成员使用相同的隧道配置
# 管理员可在 Cloudflare Zero Trust 控制台管理访问权限
```

场景三：网站反向代理

```bash
# 将本地服务暴露到公网
# 修改 xray.json 配置，将流量转发到本地 Web 服务
```

⚙️ 配置说明

环境变量配置

变量名 默认值 说明
PROTOCOL vless 代理协议：vless 或 vmess
ARGO_IP_VERSION 4 Argo 隧道 IP 版本：4 或 6
TUNNEL_NAME secure_tunnel_$(hostname) 隧道名称
CF_TEST_COUNT 3 域名测试次数
CF_TIMEOUT 2 测试超时时间（秒）

配置文件说明

1. Xray 配置文件 (/etc/secure_tunnel/xray.json)

```json
{
    "inbounds": [{
        "port": 随机端口,
        "protocol": "vless/vmess",
        "settings": {
            "clients": [{
                "id": "自动生成的UUID"
            }]
        }
    }]
}
```

2. 优选域名配置 (/etc/secure_tunnel/optimized_domains.conf)

```ini
# 自动生成的优选域名配置
DOMAIN_IPV4="icook.hk"      # IPv4 最佳域名
DOMAIN_IPV6="cf.xiu2.xyz"   # IPv6 最佳域名
```

📊 域名优选功能

测试域名列表

脚本默认测试以下 Cloudflare 节点（按延迟排序）：

1. icook.hk - 香港节点
2. cloudflare.cfgo.cc - 国内优化节点
3. cloudflare.speedcdn.cc - 速度优化节点
4. cdn.shanggan.ltd - 上海节点
5. cdn.bestg.win - 广州节点
6. cf.xiu2.xyz - 备用节点
7. cloudflare.ipq.co - 国际节点
8. cfip.icu - 智能路由节点
9. cdn.cofia.xyz - 企业级节点
10. speed.cloudflare.com - 官方测试节点

优选算法

1. 并行测试：同时测试所有域名延迟
2. 多次采样：每个域名测试 3 次取平均值
3. 智能排序：选择平均延迟最低的域名
4. 缓存机制：优选结果缓存 1 小时

手动管理优选域名

```bash
# 1. 手动测试域名延迟
sudo ./secure_tunnel.sh optimize test

# 2. 仅运行优选（不显示详细结果）
sudo ./secure_tunnel.sh optimize auto

# 3. 清理优选缓存
sudo ./secure_tunnel.sh optimize clean

# 4. 查看域名列表
sudo ./secure_tunnel.sh optimize list
```

🔧 维护与管理

查看服务状态

```bash
# 查看完整状态
sudo ./secure_tunnel.sh status

# 查看 Xray 服务日志
sudo journalctl -u secure-tunnel-xray -f

# 查看 Argo 隧道日志
sudo journalctl -u secure-tunnel-argo -f
```

更新配置

```bash
# 重新优选域名
sudo rm -f /var/lib/secure_tunnel/cache/*.cache
sudo ./secure_tunnel.sh optimize auto

# 重新生成客户端配置
sudo ./secure_tunnel.sh install --reconfigure-only
```

卸载服务

```bash
# 完全卸载（保留配置）
sudo ./secure_tunnel.sh uninstall --keep-config

# 完全卸载（清除所有）
sudo ./secure_tunnel.sh uninstall
```

🛡️ 安全最佳实践

1. 定期更新

```bash
# 更新二进制文件哈希值
# 从官方发布页面获取最新哈希：
# - Xray: https://github.com/XTLS/Xray-core/releases
# - cloudflared: https://github.com/cloudflare/cloudflared/releases
```

2. 防火墙配置

```bash
# 配置 UFW 防火墙
sudo ufw allow 22/tcp
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp
sudo ufw enable
```

3. 监控告警

```bash
# 监控服务状态
sudo systemctl status secure-tunnel-*

# 查看实时日志
sudo tail -f /var/log/secure_tunnel/xray-error.log

# 设置日志轮转
sudo cp logrotate.conf /etc/logrotate.d/secure_tunnel
```

4. 定期备份

```bash
# 备份关键配置
BACKUP_DIR="/backup/secure_tunnel-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
cp -r /etc/secure_tunnel "$BACKUP_DIR/"
cp -r /var/lib/secure_tunnel "$BACKUP_DIR/"

# 创建恢复脚本
cat > "$BACKUP_DIR/restore.sh" << EOF
#!/bin/bash
cp -r etc/secure_tunnel /etc/
cp -r var/lib/secure_tunnel /var/lib/
systemctl daemon-reload
systemctl restart secure-tunnel-xray
EOF
```

🔍 故障排查

常见问题

1. 安装失败

```bash
# 检查系统依赖
./secure_tunnel.sh --check-deps

# 查看详细错误日志
sudo journalctl -xe | tail -50
```

2. 连接失败

```bash
# 测试域名连通性
curl -v https://优选域名/cdn-cgi/trace

# 检查端口监听
sudo netstat -tlnp | grep xray
```

3. 优选域名失效

```bash
# 手动指定域名
echo 'DOMAIN_IPV4="speed.cloudflare.com"' > /etc/secure_tunnel/optimized_domains.conf
sudo systemctl restart secure-tunnel-xray
```

调试模式

```bash
# 启用调试输出
DEBUG=1 ./secure_tunnel.sh install

# 查看详细日志
sudo journalctl -u secure-tunnel-xray -f -o cat
```

📈 性能优化

调整测试参数

```bash
# 在脚本开头修改以下参数：
CF_TEST_COUNT=2      # 减少测试次数（更快）
CF_TIMEOUT=1         # 缩短超时时间（更严格）
CACHE_EXPIRE=7200    # 延长缓存时间（2小时）
```

添加自定义域名

```bash
# 编辑脚本中的 CF_TEST_DOMAINS 数组
CF_TEST_DOMAINS=(
    "your-custom-domain.com"
    "icook.hk"
    # ... 其他域名
)
```

多区域优选

```bash
# 针对不同地区使用不同域名列表
if [[ "$(curl -s ipinfo.io/country)" == "CN" ]]; then
    CF_TEST_DOMAINS=("国内优化域名列表")
else
    CF_TEST_DOMAINS=("国际域名列表")
fi
```

🤝 贡献指南

报告问题

1. 查看现有 Issues
2. 创建新 Issue，包含：
   · 操作系统版本
   · 脚本版本
   · 错误日志
   · 复现步骤

提交改进

1. Fork 仓库
2. 创建功能分支
3. 提交更改
4. 创建 Pull Request

📄 许可证

MIT License - 详见 LICENSE 文件

🆘 技术支持

官方文档

· Cloudflare Tunnel 文档
· Xray-core 文档

社区支持

· GitHub Issues: 问题反馈
· Telegram 群组: 实时交流
· Discord 频道: 技术讨论

紧急恢复

```bash
# 如果服务完全损坏
cd /tmp
curl -O https://raw.githubusercontent.com/your-repo/secure-tunnel/main/secure_tunnel.sh
chmod +x secure_tunnel.sh
sudo ./secure_tunnel.sh uninstall
sudo ./secure_tunnel.sh install
```

---

最后更新: 2024年12月
版本: v2.1
作者: Q
兼容性: Ubuntu 20.04+, Debian 10+, CentOS 8+

💡 提示：生产环境部署前，请在测试环境充分验证配置。
