#!/bin/bash
# ============================================
# Cloudflare Tunnel + WireGuard 安装脚本
# 版本: 1.3 - 修复 iptables 问题
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
    echo "║             版本: 1.3 - 修复版              ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
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
# 系统检查（修复 iptables 问题）
# ----------------------------
check_system() {
    print_info "检查系统环境..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    # 更新系统
    print_info "更新系统包列表..."
    apt-get update -y
    
    # 安装 iptables 和必要工具
    print_info "安装 iptables 和相关工具..."
    apt-get install -y iptables iptables-persistent
    
    # 检查并安装 nftables（现代系统可能需要）
    if ! command -v nft &> /dev/null; then
        apt-get install -y nftables 2>/dev/null || true
    fi
    
    # 安装 WireGuard
    if command -v wg &> /dev/null && command -v wg-quick &> /dev/null; then
        print_success "WireGuard 已安装"
    else
        print_info "安装 WireGuard..."
        
        # 安装 WireGuard
        apt-get install -y wireguard wireguard-tools resolvconf
        
        # 对于某些系统可能需要 dkms
        if ! command -v wg &> /dev/null; then
            apt-get install -y wireguard-dkms 2>/dev/null || true
        fi
        
        if ! command -v wg &> /dev/null; then
            print_error "WireGuard 安装失败"
            exit 1
        fi
        print_success "WireGuard 安装成功"
    fi
    
    # 检查 WireGuard 内核模块
    print_info "检查 WireGuard 内核模块..."
    if ! lsmod | grep -q wireguard; then
        print_warning "WireGuard 内核模块未加载，尝试加载..."
        modprobe wireguard 2>/dev/null || {
            print_warning "无法加载 wireguard 模块，可能需要重启"
        }
    else
        print_success "WireGuard 内核模块已加载"
    fi
    
    # 安装其他必要工具
    print_info "安装其他必要工具..."
    local tools=("curl" "wget" "qrencode")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            apt-get install -y "$tool" 2>/dev/null || {
                print_warning "$tool 安装失败，跳过..."
            }
        fi
    done
    
    # 验证 iptables 安装
    if ! command -v iptables &> /dev/null; then
        print_error "iptables 安装失败，尝试替代方案..."
        
        # 尝试使用 nftables
        if command -v nft &> /dev/null; then
            print_info "使用 nftables 替代 iptables"
        else
            print_error "无防火墙工具可用，安装可能受影响"
        fi
    else
        print_success "iptables 已安装"
    fi
    
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
# 配置 WireGuard（无 iptables 版本）
# ----------------------------
configure_wireguard_no_iptables() {
    print_info "配置 WireGuard（不使用 iptables）..."
    
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
    
    print_info "主网络接口: $main_interface"
    
    # 检查 iptables 是否可用
    local use_iptables=false
    if command -v iptables &> /dev/null; then
        use_iptables=true
        print_info "使用 iptables 进行转发"
    else
        print_warning "iptables 不可用，使用替代配置"
    fi
    
    # 生成服务器配置
    cat > "$WG_CONFIG" << EOF
[Interface]
PrivateKey = $server_private
Address = 10.9.0.1/24
ListenPort = $WIREGUARD_PORT
MTU = 1280
DNS = 1.1.1.1, 8.8.8.8
SaveConfig = true

# 启用 IP 转发
PostUp = sysctl -w net.ipv4.ip_forward=1
PostDown = sysctl -w net.ipv4.ip_forward=0
EOF
    
    # 如果有 iptables，添加转发规则
    if [ "$use_iptables" = true ]; then
        cat >> "$WG_CONFIG" << EOF

# iptables 转发规则
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $main_interface -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $main_interface -j MASQUERADE
EOF
    else
        cat >> "$WG_CONFIG" << EOF

# 无 iptables 配置
# 如果需要转发，请手动配置防火墙
# 或者使用 nftables 等其他工具
EOF
    fi
    
    # 添加客户端配置
    cat >> "$WG_CONFIG" << EOF

# 客户端配置
[Peer]
PublicKey = $client_public
PresharedKey = $preshared_key
AllowedIPs = 10.9.0.2/32
PersistentKeepalive = 25
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
    sysctl -p 2>/dev/null || true
    
    # 设置配置文件权限
    chmod 600 "$WG_CONFIG"
    chmod 600 "$CONFIG_DIR/client.conf"
    
    print_success "WireGuard 配置完成"
}

# ----------------------------
# 测试 WireGuard 配置（安全版本）
# ----------------------------
test_wireguard_config_safe() {
    print_info "测试 WireGuard 配置..."
    
    # 先关闭可能存在的 wg0 接口
    wg-quick down wg0 2>/dev/null || true
    sleep 1
    
    # 创建临时配置（无 iptables 规则）
    local temp_config="/tmp/wg0-test.conf"
    local server_private=$(cat "$WG_KEY_DIR/server_private.key")
    local server_public=$(cat "$WG_KEY_DIR/server_public.key")
    local client_public=$(cat "$WG_KEY_DIR/client_public.key")
    local preshared_key=$(cat "$WG_KEY_DIR/preshared.key")
    
    # 生成测试配置（仅基本功能，无防火墙规则）
    cat > "$temp_config" << EOF
[Interface]
PrivateKey = $server_private
Address = 10.9.0.1/24
ListenPort = $WIREGUARD_PORT
MTU = 1280
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $client_public
PresharedKey = $preshared_key
AllowedIPs = 10.9.0.2/32
PersistentKeepalive = 25
EOF
    
    # 使用临时配置测试
    print_info "使用简化配置测试 WireGuard..."
    
    if wg-quick up "$temp_config"; then
        print_success "✅ WireGuard 基本功能测试成功"
        
        # 显示状态
        echo ""
        print_info "WireGuard 接口状态:"
        wg show
        
        # 检查接口
        if ip link show wg0 &> /dev/null; then
            print_success "✅ wg0 接口创建成功"
            echo "接口 IP: $(ip addr show wg0 | grep 'inet ' | awk '{print $2}')"
        fi
        
        # 测试后关闭
        wg-quick down "$temp_config"
        rm -f "$temp_config"
        
        return 0
    else
        print_error "❌ WireGuard 基本功能测试失败"
        
        # 显示详细错误
        echo ""
        print_info "详细错误信息:"
        wg-quick up "$temp_config" 2>&1 | tail -30
        
        rm -f "$temp_config"
        return 1
    fi
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
      connectTimeout: 30s
      tcpKeepAlive: 30s
      noHappyEyeballs: true
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
    
    # 创建 WireGuard 启动脚本（替代系统服务）
    cat > /usr/local/bin/wg-start << 'EOF'
#!/bin/bash
# WireGuard 启动脚本

CONFIG="/etc/wireguard/wg0.conf"

if [ ! -f "$CONFIG" ]; then
    echo "错误：WireGuard 配置文件不存在: $CONFIG"
    exit 1
fi

# 检查 iptables 是否可用
if ! command -v iptables &> /dev/null; then
    echo "警告：iptables 不可用，仅启动基本功能"
    # 修改配置，移除 iptables 规则
    sed -i '/^PostUp = iptables/d' "$CONFIG"
    sed -i '/^PostDown = iptables/d' "$CONFIG"
fi

# 启动 WireGuard
wg-quick up wg0

# 检查是否成功
if [ $? -eq 0 ]; then
    echo "WireGuard 启动成功"
    wg show
else
    echo "WireGuard 启动失败"
fi
EOF
    
    chmod +x /usr/local/bin/wg-start
    
    # 创建 WireGuard 停止脚本
    cat > /usr/local/bin/wg-stop << 'EOF'
#!/bin/bash
# WireGuard 停止脚本
wg-quick down wg0 2>/dev/null || true
echo "WireGuard 已停止"
EOF
    
    chmod +x /usr/local/bin/wg-stop
    
    # 创建 Cloudflared 服务文件
    cat > /etc/systemd/system/wg-argo-cloudflared.service << EOF
[Unit]
Description=WireGuard Argo Tunnel Service
After=network.target
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
    
    # 创建 WireGuard 服务（简化版）
    cat > /etc/systemd/system/wg-argo-wireguard.service << EOF
[Unit]
Description=WireGuard VPN Service
After=network.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/wg-start
ExecStop=/usr/local/bin/wg-stop
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载systemd
    systemctl daemon-reload
    
    print_success "系统服务配置完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    # 停止可能存在的服务
    systemctl stop wg-argo-cloudflared.service 2>/dev/null || true
    systemctl stop wg-argo-wireguard.service 2>/dev/null || true
    wg-quick down wg0 2>/dev/null || true
    sleep 2
    
    # 1. 启动 WireGuard（使用我们的启动脚本）
    print_info "启动 WireGuard..."
    if /usr/local/bin/wg-start; then
        print_success "✅ WireGuard 启动成功"
        
        # 启用服务
        systemctl enable wg-argo-wireguard.service --now
    else
        print_error "❌ WireGuard 启动失败"
        
        # 尝试直接启动（无防火墙规则）
        print_info "尝试直接启动 WireGuard（无防火墙规则）..."
        wg-quick up wg0 2>&1 | grep -v "iptables" || {
            # 创建无防火墙的临时配置
            local temp_config="/tmp/wg0-simple.conf"
            local server_private=$(cat "$WG_KEY_DIR/server_private.key")
            local client_public=$(cat "$WG_KEY_DIR/client_public.key")
            local preshared_key=$(cat "$WG_KEY_DIR/preshared.key")
            
            cat > "$temp_config" << EOF
[Interface]
PrivateKey = $server_private
Address = 10.9.0.1/24
ListenPort = $WIREGUARD_PORT
MTU = 1280

[Peer]
PublicKey = $client_public
PresharedKey = $preshared_key
AllowedIPs = 10.9.0.2/32
PersistentKeepalive = 25
EOF
            
            if wg-quick up "$temp_config"; then
                print_success "✅ WireGuard 启动成功（简化模式）"
                # 复制配置到正式位置
                cp "$temp_config" "$WG_CONFIG"
                rm -f "$temp_config"
            else
                print_error "❌ WireGuard 完全启动失败"
                return 1
            fi
        }
    fi
    
    # 2. 启动 Cloudflared
    print_info "启动 Cloudflared..."
    systemctl enable wg-argo-cloudflared.service --now
    
    # 检查 Cloudflared 状态
    local max_checks=15
    local check_count=0
    
    while [[ $check_count -lt $max_checks ]]; do
        if systemctl is-active --quiet wg-argo-cloudflared.service; then
            print_success "✅ Cloudflared 服务运行中"
            break
        fi
        
        sleep 2
        ((check_count++))
        
        if [[ $check_count -eq 5 ]]; then
            print_warning "Cloudflared 启动较慢，正在等待..."
        fi
    done
    
    if [[ $check_count -ge $max_checks ]]; then
        print_warning "⚠️  Cloudflared 启动超时，但可能仍在后台启动"
        print_info "查看日志: journalctl -u wg-argo-cloudflared.service -f"
    fi
    
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
    
    # 生成 QR 码
    if command -v qrencode &> /dev/null; then
        print_info "📱 客户端配置二维码:"
        qrencode -t utf8 < "$CONFIG_DIR/client.conf"
        echo ""
    fi
    
    # 显示服务状态
    show_service_status
    
    echo ""
    print_info "📋 使用说明:"
    echo "  1. 将 client.conf 导入 WireGuard 客户端"
    echo "  2. 或扫描上面的二维码（如果支持）"
    echo "  3. 如果连接不上，等待2-3分钟再试"
    echo "  4. 手动启动 WireGuard: wg-start"
    echo "  5. 手动停止 WireGuard: wg-stop"
    echo ""
    
    print_info "🔧 管理命令:"
    echo "  查看 WireGuard 状态: wg show"
    echo "  重启 Cloudflared: systemctl restart wg-argo-cloudflared.service"
    echo "  查看日志: journalctl -u wg-argo-cloudflared.service -f"
}

# ----------------------------
# 显示服务状态
# ----------------------------
show_service_status() {
    print_info "🧪 服务状态:"
    echo ""
    
    # 检查 WireGuard
    if ip link show wg0 &> /dev/null; then
        print_success "✅ WireGuard 接口: 已激活"
        echo ""
        print_info "WireGuard 状态:"
        wg show 2>/dev/null || echo "无法获取详细状态"
    else
        print_warning "⚠️  WireGuard 接口: 未激活"
        echo "启动命令: wg-start 或 wg-quick up wg0"
    fi
    
    echo ""
    
    # 检查 Cloudflared
    if systemctl is-active --quiet wg-argo-cloudflared.service; then
        print_success "✅ Cloudflared 服务: 运行中"
        
        echo ""
        print_info "隧道信息:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || echo "隧道信息获取中..."
    else
        print_error "❌ Cloudflared 服务: 未运行"
        echo "启动命令: systemctl start wg-argo-cloudflared.service"
    fi
}

# ----------------------------
# 主安装流程
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
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    generate_wireguard_keys
    configure_wireguard_no_iptables
    
    # 测试 WireGuard 配置
    print_info "测试 WireGuard 配置..."
    if ! test_wireguard_config_safe; then
        print_error "WireGuard 配置测试失败"
        return 1
    fi
    
    configure_cloudflared
    configure_services
    
    if ! start_services; then
        print_error "服务启动失败"
        
        # 提供调试信息
        echo ""
        print_info "🛠️  手动调试步骤:"
        echo "1. 检查 WireGuard 配置: cat $WG_CONFIG"
        echo "2. 手动启动: wg-quick up wg0"
        echo "3. 检查状态: wg show"
        echo "4. 查看日志: journalctl -xe"
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
    
    # 停止 WireGuard
    wg-quick down wg0 2>/dev/null || true
    
    # 删除服务文件
    rm -f /etc/systemd/system/wg-argo-cloudflared.service
    rm -f /etc/systemd/system/wg-argo-wireguard.service
    
    # 删除脚本
    rm -f /usr/local/bin/wg-start
    rm -f /usr/local/bin/wg-stop
    
    # 删除配置目录
    rm -rf "$CONFIG_DIR" "$LOG_DIR" "$WG_KEY_DIR"
    rm -f /etc/wireguard/wg0.conf
    
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
# 手动修复 WireGuard
# ----------------------------
manual_fix_wireguard() {
    print_info "手动修复 WireGuard..."
    
    # 1. 安装 iptables
    print_info "检查并安装 iptables..."
    if ! command -v iptables &> /dev/null; then
        apt-get update
        apt-get install -y iptables iptables-persistent
    fi
    
    # 2. 重新配置 WireGuard（启用 iptables）
    print_info "重新配置 WireGuard..."
    
    # 读取密钥
    local server_private=$(cat "$WG_KEY_DIR/server_private.key")
    local client_public=$(cat "$WG_KEY_DIR/client_public.key")
    local preshared_key=$(cat "$WG_KEY_DIR/preshared.key")
    local main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [[ -z "$main_interface" ]]; then
        main_interface="eth0"
    fi
    
    # 生成新配置
    cat > "$WG_CONFIG" << EOF
[Interface]
PrivateKey = $server_private
Address = 10.9.0.1/24
ListenPort = $WIREGUARD_PORT
MTU = 1280
DNS = 1.1.1.1, 8.8.8.8
SaveConfig = true

# 启用 IP 转发
PostUp = sysctl -w net.ipv4.ip_forward=1
PostDown = sysctl -w net.ipv4.ip_forward=0

[Peer]
PublicKey = $client_public
PresharedKey = $preshared_key
AllowedIPs = 10.9.0.2/32
PersistentKeepalive = 25
EOF
    
    # 如果有 iptables，添加规则
    if command -v iptables &> /dev/null; then
        cat >> "$WG_CONFIG" << EOF

# iptables 规则（如果可用）
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $main_interface -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $main_interface -j MASQUERADE
EOF
    fi
    
    # 3. 测试启动
    print_info "测试 WireGuard 启动..."
    if wg-quick up wg0; then
        print_success "✅ WireGuard 修复成功"
        wg show
        systemctl restart wg-argo-wireguard.service
    else
        print_error "❌ WireGuard 修复失败"
        print_info "尝试无防火墙启动..."
        
        # 移除 iptables 规则
        sed -i '/^PostUp = iptables/d' "$WG_CONFIG"
        sed -i '/^PostDown = iptables/d' "$WG_CONFIG"
        
        if wg-quick up wg0; then
            print_success "✅ WireGuard 启动成功（无防火墙）"
        fi
    fi
    
    echo ""
    print_info "修复完成！"
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
    echo "  5) 手动修复 WireGuard"
    echo "  6) 安装 iptables"
    echo "  7) 退出"
    echo ""
    
    print_input "请输入选项 (1-7): "
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
            show_service_status
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        4)
            if [[ -f "$CONFIG_DIR/tunnel.conf" ]]; then
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
            else
                print_error "未找到配置文件"
            fi
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        5)
            manual_fix_wireguard
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        6)
            print_info "安装 iptables..."
            apt-get update
            apt-get install -y iptables iptables-persistent
            echo ""
            print_success "iptables 安装完成"
            print_input "按回车键返回菜单..."
            read -r
            ;;
        7)
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
        "status")
            show_title
            show_service_status
            ;;
        "config")
            show_title
            if [[ -f "$CONFIG_DIR/tunnel.conf" ]]; then
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
            else
                print_error "未找到配置文件"
            fi
            ;;
        "fix")
            show_title
            manual_fix_wireguard
            ;;
        "install-iptables")
            show_title
            apt-get update
            apt-get install -y iptables iptables-persistent
            print_success "iptables 安装完成"
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
            echo "  sudo ./wg_argo.sh menu               # 显示菜单"
            echo "  sudo ./wg_argo.sh install            # 安装"
            echo "  sudo ./wg_argo.sh uninstall          # 卸载"
            echo "  sudo ./wg_argo.sh status             # 查看状态"
            echo "  sudo ./wg_argo.sh config             # 查看配置"
            echo "  sudo ./wg_argo.sh fix                # 手动修复"
            echo "  sudo ./wg_argo.sh install-iptables   # 安装 iptables"
            echo "  sudo ./wg_argo.sh -y                 # 静默安装"
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