#!/bin/bash
# ============================================
# X-UI + Cloudflare Tunnel 一键安装脚本
# 简洁稳定版
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
CONFIG_DIR="/etc/xui_tunnel"
LOG_DIR="/var/log/xui_tunnel"
BIN_DIR="/usr/local/bin"
SERVICE_NAME="xui-tunnel"

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    X-UI + Cloudflare Tunnel 一键安装        ║"
    echo "║             简洁稳定版                       ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
}

# ----------------------------
# 检查系统
# ----------------------------
check_system() {
    print_info "检查系统..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行"
        exit 1
    fi
    
    # 安装基础工具
    apt-get update -y
    apt-get install -y curl wget jq 2>/dev/null || true
}

# ----------------------------
# 安装 X-UI
# ----------------------------
install_xui() {
    print_info "安装 X-UI 面板..."
    
    if command -v x-ui &> /dev/null; then
        print_warning "X-UI 已安装"
        return 0
    fi
    
    curl -L -o x-ui-install.sh https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh
    chmod +x x-ui-install.sh
    bash x-ui-install.sh
    rm -f x-ui-install.sh
    
    # 等待启动
    for i in {1..10}; do
        if systemctl is-active --quiet x-ui; then
            print_success "X-UI 启动成功"
            return 0
        fi
        sleep 2
    done
    
    print_warning "X-UI 启动较慢，继续安装..."
}

# ----------------------------
# 安装 Cloudflared
# ----------------------------
install_cloudflared() {
    print_info "安装 Cloudflared..."
    
    if command -v cloudflared &> /dev/null; then
        print_warning "cloudflared 已安装"
        return 0
    fi
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)
            print_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    curl -L -o /tmp/cloudflared "$URL"
    mv /tmp/cloudflared "$BIN_DIR/cloudflared"
    chmod +x "$BIN_DIR/cloudflared"
    print_success "cloudflared 安装成功"
}

# ----------------------------
# 获取用户输入
# ----------------------------
get_user_input() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           配置信息"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 域名
    while true; do
        print_input "请输入面板访问域名 (例如: hk2xui.9420ce.top):"
        read -r DOMAIN
        
        if [[ -z "$DOMAIN" ]]; then
            print_error "域名不能为空"
            continue
        fi
        
        if [[ "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "域名格式错误"
        fi
    done
    
    # 隧道名称
    print_input "隧道名称 [默认: xui-tunnel]:"
    read -r TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"xui-tunnel"}
    
    echo ""
    print_success "配置确认:"
    echo "  域名: $DOMAIN"
    echo "  隧道: $TUNNEL_NAME"
    echo ""
}

# ----------------------------
# Cloudflare 授权
# ----------------------------
cloudflare_auth() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "        Cloudflare 授权"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    rm -rf /root/.cloudflared 2>/dev/null || true
    mkdir -p /root/.cloudflared
    
    echo "请按以下步骤操作："
    echo "1. 复制下面的链接到浏览器"
    echo "2. 登录 Cloudflare 账户"
    echo "3. 选择域名并授权"
    echo "4. 返回终端继续"
    echo ""
    read -p "按回车开始授权..." -r
    
    echo ""
    echo "=============================================="
    echo "授权链接:"
    echo ""
    
    "$BIN_DIR/cloudflared" tunnel login
    
    echo ""
    echo "=============================================="
    read -p "完成授权后按回车继续..." -r
    
    # 验证授权
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "授权成功"
        return 0
    else
        print_error "授权失败"
        return 1
    fi
}

# ----------------------------
# 创建隧道
# ----------------------------
create_tunnel() {
    print_info "创建隧道: $TUNNEL_NAME"
    
    # 清理旧隧道
    "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"
    sleep 3
    
    # 获取隧道ID
    TUNNEL_INFO=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || true)
    
    if [[ -z "$TUNNEL_INFO" ]]; then
        print_error "隧道创建失败"
        return 1
    fi
    
    TUNNEL_ID=$(echo "$TUNNEL_INFO" | awk '{print $1}')
    print_success "隧道创建成功: $TUNNEL_ID"
    
    # 获取凭证文件
    CREDENTIALS_FILE=$(find /root/.cloudflared -name "*.json" -type f | head -1)
    
    if [[ -z "$CREDENTIALS_FILE" ]] || [[ ! -f "$CREDENTIALS_FILE" ]]; then
        print_error "未找到凭证文件"
        return 1
    fi
    
    print_success "使用凭证文件: $(basename "$CREDENTIALS_FILE")"
    
    # 绑定域名
    print_info "绑定域名到隧道..."
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>/dev/null || {
        print_warning "DNS绑定可能需要手动配置"
    }
    
    return 0
}

# ----------------------------
# 创建配置文件
# ----------------------------
create_config() {
    print_info "创建配置文件..."
    
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    # 创建配置文件
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
DOMAIN=$DOMAIN
TUNNEL_NAME=$TUNNEL_NAME
TUNNEL_ID=$TUNNEL_ID
CREDENTIALS_FILE=$CREDENTIALS_FILE
EOF
    
    # 创建 YAML 配置 - 极简版本
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE
logfile: $LOG_DIR/cloudflared.log
ingress:
  - hostname: $DOMAIN
    service: http://localhost:54321
  - service: http_status:404
EOF
    
    print_success "配置文件创建完成"
}

