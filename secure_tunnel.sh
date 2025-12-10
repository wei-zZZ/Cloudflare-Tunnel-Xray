#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本 (Root版)
# 版本: 4.0 - 支持手动浏览器授权
# ============================================

set -e

# ----------------------------
# 颜色输出
# ----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }
print_input() { echo -e "${CYAN}[?]${NC} $1"; }

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/secure_tunnel"
DATA_DIR="/var/lib/secure_tunnel"
LOG_DIR="/var/log/secure_tunnel"
BIN_DIR="/usr/local/bin"
SERVICE_USER="secure_tunnel"
SERVICE_GROUP="secure_tunnel"

# 用户输入变量
USER_DOMAIN=""
TUNNEL_NAME="secure-tunnel"

# ----------------------------
# 收集用户信息
# ----------------------------
collect_user_info() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 安装脚本                ║"
    echo "║                版本 4.0                      ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    
    # 获取域名
    while [[ -z "$USER_DOMAIN" ]]; do
        print_input "请输入您的域名 (例如: tunnel.yourdomain.com):"
        read -r USER_DOMAIN
        
        if [[ -z "$USER_DOMAIN" ]]; then
            print_error "域名不能为空！"
        elif ! [[ "$USER_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "域名格式不正确，请重新输入！"
            USER_DOMAIN=""
        fi
    done
    
    # 获取隧道名称
    print_input "请输入隧道名称 [默认: secure-tunnel]:"
    read -r TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"secure-tunnel"}
    
    # 显示汇总信息
    echo ""
    print_info "配置摘要:"
    echo "  ┌─────────────────────────────────────┐"
    echo "  │   域名: $USER_DOMAIN"
    echo "  │   隧道名称: $TUNNEL_NAME"
    echo "  └─────────────────────────────────────┘"
    echo ""
    
    print_input "确认以上配置是否正确？(y/N):"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_error "安装已取消"
        exit 0
    fi
}

# ----------------------------
# 系统检查
# ----------------------------
check_system() {
    print_info "检查系统环境..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    # 检查必要工具
    local required_tools=("curl" "unzip" "wget")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "安装 $tool..."
            apt-get update && apt-get install -y "$tool" || {
                print_error "无法安装 $tool"
                exit 1
            }
        fi
    done
    
    print_success "系统检查完成"
}

# ----------------------------
# 安装组件
# ----------------------------
install_components() {
    print_info "安装必要组件..."
    
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64|amd64)
            local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
            local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
            local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    # 下载并安装 Xray
    print_info "下载 Xray..."
    wget -q --show-progress -O /tmp/xray.zip "$xray_url"
    unzip -q -d /tmp /tmp/xray.zip
    find /tmp -name "xray" -type f -exec mv {} "$BIN_DIR/" \;
    chmod +x "$BIN_DIR/xray"
    
    # 下载并安装 cloudflared
    print_info "下载 cloudflared..."
    wget -q --show-progress -O "$BIN_DIR/cloudflared" "$cf_url"
    chmod +x "$BIN_DIR/cloudflared"
    
    # 清理临时文件
    rm -f /tmp/xray.zip
    
    print_success "组件安装完成"
}

