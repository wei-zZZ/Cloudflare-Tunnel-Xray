#!/bin/bash
# ====================================================
# Cloudflare Tunnel 管理脚本
# 版本: 1.0 - 安装 + 状态查看 + 卸载
# ====================================================
set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置路径
CONFIG_DIR="/etc/cf_tunnel"
CERT_DIR="/root/.cloudflared"

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    clear
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗"
    echo "║      Cloudflare Tunnel 管理脚本           ║"
    echo "╚═══════════════════════════════════════════════╝${NC}"
    echo ""
    echo "1. 安装 Cloudflare Tunnel + X-UI"
    echo "2. 查看运行状态"
    echo "3. 完全卸载"
    echo "4. 退出"
    echo ""
    echo -n "请选择 (1-4): "
}

# ----------------------------
# 安装功能
# ----------------------------
install_cf() {
    clear
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗"
    echo "║             安装 Cloudflare Tunnel           ║"
    echo "╚═══════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 1. 获取域名
    echo -e "${BLUE}[1/8] 设置域名${NC}"
    echo ""
    while true; do
        echo -n "请输入域名 (如: tunnel.yourdomain.com): "
        read DOMAIN
        if [[ -n "$DOMAIN" ]]; then
            break
        fi
        echo -e "${RED}域名不能为空${NC}"
    done
    
    TUNNEL_NAME="cf-$(date +%Y%m%d-%H%M%S)"
    echo -e "${CYAN}隧道名称: ${TUNNEL_NAME}${NC}"
    
    echo ""
    echo -e "${CYAN}预设协议：${NC}"
    echo "----------------------------------------"
    echo "1. VLESS - 端口: 20001, 路径: /vless"
    echo "2. VMESS - 端口: 20002, 路径: /vmess"
    echo "3. TROJAN - 端口: 20003, 路径: /trojan"
    echo "----------------------------------------"
    echo ""
    read -p "按回车继续..." -r
    
    # 2. 系统检查
    echo ""
    echo -e "${BLUE}[2/8] 系统准备${NC}"
    
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}请使用 sudo 运行此脚本${NC}"
        exit 1
    fi
    
    echo "更新软件包..."
    apt-get update -qq > /dev/null
    echo "安装必要工具..."
    apt-get install -y -qq curl wget > /dev/null 2>&1
    echo -e "${GREEN}✓ 系统准备完成${NC}"
    
    # 3. 安装 cloudflared
    echo ""
    echo -e "${BLUE}[3/8] 安装 cloudflared${NC}"
    
    if command -v cloudflared &> /dev/null; then
        echo -e "${CYAN}cloudflared 已安装${NC}"
    else
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
    
    # 4. 🎯 授权步骤
    echo ""
    echo -e "${BLUE}[4/8] 🎯 获取授权链接${NC}"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}         重要：现在请新开一个 SSH 窗口        ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
    echo ""
    echo "在新窗口中运行："
    echo -e "${CYAN}    cloudflared tunnel login${NC}"
    echo ""
    echo "步骤："
    echo "1. 新开SSH连接到服务器"
    echo "2. 运行上面的命令"
    echo "3. 复制链接到浏览器授权"
    echo "4. 选择域名: ${DOMAIN}"
    echo "5. 点击「Authorize」"
    echo "6. 授权成功后返回这里"
    echo ""
    echo -e "${YELLOW}注意：不要关闭这个窗口！${NC}"
    echo ""
    read -p "授权完成后按回车继续..." -r
    
    # 检查授权
    echo ""
    echo "检查授权结果..."
    sleep 3
    
    if [ -d "$CERT_DIR" ] && ls "$CERT_DIR"/*.json 1> /dev/null 2>&1; then
        CERT_FILE=$(ls -t "$CERT_DIR"/*.json | head -1)
        echo -e "${GREEN}✓ 授权成功！${NC}"
        echo -e "${CYAN}证书文件: $(basename "$CERT_FILE")${NC}"
    else
        echo -e "${RED}✗ 未找到证书文件${NC}"
        echo "请检查是否完成授权"
        read -p "按回车继续（风险）或 Ctrl+C 取消..." -r
    fi
    
    # 5. 创建隧道
    echo ""
    echo -e "${BLUE}[5/8] 创建隧道${NC}"
    
    echo "获取隧道信息..."
    TUNNEL_INFO=$(cloudflared tunnel list 2>/dev/null || echo "")
    
    if [ -n "$TUNNEL_INFO" ]; then
        TUNNEL_ID=$(echo "$TUNNEL_INFO" | grep -o '[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}' | head -1)
        echo -e "${CYAN}使用现有隧道: $TUNNEL_ID${NC}"
    else
        echo "创建新隧道: $TUNNEL_NAME"
        cloudflared tunnel create "$TUNNEL_NAME" > /tmp/tunnel_create.log 2>&1 || true
        sleep 2
        
        CERT_FILE=$(ls -t "$CERT_DIR"/*.json 2>/dev/null | head -1)
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
    
    # 6. 生成配置
    echo ""
    echo -e "${BLUE}[6/8] 生成配置${NC}"
    
    # 生成UUID和密码
    VLESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "请手动生成")
    VMESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "请手动生成")
    TROJAN_PASS=$(head -c 12 /dev/urandom | base64 | tr -d '\n' | cut -c1-16)
    
    # 创建目录
    mkdir -p "$CONFIG_DIR"
    
    # 保存配置信息
    cat > "$CONFIG_DIR/install_info.txt" << EOF
安装时间: $(date)
域名: $DOMAIN
隧道名称: $TUNNEL_NAME
隧道ID: $TUNNEL_ID

代理配置:
1. VLESS:
   端口: 20001
   路径: /vless
   UUID: $VLESS_UUID

2. VMESS:
   端口: 20002
   路径: /vmess
   UUID: $VMESS_UUID

3. TROJAN:
   端口: 20003
   路径: /trojan
   密码: $TROJAN_PASS
EOF
    
    # 生成 config.yml
    cat > "$CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CERT_DIR/$TUNNEL_ID.json

ingress:
  - hostname: $DOMAIN
    path: /vless
    service: http://127.0.0.1:20001
  
  - hostname: $DOMAIN
    path: /vmess
    service: http://127.0.0.1:20002
  
  - hostname: $DOMAIN
    path: /trojan
    service: http://127.0.0.1:20003
  
  - service: http_status:404
EOF
    
    echo -e "${GREEN}✓ 配置生成完成${NC}"
    
    # 7. 安装 X-UI（优化版）
    echo ""
    echo -e "${BLUE}[7/8] 安装 X-UI 面板${NC}"
    
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        echo -e "${CYAN}X-UI 已安装，跳过${NC}"
    else
        echo "下载 X-UI 安装脚本..."
        
        # 使用更稳定的安装方式
        XUI_SCRIPT="/tmp/xui_install.sh"
        
        # 尝试多个镜像源
        MIRRORS=(
            "https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh"
            "https://cdn.jsdelivr.net/gh/vaxilu/x-ui@master/install.sh"
            "https://ghproxy.com/https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh"
        )
        
        for mirror in "${MIRRORS[@]}"; do
            echo "尝试从镜像下载: $mirror"
            if curl -fsSL -o "$XUI_SCRIPT" "$mirror"; then
                echo "下载成功"
                break
            fi
        done
        
        if [ ! -f "$XUI_SCRIPT" ]; then
            echo -e "${YELLOW}! 无法下载X-UI安装脚本${NC}"
            echo "请手动安装: bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)"
            read -p "按回车继续（跳过X-UI）..." -r
        else
            chmod +x "$XUI_SCRIPT"
            echo "开始安装 X-UI（可能需要几分钟）..."
            
            # 后台安装，避免卡住
            bash "$XUI_SCRIPT" > /tmp/xui_install.log 2>&1 &
            XUI_PID=$!
            
            # 显示进度
            echo -n "安装中"
            for i in {1..30}; do
                if ! ps -p $XUI_PID > /dev/null 2>&1; then
                    break
                fi
                echo -n "."
                sleep 2
            done
            echo ""
            
            # 检查安装结果
            sleep 5
            if systemctl is-active --quiet x-ui; then
                echo -e "${GREEN}✓ X-UI 安装成功${NC}"
            else
                echo -e "${YELLOW}! X-UI 可能需要手动启动${NC}"
                echo "查看日志: cat /tmp/xui_install.log"
            fi
        fi
    fi
    
    # 8. 创建并启动服务
    echo ""
    echo -e "${BLUE}[8/8] 创建服务${NC}"
    
    cat > /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config $CONFIG_DIR/config.yml run
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
    
    if systemctl is-active --quiet cloudflared.service; then
        echo -e "${GREEN}✓ 服务启动成功${NC}"
    else
        echo -e "${YELLOW}! 服务启动失败${NC}"
        echo "查看状态: systemctl status cloudflared.service"
    fi
    
    # 显示安装结果
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}             安装完成！                       ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    
    SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo -e "${CYAN}▸ 连接信息：${NC}"
    echo "  域名: $DOMAIN"
    echo "  服务器IP: $SERVER_IP"
    echo ""
    
    echo -e "${CYAN}▸ X-UI 面板：${NC}"
    echo "  http://$SERVER_IP:54321"
    echo "  账号: admin"
    echo "  密码: admin"
    echo ""
    
    echo -e "${CYAN}▸ 配置文件：${NC}"
    echo "  $CONFIG_DIR/install_info.txt"
    echo ""
    
    echo -e "${YELLOW}▸ 必须完成：${NC}"
    echo "  1. 访问面板修改默认密码"
    echo "  2. 添加3个入站规则"
    echo "  3. 客户端开启TLS"
    echo ""
    
    read -p "按回车返回菜单..." -r
}

# ----------------------------
# 查看状态功能
# ----------------------------
show_status() {
    clear
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗"
    echo "║             查看运行状态               ║"
    echo "╚═══════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}1. 服务状态：${NC}"
    echo "----------------------------------------"
    
    # cloudflared 状态
    if systemctl is-active --quiet cloudflared.service 2>/dev/null; then
        echo -e "${GREEN}✓ cloudflared: 运行中${NC}"
        echo "  最近日志:"
        journalctl -u cloudflared.service -n 3 --no-pager 2>/dev/null | tail -3 || echo "  无日志"
    else
        echo -e "${RED}✗ cloudflared: 未运行${NC}"
    fi
    echo ""
    
    # X-UI 状态
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        echo -e "${GREEN}✓ x-ui: 运行中${NC}"
    else
        echo -e "${RED}✗ x-ui: 未运行${NC}"
    fi
    echo ""
    
    echo -e "${CYAN}2. 隧道信息：${NC}"
    echo "----------------------------------------"
    if command -v cloudflared &> /dev/null; then
        cloudflared tunnel list 2>/dev/null || echo "  无法获取隧道列表"
    else
        echo "  cloudflared 未安装"
    fi
    echo ""
    
    echo -e "${CYAN}3. 配置文件：${NC}"
    echo "----------------------------------------"
    if [ -f "$CONFIG_DIR/config.yml" ]; then
        echo -e "${GREEN}✓ config.yml: 存在${NC}"
        echo "  路径: $CONFIG_DIR/config.yml"
        echo "  内容摘要:"
        grep -E "(tunnel:|hostname:|path:)" "$CONFIG_DIR/config.yml" | head -5
    else
        echo -e "${RED}✗ config.yml: 不存在${NC}"
    fi
    echo ""
    
    echo -e "${CYAN}4. 证书文件：${NC}"
    echo "----------------------------------------"
    if [ -d "$CERT_DIR" ]; then
        CERT_COUNT=$(ls "$CERT_DIR"/*.json 2>/dev/null | wc -l)
        if [ "$CERT_COUNT" -gt 0 ]; then
            echo -e "${GREEN}✓ 证书文件: $CERT_COUNT 个${NC}"
            ls "$CERT_DIR"/*.json 2>/dev/null | head -3
        else
            echo -e "${YELLOW}! 证书目录存在但无证书${NC}"
        fi
    else
        echo -e "${RED}✗ 证书目录不存在${NC}"
    fi
    echo ""
    
    echo -e "${CYAN}5. 端口占用：${NC}"
    echo "----------------------------------------"
    PORTS=("20001" "20002" "20003" "54321")
    for port in "${PORTS[@]}"; do
        if ss -tulpn | grep -q ":$port "; then
            echo -e "${GREEN}✓ 端口 $port: 已占用${NC}"
        else
            echo -e "${YELLOW}○ 端口 $port: 空闲${NC}"
        fi
    done
    echo ""
    
    read -p "按回车返回菜单..." -r
}

# ----------------------------
# 卸载功能
# ----------------------------
uninstall_all() {
    clear
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════╗"
    echo "║             完全卸载                   ║"
    echo "╚═══════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  警告：这将删除所有配置文件和服务！${NC}"
    echo ""
    echo "将删除的内容："
    echo "  1. Cloudflare Tunnel 服务"
    echo "  2. X-UI 面板（可选）"
    echo "  3. 所有配置文件"
    echo "  4. 证书文件（可选）"
    echo ""
    
    echo -n "确认要卸载吗？(y/N): "
    read CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "卸载已取消"
        sleep 1
        return
    fi
    
    echo ""
    echo -e "${BLUE}[1/4] 停止服务...${NC}"
    systemctl stop cloudflared.service 2>/dev/null || true
    systemctl stop x-ui 2>/dev/null || true
    sleep 2
    
    echo -e "${BLUE}[2/4] 禁用服务...${NC}"
    systemctl disable cloudflared.service 2>/dev/null || true
    systemctl disable x-ui 2>/dev/null || true
    
    echo -e "${BLUE}[3/4] 删除文件...${NC}"
    
    # 删除服务文件
    rm -f /etc/systemd/system/cloudflared.service
    rm -f /etc/systemd/system/x-ui.service 2>/dev/null
    
    # 删除配置文件
    rm -rf "$CONFIG_DIR" 2>/dev/null
    
    # 删除二进制文件
    rm -f /usr/local/bin/cloudflared
    
    echo ""
    echo -n "是否删除 X-UI 面板？(y/N): "
    read REMOVE_XUI
    if [[ "$REMOVE_XUI" =~ ^[Yy]$ ]]; then
        echo "删除 X-UI..."
        # X-UI 通常有卸载脚本，尝试运行
        if [ -f "/usr/local/x-ui/x-ui.sh" ]; then
            /usr/local/x-ui/x-ui.sh uninstall 2>/dev/null || true
        fi
        rm -rf /etc/x-ui /usr/local/x-ui /root/x-ui 2>/dev/null
    fi
    
    echo ""
    echo -n "是否删除 Cloudflare 证书文件？(y/N): "
    read REMOVE_CERTS
    if [[ "$REMOVE_CERTS" =~ ^[Yy]$ ]]; then
        rm -rf "$CERT_DIR" 2>/dev/null
    fi
    
    echo -e "${BLUE}[4/4] 清理系统...${NC}"
    systemctl daemon-reload
    
    echo ""
    echo -e "${GREEN}✓ 卸载完成！${NC}"
    echo ""
    
    echo "已删除的内容："
    echo "  - Cloudflare Tunnel 服务"
    echo "  - 配置文件目录"
    [[ "$REMOVE_XUI" =~ ^[Yy]$ ]] && echo "  - X-UI 面板"
    [[ "$REMOVE_CERTS" =~ ^[Yy]$ ]] && echo "  - Cloudflare 证书"
    echo ""
    
    read -p "按回车返回菜单..." -r
}

# ----------------------------
# 主程序
# ----------------------------
main() {
    while true; do
        show_menu
        read CHOICE
        
        case $CHOICE in
            1) install_cf ;;
            2) show_status ;;
            3) uninstall_all ;;
            4) 
                echo ""
                echo "退出脚本"
                exit 0
                ;;
            *) 
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 检查是否root运行
if [[ $EUID -ne 0 ]] && [[ "$1" != "status" ]]; then
    echo -e "${RED}请使用 sudo 运行此脚本${NC}"
    exit 1
fi

# 启动主程序
main