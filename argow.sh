#!/bin/bash
# ============================================
# Cloudflare Tunnel + Shadowsocks 安装脚本
# 版本: 1.0 - 适配 v2rayN 客户端
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
PURPLE='\033[0;35m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }
print_input() { echo -e "${CYAN}[?]${NC} $1"; }
print_auth() { echo -e "${GREEN}[🔐]${NC} $1"; }
print_ss() { echo -e "${PURPLE}[🛡️]${NC} $1"; }

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/ss-argo"
LOG_DIR="/var/log/ss-argo"
BIN_DIR="/usr/local/bin"
SERVICE_USER="ss-argo"
SERVICE_GROUP="ss-argo"

USER_DOMAIN=""
TUNNEL_NAME="ss-argo-tunnel"
SHADOWSOCKS_PORT=10000
SHADOWSOCKS_PASSWORD=""
SHADOWSOCKS_METHOD="chacha20-ietf-poly1305"
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
    "argo.example.com"
)

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel + Shadowsocks 管理脚本         ║"
    echo "║              版本: 1.0 - v2rayN适配版               ║"
    echo "╚══════════════════════════════════════════════════════╝"
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
        USER_DOMAIN="ss.example.com"
        SHADOWSOCKS_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        print_info "静默模式：使用默认域名 $USER_DOMAIN"
        print_info "隧道名称: $TUNNEL_NAME"
        print_info "密码已自动生成"
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
            print_input "请输入您的域名 (例如: ss.yourdomain.com):"
            read -r USER_DOMAIN
            
            if [[ -z "$USER_DOMAIN" ]]; then
                print_error "域名不能为空！"
            elif ! [[ "$USER_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$ ]]; then
                print_error "域名格式不正确，请重新输入！"
                USER_DOMAIN=""
            fi
        done
    fi
    
    print_input "请输入隧道名称 [默认: ss-argo-tunnel]:"
    read -r TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"ss-argo-tunnel"}
    
    print_input "请输入 Shadowsocks 端口 [默认: 10000]:"
    read -r input_port
    SHADOWSOCKS_PORT=${input_port:-10000}
    
    # 选择加密方法
    echo ""
    print_info "选择 Shadowsocks 加密方法:"
    echo "  1) chacha20-ietf-poly1305 (推荐)"
    echo "  2) aes-256-gcm"
    echo "  3) aes-128-gcm"
    echo "  4) xchacha20-ietf-poly1305"
    echo ""
    print_input "请输入选项 (1-4) [默认: 1]:"
    read -r method_choice
    
    case $method_choice in
        1) SHADOWSOCKS_METHOD="chacha20-ietf-poly1305" ;;
        2) SHADOWSOCKS_METHOD="aes-256-gcm" ;;
        3) SHADOWSOCKS_METHOD="aes-128-gcm" ;;
        4) SHADOWSOCKS_METHOD="xchacha20-ietf-poly1305" ;;
        *) SHADOWSOCKS_METHOD="chacha20-ietf-poly1305" ;;
    esac
    
    # 设置密码
    echo ""
    print_input "请输入 Shadowsocks 密码 (留空则自动生成):"
    read -r input_password
    
    if [[ -z "$input_password" ]]; then
        SHADOWSOCKS_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        print_success "已自动生成密码: $SHADOWSOCKS_PASSWORD"
    else
        SHADOWSOCKS_PASSWORD="$input_password"
    fi
    
    echo ""
    print_success "配置已保存:"
    echo "  域名: $USER_DOMAIN"
    echo "  隧道名称: $TUNNEL_NAME"
    echo "  Shadowsocks 端口: $SHADOWSOCKS_PORT"
    echo "  加密方法: $SHADOWSOCKS_METHOD"
    echo "  密码: $SHADOWSOCKS_PASSWORD"
    echo ""
}