# ----------------------------
# 创建系统服务
# ----------------------------
create_service() {
    print_info "创建系统服务..."
    
    cat > /etc/systemd/system/$SERVICE_NAME.service << 'EOF'
[Unit]
Description=X-UI Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/xui_tunnel/config.yaml run
Restart=always
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "系统服务创建完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_service() {
    print_info "启动服务..."
    
    # 启动X-UI
    systemctl start x-ui
    sleep 2
    
    # 启动隧道
    systemctl enable $SERVICE_NAME.service
    systemctl start $SERVICE_NAME.service
    
    sleep 3
    
    # 检查状态
    if systemctl is-active --quiet $SERVICE_NAME.service; then
        print_success "✅ 隧道服务启动成功"
    else
        print_error "❌ 隧道服务启动失败"
        echo ""
        print_info "查看日志: journalctl -u $SERVICE_NAME.service -n 20 --no-pager"
        return 1
    fi
    
    return 0
}

# ----------------------------
# 显示结果
# ----------------------------
show_result() {
    echo ""
    print_success "═══════════════════════════════════════════════"
    print_success "           安装完成！"
    print_success "═══════════════════════════════════════════════"
    echo ""
    
    print_success "🎉 面板访问地址:"
    print_success "   https://$DOMAIN"
    echo ""
    
    print_success "🔐 默认登录凭据:"
    print_success "   用户名: admin"
    print_success "   密码: admin"
    echo ""
    
    print_info "🛠️  管理命令:"
    echo "  状态: systemctl status $SERVICE_NAME"
    echo "  重启: systemctl restart $SERVICE_NAME"
    echo "  停止: systemctl stop $SERVICE_NAME"
    echo "  日志: journalctl -u $SERVICE_NAME -f"
    echo ""
    
    print_info "📋 节点配置说明:"
    echo "  1. 访问 https://$DOMAIN 登录X-UI"
    echo "  2. 创建入站节点，使用端口: 10000-20000"
    echo "  3. 客户端连接: $DOMAIN:443"
    echo "  4. 协议: VLESS/VMESS/Trojan + WS + TLS"
    echo ""
    
    print_warning "⚠️  重要提示:"
    echo "  1. 首次登录后立即修改密码"
    echo "  2. 确保域名已解析到Cloudflare"
    echo "  3. 如果无法访问，等待DNS生效"
    echo ""
}

# ----------------------------
# 快速修复
# ----------------------------
quick_fix() {
    echo ""
    print_info "快速修复..."
    
    systemctl stop $SERVICE_NAME.service 2>/dev/null || true
    pkill -f cloudflared 2>/dev/null || true
    sleep 2
    
    # 重新创建配置文件
    if [ -f "$CONFIG_DIR/tunnel.conf" ]; then
        source "$CONFIG_DIR/tunnel.conf"
        
        cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE
logfile: $LOG_DIR/cloudflared.log
ingress:
  - hostname: $DOMAIN
    service: http://localhost:54321
  - service: http_status:404
EOF
        print_success "配置文件已修复"
    fi
    
    systemctl daemon-reload
    systemctl restart $SERVICE_NAME.service
    
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME.service; then
        print_success "✅ 修复成功"
    else
        print_error "❌ 修复失败"
        journalctl -u $SERVICE_NAME.service -n 20 --no-pager
    fi
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    show_title
    
    check_system
    get_user_input
    install_xui
    install_cloudflared
    
    if ! cloudflare_auth; then
        print_error "授权失败，安装中止"
        return 1
    fi
    
    if ! create_tunnel; then
        print_error "隧道创建失败"
        return 1
    fi
    
    create_config
    create_service
    
    if ! start_service; then
        print_error "服务启动失败"
        return 1
    fi
    
    show_result
    return 0
}

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    show_title
    
    echo "请选择操作："
    echo ""
    echo "  1) 一键安装"
    echo "  2) 快速修复"
    echo "  3) 查看状态"
    echo "  4) 重启服务"
    echo "  5) 卸载"
    echo "  6) 退出"
    echo ""
    
    print_input "请输入选项 (1-6): "
    read -r choice
    
    case "$choice" in
        1)
            if main_install; then
                read -p "按回车返回菜单..." -r
            fi
            ;;
        2)
            quick_fix
            read -p "按回车返回菜单..." -r
            ;;
        3)
            echo ""
            systemctl status x-ui --no-pager | head -10
            echo ""
            systemctl status $SERVICE_NAME.service --no-pager | head -10
            echo ""
            read -p "按回车返回菜单..." -r
            ;;
        4)
            systemctl restart $SERVICE_NAME.service
            print_success "服务已重启"
            read -p "按回车返回菜单..." -r
            ;;
        5)
            echo ""
            print_warning "卸载隧道服务..."
            systemctl stop $SERVICE_NAME.service 2>/dev/null || true
            systemctl disable $SERVICE_NAME.service 2>/dev/null || true
            rm -f /etc/systemd/system/$SERVICE_NAME.service
            systemctl daemon-reload
            print_success "已卸载"
            read -p "按回车返回菜单..." -r
            ;;
        6)
            print_info "再见！"
            exit 0
            ;;
        *)
            print_error "无效选项"
            sleep 1
            show_menu
            ;;
    esac
    
    show_menu
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行"
        exit 1
    fi
    
    case "${1:-}" in
        "install")
            main_install
            ;;
        "fix")
            quick_fix
            ;;
        "status")
            show_title
            systemctl status x-ui --no-pager
            echo ""
            systemctl status $SERVICE_NAME.service --no-pager
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo ./xui.sh menu        # 显示菜单"
            echo "  sudo ./xui.sh install     # 安装"
            echo "  sudo ./xui.sh fix         # 修复"
            echo "  sudo ./xui.sh status      # 状态"
            exit 1
            ;;
    esac
}

main "$@"