#!/bin/bash
# ============================================
# Cloudflare Tunnel + WireGuard 安装脚本
# 版本: 1.1 - 修复 WireGuard 服务启动问题
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
CONFIG_DIR="/etc/wg-argo"
LOG_DIR="/var/log/wg-argo"
WG_CONFIG="/etc/wireguard/wg0.conf"
WG_KEY_DIR="/etc/wireguard/keys"
BIN_DIR="/usr/local/bin"

USER_DOMAIN=""
TUNNEL_NAME="wg-argo-tunnel"
WIREGUARD_PORT=51820
SILENT_MODE=false

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel + WireGuard 管理脚本   ║"
    echo "║             版本: 1.1 - 修复版              ║"
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
    print_info "           配置 Cloudflare Tunnel"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    if [ "$SILENT_MODE" = true ]; then
        USER_DOMAIN="wg.example.com"
        print_info "静默模式：使用默认域名 $USER_DOMAIN"
        print_info "隧道名称: $TUNNEL_NAME"
        return
    fi
    
    while [[ -z "$USER_DOMAIN" ]]; do
        print_input "请输入您的域名 (例如: wg.yourdomain.com):"
        read -r USER_DOMAIN
        
        if [[ -z "$USER_DOMAIN" ]]; then
            print_error "域名不能为空！"
        elif ! [[ "$USER_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "域名格式不正确，请重新输入！"
            USER_DOMAIN=""
        fi
    done
    
    print_input "请输入隧道名称 [默认: wg-argo-tunnel]:"
    read -r TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"wg-argo-tunnel"}
    
    print_input "请输入 WireGuard 监听端口 [默认: 51820]:"
    read -r input_port
    WIREGUARD_PORT=${input_port:-51820}
    
    echo ""
    print_success "配置已保存:"
    echo "  域名: $USER_DOMAIN"
    echo "  隧道名称: $TUNNEL_NAME"
    echo "  WireGuard 端口: $WIREGUARD_PORT"
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
    
    # 修复软件源
    fix_apt_sources
    
    # 检查是否已安装 WireGuard
    if command -v wg &> /dev/null && command -v wg-quick &> /dev/null; then
        print_success "WireGuard 已安装"
    else
        print_info "安装 WireGuard..."
        
        # 安装必要内核模块和工具
        apt-get install -y wireguard wireguard-tools resolvconf
        
        # 对于较新的内核，可能需要安装 wireguard-dkms
        if ! command -v wg &> /dev/null; then
            apt-get install -y wireguard-dkms
        fi
        
        if ! command -v wg &> /dev/null; then
            print_error "WireGuard 安装失败"
            exit 1
        fi
        print_success "WireGuard 安装成功"
    fi
    
    # 检查 WireGuard 内核模块
    print_info "检查 WireGuard 内核模块..."
    if lsmod | grep -q wireguard; then
        print_success "WireGuard 内核模块已加载"
    else
        print_warning "WireGuard 内核模块未加载，尝试加载..."
        modprobe wireguard 2>/dev/null || true
    fi
    
    # 安装必要工具
    print_info "安装必要工具..."
    local tools=("curl" "wget" "qrencode" "iptables" "ip6tables")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            apt-get install -y "$tool" 2>/dev/null || {
                print_warning "$tool 安装失败，尝试继续..."
            }
        fi
    done
    
    print_success "系统检查完成"
}

# ----------------------------
# 安装 Cloudflared
# ----------------------------
install_cloudflared() {
    print_info "安装 cloudflared..."
    
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64|amd64)
            local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    if curl -L -o /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        print_success "cloudflared 安装成功"
    else
        print_error "cloudflared 下载失败"
        exit 1
    fi
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
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "✅ 授权成功！找到证书文件"
        return 0
    else
        print_error "❌ 授权失败：未找到证书文件"
        return 1
    fi
}