# ----------------------------
# 手动浏览器授权
# ----------------------------
manual_cloudflare_auth() {
    print_warning "═══════════════════════════════════════════════"
    print_warning "    需要手动完成 Cloudflare 授权"
    print_warning "═══════════════════════════════════════════════"
    echo ""
    
    # 生成授权URL
    print_info "请按照以下步骤操作："
    echo ""
    print_info "1. 在您的电脑浏览器中访问以下链接："
    echo ""
    
    # 使用cloudflared生成授权URL
    local auth_url
    auth_url=$("$BIN_DIR/cloudflared" tunnel login 2>&1 | grep -o 'https://[^ ]*' | head -1)
    
    if [[ -z "$auth_url" ]]; then
        # 如果无法获取URL，使用备用方法
        print_warning "无法自动获取授权链接，请手动运行以下命令获取："
        echo ""
        echo "  $BIN_DIR/cloudflared tunnel login"
        echo ""
        print_input "请按回车键继续，然后在新的终端中手动获取授权URL..."
        read -r
    else
        echo "    $auth_url"
        echo ""
        print_info "2. 在浏览器中登录您的Cloudflare账户并授权"
        print_info "3. 授权成功后返回此处继续"
        echo ""
        
        # 尝试打开浏览器（如果是在桌面环境）
        if [[ -n "$DISPLAY" ]] && command -v xdg-open &> /dev/null; then
            print_input "是否尝试自动打开浏览器？(Y/n):"
            read -r open_browser
            if [[ "$open_browser" != "n" && "$open_browser" != "N" ]]; then
                xdg-open "$auth_url" 2>/dev/null &
            fi
        fi
    fi
    
    print_input "请在浏览器完成授权后，按回车键继续安装..."
    read -r
    
    # 验证授权是否成功
    if [[ ! -d "/root/.cloudflared" ]] || [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "未检测到授权成功！"
        print_error "请检查是否已完成浏览器授权，或手动运行："
        echo ""
        echo "  $BIN_DIR/cloudflared tunnel login"
        echo ""
        print_input "手动完成后按回车键继续..."
        read -r
    fi
    
    print_success "Cloudflare 授权完成"
}

# ----------------------------
# 创建隧道和配置
# ----------------------------
setup_tunnel() {
    print_info "设置 Cloudflare Tunnel..."
    
    # 创建隧道
    print_info "创建隧道: $TUNNEL_NAME"
    "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"
    
    # 绑定域名
    print_info "绑定域名: $USER_DOMAIN"
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN"
    
    # 获取隧道ID
    local tunnel_id
    tunnel_id=$("$BIN_DIR/cloudflared" tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -n "$tunnel_id" ]]; then
        # 保存隧道配置
        mkdir -p "$CONFIG_DIR"
        echo "TUNNEL_ID=$tunnel_id" > "$CONFIG_DIR/tunnel.conf"
        echo "TUNNEL_NAME=$TUNNEL_NAME" >> "$CONFIG_DIR/tunnel.conf"
        echo "DOMAIN=$USER_DOMAIN" >> "$CONFIG_DIR/tunnel.conf"
        
        print_success "隧道设置完成 (ID: ${tunnel_id:0:8}...)"
    else
        print_error "无法获取隧道ID，请检查隧道是否创建成功"
        exit 1
    fi
}

# ----------------------------
# 配置 Xray
# ----------------------------
configure_xray() {
    print_info "配置 Xray..."
    
    # 生成UUID和端口
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=10000  # 固定端口，便于管理
    
    # 保存到配置文件
    echo "UUID=$uuid" >> "$CONFIG_DIR/tunnel.conf"
    echo "PORT=$port" >> "$CONFIG_DIR/tunnel.conf"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # 生成Xray配置文件
    cat > "$CONFIG_DIR/xray.json" << EOF
{
    "log": {
        "loglevel": "warning",
        "access": "$LOG_DIR/xray-access.log",
        "error": "$LOG_DIR/xray-error.log"
    },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "vless",
        "settings": {
            "clients": [{
                "id": "$uuid",
                "flow": ""
            }],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
                "path": "/$uuid"
            }
        }
    }],
    "outbounds": [{
        "protocol": "freedom",
        "settings": {}
    }]
}
EOF
    
    # 创建隧道配置文件
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: /root/.cloudflared/$tunnel_id.json

ingress:
  - hostname: $USER_DOMAIN
    service: http://localhost:$port
  - service: http_status:404
EOF
    
    print_success "Xray 配置完成"
}

