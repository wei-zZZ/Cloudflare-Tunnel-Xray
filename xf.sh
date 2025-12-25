#!/bin/bash
# ============================================
# Cloudflare Tunnel + X-UI 安装脚本（稳定版）
# 版本: 2.1 - 增加 WS 节点走 Tunnel（不精简）
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

XUI_PORT=54321

# ===== 新增：WS 节点配置（仅新增，不影响原逻辑）=====
XRAY_PORT=10000
XRAY_DOMAIN=""
WS_PATH="/ws"

DEFAULT_USERNAME="admin"
DEFAULT_PASSWORD="admin"

USER_DOMAIN=""
TUNNEL_NAME="xui-tunnel"
SILENT_MODE=false

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel + X-UI 安装脚本        ║"
    echo "║        含 WS 节点 Tunnel（稳定版）         ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
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

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        print_info "检测到系统: $OS"
    else
        print_error "无法检测操作系统"
        exit 1
    fi

    print_info "更新系统包..."
    apt-get update -y

    print_info "安装必要工具..."
    local tools=("curl" "wget" "git" "jq" "net-tools" "dnsutils")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            apt-get install -y "$tool" || true
        fi
    done

    print_success "系统检查完成"
}

# ----------------------------
# 收集用户信息
# ----------------------------
collect_user_info() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           配置信息收集"
    print_info "═══════════════════════════════════════════════"
    echo ""

    # X-UI 面板域名
    while true; do
        print_input "请输入 X-UI 面板域名 (如 xui.yourdomain.com):"
        read -r USER_DOMAIN
        [[ -n "$USER_DOMAIN" ]] && break
        print_error "域名不能为空"
    done

    # ===== 新增：代理节点域名 =====
    while true; do
        print_input "请输入代理节点域名 (如 node.yourdomain.com):"
        read -r XRAY_DOMAIN
        [[ -n "$XRAY_DOMAIN" ]] && break
        print_error "节点域名不能为空"
    done

    print_input "请输入隧道名称 [默认: xui-tunnel]:"
    read -r TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"xui-tunnel"}

    echo ""
    print_success "配置确认:"
    echo "  面板域名: $USER_DOMAIN"
    echo "  节点域名: $XRAY_DOMAIN"
    echo "  WS 路径 : $WS_PATH"
    echo "  隧道名称: $TUNNEL_NAME"
    echo ""
}

# ----------------------------
# 安装 X-UI
# ----------------------------
install_xui() {
    print_info "安装 X-UI..."

    if ! command -v x-ui &>/dev/null; then
        bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
    fi

    systemctl enable x-ui
    systemctl restart x-ui
}

# ----------------------------
# 安装 Cloudflared
# ----------------------------
install_cloudflared() {
    print_info "安装 cloudflared..."

    if command -v cloudflared &>/dev/null; then
        print_success "cloudflared 已存在"
        return
    fi

    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    else
        URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    fi

    wget -O "$BIN_DIR/cloudflared" "$URL"
    chmod +x "$BIN_DIR/cloudflared"
}

# ----------------------------
# Cloudflare 授权
# ----------------------------
cloudflare_auth() {
    rm -rf /root/.cloudflared
    cloudflared tunnel login
}

# ----------------------------
# 创建隧道
# ----------------------------
create_tunnel() {
    cloudflared tunnel delete "$TUNNEL_NAME" -f >/dev/null 2>&1 || true
    cloudflared tunnel create "$TUNNEL_NAME"

    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    CREDS=$(ls /root/.cloudflared/*.json | head -1)

    mkdir -p "$CONFIG_DIR"

    cat > "$CONFIG_DIR/tunnel.conf" <<EOF
TUNNEL_ID=$TUNNEL_ID
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
XRAY_DOMAIN=$XRAY_DOMAIN
XRAY_PORT=$XRAY_PORT
WS_PATH=$WS_PATH
CREDENTIALS_FILE=$CREDS
XUI_PORT=$XUI_PORT
EOF
}

# ----------------------------
# 配置 DNS
# ----------------------------
setup_dns() {
    cloudflared tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN"
    cloudflared tunnel route dns "$TUNNEL_NAME" "$XRAY_DOMAIN"
}

# ----------------------------
# 创建 cloudflared 配置文件
# ----------------------------
create_config_files() {
    source "$CONFIG_DIR/tunnel.conf"

    cat > "$CONFIG_DIR/config.yaml" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE

logfile: $LOG_DIR/cloudflared.log
loglevel: info

ingress:
  - hostname: $DOMAIN
    service: http://127.0.0.1:$XUI_PORT

  - hostname: $XRAY_DOMAIN
    service: http://127.0.0.1:$XRAY_PORT
    originRequest:
      httpHostHeader: $XRAY_DOMAIN

  - service: http_status:404
EOF
}

# ----------------------------
# systemd 服务
# ----------------------------
create_system_service() {
cat > /etc/systemd/system/xui-tunnel.service <<EOF
[Unit]
Description=X-UI Cloudflare Tunnel Service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xui-tunnel
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    systemctl restart x-ui
    systemctl restart xui-tunnel
}

# ----------------------------
# 主流程
# ----------------------------
main_install() {
    show_title
    check_system
    collect_user_info
    install_xui
    install_cloudflared
    cloudflare_auth
    create_tunnel
    setup_dns
    create_config_files
    create_system_service
    start_services
}

main_install