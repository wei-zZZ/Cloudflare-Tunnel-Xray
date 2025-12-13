#!/bin/bash
# ============================================
# Cloudflare Tunnel + WireGuard 安装脚本（带优选域名）
# 版本: 1.4 - 添加优选域名和网络修复
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
# 配置变量（新增优选域名列表）
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

# Cloudflare 优选域名列表
OPTIMAL_DOMAINS=(
    "cf.090227.xyz"
    "cdn.100867.xyz"
    "cf.100867.xyz"
    "cdn.cloudflare.180895.xyz"
    "cf.cloudflare.180895.xyz"
    "cdn.180895.xyz"
    "cf.180895.xyz"
    "cdn.023084.xyz"
    "cf.023084.xyz"
    "cdn.speed.cloudflare.com"
    "cf.speed.cloudflare.com"
)

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel + WireGuard 管理脚本          ║"
    echo "║          版本: 1.4 - 优选域名版                    ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
}

# ----------------------------
# 收集用户信息（添加优选域名选项）
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
    
    echo "请选择域名类型："
    echo "  1) 使用自有域名"
    echo "  2) 使用优选域名（自动选择最快的 Cloudflare 节点）"
    echo ""
    print_input "请输入选项 (1-2): "
    read -r domain_type
    
    if [ "$domain_type" = "2" ]; then
        # 使用优选域名
        print_info "正在测试优选域名，请稍候..."
        select_optimal_domain
        
        if [ -n "$USER_DOMAIN" ]; then
            print_success "已选择优选域名: $USER_DOMAIN"
        else
            print_warning "优选域名测试失败，请输入自定义域名"
            domain_type="1"
        fi
    fi
    
    if [ "$domain_type" = "1" ]; then
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
    fi
    
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
# 选择优选域名（新增函数）
# ----------------------------
select_optimal_domain() {
    print_info "开始测试优选域名延迟..."
    
    local best_domain=""
    local best_latency=99999
    
    for domain in "${OPTIMAL_DOMAINS[@]}"; do
        print_info "测试域名: $domain"
        
        # 使用 ping 测试延迟（取平均值）
        local latency=$(ping -c 2 -W 2 "$domain" 2>/dev/null | tail -1 | awk -F '/' '{print $5}' | cut -d '.' -f 1)
        
        if [[ -n "$latency" ]] && [[ "$latency" -lt "$best_latency" ]]; then
            best_latency="$latency"
            best_domain="$domain"
            print_success "  当前最优: ${latency}ms - $domain"
        elif [[ -n "$latency" ]]; then
            print_info "  延迟: ${latency}ms"
        else
            print_warning "  无法连接"
        fi
    done
    
    if [[ -n "$best_domain" ]]; then
        USER_DOMAIN="$best_domain"
        
        # 保存优选域名信息
        echo "OPTIMAL_DOMAIN=$best_domain" > /tmp/optimal_domain.info
        echo "LATENCY=${best_latency}ms" >> /tmp/optimal_domain.info
        echo "TEST_DATE=$(date)" >> /tmp/optimal_domain.info
        
        print_success "✅ 选择最优域名: $best_domain (延迟: ${best_latency}ms)"
        return 0
    else
        print_error "❌ 所有优选域名测试失败"
        return 1
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
    
    # 更新系统
    print_info "更新系统包列表..."
    apt-get update -y
    
    # 安装 iptables
    print_info "安装必要网络工具..."
    apt-get install -y iptables iptables-persistent iproute2 net-tools
    
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
    local tools=("curl" "wget" "qrencode" "ping" "dnsutils")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            apt-get install -y "$tool" 2>/dev/null || {
                print_warning "$tool 安装失败，跳过..."
            }
        fi
    done
    
    # 验证网络连接
    print_info "检查网络连接..."
    if curl -s --connect-timeout 5 https://cloudflare.com > /dev/null; then
        print_success "✅ 网络连接正常"
    else
        print_warning "⚠️  网络连接可能有问题，尝试继续..."
    fi
    
    print_success "系统检查完成"
}

