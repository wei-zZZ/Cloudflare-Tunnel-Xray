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
# 修复软件源问题
# ----------------------------
fix_apt_sources() {
    print_info "检查软件源配置..."
    
    cp /etc/apt/sources.list /etc/apt/sources.list.backup 2>/dev/null || true
    
    if grep -q "debian" /etc/os-release; then
        print_info "检测到 Debian 系统，修复软件源..."
        cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian bullseye main contrib non-free
deb http://deb.debian.org/debian bullseye-updates main contrib non-free
deb http://security.debian.org/debian-security bullseye-security main contrib non-free
EOF
    elif grep -q "ubuntu" /etc/os-release; then
        print_info "检测到 Ubuntu 系统，修复软件源..."
        cat > /etc/apt/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
EOF
    fi
    
    rm -f /etc/apt/sources.list.d/*bullseye-backports* 2>/dev/null || true
    apt-get update -y || {
        print_warning "软件源更新失败，尝试继续安装..."
    }
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
# 系统检查（修复版）
# ----------------------------
check_system() {
    print_info "检查系统环境..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    fix_apt_sources
    
    print_info "安装必要工具..."
    
    local tools=("curl" "wget" "unzip")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "正在安装 $tool..."
            
            if apt-get install -y -qq "$tool" 2>/dev/null; then
                print_success "$tool 安装成功"
            else
                print_warning "apt安装 $tool 失败，尝试其他方法..."
                
                case "$tool" in
                    "curl")
                        apt-get install -y libcurl4-openssl-dev || true
                        ;;
                    "wget")
                        wget_direct_install || true
                        ;;
                    "unzip")
                        unzip_direct_install || true
                        ;;
                esac
                
                if ! command -v "$tool" &> /dev/null; then
                    print_error "无法安装 $tool，安装可能不完整"
                else
                    print_success "$tool 安装完成"
                fi
            fi
        else
            print_info "$tool 已安装"
        fi
    done
    
    print_success "系统检查完成"
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
    read
}

# ----------------------------
# Xray 配置
# ----------------------------
configure_xray() {
    print_info "配置 Xray..."

    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=10000

    mkdir -p "$CONFIG_DIR"

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
# 主要功能执行
# ----------------------------
main() {
    show_title
    check_system
    collect_user_info
    install_components
    configure_xray
    direct_cloudflare_auth
    print_success "安装和配置完成"
}

# ----------------------------
# 执行脚本
# ----------------------------
main
