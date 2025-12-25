#!/bin/bash
# ====================================================
# Cloudflare Tunnel 核心安装脚本
# 版本: 1.0 - 专注核心，明确提示新窗口获取链接
# ====================================================
set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════╗"
echo "║     Cloudflare Tunnel 核心安装脚本           ║"
echo "║       专注：安装 + 新窗口获取链接            ║"
echo "╚═══════════════════════════════════════════════╝${NC}"
echo ""

# 显示当前时间
echo "开始时间: $(date)"
echo ""

# ----------------------------
# 1. 收集信息
# ----------------------------
echo -e "${BLUE}[1/6] 收集配置信息${NC}"
echo ""

# 域名
while true; do
    echo -n "请输入域名 (如: tunnel.yourdomain.com): "
    read DOMAIN
    if [[ -n "$DOMAIN" ]]; then
        break
    fi
    echo -e "${RED}域名不能为空${NC}"
done

# 隧道名称（自动生成）
TUNNEL_NAME="cf-$(date +%Y%m%d-%H%M%S)"
echo -e "${CYAN}隧道名称: ${TUNNEL_NAME}${NC}"

# 协议配置（固定）
PROTOCOLS=("vless:20001:/vless" "vmess:20002:/vmess" "trojan:20003:/trojan")

echo ""
echo -e "${CYAN}预设协议配置：${NC}"
echo "----------------------------------------"
echo "1. VLESS - 端口: 20001, 路径: /vless"
echo "2. VMESS - 端口: 20002, 路径: /vmess"
echo "3. TROJAN - 端口: 20003, 路径: /trojan"
echo "----------------------------------------"
echo ""

read -p "按回车继续安装..." -r

# ----------------------------
# 2. 系统准备
# ----------------------------
echo ""
echo -e "${BLUE}[2/6] 系统准备${NC}"

# 检查root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请使用 sudo 运行此脚本${NC}"
    exit 1
fi

# 更新并安装工具
echo "更新软件包..."
apt-get update -qq > /dev/null

echo "安装必要工具..."
apt-get install -y -qq curl wget > /dev/null 2>&1

echo -e "${GREEN}✓ 系统准备完成${NC}"

# ----------------------------
# 3. 安装 cloudflared
# ----------------------------
echo ""
echo -e "${BLUE}[3/6] 安装 cloudflared${NC}"

# 检查是否已安装
if command -v cloudflared &> /dev/null; then
    echo -e "${CYAN}cloudflared 已安装，跳过${NC}"
else
    # 根据架构选择
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    else
        echo -e "${RED}不支持的架构: $ARCH${NC}"
        exit 1
    fi
    
    echo "下载 cloudflared..."
    curl -fsSL -o /usr/local/bin/cloudflared "$URL"
    chmod +x /usr/local/bin/cloudflared
    
    echo -e "${GREEN}✓ cloudflared 安装完成${NC}"
fi

# 显示版本
VERSION=$(cloudflared --version 2>/dev/null | head -1 || echo "未知版本")
echo -e "${CYAN}版本: $VERSION${NC}"

# ----------------------------
# 4. 🎯 关键步骤：授权（新窗口获取链接）
# ----------------------------
echo ""
echo -e "${BLUE}[4/6] 🎯 获取授权链接${NC}"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}         重要：现在请新开一个 SSH 窗口        ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""
echo "在新窗口中运行以下命令获取授权链接："
echo ""
echo -e "${CYAN}    cloudflared tunnel login${NC}"
echo ""
echo "操作步骤："
echo "1. 新开一个 SSH 连接到服务器"
echo "2. 运行上面的命令"
echo "3. 复制显示的链接到浏览器"
echo "4. 登录 Cloudflare 账户"
echo "5. 选择域名: ${DOMAIN}"
echo "6. 点击「Authorize」授权"
echo "7. 授权成功后，新窗口会显示成功信息"
echo ""
echo -e "${YELLOW}注意：不要关闭这个窗口！${NC}"
echo "授权完成后返回这里继续..."
echo ""
read -p "授权完成后按回车继续..." -r

# 检查授权结果
echo ""
echo "检查授权结果..."
sleep 3