# ----------------------------
# 配置系统服务
# ----------------------------
configure_services() {
    print_info "配置系统服务..."
    
    # 创建专用用户（用于运行服务）
    if ! id -u "$SERVICE_USER" &> /dev/null; then
        useradd -r -s /usr/sbin/nologin "$SERVICE_USER"
    fi
    
    # 转移文件所有权
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # Xray 服务文件
    cat > /etc/systemd/system/secure-tunnel-xray.service << EOF
[Unit]
Description=Secure Tunnel Xray Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$BIN_DIR/xray run -config $CONFIG_DIR/xray.json
Restart=on-failure
RestartSec=3
StandardOutput=append:$LOG_DIR/xray.log
StandardError=append:$LOG_DIR/xray-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Argo Tunnel 服务文件
    cat > /etc/systemd/system/secure-tunnel-argo.service << EOF
[Unit]
Description=Secure Tunnel Argo Service
After=network.target secure-tunnel-xray.service
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=on-failure
RestartSec=5
StandardOutput=append:$LOG_DIR/argo.log
StandardError=append:$LOG_DIR/argo-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd
    systemctl daemon-reload
    
    print_success "系统服务配置完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    # 启动Xray
    systemctl enable secure-tunnel-xray.service
    if systemctl start secure-tunnel-xray.service; then
        print_success "Xray 服务启动成功"
    else
        print_error "Xray 服务启动失败"
        journalctl -u secure-tunnel-xray.service -n 10 --no-pager
    fi
    
    # 启动Argo Tunnel
    systemctl enable secure-tunnel-argo.service
    if systemctl start secure-tunnel-argo.service; then
        print_success "Argo Tunnel 服务启动成功"
    else
        print_error "Argo Tunnel 服务启动失败"
        journalctl -u secure-tunnel-argo.service -n 10 --no-pager
    fi
    
    # 等待服务稳定
    sleep 2
}

# ----------------------------
# 显示连接信息
# ----------------------------
show_connection_info() {
    print_info "═══════════════════════════════════════════════"
    print_info "           安装完成！连接信息"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 读取配置
    source "$CONFIG_DIR/tunnel.conf" 2>/dev/null
    
    print_success "域名: $DOMAIN"
    print_success "UUID: $UUID"
    print_success "端口: 443 (TLS) / 80 (非TLS)"
    print_success "路径: /$UUID"
    echo ""
    
    print_info "VLESS 连接配置:"
    echo ""
    echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/${UUID}#安全隧道"
    echo ""
    
    print_info "服务管理命令:"
    echo "  启动: systemctl start secure-tunnel-{xray,argo}"
    echo "  停止: systemctl stop secure-tunnel-{xray,argo}"
    echo "  状态: systemctl status secure-tunnel-{xray,argo}"
    echo "  日志: journalctl -u secure-tunnel-argo.service -f"
    echo ""
    
    print_info "配置文件位置:"
    echo "  Xray配置: $CONFIG_DIR/xray.json"
    echo "  隧道配置: $CONFIG_DIR/config.yaml"
    echo "  连接信息: $CONFIG_DIR/tunnel.conf"
    echo ""
    
    print_warning "重要提示:"
    print_warning "1. 请等待几分钟让DNS生效"
    print_warning "2. 在Cloudflare DNS中确认 $DOMAIN 已正确解析"
    print_warning "3. 首次连接可能需要等待证书签发"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    print_info "开始安装流程..."
    
    # 收集用户信息
    collect_user_info
    
    # 执行安装步骤
    check_system
    install_components
    manual_cloudflare_auth
    setup_tunnel
    configure_xray
    configure_services
    start_services
    show_connection_info
    
    echo ""
    print_success "🎉 安装全部完成！"
    print_info "请使用上面的VLESS链接配置您的客户端。"
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 一键安装脚本            ║"
    echo "║                版本4.0 (Root版)             ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    
    case "${1:-}" in
        "install")
            main_install
            ;;
        "status")
            systemctl status secure-tunnel-xray.service secure-tunnel-argo.service --no-pager
            ;;
        "restart")
            systemctl restart secure-tunnel-xray.service secure-tunnel-argo.service
            print_success "服务已重启"
            ;;
        "uninstall")
            print_warning "正在卸载..."
            systemctl stop secure-tunnel-xray.service secure-tunnel-argo.service 2>/dev/null || true
            systemctl disable secure-tunnel-xray.service secure-tunnel-argo.service 2>/dev/null || true
            rm -f /etc/systemd/system/secure-tunnel-*.service
            systemctl daemon-reload
            rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
            userdel "$SERVICE_USER" 2>/dev/null || true
            print_success "卸载完成"
            ;;
        "config")
            if [[ -f "$CONFIG_DIR/tunnel.conf" ]]; then
                print_info "当前配置:"
                cat "$CONFIG_DIR/tunnel.conf"
            else
                print_error "未找到配置文件"
            fi
            ;;
        *)
            echo "使用方法:"
            echo "  sudo $0 install    # 安装"
            echo "  sudo $0 status     # 查看状态"
            echo "  sudo $0 restart    # 重启服务"
            echo "  sudo $0 config     # 查看配置"
            echo "  sudo $0 uninstall  # 卸载"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"