# ----------------------------
# 选择优选域名
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
        mkdir -p "$CONFIG_DIR"
        echo "OPTIMAL_DOMAIN=$best_domain" > "$CONFIG_DIR/optimal_domain.info"
        echo "LATENCY=${best_latency}ms" >> "$CONFIG_DIR/optimal_domain.info"
        echo "TEST_DATE=$(date)" >> "$CONFIG_DIR/optimal_domain.info"
        
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
    
    # 安装必要工具
    print_info "安装必要工具..."
    local tools=("curl" "wget" "unzip" "jq" "net-tools" "iproute2")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            apt-get install -y "$tool" 2>/dev/null || {
                print_warning "$tool 安装失败，跳过..."
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
    
    # 清理旧版本
    rm -f /tmp/cloudflared 2>/dev/null
    rm -f "$BIN_DIR/cloudflared" 2>/dev/null
    
    # 下载 cloudflared
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
# 安装 Shadowsocks-rust
# ----------------------------
install_shadowsocks() {
    print_info "安装 Shadowsocks-rust..."
    
    local arch
    arch=$(uname -m)
    
    # 根据架构选择下载链接
    case "$arch" in
        x86_64|amd64)
            local ss_url="https://github.com/shadowsocks/shadowsocks-rust/releases/latest/download/shadowsocks-x86_64-unknown-linux-gnu.tar.xz"
            ;;
        aarch64|arm64)
            local ss_url="https://github.com/shadowsocks/shadowsocks-rust/releases/latest/download/shadowsocks-aarch64-unknown-linux-gnu.tar.xz"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    # 下载并解压
    print_info "下载 Shadowsocks-rust..."
    if curl -L -o /tmp/shadowsocks.tar.xz "$ss_url" --connect-timeout 30 --retry 3; then
        mkdir -p /tmp/shadowsocks
        tar -xf /tmp/shadowsocks.tar.xz -C /tmp/shadowsocks
        
        # 找到 sslocal 和 ssserver 二进制文件
        local sslocal_bin=$(find /tmp/shadowsocks -name "sslocal" -type f | head -1)
        local ssserver_bin=$(find /tmp/shadowsocks -name "ssserver" -type f | head -1)
        
        if [[ -n "$sslocal_bin" ]] && [[ -f "$sslocal_bin" ]]; then
            cp "$sslocal_bin" "$BIN_DIR/sslocal"
            chmod +x "$BIN_DIR/sslocal"
            print_success "sslocal 安装成功"
        fi
        
        if [[ -n "$ssserver_bin" ]] && [[ -f "$ssserver_bin" ]]; then
            cp "$ssserver_bin" "$BIN_DIR/ssserver"
            chmod +x "$BIN_DIR/ssserver"
            print_success "ssserver 安装成功"
        fi
        
        # 清理临时文件
        rm -rf /tmp/shadowsocks /tmp/shadowsocks.tar.xz
        
        # 验证安装
        if command -v ssserver &> /dev/null; then
            print_success "Shadowsocks-rust 安装完成"
            return 0
        else
            print_error "Shadowsocks-rust 安装失败"
            return 1
        fi
    else
        print_error "Shadowsocks-rust 下载失败"
        
        # 尝试使用 apt 安装
        print_info "尝试使用 apt 安装 Shadowsocks..."
        if apt-get install -y shadowsocks-libev 2>/dev/null; then
            print_success "Shadowsocks-libev 安装成功"
            # 设置二进制文件路径
            ln -sf /usr/bin/ss-server "$BIN_DIR/ssserver"
            ln -sf /usr/bin/ss-local "$BIN_DIR/sslocal"
            return 0
        else
            print_error "无法安装 Shadowsocks"
            return 1
        fi
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
    
    # 绑定域名（如果是自有域名）
    if [[ "$USER_DOMAIN" != argo.example.com ]] && [[ ! "$USER_DOMAIN" =~ ^(cf\.|cdn\.) ]]; then
        print_info "绑定域名: $USER_DOMAIN"
        "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN" > /dev/null 2>&1
        print_success "✅ 域名绑定成功"
    else
        print_info "使用优选域名，无需 DNS 绑定"
    fi
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 保存隧道配置
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
SS_PORT=$SHADOWSOCKS_PORT
SS_METHOD=$SHADOWSOCKS_METHOD
SS_PASSWORD=$SHADOWSOCKS_PASSWORD
CERT_PATH=/root/.cloudflared/cert.pem
CREDENTIALS_FILE=$json_file
CREATED_DATE=$(date +"%Y-%m-%d")
EOF
    
    print_success "隧道设置完成"
}