if [ -d "/root/.cloudflared" ] && ls /root/.cloudflared/*.json 1> /dev/null 2>&1; then
    CERT_FILE=$(ls -t /root/.cloudflared/*.json | head -1)
    echo -e "${GREEN}✓ 授权成功！找到证书文件${NC}"
    echo -e "${CYAN}证书文件: $(basename "$CERT_FILE")${NC}"
else
    echo -e "${RED}✗ 未找到证书文件${NC}"
    echo ""
    echo "可能的原因："
    echo "1. 没有完成授权"
    echo "2. 证书保存在其他位置"
    echo ""
    echo "请检查新窗口是否显示授权成功"
    read -p "按回车继续（风险）或 Ctrl+C 取消..." -r
fi

# ----------------------------
# 5. 创建隧道和配置
# ----------------------------
echo ""
echo -e "${BLUE}[5/6] 创建隧道和配置${NC}"

# 获取隧道ID
echo "获取隧道信息..."
TUNNEL_INFO=$(cloudflared tunnel list 2>/dev/null || echo "")

if [ -n "$TUNNEL_INFO" ]; then
    # 使用现有隧道
    TUNNEL_ID=$(echo "$TUNNEL_INFO" | grep -o '[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}' | head -1)
    echo -e "${CYAN}使用现有隧道: $TUNNEL_ID${NC}"
else
    # 创建新隧道
    echo "创建新隧道: $TUNNEL_NAME"
    cloudflared tunnel create "$TUNNEL_NAME" > /tmp/tunnel_create.log 2>&1 || true
    sleep 2
    
    # 从证书文件获取ID
    CERT_FILE=$(ls -t /root/.cloudflared/*.json 2>/dev/null | head -1)
    if [ -n "$CERT_FILE" ]; then
        TUNNEL_ID=$(basename "$CERT_FILE" .json)
        echo -e "${GREEN}✓ 隧道创建成功: $TUNNEL_ID${NC}"
    else
        echo -e "${RED}✗ 无法获取隧道ID${NC}"
        exit 1
    fi
fi

# 绑定域名
echo "绑定域名到隧道..."
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" > /dev/null 2>&1 || true

# 生成UUID和密码
echo "生成UUID和密码..."
VLESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "请手动生成UUID")
VMESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "请手动生成UUID")
TROJAN_PASS=$(head -c 12 /dev/urandom | base64 | tr -d '\n' | cut -c1-16)

# 创建配置目录
mkdir -p /etc/cf_tunnel

# 生成 config.yml
cat > /etc/cf_tunnel/config.yml << EOF
# Cloudflare Tunnel 配置
# 生成时间: $(date)

tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  # VLESS 代理
  - hostname: $DOMAIN
    path: /vless
    service: http://127.0.0.1:20001
  
  # VMESS 代理
  - hostname: $DOMAIN
    path: /vmess
    service: http://127.0.0.1:20002
  
  # TROJAN 代理
  - hostname: $DOMAIN
    path: /trojan
    service: http://127.0.0.1:20003
  
  # 其他所有流量
  - service: http_status:404
EOF

echo -e "${GREEN}✓ 配置文件生成完成${NC}"

# ----------------------------
# 6. 安装 X-UI
# ----------------------------
echo ""
echo -e "${BLUE}[6/6] 安装 X-UI 面板${NC}"

if systemctl is-active --quiet x-ui 2>/dev/null; then
    echo -e "${CYAN}X-UI 已安装，跳过${NC}"
else
    echo "下载并安装 X-UI..."
    bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh) > /tmp/xui_install.log 2>&1 || true
    
    sleep 5
    
    if systemctl is-active --quiet x-ui; then
        echo -e "${GREEN}✓ X-UI 安装成功${NC}"
    else
        echo -e "${YELLOW}! X-UI 可能需要手动启动${NC}"
    fi
fi

# ----------------------------
# 创建服务
# ----------------------------
echo "创建系统服务..."
cat > /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cf_tunnel/config.yml run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cloudflared.service

echo "启动隧道服务..."
systemctl start cloudflared.service
sleep 3

# ----------------------------
# 显示结果
# ----------------------------
clear
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════╗"
echo "║           安装完成！                         ║"
echo "╚═══════════════════════════════════════════════╝${NC}"
echo ""

# 获取服务器IP
SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' | head -1)

echo -e "${CYAN}▸ 服务器信息：${NC}"
echo "  服务器IP: $SERVER_IP"
echo "  域名: $DOMAIN"
echo "  隧道ID: $TUNNEL_ID"
echo ""

echo -e "${CYAN}▸ 代理配置：${NC}"
echo "  1. VLESS:"
echo "     地址: $DOMAIN"
echo "     端口: 443"
echo "     路径: /vless"
echo "     UUID: $VLESS_UUID"
echo ""

echo "  2. VMESS:"
echo "     地址: $DOMAIN"
echo "     端口: 443"
echo "     路径: /vmess"
echo "     UUID: $VMESS_UUID"
echo ""

echo "  3. TROJAN:"
echo "     地址: $DOMAIN"
echo "     端口: 443"
echo "     路径: /trojan"
echo "     密码: $TROJAN_PASS"
echo ""

echo -e "${CYAN}▸ X-UI 面板：${NC}"
echo "  地址: http://$SERVER_IP:54321"
echo "  账号: admin"
echo "  密码: admin"
echo ""

echo -e "${CYAN}▸ 配置文件位置：${NC}"
echo "  Tunnel配置: /etc/cf_tunnel/config.yml"
echo "  证书文件: /root/.cloudflared/$TUNNEL_ID.json"
echo ""

echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}           必须完成的操作                      ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""
echo "1. 访问 X-UI 面板: http://$SERVER_IP:54321"
echo "2. 立即修改默认密码！"
echo "3. 添加3个入站规则："
echo "   - VLESS: 端口 20001, UUID如上"
echo "   - VMESS: 端口 20002, UUID如上"
echo "   - TROJAN: 端口 20003, 密码如上"
echo "4. 客户端必须开启 TLS"
echo ""

echo -e "${CYAN}▸ 服务管理命令：${NC}"
echo "  查看状态: systemctl status cloudflared"
echo "  重启服务: systemctl restart cloudflared"
echo "  查看日志: journalctl -u cloudflared -f"
echo ""

echo -e "${GREEN}安装完成时间: $(date)${NC}"
echo ""
read -p "按回车退出..." -r