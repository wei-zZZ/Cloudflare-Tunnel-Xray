#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本
# 版本: 5.3 - 修复授权显示问题
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
print_url() { echo -e "${YELLOW}[🔗]${NC} $1"; }

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/secure_tunnel"
DATA_DIR="/var/lib/secure_tunnel"
LOG_DIR="/var/log/secure_tunnel"
BIN_DIR="/usr/local/bin"
SERVICE_USER="secure_tunnel"
SERVICE_GROUP="secure_tunnel"

USER_DOMAIN=""
TUNNEL_NAME="secure-tunnel"
SILENT_MODE=false

# ----------------------------
# 收集用户信息（放回前面）
# ----------------------------
collect_user_info() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 安装脚本 v5.3          ║"
    echo "║        修复授权显示问题                     ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    
    if [ "$SILENT_MODE" = true ]; then
        USER_DOMAIN="tunnel.example.com"
        print_info "静默模式：使用默认域名 $USER_DOMAIN"
        print_info "隧道名称: $TUNNEL_NAME"
        return
    fi
    
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           配置 Cloudflare Tunnel"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
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
    
    print_input "请输入隧道名称 [默认: secure-tunnel]:"
    read -r TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"secure-tunnel"}
    
    echo ""
    print_success "配置已保存:"
    echo "  域名: $USER_DOMAIN"
    echo "  隧道名称: $TUNNEL_NAME"
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
    
    local required_tools=("curl" "unzip" "wget")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "安装 $tool..."
            apt-get update -qq && apt-get install -y -qq "$tool" || {
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
            local xray_urls=(
                "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
                "https://ghproxy.com/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
            )
            local cf_urls=(
                "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
                "https://ghproxy.com/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            )
            ;;
        aarch64|arm64)
            local xray_urls=(
                "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
                "https://ghproxy.com/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
            )
            local cf_urls=(
                "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
                "https://ghproxy.com/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            )
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    download_with_retry() {
        local urls=("$@")
        local output_file="${urls[-1]}"
        unset "urls[${#urls[@]}-1]"
        
        local max_retries=2
        
        for url in "${urls[@]}"; do
            print_info "下载: $(basename "$output_file")"
            
            for ((i=1; i<=max_retries; i++)); do
                if wget --timeout=30 --tries=1 --quiet -O "$output_file" "$url"; then
                    if [[ -s "$output_file" ]]; then
                        print_success "下载成功"
                        return 0
                    fi
                fi
                
                if [[ $i -lt $max_retries ]]; then
                    sleep 1
                fi
            done
        done
        
        print_error "下载失败"
        return 1
    }
    
    if download_with_retry "${xray_urls[@]}" "/tmp/xray.zip"; then
        unzip -q -o /tmp/xray.zip -d /tmp/
        local xray_binary=$(find /tmp -name "xray" -type f | head -1)
        if [[ -n "$xray_binary" ]]; then
            mv "$xray_binary" "$BIN_DIR/xray"
            chmod +x "$BIN_DIR/xray"
            print_success "Xray 安装成功"
        fi
    else
        print_error "Xray 下载失败"
        exit 1
    fi
    
    if download_with_retry "${cf_urls[@]}" "/tmp/cloudflared"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        print_success "cloudflared 安装成功"
    else
        print_error "cloudflared 下载失败"
        exit 1
    fi
    
    rm -rf /tmp/xray* /tmp/cloudflare* 2>/dev/null
}

# ----------------------------
# Cloudflare 授权（修复版）
# ----------------------------
direct_cloudflare_auth() {
    echo ""
    print_auth "═══════════════════════════════════════════════"
    print_auth "         Cloudflare 授权（请按提示操作）       "
    print_auth "═══════════════════════════════════════════════"
    echo ""
    
    rm -rf /root/.cloudflared 2>/dev/null
    mkdir -p /root/.cloudflared
    
    print_auth "请按以下步骤完成授权："
    echo ""
    print_info "1. 脚本将运行 cloudflared tunnel login"
    print_info "2. 控制台会显示授权链接"
    print_info "3. 复制链接到浏览器打开"
    print_info "4. 在浏览器中选择要授权的域名"
    print_info "5. 授权成功后返回终端按回车"
    echo ""
    print_input "按回车键开始授权..."
    read -r
    
    echo ""
    print_info "正在运行 cloudflared tunnel login..."
    echo "=============================================="
    
    # 直接运行并显示输出
    "$BIN_DIR/cloudflared" tunnel login
    
    echo "=============================================="
    echo ""
    
    # 检查授权是否成功
    local check_count=0
    local max_checks=30
    
    while [[ $check_count -lt $max_checks ]]; do
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 授权成功！检测到证书文件"
            
            local json_file=$(find /root/.cloudflared -name "*.json" -type f | head -1)
            if [[ -n "$json_file" ]]; then
                print_success "✅ 检测到凭证文件: $(basename "$json_file")"
                return 0
            else
                print_warning "⚠️  未找到凭证文件，但证书已存在"
                return 0
            fi
        fi
        
        if [[ $check_count -eq 0 ]]; then
            echo ""
            print_input "授权完成后，按回车键继续检查..."
            read -r
        fi
        
        if [[ $check_count -eq 5 ]]; then
            echo ""
            print_warning "仍未检测到授权证书，请确认："
            echo "  1. 是否在浏览器中完成了授权？"
            echo "  2. 是否选择了正确的域名？"
            echo "  3. 是否点击了 'Authorize' 按钮？"
            echo ""
            print_input "如果已完成授权，按回车键继续等待..."
            read -r
        fi
        
        if [[ $check_count -eq 15 ]]; then
            echo ""
            print_error "长时间未检测到授权证书"
            echo ""
            print_info "请手动检查："
            echo "  1. 重新运行: sudo $BIN_DIR/cloudflared tunnel login"
            echo "  2. 查看文件: ls -la /root/.cloudflared/"
            echo ""
            print_input "按回车键重新尝试授权..."
            read -r
            
            rm -rf /root/.cloudflared 2>/dev/null
            mkdir -p /root/.cloudflared
            
            echo ""
            print_info "重新运行授权..."
            "$BIN_DIR/cloudflared" tunnel login
            echo ""
            
            check_count=0
            continue
        fi
        
        print_info "等待授权完成... ($((check_count*2))秒)"
        sleep 2
        ((check_count++))
    done
    
    print_error "❌ 授权失败"
    echo ""
    print_info "请尝试以下方法："
    echo "  1. 手动运行: sudo $BIN_DIR/cloudflared tunnel login"
    echo "  2. 确保使用正确的 Cloudflare 账号"
    echo "  3. 确保域名已在 Cloudflare 管理"
    echo "  4. 检查网络连接"
    echo ""
    print_input "按回车键退出脚本，手动完成授权后再运行..."
    read -r
    exit 1
}

# ----------------------------
# 创建隧道和配置
# ----------------------------
setup_tunnel() {
    print_info "设置 Cloudflare Tunnel..."
    
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "未找到证书文件"
        exit 1
    fi
    
    if [[ -z "$USER_DOMAIN" ]]; then
        if [ "$SILENT_MODE" = true ]; then
            USER_DOMAIN="tunnel.example.com"
        else
            print_error "未设置域名"
            exit 1
        fi
    fi
    
    export TUNNEL_ORIGIN_CERT="/root/.cloudflared/cert.pem"
    
    local existing_tunnel
    existing_tunnel=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -n "$existing_tunnel" ]]; then
        print_warning "使用现有隧道: $existing_tunnel"
        local tunnel_id="$existing_tunnel"
    else
        print_info "创建隧道: $TUNNEL_NAME"
        "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME" > /dev/null 2>&1
        
        local tunnel_id
        tunnel_id=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
        
        if [[ -z "$tunnel_id" ]]; then
            print_error "无法获取隧道ID"
            exit 1
        fi
    fi
    
    print_info "绑定域名: $USER_DOMAIN"
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN" > /dev/null 2>&1
    
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
CERT_PATH=/root/.cloudflared/cert.pem
CREATED_DATE=$(date +"%Y-%m-%d")
EOF
    
    print_success "隧道设置完成 (ID: ${tunnel_id})"
}