# ----------------------------
# 配置 Shadowsocks
# ----------------------------
configure_shadowsocks() {
    print_info "配置 Shadowsocks..."
    
    # 创建 Shadowsocks 配置文件
    cat > "$CONFIG_DIR/shadowsocks.json" << EOF
{
    "server": "127.0.0.1",
    "server_port": $SHADOWSOCKS_PORT,
    "password": "$SHADOWSOCKS_PASSWORD",
    "method": "$SHADOWSOCKS_METHOD",
    "mode": "tcp_and_udp",
    "fast_open": true,
    "timeout": 300,
    "plugin": "",
    "plugin_opts": "",
    "user": "nobody",
    "workers": 2,
    "nameserver": "1.1.1.1",
    "tcp_no_delay": true,
    "keep_alive": 30
}
EOF
    
    # 创建 Shadowsocks 启动脚本
    cat > "$CONFIG_DIR/start-ss.sh" << 'EOF'
#!/bin/bash
CONFIG_DIR="/etc/ss-argo"
LOG_DIR="/var/log/ss-argo"

# 停止已有的 ssserver
pkill -f "ssserver" || true
sleep 1

# 启动 Shadowsocks 服务器
if command -v ssserver &> /dev/null; then
    ssserver -c "$CONFIG_DIR/shadowsocks.json" --log-without-time > "$LOG_DIR/ss.log" 2>&1 &
    echo $! > /tmp/ss-server.pid
    echo "Shadowsocks 启动成功"
else
    echo "错误: ssserver 未找到"
    exit 1
fi
EOF
    
    chmod +x "$CONFIG_DIR/start-ss.sh"
    
    print_success "Shadowsocks 配置完成"
}