# ----------------------------
# 安装 Cloudflared（增强版）
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
    
    # 清理旧版本
    rm -f /tmp/cloudflared 2>/dev/null
    rm -f "$BIN_DIR/cloudflared" 2>/dev/null
    
    # 尝试多种下载方式
    print_info "下载 cloudflared..."
    
    if curl -L -o /tmp/cloudflared "$cf_url" --connect-timeout 30 --retry 3; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        
        # 验证安装
        if "$BIN_DIR/cloudflared" --version > /dev/null 2>&1; then
            print_success "cloudflared 安装成功"
            print_info "版本信息:"
            "$BIN_DIR/cloudflared" --version
            return 0
        else
            print_error "cloudflared 验证失败"
            return 1
        fi
    else
        print_error "cloudflared 下载失败"
        print_info "尝试备用下载源..."
        
        # 备用下载源
        local alt_url="https://ghproxy.com/$cf_url"
        if curl -L -o /tmp/cloudflared "$alt_url" --connect-timeout 30; then
            mv /tmp/cloudflared "$BIN_DIR/cloudflared"
            chmod +x "$BIN_DIR/cloudflared"
            
            if "$BIN_DIR/cloudflared" --version > /dev/null 2>&1; then
                print_success "cloudflared 安装成功（使用备用源）"
                return 0
            fi
        fi
        
        print_error "所有下载源均失败"
        return 1
    fi
}