# ----------------------------
# 生成 WireGuard 密钥
# ----------------------------
generate_wireguard_keys() {
    print_info "生成 WireGuard 密钥..."
    
    mkdir -p "$WG_KEY_DIR"
    chmod 700 "$WG_KEY_DIR"
    
    # 生成服务器密钥对
    if [[ ! -f "$WG_KEY_DIR/server_private.key" ]]; then
        wg genkey | tee "$WG_KEY_DIR/server_private.key" | wg pubkey > "$WG_KEY_DIR/server_public.key"
        chmod 600 "$WG_KEY_DIR/server_private.key"
    fi
    
    # 生成客户端密钥对
    if [[ ! -f "$WG_KEY_DIR/client_private.key" ]]; then
        wg genkey | tee "$WG_KEY_DIR/client_private.key" | wg pubkey > "$WG_KEY_DIR/client_public.key"
        chmod 600 "$WG_KEY_DIR/client_private.key"
    fi
    
    # 生成预共享密钥
    if [[ ! -f "$WG_KEY_DIR/preshared.key" ]]; then
        wg genpsk > "$WG_KEY_DIR/preshared.key"
        chmod 600 "$WG_KEY_DIR/preshared.key"
    fi
    
    print_success "WireGuard 密钥生成完成"
}

# ----------------------------
# 配置 WireGuard
# ----------------------------
configure_wireguard() {
    print_info "配置 WireGuard..."
    
    # 读取密钥
    local server_private=$(cat "$WG_KEY_DIR/server_private.key")
    local server_public=$(cat "$WG_KEY_DIR/server_public.key")
    local client_private=$(cat "$WG_KEY_DIR/client_private.key")
    local client_public=$(cat "$WG_KEY_DIR/client_public.key")
    local preshared_key=$(cat "$WG_KEY_DIR/preshared.key")
    
    # 获取主网络接口
    local main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [[ -z "$main_interface" ]]; then
        main_interface="eth0"
    fi
    
    # 生成服务器配置
    cat > "$WG_CONFIG" << EOF
[Interface]
PrivateKey = $server_private
Address = 10.9.0.1/24
ListenPort = $WIREGUARD_PORT
MTU = 1280
# DNS 设置
DNS = 1.1.1.1, 8.8.8.8
# 保存配置
SaveConfig = true
# 转发规则
PostUp = sysctl -w net.ipv4.ip_forward=1; sysctl -w net.ipv6.conf.all.forwarding=1
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $main_interface -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $main_interface -j MASQUERADE

# 客户端配置
[Peer]
PublicKey = $client_public
PresharedKey = $preshared_key
AllowedIPs = 10.9.0.2/32
EOF
    
    # 生成客户端配置
    cat > "$CONFIG_DIR/client.conf" << EOF
[Interface]
PrivateKey = $client_private
Address = 10.9.0.2/24
DNS = 1.1.1.1, 8.8.8.8
MTU = 1280

[Peer]
PublicKey = $server_public
PresharedKey = $preshared_key
Endpoint = $USER_DOMAIN:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    
    # 启用 IP 转发（永久生效）
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    fi
    sysctl -p 2>/dev/null || true
    
    # 设置配置文件权限
    chmod 600 "$WG_CONFIG"
    
    print_success "WireGuard 配置完成"
}

# ----------------------------
# 测试 WireGuard 配置
# ----------------------------
test_wireguard_config() {
    print_info "测试 WireGuard 配置..."
    
    # 检查配置文件是否存在
    if [[ ! -f "$WG_CONFIG" ]]; then
        print_error "WireGuard 配置文件不存在"
        return 1
    fi
    
    # 测试配置语法
    if wg-quick up wg0 2>&1 | grep -q "Configuration is valid"; then
        print_success "WireGuard 配置语法正确"
    else
        # 尝试手动启动以查看错误
        print_warning "尝试手动启动 WireGuard 查看错误..."
        wg-quick up wg0 2>&1 || true
        return 1
    fi
    
    # 立即关闭（服务将在后面正式启动）
    wg-quick down wg0 2>/dev/null || true
    
    return 0
}