# ----------------------------
# 配置 Cloudflared
# ----------------------------
configure_cloudflared() {
    print_info "配置 cloudflared..."
    
    local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local json_file=$(grep "^CREDENTIALS_FILE=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local ss_port=$(grep "^SS_PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    # 创建 cloudflared 配置文件
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
metrics: 0.0.0.0:41784
no-tls-verify: false

ingress:
  - hostname: $domain
    service: tcp://localhost:$ss_port
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
    
    print_success "cloudflared 配置完成"
}

# ----------------------------
# 配置系统服务
# ----------------------------
configure_services() {
    print_info "配置系统服务..."
    
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    
    # 创建服务用户
    if ! id -u "$SERVICE_USER" &> /dev/null; then
        useradd -r -s /usr/sbin/nologin "$SERVICE_USER"
    fi
    
    # 设置目录权限
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR" "$LOG_DIR"
    
    # 创建 Shadowsocks 服务
    cat > /etc/systemd/system/ss-argo-shadowsocks.service << EOF
[Unit]
Description=Shadowsocks Server for Argo Tunnel
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$BIN_DIR/ssserver -c $CONFIG_DIR/shadowsocks.json
Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/ss.log
StandardError=append:$LOG_DIR/ss-error.log
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF
    
    # 创建 Cloudflared 服务
    cat > /etc/systemd/system/ss-argo-cloudflared.service << EOF
[Unit]
Description=Shadowsocks Argo Tunnel Service
After=network.target ss-argo-shadowsocks.service
Wants=network-online.target

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
    
    # 重载 systemd
    systemctl daemon-reload
    
    print_success "系统服务配置完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    # 停止可能存在的旧服务
    systemctl stop ss-argo-cloudflared.service 2>/dev/null || true
    systemctl stop ss-argo-shadowsocks.service 2>/dev/null || true
    
    # 启动 Shadowsocks 服务
    print_info "启动 Shadowsocks..."
    systemctl enable ss-argo-shadowsocks.service --now
    
    if systemctl is-active --quiet ss-argo-shadowsocks.service; then
        print_success "✅ Shadowsocks 启动成功"
    else
        print_error "❌ Shadowsocks 启动失败"
        journalctl -u ss-argo-shadowsocks.service -n 20 --no-pager
        return 1
    fi
    
    # 启动 Cloudflared 服务
    print_info "启动 Cloudflared..."
    systemctl enable ss-argo-cloudflared.service --now
    
    # 等待隧道连接
    local wait_time=0
    local max_wait=60
    
    print_info "等待隧道连接建立（最多60秒）..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        if systemctl is-active --quiet ss-argo-cloudflared.service; then
            # 检查隧道状态
            local tunnel_status=$("$BIN_DIR/cloudflared" tunnel info "$TUNNEL_NAME" 2>/dev/null | grep -i "status\|conns" || true)
            
            if echo "$tunnel_status" | grep -q "running\|active"; then
                print_success "✅ Cloudflared 服务运行中"
                print_info "隧道状态:"
                echo "$tunnel_status"
                break
            fi
        fi
        
        if [[ $((wait_time % 15)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            print_info "已等待 ${wait_time}秒..."
        fi
        
        sleep 3
        ((wait_time+=3))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        print_warning "⚠️  隧道连接较慢，服务可能在后台继续建立连接"
        print_info "查看实时日志: journalctl -u ss-argo-cloudflared.service -f"
    fi
    
    return 0
}

# ----------------------------
# 生成 v2rayN 配置文件
# ----------------------------
generate_v2rayn_config() {
    print_info "生成 v2rayN 配置文件..."
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local password=$(grep "^SS_PASSWORD=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local method=$(grep "^SS_METHOD=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    # 生成 Shadowsocks 链接
    local ss_link=$(echo -n "${method}:${password}@${domain}:443" | base64 -w 0)
    ss_link="ss://${ss_link}#Argo-Shadowsocks"
    
    # 生成 v2rayN JSON 配置
    cat > "$CONFIG_DIR/v2rayN.json" << EOF
{
    "remarks": "Argo-Shadowsocks",
    "server": "$domain",
    "server_port": 443,
    "password": "$password",
    "method": "$method",
    "plugin": "",
    "plugin_opts": "",
    "timeout": 300,
    "fast_open": true,
    "protocol": "origin",
    "protocol_param": "",
    "obfs": "plain",
    "obfs_param": "",
    "udp": true,
    "tcp": true
}
EOF
    
    # 生成 Clash 配置
    cat > "$CONFIG_DIR/clash.yaml" << EOF
proxies:
  - name: "Argo-Shadowsocks"
    type: ss
    server: $domain
    port: 443
    cipher: $method
    password: "$password"
    udp: true
    plugin: ""
    plugin-opts: {}
    
proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "Argo-Shadowsocks"

rules:
  - "MATCH,PROXY"
EOF
    
    # 生成客户端配置文件
    cat > "$CONFIG_DIR/client-guide.md" << EOF
# Shadowsocks 客户端配置指南

## 连接信息
- 服务器地址: $domain
- 端口: 443
- 密码: $password
- 加密方法: $method
- 协议: origin
- 混淆: plain

## v2rayN 配置
1. 打开 v2rayN
2. 点击 "服务器" -> "添加[Shadowsocks]服务器"
3. 填写以下信息：
   - 地址(Address): $domain
   - 端口(Port): 443
   - 密码(Password): $password
   - 加密方式(Encryption): $method
4. 点击 "确定" 保存

## 通用 Shadowsocks 链接
\`\`\`
$ss_link
\`\`\`

## Clash 配置
配置文件已生成: \`$CONFIG_DIR/clash.yaml\`

## 注意事项
1. 确保使用 TCP 协议
2. 首次连接可能需要等待隧道建立（1-2分钟）
3. 如果连接失败，尝试更换优选域名
EOF
    
    echo ""
    print_success "✅ v2rayN 配置文件生成完成"
    echo "配置文件位置: $CONFIG_DIR/"
    echo ""
    print_info "📋 Shadowsocks 链接:"
    echo "$ss_link"
    echo ""
    print_info "📱 二维码:"
    if command -v qrencode &> /dev/null; then
        qrencode -t utf8 <<< "$ss_link"
    else
        echo "安装 qrencode 以生成二维码: apt-get install -y qrencode"
    fi
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
    local password=$(grep "^SS_PASSWORD=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local method=$(grep "^SS_METHOD=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    print_success "🔗 服务器地址: $domain"
    print_success "🚪 端口: 443 (通过 Cloudflare Tunnel)"
    print_success "🔑 密码: $password"
    print_success "🔐 加密方法: $method"
    print_success "📁 配置文件: $CONFIG_DIR/"
    
    echo ""
    
    # 生成 Shadowsocks 链接
    local ss_link=$(echo -n "${method}:${password}@${domain}:443" | base64 -w 0)
    ss_link="ss://${ss_link}#Argo-Shadowsocks"
    
    print_info "📋 Shadowsocks 链接:"
    echo "$ss_link"
    echo ""
    
    # 生成二维码
    if command -v qrencode &> /dev/null; then
        print_info "📱 二维码:"
        qrencode -t utf8 <<< "$ss_link"
        echo ""
    fi
    
    print_info "🧪 服务状态:"
    echo ""
    
    if systemctl is-active --quiet ss-argo-shadowsocks.service; then
        print_success "✅ Shadowsocks 服务: 运行中"
    else
        print_error "❌ Shadowsocks 服务: 未运行"
    fi
    
    echo ""
    
    if systemctl is-active --quiet ss-argo-cloudflared.service; then
        print_success "✅ Cloudflared 服务: 运行中"
        
        echo ""
        print_info "隧道信息:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || echo "正在获取隧道信息..."
    else
        print_error "❌ Cloudflared 服务: 未运行"
    fi
    
    echo ""
    print_info "📋 v2rayN 配置说明:"
    echo "  1. 服务器类型选择 Shadowsocks"
    echo "  2. 地址: $domain"
    echo "  3. 端口: 443"
    echo "  4. 密码: $password"
    echo "  5. 加密: $method"
    echo "  6. 协议: origin"
    echo "  7. 混淆: plain"
    echo ""
    
    print_info "🔧 管理命令:"
    echo "  状态检查: sudo ./ss_argo.sh status"
    echo "  重启服务: systemctl restart ss-argo-cloudflared.service"
    echo "  查看日志: journalctl -u ss-argo-cloudflared.service -f"
    echo "  重新生成配置: sudo ./ss_argo.sh config"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    print_info "开始安装流程..."
    
    check_system
    install_cloudflared
    install_shadowsocks
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
    
    configure_shadowsocks
    configure_cloudflared
    configure_services
    
    if ! start_services; then
        print_error "服务启动失败"
        return 1
    fi
    
    generate_v2rayn_config
    show_connection_info
    
    echo ""
    print_success "🎉 安装完成！"
    return 0
}

# ----------------------------
# 卸载功能
# ----------------------------
uninstall_all() {
    print_info "开始卸载 Argo Shadowsocks..."
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
    
    systemctl stop ss-argo-cloudflared.service 2>/dev/null || true
    systemctl stop ss-argo-shadowsocks.service 2>/dev/null || true
    
    systemctl disable ss-argo-cloudflared.service 2>/dev/null || true
    systemctl disable ss-argo-shadowsocks.service 2>/dev/null || true
    
    rm -f /etc/systemd/system/ss-argo-cloudflared.service
    rm -f /etc/systemd/system/ss-argo-shadowsocks.service
    
    print_input "是否删除 Cloudflare 隧道？(y/N): "
    read -r delete_tunnel
    if [[ "$delete_tunnel" == "y" || "$delete_tunnel" == "Y" ]]; then
        print_info "删除 Cloudflare 隧道..."
        "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    fi
    
    rm -rf "$CONFIG_DIR" "$LOG_DIR"
    
    print_input "是否删除 Shadowsocks 和 cloudflared 二进制文件？(y/N): "
    read -r delete_bin
    if [[ "$delete_bin" == "y" || "$delete_bin" == "Y" ]]; then
        rm -f "$BIN_DIR/ssserver" "$BIN_DIR/sslocal" "$BIN_DIR/cloudflared"
    fi
    
    print_input "是否删除 Cloudflare 授权文件？(y/N): "
    read -r delete_auth
    if [[ "$delete_auth" == "y" || "$delete_auth" == "Y" ]]; then
        rm -rf /root/.cloudflared
    fi
    
    userdel "$SERVICE_USER" 2>/dev/null || true
    groupdel "$SERVICE_GROUP" 2>/dev/null || true
    
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
    local password=$(grep "^SS_PASSWORD=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local method=$(grep "^SS_METHOD=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    echo ""
    print_success "当前配置:"
    echo "  域名: $domain"
    echo "  隧道名称: $TUNNEL_NAME"
    echo "  Shadowsocks 端口: $SHADOWSOCKS_PORT"
    echo "  加密方法: $method"
    echo "  密码: $password"
    echo ""
    
    # 生成 Shadowsocks 链接
    local ss_link=$(echo -n "${method}:${password}@${domain}:443" | base64 -w 0)
    ss_link="ss://${ss_link}#Argo-Shadowsocks"
    
    print_info "📡 Shadowsocks 链接:"
    echo "$ss_link"
    echo ""
    
    if command -v qrencode &> /dev/null; then
        print_info "📱 二维码:"
        qrencode -t utf8 <<< "$ss_link"
        echo ""
    fi
}

# ----------------------------
# 重新生成配置文件
# ----------------------------
regenerate_config() {
    print_info "重新生成配置文件..."
    
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件，可能未安装"
        return 1
    fi
    
    configure_shadowsocks
    configure_cloudflared
    generate_v2rayn_config
    
    print_success "✅ 配置文件已重新生成"
    
    # 重启服务
    print_info "重启服务..."
    systemctl restart ss-argo-shadowsocks.service
    systemctl restart ss-argo-cloudflared.service
    
    show_config
}

# ----------------------------
# 显示服务状态
# ----------------------------
show_status() {
    print_info "服务状态检查..."
    echo ""
    
    if systemctl is-active --quiet ss-argo-shadowsocks.service; then
        print_success "Shadowsocks 服务: 运行中"
        echo "监听端口: $SHADOWSOCKS_PORT"
        echo "进程:"
        ps aux | grep "ssserver" | grep -v grep || true
    else
        print_error "Shadowsocks 服务: 未运行"
    fi
    
    echo ""
    
    if systemctl is-active --quiet ss-argo-cloudflared.service; then
        print_success "Cloudflared 服务: 运行中"
        
        echo ""
        print_info "隧道信息:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || true
        
        echo ""
        print_info "隧道连接状态:"
        "$BIN_DIR/cloudflared" tunnel info "$TUNNEL_NAME" 2>/dev/null || echo "无法获取隧道详情"
    else
        print_error "Cloudflared 服务: 未运行"
    fi
    
    # 检查端口监听
    echo ""
    print_info "端口监听状态:"
    ss -tlnp | grep ":$SHADOWSOCKS_PORT" || echo "Shadowsocks 端口未监听"
}

# ----------------------------
# 测试连接性
# ----------------------------
test_connection() {
    print_info "测试连接性..."
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -z "$domain" ]]; then
        print_error "未找到域名配置"
        return 1
    fi
    
    echo ""
    print_info "1. 测试域名解析..."
    if nslookup "$domain" > /dev/null 2>&1; then
        print_success "✅ 域名解析正常"
    else
        print_warning "⚠️  域名解析可能有问题"
    fi
    
    echo ""
    print_info "2. 测试 Cloudflare Tunnel 连接..."
    if timeout 10 curl -s "https://$domain" --head | grep -q "HTTP"; then
        print_success "✅ Cloudflare Tunnel 连接正常"
    else
        print_warning "⚠️  Cloudflare Tunnel 连接测试失败"
    fi
    
    echo ""
    print_info "3. 测试 Shadowsocks 服务..."
    if ss -tlnp | grep -q ":$SHADOWSOCKS_PORT"; then
        print_success "✅ Shadowsocks 服务运行中"
    else
        print_error "❌ Shadowsocks 服务未运行"
    fi
}

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    show_title
    
    echo "请选择操作："
    echo ""
    echo "  1) 安装 Argo + Shadowsocks"
    echo "  2) 卸载 Argo + Shadowsocks"
    echo "  3) 查看服务状态"
    echo "  4) 查看配置信息"
    echo "  5) 重新生成配置文件"
    echo "  6) 测试连接性"
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
            regenerate_config
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        6)
            test_connection
            echo ""
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
        "config")
            show_title
            show_config
            ;;
        "status")
            show_title
            show_status
            ;;
        "regenerate")
            show_title
            regenerate_config
            ;;
        "test")
            show_title
            test_connection
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
            echo "  sudo ./ss_argo.sh menu          # 显示菜单"
            echo "  sudo ./ss_argo.sh install       # 安装"
            echo "  sudo ./ss_argo.sh uninstall     # 卸载"
            echo "  sudo ./ss_argo.sh status        # 查看状态"
            echo "  sudo ./ss_argo.sh config        # 查看配置"
            echo "  sudo ./ss_argo.sh regenerate    # 重新生成配置"
            echo "  sudo ./ss_argo.sh test          # 测试连接"
            echo "  sudo ./ss_argo.sh -y            # 静默安装"
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