# ----------------------------
# 配置 Xray
# ----------------------------
configure_xray() {
    print_info "配置 Xray..."
    
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=10000
    
    echo "UUID=$uuid" >> "$CONFIG_DIR/tunnel.conf"
    echo "PORT=$port" >> "$CONFIG_DIR/tunnel.conf"
    
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    cat > "$CONFIG_DIR/xray.json" << EOF
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
    
    local json_file=$(find /root/.cloudflared -name "*.json" -type f | head -1)
    if [[ -z "$json_file" ]]; then
        print_error "找不到隧道凭证文件"
        exit 1
    fi
    
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: $json_file
originCert: /root/.cloudflared/cert.pem
ingress:
  - hostname: $USER_DOMAIN
    service: http://localhost:$port
    originRequest:
      noTLSVerify: true
      httpHostHeader: $USER_DOMAIN
  - service: http_status:404
EOF
    
    print_success "Xray 配置完成"
}

# ----------------------------
# 配置系统服务
# ----------------------------
configure_services() {
    print_info "配置系统服务..."
    
    if ! id -u "$SERVICE_USER" &> /dev/null; then
        useradd -r -s /usr/sbin/nologin "$SERVICE_USER"
    fi
    
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    cat > /etc/systemd/system/secure-tunnel-xray.service << EOF
[Unit]
Description=Secure Tunnel Xray Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$BIN_DIR/xray run -config $CONFIG_DIR/xray.json
Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/xray.log
StandardError=append:$LOG_DIR/xray-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    cat > /etc/systemd/system/secure-tunnel-argo.service << EOF
[Unit]
Description=Secure Tunnel Argo Service
After=network.target secure-tunnel-xray.service

[Service]
Type=simple
User=root
Group=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=always
RestartSec=5
StandardOutput=append:$LOG_DIR/argo.log
StandardError=append:$LOG_DIR/argo-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "系统服务配置完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    systemctl enable --now secure-tunnel-xray.service > /dev/null 2>&1
    print_success "Xray 启动成功"
    
    sleep 2
    
    systemctl enable --now secure-tunnel-argo.service > /dev/null 2>&1
    print_success "Argo Tunnel 启动成功"
    
    sleep 3
}