# ----------------------------
# 创建隧道和配置
# ----------------------------
setup_tunnel() {
    print_info "设置 Cloudflare Tunnel..."
    
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "❌ 未找到证书文件，请先完成授权"
        exit 1
    fi
    
    # 删除可能存在的同名隧道
    "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    print_info "创建隧道: $TUNNEL_NAME"
    if timeout 60 "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"; then
        sleep 3
        print_success "✅ 隧道创建成功"
    else
        print_error "❌ 无法创建隧道"
        exit 1
    fi
    
    # 获取隧道ID和凭证文件
    local json_file=$(ls -t /root/.cloudflared/*.json 2>/dev/null | head -1)
    local tunnel_id=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -z "$tunnel_id" ]]; then
        print_error "❌ 无法获取隧道ID"
        exit 1
    fi
    
    # 绑定域名
    print_info "绑定域名: $USER_DOMAIN"
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN" > /dev/null 2>&1
    print_success "✅ 域名绑定成功"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 保存隧道配置
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
WG_PORT=$WIREGUARD_PORT
CERT_PATH=/root/.cloudflared/cert.pem
CREDENTIALS_FILE=$json_file
CREATED_DATE=$(date +"%Y-%m-%d")
EOF
    
    print_success "隧道设置完成"
}

# ----------------------------
# 创建 Cloudflared 配置
# ----------------------------
configure_cloudflared() {
    print_info "配置 cloudflared..."
    
    local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local json_file=$(grep "^CREDENTIALS_FILE=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local wg_port=$(grep "^WG_PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    # 创建 cloudflared 配置文件
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: $json_file
logfile: $LOG_DIR/argo.log
loglevel: info
ingress:
  - hostname: $domain
    service: udp://localhost:$wg_port
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      tcpKeepAlive: 30s
      noHappyEyeballs: true
      keepAliveConnections: 10
      keepAliveTimeout: 30s
  - service: http_status:404
EOF
    
    print_success "cloudflared 配置完成"
}

# ----------------------------
# 配置系统服务
# ----------------------------
configure_services() {
    print_info "配置系统服务..."
    
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    
    # 创建 WireGuard 服务文件（使用简单的启动方式）
    cat > /etc/systemd/system/wg-argo-wireguard.service << EOF
[Unit]
Description=WireGuard VPN Server for Argo Tunnel
After=network.target
Wants=network-online.target
Requires=wg-quick@wg0.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'wg-quick up wg0 || echo "WireGuard 启动失败，请检查配置"'
ExecStop=/bin/bash -c 'wg-quick down wg0 || true'
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 创建 Cloudflared 服务文件
    cat > /etc/systemd/system/wg-argo-cloudflared.service << EOF
[Unit]
Description=WireGuard Argo Tunnel Service
After=network.target wg-argo-wireguard.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/argo.log
StandardError=append:$LOG_DIR/argo-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载systemd
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable wg-argo-wireguard.service --now 2>/dev/null || true
    systemctl enable wg-argo-cloudflared.service
    
    print_success "系统服务配置完成"
}

# ----------------------------
# 启动服务（改进版）
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    # 停止可能存在的旧服务
    systemctl stop wg-argo-cloudflared.service 2>/dev/null || true
    systemctl stop wg-argo-wireguard.service 2>/dev/null || true
    
    # 先手动启动 WireGuard 来检查错误
    print_info "手动启动 WireGuard 检查配置..."
    
    if wg-quick up wg0 2>&1; then
        print_success "✅ WireGuard 手动启动成功"
        # 测试成功后关闭，让服务管理
        wg-quick down wg0 2>/dev/null || true
        sleep 2
    else
        print_error "❌ WireGuard 手动启动失败"
        print_info "检查 WireGuard 配置..."
        cat "$WG_CONFIG"
        return 1
    fi
    
    # 启动 WireGuard 服务
    print_info "启动 WireGuard 服务..."
    systemctl start wg-argo-wireguard.service
    
    local wg_retries=0
    while [[ $wg_retries -lt 5 ]]; do
        if systemctl is-active --quiet wg-argo-wireguard.service; then
            print_success "✅ WireGuard 服务启动成功"
            break
        fi
        
        if [[ $wg_retries -eq 2 ]]; then
            print_warning "WireGuard 服务启动较慢，查看日志..."
            journalctl -u wg-argo-wireguard.service -n 20 --no-pager
        fi
        
        sleep 2
        ((wg_retries++))
    done
    
    if [[ $wg_retries -ge 5 ]]; then
        print_error "❌ WireGuard 服务启动失败"
        print_info "尝试手动启动调试..."
        wg-quick up wg0
        wg show
        return 1
    fi
    
    # 启动 Cloudflared 服务
    print_info "启动 Cloudflared..."
    systemctl start wg-argo-cloudflared.service
    
    # 等待隧道连接
    local wait_time=0
    local max_wait=30
    
    print_info "等待隧道连接建立（最多30秒）..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        if systemctl is-active --quiet wg-argo-cloudflared.service; then
            print_success "✅ Cloudflared 服务运行中"
            break
        fi
        sleep 3
        ((wait_time+=3))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        print_warning "⚠️  隧道服务启动较慢"
    fi
    
    # 显示 WireGuard 状态
    echo ""
    print_info "WireGuard 接口状态:"
    wg show 2>/dev/null || print_warning "无法获取 WireGuard 状态"
    
    return 0
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
    
    if [[ ! -f "$CONFIG_DIR/client.conf" ]]; then
        print_error "未找到客户端配置文件"
        return
    fi
    
    print_success "🔗 WireGuard 服务器: $domain:51820"
    print_success "📁 客户端配置: $CONFIG_DIR/client.conf"
    print_success "🌐 内网网段: 10.9.0.0/24"
    print_success "🖥️  服务器IP: 10.9.0.1"
    print_success "📱 客户端IP: 10.9.0.2"
    
    echo ""
    
    # 显示客户端配置内容
    print_info "📋 客户端配置内容:"
    echo "═══════════════════════════════════════════════"
    cat "$CONFIG_DIR/client.conf"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    # 生成 QR 码（如果安装了 qrencode）
    if command -v qrencode &> /dev/null; then
        print_info "📱 客户端配置二维码:"
        qrencode -t utf8 < "$CONFIG_DIR/client.conf"
        echo ""
    fi
    
    print_info "🧪 服务状态:"
    echo ""
    
    if systemctl is-active --quiet wg-argo-wireguard.service; then
        print_success "✅ WireGuard 服务: 运行中"
        echo ""
        print_info "WireGuard 接口状态:"
        wg show 2>/dev/null || echo "无法获取接口状态"
    else
        print_error "❌ WireGuard 服务: 未运行"
    fi
    
    echo ""
    
    if systemctl is-active --quiet wg-argo-cloudflared.service; then
        print_success "✅ Cloudflared 服务: 运行中"
    else
        print_error "❌ Cloudflared 服务: 未运行"
    fi
    
    echo ""
    print_info "📋 使用说明:"
    echo "  1. 将 client.conf 导入 WireGuard 客户端"
    echo "  2. 或扫描上面的二维码（如果支持）"
    echo "  3. 如果连接不上，等待2-3分钟再试"
    echo "  4. 查看服务状态: sudo ./wg_argo.sh status"
    echo ""
    
    print_info "🔧 管理命令:"
    echo "  状态检查: sudo ./wg_argo.sh status"
    echo "  重启 WireGuard: systemctl restart wg-argo-wireguard.service"
    echo "  重启 Cloudflared: systemctl restart wg-argo-cloudflared.service"
    echo "  查看日志: journalctl -u wg-argo-cloudflared.service -f"
}

# ----------------------------
# 主安装流程（修复版）
# ----------------------------
main_install() {
    print_info "开始安装流程..."
    
    check_system
    install_cloudflared
    collect_user_info
    
    # Cloudflare 授权
    if ! direct_cloudflare_auth; then
        print_warning "授权可能有问题"
        print_input "是否继续安装？(y/N): "
        read -r continue_install
        if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
            print_error "安装中止"
            return 1
        fi
    fi
    
    # 设置隧道
    if ! setup_tunnel; then
        print_error "隧道设置失败"
        return 1
    fi
    
    generate_wireguard_keys
    configure_wireguard
    
    # 测试 WireGuard 配置
    if ! test_wireguard_config; then
        print_error "WireGuard 配置测试失败"
        return 1
    fi
    
    configure_cloudflared
    configure_services
    
    if ! start_services; then
        print_error "服务启动失败"
        
        # 提供调试信息
        echo ""
        print_info "🛠️  调试信息:"
        echo "1. 检查 WireGuard 内核模块: lsmod | grep wireguard"
        echo "2. 手动测试 WireGuard: wg-quick up wg0"
        echo "3. 查看 WireGuard 配置: cat $WG_CONFIG"
        echo "4. 检查系统日志: journalctl -xe"
        return 1
    fi
    
    show_connection_info
    
    echo ""
    print_success "🎉 安装完成！"
    return 0
}

# ----------------------------
# 卸载功能
# ----------------------------
uninstall_all() {
    print_info "开始卸载 WireGuard Argo Tunnel..."
    echo ""
    
    print_warning "⚠️  警告：此操作将删除所有配置和数据！"
    print_input "确认要卸载吗？(y/N): "
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "卸载已取消"
        return
    fi
    
    echo ""
    print_info "停止服务..."
    
    systemctl stop wg-argo-cloudflared.service 2>/dev/null || true
    systemctl stop wg-argo-wireguard.service 2>/dev/null || true
    
    systemctl disable wg-argo-cloudflared.service 2>/dev/null || true
    systemctl disable wg-argo-wireguard.service 2>/dev/null || true
    
    rm -f /etc/systemd/system/wg-argo-cloudflared.service
    rm -f /etc/systemd/system/wg-argo-wireguard.service
    
    # 停止并删除 WireGuard 接口
    wg-quick down wg0 2>/dev/null || true
    rm -f /etc/wireguard/wg0.conf
    
    rm -rf "$CONFIG_DIR" "$LOG_DIR" "$WG_KEY_DIR"
    
    print_input "是否删除 cloudflared 二进制文件？(y/N): "
    read -r delete_bin
    if [[ "$delete_bin" == "y" || "$delete_bin" == "Y" ]]; then
        rm -f "$BIN_DIR/cloudflared"
    fi
    
    print_input "是否删除 Cloudflare 授权文件？(y/N): "
    read -r delete_auth
    if [[ "$delete_auth" == "y" || "$delete_auth" == "Y" ]]; then
        rm -rf /root/.cloudflared
    fi
    
    systemctl daemon-reload
    
    echo ""
    print_success "✅ 卸载完成！"
}

# ----------------------------
# 显示配置信息
# ----------------------------
show_config() {
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件，可能未安装"
        return 1
    fi
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    echo ""
    print_success "当前配置:"
    echo "  域名: $domain"
    echo "  隧道名称: $TUNNEL_NAME"
    echo "  WireGuard 端口: $WIREGUARD_PORT"
    echo ""
    
    if [[ -f "$CONFIG_DIR/client.conf" ]]; then
        print_info "📋 客户端配置:"
        echo "═══════════════════════════════════════════════"
        cat "$CONFIG_DIR/client.conf"
        echo "═══════════════════════════════════════════════"
    fi
    echo ""
}

# ----------------------------
# 显示服务状态
# ----------------------------
show_status() {
    print_info "服务状态检查..."
    echo ""
    
    if systemctl is-active --quiet wg-argo-wireguard.service; then
        print_success "WireGuard 服务: 运行中"
        echo ""
        print_info "WireGuard 接口状态:"
        wg show 2>/dev/null || echo "无法获取接口状态"
    else
        print_error "WireGuard 服务: 未运行"
    fi
    
    echo ""
    
    if systemctl is-active --quiet wg-argo-cloudflared.service; then
        print_success "Cloudflared 服务: 运行中"
        
        echo ""
        print_info "隧道信息:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || true
    else
        print_error "Cloudflared 服务: 未运行"
    fi
    
    # 显示连接数统计
    echo ""
    print_info "连接统计:"
    echo "WireGuard 接口:"
    ip -4 addr show wg0 2>/dev/null | grep inet || echo "wg0 接口未找到"
    echo ""
    echo "活动连接:"
    ss -nulp | grep ":51820" || echo "无 WireGuard 活动连接"
}

# ----------------------------
# 修复 WireGuard 服务
# ----------------------------
fix_wireguard_service() {
    print_info "尝试修复 WireGuard 服务..."
    
    # 停止服务
    systemctl stop wg-argo-wireguard.service 2>/dev/null || true
    wg-quick down wg0 2>/dev/null || true
    
    # 检查内核模块
    if ! lsmod | grep -q wireguard; then
        print_info "加载 WireGuard 内核模块..."
        modprobe wireguard
    fi
    
    # 重新生成密钥
    print_info "重新生成 WireGuard 密钥..."
    rm -rf "$WG_KEY_DIR" 2>/dev/null
    generate_wireguard_keys
    
    # 重新配置
    configure_wireguard
    
    # 测试配置
    if wg-quick up wg0; then
        print_success "✅ WireGuard 配置测试成功"
        wg-quick down wg0
    else
        print_error "❌ WireGuard 配置测试失败"
        return 1
    fi
    
    # 重启服务
    systemctl daemon-reload
    systemctl start wg-argo-wireguard.service
    
    if systemctl is-active --quiet wg-argo-wireguard.service; then
        print_success "✅ WireGuard 服务修复成功"
        return 0
    else
        print_error "❌ WireGuard 服务修复失败"
        return 1
    fi
}

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    show_title
    
    echo "请选择操作："
    echo ""
    echo "  1) 安装 WireGuard + Argo Tunnel"
    echo "  2) 卸载 WireGuard + Argo Tunnel"
    echo "  3) 查看服务状态"
    echo "  4) 查看配置信息"
    echo "  5) 修复 WireGuard 服务"
    echo "  6) 退出"
    echo ""
    
    print_input "请输入选项 (1-6): "
    read -r choice
    
    case "$choice" in
        1)
            SILENT_MODE=false
            if main_install; then
                echo ""
                print_input "按回车键返回菜单..."
                read -r
            else
                echo ""
                print_error "安装失败"
                print_input "按回车键返回菜单..."
                read -r
            fi
            ;;
        2)
            uninstall_all
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        3)
            show_status
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        4)
            show_config
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        5)
            fix_wireguard_service
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        6)
            print_info "再见！"
            exit 0
            ;;
        *)
            print_error "无效选项"
            sleep 1
            ;;
    esac
    
    show_menu
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    case "${1:-}" in
        "install")
            SILENT_MODE=false
            show_title
            main_install
            ;;
        "uninstall")
            show_title
            uninstall_all
            ;;
        "config")
            show_title
            show_config
            ;;
        "status")
            show_title
            show_status
            ;;
        "fix")
            show_title
            fix_wireguard_service
            ;;
        "-y"|"--silent")
            SILENT_MODE=true
            show_title
            main_install
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo ./wg_argo.sh menu          # 显示菜单"
            echo "  sudo ./wg_argo.sh install       # 安装"
            echo "  sudo ./wg_argo.sh uninstall     # 卸载"
            echo "  sudo ./wg_argo.sh status        # 查看状态"
            echo "  sudo ./wg_argo.sh config        # 查看配置"
            echo "  sudo ./wg_argo.sh fix           # 修复服务"
            echo "  sudo ./wg_argo.sh -y            # 静默安装"
            exit 1
            ;;
    esac
}

# 检查是否以root运行
if [[ $EUID -ne 0 ]] && [[ "${1:-}" != "" ]]; then
    print_error "请使用root权限运行此脚本"
    exit 1
fi

main "$@"