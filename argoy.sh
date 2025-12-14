#!/bin/bash
# ============================================
# Argox Tunnel + Xray 安装及管理脚本
# 版本: 1.0
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
    echo "║               版本: 1.0                      ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
}

# ----------------------------
# 安装组件（Cloudflared 和 Xray）
# ----------------------------
install_components() {
    print_info "安装必要组件..."
    
    # 安装 curl 和 unzip
    local tools=("curl" "unzip")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "正在安装 $tool..."
            apt-get install -y "$tool" || { print_error "$tool 安装失败"; exit 1; }
            print_success "$tool 安装完成"
        fi
    done
    
    # 检测系统架构
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" || "$arch" == "amd64" ]]; then
        local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
    else
        print_error "不支持的架构: $arch"
        exit 1
    fi
    
    # 下载并安装 cloudflared
    print_info "下载 cloudflared..."
    curl -L -o /tmp/cloudflared "$cf_url"
    mv /tmp/cloudflared "$BIN_DIR/cloudflared"
    chmod +x "$BIN_DIR/cloudflared"
    print_success "cloudflared 安装成功"

    # 下载并安装 Xray
    print_info "下载 Xray..."
    curl -L -o /tmp/xray.zip "$xray_url"
    unzip -q -o /tmp/xray.zip -d /tmp/
    mv /tmp/xray "$BIN_DIR/xray"
    chmod +x "$BIN_DIR/xray"
    print_success "Xray 安装成功"
    
    rm -rf /tmp/xray* /tmp/cloudflared* 2>/dev/null
    print_success "所有组件安装完成"
}

# ----------------------------
# Cloudflare 授权
# ----------------------------
direct_cloudflare_auth() {
    echo ""
    print_auth "═══════════════════════════════════════════════"
    print_auth "         Cloudflare 授权                      "
    print_auth "═══════════════════════════════════════════════"
    echo ""
    
    # 清理旧的授权文件
    rm -rf /root/.cloudflared 2>/dev/null
    mkdir -p /root/.cloudflared
    
    echo "请按以下步骤操作："
    echo "1. 脚本将显示一个 Cloudflare 授权链接"
    echo "2. 复制链接到浏览器打开"
    echo "3. 登录您的 Cloudflare 账户"
    echo "4. 选择您要使用的域名并授权"
    echo "5. 返回终端按回车继续"
    echo ""
    print_input "按回车开始授权..."
    read -r
    
    echo ""
    echo "=============================================="
    echo "请复制以下链接到浏览器："
    echo ""
    
    # 运行授权命令
    "$BIN_DIR/cloudflared" tunnel login
    
    echo ""
    echo "=============================================="
    print_input "完成授权后按回车继续..."
    read -r
    
    # 检查授权结果
    local check_count=0
    while [[ $check_count -lt 10 ]]; do
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 授权成功！找到证书文件"
            
            # 检查凭证文件
            if ls /root/.cloudflared/*.json 1> /dev/null 2>&1; then
                local json_file=$(ls /root/.cloudflared/*.json | head -1)
                print_success "✅ 找到凭证文件: $(basename "$json_file")"
                return 0
            else
                print_warning "⚠️  未找到JSON凭证文件，将在创建隧道时生成"
                return 0
            fi
        fi
        sleep 2
        ((check_count++))
    done
    
    print_error "❌ 授权失败：未找到证书文件"
    return 1
}



# ----------------------------
# 配置 Xray
# ----------------------------
configure_xray() {
    print_info "配置 Xray..."
    mkdir -p "$CONFIG_DIR"
    
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=10000
    
    # 创建 Xray 配置文件
    cat > "$CONFIG_DIR/xray.json" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": $port,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$uuid", "level": 0}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "security": "none",
      "wsSettings": {"path": "/$uuid"}
    }
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF
    print_success "Xray 配置完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    print_info "启动 Xray 服务..."
    systemctl start xray
    systemctl enable xray
    print_success "Xray 服务已启动"

    print_info "启动 Cloudflare Tunnel..."
    cloudflared tunnel run "$TUNNEL_NAME"
    print_success "Cloudflare Tunnel 已启动"
}

# ----------------------------
# 卸载功能
# ----------------------------
uninstall() {
    print_info "卸载 Argox Tunnel 和 Xray..."
    
    # 停止服务
    systemctl stop xray
    systemctl disable xray
    print_success "Xray 服务已停止"
    
    # 删除文件
    rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    rm -f "$BIN_DIR/xray" "$BIN_DIR/cloudflared"
    print_success "组件已删除"
    
    print_success "卸载完成"
}

# ----------------------------
# 主功能执行
# ----------------------------
main() {
    show_title
    print_input "请选择操作：1. 安装 2. 卸载"
    read -r option
    
    case "$option" in
        1)
            install_components
            direct_cloudflare_auth
            configure_xray
            start_services
            print_success "安装和配置完成，服务已启动"
            ;;
        2)
            uninstall
            ;;
        *)
            print_error "无效选择，请选择 1 或 2"
            ;;
    esac
}

# ----------------------------
# 执行脚本
# ----------------------------
main