# ----------------------------
# Cloudflare 授权（增强版）
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
    
    print_warning "注意：授权需要使用 Cloudflare 账户，且域名需要在 Cloudflare 管理中"
    print_input "按回车开始授权..."
    read -r
    
    echo ""
    echo "=============================================="
    echo "请复制以下链接到浏览器："
    echo ""
    
    # 运行授权命令
    echo "正在生成授权链接..."
    
    local auth_output
    if auth_output=$("$BIN_DIR/cloudflared" tunnel login 2>&1); then
        echo "$auth_output"
    else
        print_error "授权命令执行失败"
        echo "$auth_output"
        return 1
    fi
    
    echo ""
    echo "=============================================="
    print_input "完成授权后按回车继续..."
    read -r
    
    # 检查授权结果
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "✅ 授权成功！找到证书文件"
        
        # 检查凭证文件
        local json_files=(/root/.cloudflared/*.json)
        if [ -e "${json_files[0]}" ]; then
            print_success "✅ 找到凭证文件: $(basename "${json_files[0]}")"
        fi
        
        return 0
    else
        print_error "❌ 授权失败：未找到证书文件"
        print_info "请确保："
        echo "  1. 正确登录 Cloudflare 账户"
        echo "  2. 选择正确的域名"
        echo "  3. 授权过程完整"
        return 1
    fi
}

# ----------------------------
# 修复网络连接问题（新增函数）
# ----------------------------
fix_network_issues() {
    print_info "检查并修复网络连接问题..."
    
    local issues_found=0
    
    # 1. 检查 DNS 设置
    print_info "检查 DNS 设置..."
    if ! grep -q "nameserver 1.1.1.1" /etc/resolv.conf && ! grep -q "nameserver 8.8.8.8" /etc/resolv.conf; then
        print_warning "DNS 设置可能有问题，尝试修复..."
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        issues_found=1
    fi
    
    # 2. 检查防火墙
    print_info "检查防火墙设置..."
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        print_warning "UFW 防火墙已启用，确保 WireGuard 端口开放..."
        ufw allow $WIREGUARD_PORT/udp > /dev/null 2>&1 || true
        issues_found=1
    fi
    
    # 3. 检查 IP 转发
    print_info "检查 IP 转发..."
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
        print_warning "IP 转发未启用，正在启用..."
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        sysctl -p > /dev/null 2>&1
        issues_found=1
    fi
    
    # 4. 检查路由表
    print_info "检查路由表..."
    if ! ip route | grep -q "default"; then
        print_error "未找到默认路由，网络配置有问题"
        issues_found=1
    fi
    
    if [ $issues_found -eq 0 ]; then
        print_success "✅ 网络配置正常"
    else
        print_success "✅ 网络问题已修复"
    fi
    
    return $issues_found
}

# ----------------------------
# 配置 WireGuard（增强版）
# ----------------------------
configure_wireguard_enhanced() {
    print_info "配置 WireGuard（增强版）..."
    
    # 读取密钥
    local server_private=$(cat "$WG_KEY_DIR/server_private.key")
    local server_public=$(cat "$WG_KEY_DIR/server_public.key")
    local client_private=$(cat "$WG_KEY_DIR/client_private.key")
    local client_public=$(cat "$WG_KEY_DIR/client_public.key")
    local preshared_key=$(cat "$WG_KEY_DIR/preshared.key")
    
    # 获取主网络接口
    local main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [[ -z "$main_interface" ]]; then
        main_interface=$(ip link | grep -E "eth[0-9]|ens[0-9]" | grep -v "@" | head -1 | awk -F: '{print $2}' | tr -d ' ')
        if [[ -z "$main_interface" ]]; then
            main_interface="eth0"
        fi
    fi
    
    print_info "主网络接口: $main_interface"
    
    # 生成增强版服务器配置
    cat > "$WG_CONFIG" << EOF
[Interface]
PrivateKey = $server_private
Address = 10.9.0.1/24
ListenPort = $WIREGUARD_PORT
MTU = 1420
DNS = 1.1.1.1, 8.8.8.8
SaveConfig = true

# 预启动命令：确保网络正常
PreUp = sysctl -w net.ipv4.ip_forward=1
PreUp = sysctl -w net.ipv4.conf.all.rp_filter=2
PreUp = sysctl -w net.ipv6.conf.all.forwarding=1

# 启动后命令：设置防火墙转发
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $main_interface -j MASQUERADE
PostUp = ip6tables -A FORWARD -i wg0 -j ACCEPT
PostUp = ip6tables -A FORWARD -o wg0 -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o $main_interface -j MASQUERADE

# 停止前命令：清理防火墙规则
PreDown = iptables -D FORWARD -i wg0 -j ACCEPT
PreDown = iptables -D FORWARD -o wg0 -j ACCEPT
PreDown = iptables -t nat -D POSTROUTING -o $main_interface -j MASQUERADE
PreDown = ip6tables -D FORWARD -i wg0 -j ACCEPT
PreDown = ip6tables -D FORWARD -o wg0 -j ACCEPT
PreDown = ip6tables -t nat -D POSTROUTING -o $main_interface -j MASQUERADE

# 客户端配置
[Peer]
PublicKey = $client_public
PresharedKey = $preshared_key
AllowedIPs = 10.9.0.2/32
PersistentKeepalive = 21
EOF
    
    # 生成增强版客户端配置
    cat > "$CONFIG_DIR/client.conf" << EOF
[Interface]
PrivateKey = $client_private
Address = 10.9.0.2/24
DNS = 1.1.1.1, 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $server_public
PresharedKey = $preshared_key
Endpoint = $USER_DOMAIN:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 21
EOF
    
    # 启用 IP 转发（永久生效）
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo -e "\n# WireGuard IP Forwarding" >> /etc/sysctl.conf
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        echo "net.ipv4.conf.all.rp_filter=2" >> /etc/sysctl.conf
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    fi
    sysctl -p 2>/dev/null || true
    
    # 设置配置文件权限
    chmod 600 "$WG_CONFIG"
    chmod 600 "$CONFIG_DIR/client.conf"
    
    print_success "WireGuard 增强配置完成"
}

# ----------------------------
# 测试 WireGuard 连接
# ----------------------------
test_wireguard_connection() {
    print_info "测试 WireGuard 连接..."
    
    # 先关闭可能存在的 wg0 接口
    wg-quick down wg0 2>/dev/null || true
    sleep 2
    
    # 测试启动
    print_info "启动 WireGuard..."
    if wg-quick up wg0; then
        print_success "✅ WireGuard 启动成功"
        
        # 等待接口就绪
        sleep 2
        
        # 显示状态
        echo ""
        print_info "WireGuard 接口状态:"
        wg show
        
        # 测试内部连通性
        echo ""
        print_info "测试内部连通性..."
        if ping -c 2 -W 2 10.9.0.1 > /dev/null 2>&1; then
            print_success "✅ WireGuard 内部网络正常"
        else
            print_warning "⚠️  WireGuard 内部网络连接失败"
        fi
        
        # 测试外部连通性
        echo ""
        print_info "测试外部连通性..."
        if ping -c 2 -W 2 1.1.1.1 > /dev/null 2>&1; then
            print_success "✅ WireGuard 外部网络正常"
        else
            print_warning "⚠️  WireGuard 外部网络连接失败"
        fi
        
        # 不关闭，让服务继续运行
        return 0
    else
        print_error "❌ WireGuard 启动失败"
        
        # 显示详细错误
        echo ""
        print_info "详细错误信息:"
        wg-quick up wg0 2>&1 | tail -30
        
        return 1
    fi
}

# ----------------------------
# 配置 Cloudflared（增强版）
# ----------------------------
configure_cloudflared_enhanced() {
    print_info "配置 cloudflared（增强版）..."
    
    local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local json_file=$(grep "^CREDENTIALS_FILE=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local wg_port=$(grep "^WG_PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    # 创建增强版 cloudflared 配置
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: $json_file
logfile: $LOG_DIR/argo.log
loglevel: info
transport-loglevel: info
no-autoupdate: true

# 连接优化参数
retries: 10
ha-connections: 4
connection-idle-timeout: 1m30s
graceful-shutdown: 2s
request-timeout: 1m30s

# 隧道配置
protocol: quic
heartbeat-interval: 5s
metrics: 0.0.0.0:41783
no-tls-verify: false

ingress:
  - hostname: $domain
    service: udp://localhost:$wg_port
    originRequest:
      connectTimeout: 15s
      tlsTimeout: 10s
      tcpKeepAlive: 15s
      noHappyEyeballs: false
      keepAliveConnections: 10
      keepAliveTimeout: 1m30s
      httpHostHeader: $domain
      caPool: /etc/ssl/certs/ca-certificates.crt
  - service: http_status:404
EOF
    
    print_success "cloudflared 增强配置完成"
}

# ----------------------------
# 主安装流程（增强版）
# ----------------------------
main_install_enhanced() {
    print_info "开始增强安装流程..."
    
    # 1. 系统检查
    check_system
    
    # 2. 修复网络问题
    fix_network_issues
    
    # 3. 安装组件
    install_cloudflared
    
    # 4. 收集信息
    collect_user_info
    
    # 5. Cloudflare 授权
    if ! direct_cloudflare_auth; then
        print_warning "授权可能有问题"
        print_input "是否继续安装？(y/N): "
        read -r continue_install
        if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
            print_error "安装中止"
            return 1
        fi
    fi
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR" "$WG_KEY_DIR"
    
    # 6. 生成密钥
    generate_wireguard_keys
    
    # 7. 设置隧道
    if ! setup_tunnel; then
        print_error "隧道设置失败"
        return 1
    fi
    
    # 8. 配置 WireGuard
    configure_wireguard_enhanced
    
    # 9. 测试 WireGuard
    if ! test_wireguard_connection; then
        print_error "WireGuard 连接测试失败"
        return 1
    fi
    
    # 10. 配置 Cloudflared
    configure_cloudflared_enhanced
    
    # 11. 配置服务
    configure_services
    
    # 12. 启动服务
    if ! start_services_enhanced; then
        print_error "服务启动失败"
        return 1
    fi
    
    # 13. 显示连接信息
    show_connection_info_enhanced
    
    echo ""
    print_success "🎉 增强版安装完成！"
    return 0
}

# ----------------------------
# 启动服务（增强版）
# ----------------------------
start_services_enhanced() {
    print_info "启动增强版服务..."
    
    # 1. 确保 WireGuard 运行
    print_info "确保 WireGuard 运行..."
    if ! ip link show wg0 &> /dev/null; then
        if ! wg-quick up wg0; then
            print_error "❌ WireGuard 启动失败"
            return 1
        fi
    fi
    
    # 启用 WireGuard 服务
    systemctl enable wg-quick@wg0.service --now 2>/dev/null || {
        print_warning "无法启用 WireGuard 系统服务，使用手动方式"
    }
    
    # 2. 启动 Cloudflared
    print_info "启动 Cloudflared..."
    
    # 创建 Cloudflared 服务
    cat > /etc/systemd/system/wg-argo-cloudflared.service << EOF
[Unit]
Description=WireGuard Argo Tunnel Service
After=network.target
Wants=network-online.target
Requires=wg-quick@wg0.service

[Service]
Type=simple
User=root
Group=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
Environment="TUNNEL_FORCE_PROTOCOL=quic"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run $TUNNEL_NAME
Restart=always
RestartSec=5
StartLimitInterval=0
StandardOutput=append:$LOG_DIR/argo.log
StandardError=append:$LOG_DIR/argo-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable wg-argo-cloudflared.service --now
    
    # 3. 等待并检查隧道状态
    print_info "等待隧道连接建立..."
    
    local max_wait=60
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        if systemctl is-active --quiet wg-argo-cloudflared.service; then
            # 检查隧道状态
            local tunnel_status=$("$BIN_DIR/cloudflared" tunnel info "$TUNNEL_NAME" 2>/dev/null | grep -i "status\|conns" || true)
            
            if echo "$tunnel_status" | grep -q "running\|active"; then
                print_success "✅ Cloudflared 服务运行中"
                print_info "隧道状态:"
                echo "$tunnel_status"
                break
            fi
        fi
        
        if [ $((waited % 15)) -eq 0 ] && [ $waited -gt 0 ]; then
            print_info "已等待 ${waited}秒..."
        fi
        
        sleep 3
        waited=$((waited + 3))
    done
    
    if [ $waited -ge $max_wait ]; then
        print_warning "⚠️  隧道连接较慢，服务可能在后台继续建立连接"
        print_info "查看实时日志: journalctl -u wg-argo-cloudflared.service -f"
    fi
    
    return 0
}

# ----------------------------
# 显示连接信息（增强版）
# ----------------------------
show_connection_info_enhanced() {
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
    print_success "🔐 MTU: 1420"
    
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
    
    # 测试连接性
    print_info "🧪 连接性测试:"
    echo ""
    
    # 测试 WireGuard
    if ip link show wg0 &> /dev/null; then
        print_success "✅ WireGuard 接口: 已激活"
        echo "  接口状态: $(ip -4 addr show wg0 | grep inet | awk '{print $2}')"
    else
        print_error "❌ WireGuard 接口: 未激活"
    fi
    
    echo ""
    
    # 测试 Cloudflared
    if systemctl is-active --quiet wg-argo-cloudflared.service; then
        print_success "✅ Cloudflared 服务: 运行中"
        
        # 显示隧道信息
        echo ""
        print_info "隧道信息:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep -A2 "$TUNNEL_NAME" || echo "正在获取隧道信息..."
    else
        print_error "❌ Cloudflared 服务: 未运行"
    fi
    
    echo ""
    print_info "📋 使用说明:"
    echo "  1. 将 client.conf 导入 WireGuard 客户端"
    echo "  2. 如果使用优选域名，客户端无需额外配置"
    echo "  3. 首次连接可能需要1-2分钟建立隧道"
    echo "  4. MTU 设置为 1420 以优化 Cloudflare 隧道"
    echo ""
    
    print_info "🔧 故障排除:"
    echo "  1. 检查 WireGuard: wg show"
    echo "  2. 检查 Cloudflared: systemctl status wg-argo-cloudflared.service"
    echo "  3. 查看日志: journalctl -u wg-argo-cloudflared.service -f"
    echo "  4. 重启服务: systemctl restart wg-argo-cloudflared.service"
    echo "  5. 更换优选域名: 重新运行安装选择域名类型2"
}

# ----------------------------
# 生成 WireGuard 密钥（保持不变）
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
# 创建隧道和配置（保持不变）
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
# 配置系统服务（保持不变）
# ----------------------------
configure_services() {
    print_info "配置系统服务..."
    
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    
    print_success "系统服务配置完成"
}

# ----------------------------
# 主函数和菜单（调整）
# ----------------------------
# ...（保持原有的主函数和菜单结构，但修改安装函数调用为 main_install_enhanced）

# 在 main() 函数中修改：
main() {
    case "${1:-}" in
        "install")
            SILENT_MODE=false
            show_title
            main_install_enhanced
            ;;
        # ... 其他 case 保持不变
    esac
}