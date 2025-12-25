#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本（终版入口固定）
# 基于 6.3，仅修入口模型，不精简
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
print_config() { echo -e "${CYAN}[⚙️]${NC} $1"; }

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/secure_tunnel"
LOG_DIR="/var/log/secure_tunnel"
BIN_DIR="/usr/local/bin"

USER_DOMAIN=""
TUNNEL_NAME="secure-tunnel"
PROXY_PORT=10086
PANEL_PORT=54321

XUI_USERNAME="admin"
XUI_PASSWORD="admin"
PROTOCOL="both"

# ----------------------------
# 标题
# ----------------------------
show_title() {
    clear
    echo "============================================"
    echo " Cloudflare Tunnel + Xray 终版入口固定脚本 "
    echo "============================================"
    echo ""
}

# ----------------------------
# 系统检查
# ----------------------------
check_system() {
    [[ $EUID -ne 0 ]] && print_error "请使用 root 运行" && exit 1

    for i in curl wget unzip jq uuid-runtime; do
        command -v $i >/dev/null || apt update -y && apt install -y $i
    done
}

# ----------------------------
# 收集配置
# ----------------------------
collect_config() {
    while [[ -z "$USER_DOMAIN" ]]; do
        print_input "请输入绑定到 Tunnel 的域名:"
        read -r USER_DOMAIN
    done
}

# ----------------------------
# 安装组件
# ----------------------------
install_components() {
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
            CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
            CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *) print_error "不支持的架构"; exit 1 ;;
    esac

    curl -L -o /tmp/xray.zip "$XRAY_URL"
    unzip -o /tmp/xray.zip -d /tmp
    install -m 755 /tmp/xray "$BIN_DIR/xray"

    curl -L -o "$BIN_DIR/cloudflared" "$CF_URL"
    chmod +x "$BIN_DIR/cloudflared"
}

# ----------------------------
# Cloudflare 授权
# ----------------------------
cloudflare_auth() {
    "$BIN_DIR/cloudflared" tunnel login
}

# ----------------------------
# 创建 Tunnel
# ----------------------------
create_tunnel() {
    "$BIN_DIR/cloudflared" tunnel delete "$TUNNEL_NAME" 2>/dev/null || true
    "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"

    TUNNEL_ID=$("$BIN_DIR/cloudflared" tunnel list --name "$TUNNEL_NAME" --format json | jq -r '.[0].id')
    TUNNEL_CERT_FILE="/root/.cloudflared/$TUNNEL_ID.json"

    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN"
}

# ----------------------------
# ingress（入口固定 /ws）
# ----------------------------
generate_ingress_config() {
    mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_NAME
credentials-file: $TUNNEL_CERT_FILE

ingress:
  - hostname: $USER_DOMAIN
    path: /ws
    service: http://127.0.0.1:$PROXY_PORT

  - service: http_status:404
EOF
}

# ----------------------------
# 生成 Xray（保留）
# ----------------------------
generate_xray_config() {
    uuid=$(uuidgen)
    echo "$uuid" > "$CONFIG_DIR/uuid.txt"

cat > "$CONFIG_DIR/xray.json" << EOF
{
  "inbounds": [],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
}

# ----------------------------
# 安装 X-UI
# ----------------------------
install_xui() {
    bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
    sleep 10
    add_xui_inbound
}

# ----------------------------
# X-UI 入站（path 固定）
# ----------------------------
add_xui_inbound() {
    uuid=$(cat "$CONFIG_DIR/uuid.txt")

cat > /tmp/inbound.json << EOF
{
  "remark": "CF-Fixed",
  "enable": true,
  "port": $PROXY_PORT,
  "protocol": "vless",
  "settings": {
    "clients": [{ "id": "$uuid" }],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "security": "none",
    "wsSettings": {
      "path": "/ws",
      "headers": { "Host": "$USER_DOMAIN" }
    }
  }
}
EOF

    curl -s -X POST http://127.0.0.1:$PANEL_PORT/login \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$XUI_USERNAME\",\"password\":\"$XUI_PASSWORD\"}" \
      -c /tmp/xui.cookie >/dev/null

    curl -s -X POST http://127.0.0.1:$PANEL_PORT/xui/inbound/add \
      -b /tmp/xui.cookie \
      -H "Content-Type: application/json" \
      -d @/tmp/inbound.json >/dev/null
}

# ----------------------------
# 服务
# ----------------------------
create_services() {
cat > /etc/systemd/system/cloudflared.service << EOF
[Service]
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yml run
Restart=always
EOF

    systemctl daemon-reload
    systemctl enable cloudflared
    systemctl restart cloudflared
}

# ----------------------------
# 客户端配置
# ----------------------------
generate_client_config() {
    uuid=$(cat "$CONFIG_DIR/uuid.txt")

    echo ""
    echo "====== 客户端配置 ======"
    echo "地址: $USER_DOMAIN"
    echo "端口: 443"
    echo "UUID: $uuid"
    echo "WS Path: /ws"
    echo "TLS: 开"
    echo ""

    echo "vless://$uuid@$USER_DOMAIN:443?type=ws&security=tls&encryption=none&host=$USER_DOMAIN&path=%2Fws&sni=$USER_DOMAIN#CF-Fixed"
}

# ----------------------------
# 主流程
# ----------------------------
main() {
    show_title
    check_system
    collect_config
    install_components
    cloudflare_auth
    create_tunnel
    generate_ingress_config
    generate_xray_config
    install_xui
    create_services
    generate_client_config
}

main "$@"
