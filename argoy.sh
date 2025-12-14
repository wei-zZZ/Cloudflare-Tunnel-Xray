#!/bin/bash
# ============================================
# Argox Tunnel + Xray 安装脚本
# 版本: 6.1 - 修复版
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
print_auth() { echo -e "${GREEN}[🔐]${NC} $1"; }

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/argox"
DATA_DIR="/var/lib/argox"
LOG_DIR="/var/log/argox"
BIN_DIR="/usr/local/bin"
SERVICE_USER="argox"
SERVICE_GROUP="argox"

USER_DOMAIN=""
TUNNEL_NAME="argox-tunnel"
SILENT_MODE=false

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║     Argox Tunnel + Xray 管理脚本             ║"
    echo "║             版本: 6.1 - 修复版               ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
}

# ----------------------------
# 收集用户信息
# ----------------------------
collect_user_info() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           配置 Argox Tunnel"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    if [ "$SILENT_MODE" = true ]; then
        USER_DOMAIN="tunnel.example.com"
        print_info "静默模式：使用默认域名 $USER_DOMAIN"
        print_info "隧道名称: $TUNNEL_NAME"
        return
    fi
    
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
    
    print_input "请输入隧道名称 [默认: argox-tunnel]:" 
    read -r TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"argox-tunnel"}
    
    echo ""
    print_success "配置已保存:"
    echo "  域名: $USER_DOMAIN"
    echo "  隧道名称: $TUNNEL_NAME"
    echo ""
}

# ----------------------------
# 安装组件（改进版）
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
    
    print_info "下载 Xray..."
    if curl -L -o /tmp/xray.zip "$xray_url"; then
        if unzip -q -o /tmp/xray.zip -d /tmp/; then
            local xray_binary=$(find /tmp -name "xray" -type f | head -1)
            if [[ -n "$xray_binary" ]] && [[ -f "$xray_binary" ]]; then
                mv "$xray_binary" "$BIN_DIR/xray"
                chmod +x "$BIN_DIR/xray"
                print_success "Xray 安装成功"
            else
                print_error "Xray 解压后未找到二进制文件"
                exit 1
            fi
        else
            print_error "Xray 解压失败"
            exit 1
        fi
    else
        print_error "Xray 下载失败"
        exit 1
    fi
    
    print_info "下载 cloudflared..."
    if curl -L -o /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        print_success "cloudflared 安装成功"
    else
        print_error "cloudflared 下载失败"
        exit 1
    fi
    
    rm -rf /tmp/xray* /tmp/cloudflare* 2>/dev/null
    
    print_success "所有组件安装完成"
}

# ----------------------------
# Cloudflare 授权
# ----------------------------
direct_cloudflare_auth() {
    echo ""
    print_info "请进行 Cloudflare Tunnel 授权..."
    print_info "执行以下命令获取凭证："
    echo "cloudflared tunnel login"
    echo ""
    print_input "按 Enter 键继续..."
    read -r
    
    # 检查 cloudflared 是否安装并提供授权命令
    if command -v cloudflared &>/dev/null; then
        print_success "cloudflared 已安装，您可以运行 'cloudflared tunnel login' 来完成授权。"
        
        # 直接运行 cloudflared tunnel login，并捕获输出
        print_info "开始获取授权链接，请稍等..."
        
        # 执行 cloudflared tunnel login 并捕获输出中的授权链接
        AUTH_URL=$(cloudflared tunnel login 2>&1 | grep -o 'https://.*cloudflare.com.*' | head -n 1)
        
        if [ -n "$AUTH_URL" ]; then
            print_info "授权链接已生成：$AUTH_URL"
            print_info "请在浏览器中打开该链接进行授权。"
        else
            print_error "未能获取到授权链接，请检查您的环境配置。"
            exit 1
        fi
        
        # 提示用户按 Enter 键继续
        print_input "授权完成后按 Enter 键继续..."
        read -r
    else
        print_error "cloudflared 未安装，请检查安装步骤。"
        exit 1
    fi
}

# ----------------------------
# 配置 Cloudflare Tunnel
# ----------------------------
configure_cloudflare_tunnel() {
    print_info "创建并启动 Cloudflare Tunnel..."

    # 创建 Cloudflare Tunnel
    cloudflared tunnel create "$TUNNEL_NAME"

    # 创建 config.yml 配置文件
    cat > /etc/cloudflared/config.yml <<EOF
tunnel: $(cat ~/.cloudflared/${TUNNEL_NAME}.json | jq -r '.TunnelID')  # 使用 tunnel 的 ID
credentials-file: /root/.cloudflared/${TUNNEL_NAME}.json  # 使用凭证文件路径

ingress:
  - hostname: $USER_DOMAIN  # 使用用户提供的域名
    service: http://127.0.0.1:10000  # Xray 监听端口
  - service: http_status:404  # 其他流量返回 404
EOF

    print_success "Cloudflare Tunnel 配置完成"
}

# ----------------------------
# 启动 Xray 和 Cloudflare Tunnel
# ----------------------------
start_services() {
    print_info "启动 Xray 服务..."
    sudo systemctl start xray
    sudo systemctl enable xray
    print_success "Xray 服务已启动"

    print_info "启动 Cloudflare Tunnel..."
    sudo cloudflared tunnel run "$TUNNEL_NAME"
    print_success "Cloudflare Tunnel 已启动"
}

# ----------------------------
# 主要功能执行
# ----------------------------
main() {
    show_title
    collect_user_info
    install_components
    direct_cloudflare_auth
    configure_cloudflare_tunnel
    start_services
    print_success "安装和配置完成，服务已启动"
}

# ----------------------------
# 执行脚本
# ----------------------------