# ----------------------------
# 显示连接信息
# ----------------------------
show_connection_info() {
    print_info "═══════════════════════════════════════════════"
    print_info "           安装完成！连接信息"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件"
        return
    fi
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local uuid=$(grep "^UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    if [[ -z "$domain" ]] || [[ -z "$uuid" ]]; then
        print_error "无法读取配置"
        return
    fi
    
    print_success "🔗 域名: $domain"
    print_success "🔑 UUID: $uuid"
    print_success "🚪 端口: 443 (TLS) / 80 (非TLS)"
    print_success "🛣️  路径: /$uuid"
    echo ""
    
    local vless_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${uuid}&sni=${domain}#安全隧道"
    
    echo "VLESS 链接:"
    echo "$vless_tls"
    echo ""
    
    print_info "🌐 使用说明:"
    echo "1. 复制上面的VLESS链接到客户端"
    echo ""
    
    print_info "🔧 服务管理:"
    echo "  状态: systemctl status secure-tunnel-argo.service"
    echo "  重启: systemctl restart secure-tunnel-argo.service"
    echo "  停止: systemctl stop secure-tunnel-argo.service"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    print_info "开始安装流程..."
    
    check_system
    install_components
    collect_user_info
    direct_cloudflare_auth
    setup_tunnel
    configure_xray
    configure_services
    start_services
    show_connection_info
    
    echo ""
    print_success "🎉 安装全部完成！"
}

# ----------------------------
# 显示配置信息
# ----------------------------
show_config() {
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未安装"
        return 1
    fi
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local uuid=$(grep "^UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    echo ""
    print_success "当前配置:"
    echo "  域名: $domain"
    echo "  UUID: $uuid"
    echo ""
    
    local vless_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${uuid}&sni=${domain}#安全隧道"
    
    print_info "📡 VLESS链接:"
    echo "$vless_tls"
    echo ""
}

# ----------------------------
# 显示服务状态
# ----------------------------
show_status() {
    print_info "服务状态检查..."
    
    if systemctl is-active --quiet secure-tunnel-xray.service; then
        print_success "Xray 服务: 运行中"
    else
        print_error "Xray 服务: 未运行"
    fi
    
    if systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "Argo Tunnel 服务: 运行中"
    else
        print_error "Argo Tunnel 服务: 未运行"
    fi
    
    echo ""
    print_info "详细状态:"
    systemctl status secure-tunnel-xray.service --no-pager -l | head -20
    echo ""
    systemctl status secure-tunnel-argo.service --no-pager -l | head -20
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    if [[ "$1" == "-y" ]] || [[ "$2" == "-y" ]]; then
        SILENT_MODE=true
    fi
    
    clear
    
    case "${1:-}" in
        "install")
            main_install
            ;;
        "config"|"subscription")
            show_config
            ;;
        "status")
            show_status
            ;;
        "-y"|"--silent")
            SILENT_MODE=true
            main_install
            ;;
        *)
            echo ""
            echo "╔══════════════════════════════════════════════╗"
            echo "║    Cloudflare Tunnel 安装脚本 v5.3          ║"
            echo "║        修复授权显示问题                     ║"
            echo "╚══════════════════════════════════════════════╝"
            echo ""
            echo "使用方法:"
            echo "  sudo ./secure_tunnel.sh install       # 交互式安装"
            echo "  sudo ./secure_tunnel.sh -y           # 静默安装"
            echo "  sudo ./secure_tunnel.sh config       # 显示配置"
            echo "  sudo ./secure_tunnel.sh status       # 查看服务状态"
            exit 1
            ;;
    esac
}

main "$@"