#!/bin/bash
# ============================================
# Argo Tunnel + Shadowsocks 一键安装脚本
# 版本: 2.0 - 传统授权方式版
# 特点: 使用标准授权流程，稳定可靠
# ============================================

set -e

# ----------------------------
# 颜色和样式定义
# ----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[ℹ]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_input() { echo -e "${CYAN}[?]${NC} $1"; }

# ----------------------------
# 全局配置
# ----------------------------
CONFIG_DIR="/etc/argo-ss"
LOG_DIR="/var/log/argo-ss"
BIN_DIR="/usr/local/bin"
SERVICE_USER="argo-ss"
SS_PORT=10000
SS_PASSWORD=""
SS_METHOD="chacha20-ietf-poly1305"
TUNNEL_NAME="argo-ss-tunnel"
DOMAIN=""

# ----------------------------
# 显示标题
# ----------------------------
show_banner() {
    clear
    cat << "EOF"

    ╔══════════════════════════════════════════════╗
    ║        Argo Tunnel + Shadowsocks            ║
    ║            一键安装脚本 v2.0                ║
    ║            传统授权方式版                    ║
    ╚══════════════════════════════════════════════╝

EOF
}

# ----------------------------
# 系统检查与准备
# ----------------------------
system_check() {
    log_info "系统环境检查..."
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    # 检测系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "操作系统: $NAME $VERSION"
    else
        log_warning "无法检测操作系统"
    fi
    
    # 更新软件源
    log_info "更新软件包列表..."
    apt-get update -y > /dev/null 2>&1 || {
        log_warning "软件源更新失败，尝试继续..."
    }
    
    # 安装基础工具
    log_info "安装必要工具..."
    local tools=("curl" "wget" "unzip" "jq" "net-tools" "iproute2" "openssl" "qrencode")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            apt-get install -y "$tool" > /dev/null 2>&1 || {
                log_warning "$tool 安装失败"
            }
        fi
    done
    
    log_success "系统检查完成"
}

# ----------------------------
# 安装 Cloudflared（稳定版）
# ----------------------------
install_cloudflared() {
    log_info "安装 Cloudflared..."
    
    # 检查是否已安装
    if command -v cloudflared &> /dev/null; then
        local version=$("$BIN_DIR/cloudflared" --version 2>/dev/null || echo "unknown")
        log_success "Cloudflared 已安装 ($version)"
        return 0
    fi
    
    # 清理旧版本
    rm -f /tmp/cloudflared* 2>/dev/null
    rm -f "$BIN_DIR/cloudflared" 2>/dev/null
    
    # 固定版本，避免API变动
    local version="2025.11.1"
    local arch=$(uname -m)
    local cf_url=""
    
    # 根据架构选择下载链接
    case "$arch" in
        x86_64|amd64)
            cf_url="https://github.com/cloudflare/cloudflared/releases/download/${version}/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            cf_url="https://github.com/cloudflare/cloudflared/releases/download/${version}/cloudflared-linux-arm64"
            ;;
        *)
            log_error "不支持的架构: $arch"
            return 1
            ;;
    esac
    
    log_info "下载 Cloudflared (v$version)..."
    
    # 尝试多个下载源
    local download_success=false
    local sources=(
        "$cf_url"
        "https://ghproxy.com/$cf_url"
        "https://gh-proxy.com/$cf_url"
    )
    
    for source in "${sources[@]}"; do
        log_info "尝试下载源: $(echo "$source" | cut -d'/' -f3)"
        
        if wget -q --timeout=30 --tries=2 -O /tmp/cloudflared "$source"; then
            if [ -s /tmp/cloudflared ]; then
                download_success=true
                log_success "下载成功"
                break
            fi
        fi
        sleep 1
    done
    
    if [ "$download_success" = false ]; then
        log_error "所有下载源均失败"
        return 1
    fi
    
    # 安装
    mv /tmp/cloudflared "$BIN_DIR/cloudflared"
    chmod +x "$BIN_DIR/cloudflared"
    
    # 验证安装
    if "$BIN_DIR/cloudflared" --version &> /dev/null; then
        local installed_version=$("$BIN_DIR/cloudflared" --version | head -1)
        log_success "Cloudflared 安装成功 ($installed_version)"
        return 0
    else
        log_error "Cloudflared 验证失败"
        return 1
    fi
}

# ----------------------------
# 安装 Shadowsocks-libev（稳定）
# ----------------------------
install_shadowsocks() {
    log_info "安装 Shadowsocks..."
    
    # 检查是否已安装
    if command -v ss-server &> /dev/null; then
        log_success "Shadowsocks-libev 已安装"
        return 0
    fi
    
    # 首先尝试使用系统包管理器
    log_info "使用系统包安装 Shadowsocks-libev..."
    
    # 检测系统并添加合适的源
    if grep -q "ubuntu" /etc/os-release; then
        # Ubuntu
        ubuntu_version=$(grep "VERSION_ID" /etc/os-release | cut -d'"' -f2)
        if [[ "$ubuntu_version" == "20.04" || "$ubuntu_version" == "22.04" || "$ubuntu_version" == "24.04" ]]; then
            apt-get install -y shadowsocks-libev > /dev/null 2>&1 && {
                log_success "Shadowsocks-libev 安装成功"
                return 0
            }
        fi
    elif grep -q "debian" /etc/os-release; then
        # Debian
        apt-get install -y shadowsocks-libev > /dev/null 2>&1 && {
            log_success "Shadowsocks-libev 安装成功"
            return 0
        }
    fi
    
    # 如果系统包安装失败，使用编译安装
    log_warning "系统包安装失败，尝试编译安装..."
    compile_shadowsocks_libev
}

# ----------------------------
# 编译安装 Shadowsocks-libev
# ----------------------------
compile_shadowsocks_libev() {
    log_info "编译安装 Shadowsocks-libev..."
    
    # 安装编译依赖
    log_info "安装编译依赖..."
    apt-get install -y --no-install-recommends \
        build-essential \
        autoconf \
        libtool \
        libssl-dev \
        gawk \
        debhelper \
        dh-systemd \
        init-system-helpers \
        pkg-config \
        asciidoc \
        xmlto \
        apg \
        libpcre3-dev \
        zlib1g-dev \
        libev-dev \
        libudns-dev \
        libsodium-dev \
        libmbedtls-dev \
        libc-ares-dev \
        git > /dev/null 2>&1
    
    # 创建临时目录
    local temp_dir="/tmp/shadowsocks-build"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # 下载源代码（使用固定版本避免变动）
    local ss_version="3.3.5"
    local ss_url="https://github.com/shadowsocks/shadowsocks-libev/archive/v${ss_version}.tar.gz"
    
    log_info "下载 Shadowsocks-libev v${ss_version}..."
    if wget -q --timeout=30 "$ss_url"; then
        tar -xzf "v${ss_version}.tar.gz"
        cd "shadowsocks-libev-${ss_version}"
        
        # 编译
        log_info "开始编译..."
        ./autogen.sh > /dev/null 2>&1
        ./configure --disable-documentation > /dev/null 2>&1
        make -j$(nproc) > /dev/null 2>&1
        
        # 安装
        make install > /dev/null 2>&1
        
        # 创建服务文件
        if [ ! -f /etc/systemd/system/shadowsocks-libev.service ]; then
            cat > /etc/systemd/system/shadowsocks-libev.service << 'EOF'
[Unit]
Description=Shadowsocks-libev Default Server Service
Documentation=man:shadowsocks-libev(8)
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=/usr/local/bin/ss-server -c /etc/shadowsocks-libev/config.json

[Install]
WantedBy=multi-user.target
EOF
        fi
        
        log_success "Shadowsocks-libev 编译安装成功"
        return 0
    else
        log_error "下载源代码失败"
        return 1
    fi
}

# ----------------------------
# 获取用户配置
# ----------------------------
get_user_config() {
    echo ""
    log_info "═══════════════════════════════════════════════"
    log_info "             配置信息输入"
    log_info "═══════════════════════════════════════════════"
    echo ""
    
    # 获取域名
    log_input "请输入要绑定的域名（必须属于您的 Cloudflare 账户）："
    read -r DOMAIN
    
    if [[ -z "$DOMAIN" ]]; then
        log_error "域名不能为空"
        exit 1
    fi
    
    # 验证域名格式
    if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "域名格式不正确"
        exit 1
    fi
    
    # Shadowsocks 配置
    log_input "请输入 Shadowsocks 监听端口 [默认: 10000]:"
    read -r port_input
    SS_PORT=${port_input:-10000}
    
    # 验证端口
    if ! [[ "$SS_PORT" =~ ^[0-9]+$ ]] || [ "$SS_PORT" -lt 1 ] || [ "$SS_PORT" -gt 65535 ]; then
        log_error "端口号无效"
        exit 1
    fi
    
    echo ""
    log_info "选择加密方法："
    echo "  1) chacha20-ietf-poly1305 (推荐)"
    echo "  2) aes-256-gcm"
    echo "  3) aes-128-gcm"
    echo "  4) xchacha20-ietf-poly1305"
    echo ""
    
    while true; do
        log_input "请选择 [1-4, 默认: 1]:"
        read -r method_choice
        
        case "$method_choice" in
            1|"") 
                SS_METHOD="chacha20-ietf-poly1305"
                break
                ;;
            2) 
                SS_METHOD="aes-256-gcm"
                break
                ;;
            3) 
                SS_METHOD="aes-128-gcm"
                break
                ;;
            4) 
                SS_METHOD="xchacha20-ietf-poly1305"
                break
                ;;
            *) 
                log_error "无效选择，请重试"
                ;;
        esac
    done
    
    # 生成强密码
    SS_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
    
    echo ""
    log_success "配置摘要："
    echo "  域名: $DOMAIN"
    echo "  Shadowsocks 端口: $SS_PORT"
    echo "  加密方法: $SS_METHOD"
    echo "  密码: $SS_PASSWORD"
    echo "  隧道名称: $TUNNEL_NAME"
    echo ""
    
    log_input "确认配置无误？[Y/n]:"
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        get_user_config
    fi
}

# ----------------------------
# 网络诊断
# ----------------------------
network_diagnosis() {
    log_info "网络连接诊断..."
    
    echo ""
    log_info "1. 测试 Cloudflare API 连接..."
    if timeout 5 curl -s -I https://api.cloudflare.com > /dev/null; then
        log_success "  ✓ Cloudflare API 可达"
    else
        log_error "  ✗ 无法连接到 Cloudflare API"
        return 1
    fi
    
    echo ""
    log_info "2. 测试 GitHub 连接..."
    if timeout 5 curl -s -I https://github.com > /dev/null; then
        log_success "  ✓ GitHub 可达"
    else
        log_warning "  ⚠️ GitHub 连接较慢"
    fi
    
    echo ""
    log_info "3. 测试 Argo 隧道端点..."
    local argo_endpoints=(
        "region1.v2.argotunnel.com"
        "region2.v2.argotunnel.com"
    )
    
    for endpoint in "${argo_endpoints[@]}"; do
        if timeout 5 nslookup "$endpoint" > /dev/null 2>&1; then
            log_success "  ✓ $endpoint 解析正常"
            break
        fi
    done
    
    echo ""
    log_info "4. 检查本地端口..."
    if ss -tln | grep ":$SS_PORT" > /dev/null; then
        log_warning "  ⚠️ 端口 $SS_PORT 已被占用"
        return 1
    else
        log_success "  ✓ 端口 $SS_PORT 可用"
    fi
    
    return 0
}

# ----------------------------
# Cloudflare 传统授权
# ----------------------------
cloudflare_auth_traditional() {
    echo ""
    log_info "═══════════════════════════════════════════════"
    log_info "         Cloudflare 账户授权（传统方式）"
    log_info "═══════════════════════════════════════════════"
    echo ""
    
    log_info "传统授权流程说明："
    echo "  1. cloudflared 将生成一个授权链接"
    echo "  2. 复制链接到浏览器打开"
    echo "  3. 登录您的 Cloudflare 账户"
    echo "  4. 选择域名进行授权"
    echo "  5. 授权完成后返回终端继续"
    echo ""
    
    # 清理旧授权文件
    log_info "清理旧授权文件..."
    rm -rf /root/.cloudflared 2>/dev/null
    mkdir -p /root/.cloudflared
    
    # 重要提示
    echo "═══════════════════════════════════════════════"
    echo "重要：请确保满足以下条件："
    echo "  1. 域名 $DOMAIN 已在您的 Cloudflare 账户中"
    echo "  2. 服务器可以访问 Cloudflare API"
    echo "  3. 浏览器可以正常登录 Cloudflare"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    log_input "按回车键开始授权流程..."
    read -r
    
    echo ""
    log_info "正在生成授权链接，请稍候..."
    echo "═══════════════════════════════════════════════"
    
    # 方法1：直接运行授权命令
    local auth_result=""
    local auth_attempt=1
    
    while [ $auth_attempt -le 3 ]; do
        log_info "第 $auth_attempt 次尝试获取授权链接..."
        
        # 使用 timeout 防止命令卡住
        if auth_result=$(timeout 45 "$BIN_DIR/cloudflared" tunnel login 2>&1); then
            # 检查输出中是否包含链接
            if echo "$auth_result" | grep -q "https://"; then
                echo "$auth_result"
                log_success "授权链接生成成功！"
                break
            fi
        fi
        
        log_warning "获取授权链接失败，重试中..."
        sleep 3
        ((auth_attempt++))
    done
    
    # 如果上述方法失败，使用备用方法
    if [ $auth_attempt -gt 3 ]; then
        log_warning "标准授权方法失败，尝试备用方法..."
        cloudflare_auth_fallback
        return $?
    fi
    
    echo "═══════════════════════════════════════════════"
    echo ""
    log_input "完成浏览器授权后，按回车键继续..."
    read -r
    
    # 验证授权结果
    if cloudflare_verify_auth; then
        return 0
    else
        return 1
    fi
}

# ----------------------------
# 备用授权方法
# ----------------------------
cloudflare_auth_fallback() {
    log_info "使用备用授权方法..."
    
    # 方法1：使用 --url-only 参数
    log_info "尝试方法1：获取纯URL链接..."
    local auth_url=$("$BIN_DIR/cloudflared" tunnel login --url-only 2>/dev/null || echo "")
    
    if [[ -n "$auth_url" ]]; then
        echo "请复制以下链接到浏览器打开："
        echo ""
        echo "$auth_url"
        echo ""
        log_input "完成浏览器授权后，按回车键继续..."
        read -r
        
        if cloudflare_verify_auth; then
            return 0
        fi
    fi
    
    # 方法2：手动获取授权链接
    log_info "尝试方法2：手动获取授权信息..."
    echo ""
    echo "如果以上方法都不工作，请手动执行以下步骤："
    echo "  1. 登录 https://dash.cloudflare.com/"
    echo "  2. 进入 Zero Trust → Networks → Tunnels"
    echo "  3. 点击 'Create a tunnel'"
    echo "  4. 选择 'cloudflared' 连接方式"
    echo "  5. 复制显示的命令行中的 URL"
    echo ""
    log_input "请粘贴您手动获取的授权链接："
    read -r manual_url
    
    if [[ -n "$manual_url" ]]; then
        echo ""
        echo "请访问：$manual_url"
        echo "完成授权后返回终端继续"
        echo ""
        log_input "完成授权后按回车继续..."
        read -r
        
        if cloudflare_verify_auth; then
            return 0
        fi
    fi
    
    log_error "所有授权方法均失败"
    return 1
}

# ----------------------------
# 验证授权结果
# ----------------------------
cloudflare_verify_auth() {
    log_info "验证授权结果..."
    
    # 检查证书文件
    if [ -f /root/.cloudflared/cert.pem ]; then
        log_success "✅ 证书文件创建成功"
        
        # 尝试读取证书信息
        local cert_info=$(openssl x509 -in /root/.cloudflared/cert.pem -noout -subject 2>/dev/null || echo "")
        if [[ -n "$cert_info" ]]; then
            log_success "证书信息：$cert_info"
        fi
    else
        log_error "❌ 未找到证书文件，授权可能失败"
        return 1
    fi
    
    # 检查凭证文件
    local json_files=(/root/.cloudflared/*.json)
    if [ ${#json_files[@]} -gt 0 ] && [ -e "${json_files[0]}" ]; then
        local cred_file="${json_files[0]}"
        log_success "✅ 找到凭证文件: $(basename "$cred_file")"
        
        # 检查JSON文件是否有效
        if jq -e . "$cred_file" > /dev/null 2>&1; then
            log_success "✅ 凭证文件格式正确"
            
            # 提取账户信息
            local account_tag=$(jq -r '.AccountTag // empty' "$cred_file")
            local tunnel_id=$(jq -r '.TunnelID // empty' "$cred_file")
            
            if [[ -n "$account_tag" ]]; then
                log_success "账户标识: $account_tag"
            fi
            
            if [[ -n "$tunnel_id" ]]; then
                log_success "隧道ID: $tunnel_id"
                # 更新隧道名称
                TUNNEL_NAME="$tunnel_id"
            fi
            
            return 0
        else
            log_warning "⚠️ 凭证文件格式可能不正确"
        fi
    else
        log_warning "⚠️ 未找到JSON凭证文件，将在创建隧道时生成"
    fi
    
    return 0
}

# ----------------------------
# 创建隧道
# ----------------------------
create_tunnel() {
    log_info "创建 Cloudflare 隧道..."
    
    # 检查是否已授权
    if [ ! -f /root/.cloudflared/cert.pem ]; then
        log_error "未找到授权证书，请先完成授权"
        return 1
    fi
    
    # 检查是否已有同名隧道
    log_info "检查现有隧道..."
    local existing_tunnels=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null || echo "")
    
    if echo "$existing_tunnels" | grep -q "$TUNNEL_NAME"; then
        log_warning "已存在同名隧道 '$TUNNEL_NAME'，尝试删除..."
        "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
        sleep 2
    fi
    
    # 创建新隧道
    log_info "创建新隧道: $TUNNEL_NAME"
    echo ""
    
    if "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"; then
        log_success "✅ 隧道创建成功"
        sleep 2
        
        # 获取隧道ID
        local tunnel_info=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || echo "")
        if [[ -n "$tunnel_info" ]]; then
            local tunnel_id=$(echo "$tunnel_info" | awk '{print $1}')
            log_success "隧道ID: $tunnel_id"
            
            # 绑定域名到DNS
            log_info "绑定域名 $DOMAIN 到隧道..."
            if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$DOMAIN" > /dev/null 2>&1; then
                log_success "✅ 域名绑定成功"
            else
                log_warning "⚠️ 域名绑定失败，可能需要手动操作"
            fi
        fi
        
        return 0
    else
        log_error "❌ 隧道创建失败"
        return 1
    fi
}

# ----------------------------
# 配置 Shadowsocks
# ----------------------------
configure_shadowsocks() {
    log_info "配置 Shadowsocks 服务..."
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    # 创建 Shadowsocks 配置文件
    cat > "$CONFIG_DIR/shadowsocks.json" << EOF
{
    "server": "127.0.0.1",
    "server_port": $SS_PORT,
    "password": "$SS_PASSWORD",
    "method": "$SS_METHOD",
    "mode": "tcp_only",
    "timeout": 300,
    "fast_open": true,
    "no_delay": true,
    "ipv6_first": false,
    "dns": "1.1.1.1",
    "plugin": "",
    "plugin_opts": "",
    "reuse_port": true,
    "tcp_keep_alive": 600
}
EOF
    
    # 设置权限
    chmod 600 "$CONFIG_DIR/shadowsocks.json"
    log_success "Shadowsocks 配置完成"
}

# ----------------------------
# 配置 Cloudflared
# ----------------------------
configure_cloudflared() {
    log_info "配置 Cloudflared 隧道..."
    
    # 获取最新的凭证文件
    local json_files=(/root/.cloudflared/*.json)
    local cred_file=""
    
    if [ ${#json_files[@]} -gt 0 ] && [ -e "${json_files[0]}" ]; then
        cred_file="${json_files[0]}"
    else
        log_error "未找到隧道凭证文件"
        return 1
    fi
    
    # 创建 Cloudflared 配置文件
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_NAME
credentials-file: $cred_file
logfile: $LOG_DIR/cloudflared.log
loglevel: info
no-autoupdate: true

# 连接设置
protocol: quic
retries: 10
connection-idle-timeout: 1m30s
graceful-shutdown: 2s
request-timeout: 1m30s

# 入口规则
ingress:
  - hostname: $DOMAIN
    service: tcp://localhost:$SS_PORT
    originRequest:
      connectTimeout: 15s
      tlsTimeout: 10s
      tcpKeepAlive: 30s
      noHappyEyeballs: false
      keepAliveConnections: 10
      keepAliveTimeout: 1m30s
      httpHostHeader: $DOMAIN
  - service: http_status:404
EOF
    
    log_success "Cloudflared 配置完成"
}

# ----------------------------
# 配置系统服务
# ----------------------------
configure_services() {
    log_info "配置系统服务..."
    
    # 创建服务用户
    if ! id -u "$SERVICE_USER" &> /dev/null; then
        useradd -r -s /usr/sbin/nologin "$SERVICE_USER"
    fi
    
    # 设置权限
    chown -R "$SERVICE_USER:$SERVICE_USER" "$CONFIG_DIR" "$LOG_DIR"
    
    # 1. Shadowsocks 服务
    cat > /etc/systemd/system/argo-ss.service << EOF
[Unit]
Description=Argo Shadowsocks Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
ExecStart=$(command -v ss-server) -c $CONFIG_DIR/shadowsocks.json
Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/ss.log
StandardError=append:$LOG_DIR/ss-error.log
LimitNOFILE=51200
Environment="TZ=UTC"

[Install]
WantedBy=multi-user.target
EOF
    
    # 2. Cloudflared 服务
    cat > /etc/systemd/system/argo-tunnel.service << EOF
[Unit]
Description=Argo Tunnel Service
After=network.target argo-ss.service
Wants=network-online.target
Requires=argo-ss.service

[Service]
Type=simple
User=root
Group=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
Environment="TUNNEL_FORCE_PROTOCOL=quic"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=always
RestartSec=5
StandardOutput=append:$LOG_DIR/tunnel.log
StandardError=append:$LOG_DIR/tunnel-error.log
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载 systemd
    systemctl daemon-reload
    log_success "系统服务配置完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    log_info "启动服务..."
    
    # 停止可能存在的旧服务
    systemctl stop argo-tunnel.service 2>/dev/null || true
    systemctl stop argo-ss.service 2>/dev/null || true
    sleep 2
    
    # 1. 启动 Shadowsocks
    log_info "启动 Shadowsocks..."
    systemctl enable --now argo-ss.service
    
    local ss_attempt=0
    while [ $ss_attempt -lt 5 ]; do
        if systemctl is-active --quiet argo-ss.service; then
            log_success "✅ Shadowsocks 启动成功"
            break
        fi
        sleep 2
        ((ss_attempt++))
    done
    
    if [ $ss_attempt -ge 5 ]; then
        log_error "❌ Shadowsocks 启动失败"
        journalctl -u argo-ss.service -n 20 --no-pager
        return 1
    fi
    
    # 2. 启动 Cloudflared
    log_info "启动 Cloudflared 隧道..."
    systemctl enable --now argo-tunnel.service
    
    # 等待隧道连接
    local tunnel_attempt=0
    log_info "等待隧道连接建立..."
    
    while [ $tunnel_attempt -lt 30 ]; do
        if systemctl is-active --quiet argo-tunnel.service; then
            # 检查隧道状态
            local tunnel_status=$("$BIN_DIR/cloudflared" tunnel info "$TUNNEL_NAME" 2>/dev/null | grep -i "status" || echo "")
            
            if echo "$tunnel_status" | grep -q "running\|active"; then
                log_success "✅ Cloudflared 隧道启动成功"
                echo "隧道状态: $tunnel_status"
                break
            fi
        fi
        
        if [ $((tunnel_attempt % 10)) -eq 0 ] && [ $tunnel_attempt -gt 0 ]; then
            log_info "已等待 ${tunnel_attempt}秒..."
        fi
        
        sleep 2
        ((tunnel_attempt++))
    done
    
    if [ $tunnel_attempt -ge 30 ]; then
        log_warning "⚠️ 隧道启动较慢，可能仍在连接中"
        log_info "使用命令查看状态: systemctl status argo-tunnel.service"
    fi
    
    return 0
}

# ----------------------------
# 显示连接信息
# ----------------------------
show_connection_info() {
    echo ""
    log_info "═══════════════════════════════════════════════"
    log_info "             安装完成！连接信息"
    log_info "═══════════════════════════════════════════════"
    echo ""
    
    # 显示配置
    log_success "🔗 服务器地址: $DOMAIN"
    log_success "🚪 端口: 443 (Cloudflare Tunnel)"
    log_success "🔑 密码: $SS_PASSWORD"
    log_success "🔐 加密: $SS_METHOD"
    log_success "🏷️  隧道名称: $TUNNEL_NAME"
    
    echo ""
    
    # 生成 Shadowsocks 链接
    local ss_uri="${SS_METHOD}:${SS_PASSWORD}@${DOMAIN}:443"
    local ss_link="ss://$(echo -n "$ss_uri" | base64 -w 0)#Argo-Shadowsocks"
    
    log_info "📋 Shadowsocks 链接："
    echo "$ss_link"
    echo ""
    
    # 生成二维码
    if command -v qrencode &> /dev/null; then
        log_info "📱 二维码："
        qrencode -t utf8 <<< "$ss_link"
        echo ""
    fi
    
    # v2rayN 配置说明
    log_info "🎯 v2rayN 客户端配置："
    echo "  服务器类型: Shadowsocks"
    echo "  地址(Address): $DOMAIN"
    echo "  端口(Port): 443"
    echo "  密码(Password): $SS_PASSWORD"
    echo "  加密方式(Encryption): $SS_METHOD"
    echo "  插件(Plugin): 无"
    echo ""
    
    # 服务状态
    log_info "🔧 服务状态："
    
    local ss_status=$(systemctl is-active argo-ss.service 2>/dev/null || echo "unknown")
    local tunnel_status=$(systemctl is-active argo-tunnel.service 2>/dev/null || echo "unknown")
    
    if [ "$ss_status" = "active" ]; then
        echo "  Shadowsocks: ✅ 运行中"
    else
        echo "  Shadowsocks: ❌ $ss_status"
    fi
    
    if [ "$tunnel_status" = "active" ]; then
        echo "  Argo Tunnel: ✅ 运行中"
    else
        echo "  Argo Tunnel: ❌ $tunnel_status"
    fi
    
    echo ""
    log_info "📝 管理命令："
    echo "  查看状态: sudo systemctl status argo-tunnel.service"
    echo "  查看日志: sudo journalctl -u argo-tunnel.service -f"
    echo "  重启服务: sudo systemctl restart argo-tunnel.service"
    echo "  停止服务: sudo systemctl stop argo-tunnel.service"
    echo "  卸载脚本: sudo ./argo-ss.sh uninstall"
    
    # 保存配置文件
    cat > "$CONFIG_DIR/client-config.txt" << EOF
# Argo Shadowsocks 客户端配置
服务器地址: $DOMAIN
端口: 443
密码: $SS_PASSWORD
加密: $SS_METHOD

Shadowsocks链接:
$ss_link

v2rayN 配置:
服务器类型: Shadowsocks
地址: $DOMAIN
端口: 443
密码: $SS_PASSWORD
加密: $SS_METHOD

创建时间: $(date)
EOF
    
    log_success "配置文件已保存: $CONFIG_DIR/client-config.txt"
}

# ----------------------------
# 测试连接
# ----------------------------
test_connection() {
    echo ""
    log_info "运行连接测试..."
    
    # 1. 测试本地服务
    log_info "1. 测试 Shadowsocks 服务..."
    if ss -tlnp | grep ":$SS_PORT" &> /dev/null; then
        log_success "  ✅ 端口 $SS_PORT 监听正常"
    else
        log_error "  ❌ 端口 $SS_PORT 未监听"
    fi
    
    # 2. 测试隧道服务
    log_info "2. 测试 Argo 隧道服务..."
    if systemctl is-active --quiet argo-tunnel.service; then
        log_success "  ✅ 隧道服务运行正常"
        
        # 获取隧道信息
        local tunnel_info=$("$BIN_DIR/cloudflared" tunnel info "$TUNNEL_NAME" 2>/dev/null || echo "")
        if [[ -n "$tunnel_info" ]]; then
            echo "  隧道状态:"
            echo "$tunnel_info" | head -10
        fi
    else
        log_error "  ❌ 隧道服务未运行"
    fi
    
    # 3. 测试域名解析
    log_info "3. 测试域名解析..."
    if nslookup "$DOMAIN" &> /dev/null; then
        log_success "  ✅ 域名解析正常"
    else
        log_warning "  ⚠️  域名解析可能有问题"
    fi
}

# ----------------------------
# 安装完成后的提示
# ----------------------------
installation_complete() {
    echo ""
    log_info "═══════════════════════════════════════════════"
    log_info "           安装流程完成"
    log_info "═══════════════════════════════════════════════"
    echo ""
    
    log_success "✅ 所有组件安装完成"
    log_success "✅ 服务配置完成"
    log_success "✅ 隧道创建完成"
    
    echo ""
    log_info "下一步："
    echo "  1. 使用上面的连接信息配置客户端"
    echo "  2. 首次连接可能需要1-2分钟建立隧道"
    echo "  3. 如果连接失败，请检查服务状态"
    echo "  4. 可以使用 'sudo ./argo-ss.sh status' 查看状态"
    
    echo ""
    log_input "按回车键返回主菜单..."
    read -r
}

# ----------------------------
# 卸载脚本
# ----------------------------
uninstall() {
    echo ""
    log_warning "═══════════════════════════════════════════════"
    log_warning "               卸载程序"
    log_warning "═══════════════════════════════════════════════"
    echo ""
    
    log_warning "⚠️  这将删除所有配置、数据和服务！"
    log_input "确认要卸载吗？[y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "卸载已取消"
        return
    fi
    
    log_info "开始卸载..."
    
    # 停止服务
    log_info "停止服务..."
    systemctl stop argo-tunnel.service 2>/dev/null || true
    systemctl stop argo-ss.service 2>/dev/null || true
    
    # 禁用服务
    systemctl disable argo-tunnel.service 2>/dev/null || true
    systemctl disable argo-ss.service 2>/dev/null || true
    
    # 删除服务文件
    rm -f /etc/systemd/system/argo-tunnel.service
    rm -f /etc/systemd/system/argo-ss.service
    
    # 删除配置目录
    log_info "删除配置目录..."
    rm -rf "$CONFIG_DIR" "$LOG_DIR"
    
    # 删除二进制文件（可选）
    log_input "是否删除 Cloudflared 和 Shadowsocks 二进制文件？[y/N]: "
    read -r delete_bin
    if [[ "$delete_bin" =~ ^[Yy]$ ]]; then
        rm -f "$BIN_DIR/cloudflared"
        # 注意：不要删除系统安装的 ss-server
    fi
    
    # 删除 Cloudflare 配置
    log_input "是否删除 Cloudflare 授权文件？[y/N]: "
    read -r delete_auth
    if [[ "$delete_auth" =~ ^[Yy]$ ]]; then
        rm -rf /root/.cloudflared
    fi
    
    # 删除隧道
    log_input "是否删除 Cloudflare 隧道？[y/N]: "
    read -r delete_tunnel
    if [[ "$delete_tunnel" =~ ^[Yy]$ ]]; then
        log_info "删除 Cloudflare 隧道..."
        "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    fi
    
    # 删除用户
    userdel "$SERVICE_USER" 2>/dev/null || true
    
    # 重载 systemd
    systemctl daemon-reload
    
    echo ""
    log_success "✅ 卸载完成！"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    show_banner
    
    # 1. 系统检查
    system_check
    
    # 2. 网络诊断
    if ! network_diagnosis; then
        log_error "网络诊断失败，请检查网络连接"
        return 1
    fi
    
    # 3. 安装组件
    if ! install_cloudflared; then
        log_error "Cloudflared 安装失败"
        return 1
    fi
    
    if ! install_shadowsocks; then
        log_error "Shadowsocks 安装失败"
        return 1
    fi
    
    # 4. 获取用户配置
    get_user_config
    
    # 5. Cloudflare 授权
    echo ""
    log_info "═══════════════════════════════════════════════"
    log_info "         Cloudflare 授权阶段"
    log_info "═══════════════════════════════════════════════"
    
    if ! cloudflare_auth_traditional; then
        log_error "Cloudflare 授权失败"
        return 1
    fi
    
    # 6. 创建隧道
    if ! create_tunnel; then
        log_error "隧道创建失败"
        return 1
    fi
    
    # 7. 配置服务
    configure_shadowsocks
    configure_cloudflared
    configure_services
    
    # 8. 启动服务
    if ! start_services; then
        log_error "服务启动失败"
        return 1
    fi
    
    # 9. 测试连接
    test_connection
    
    # 10. 显示连接信息
    show_connection_info
    
    # 11. 完成提示
    installation_complete
}

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    show_banner
    
    echo "请选择操作："
    echo ""
    echo "  1) 安装 Argo + Shadowsocks"
    echo "  2) 卸载"
    echo "  3) 查看服务状态"
    echo "  4) 测试连接"
    echo "  5) 显示配置"
    echo "  6) 退出"
    echo ""
    
    log_input "请输入选项 [1-6]: "
    read -r choice
    
    case "$choice" in
        1)
            if main_install; then
                log_success "安装完成！"
            else
                log_error "安装失败"
            fi
            echo ""
            log_input "按回车键返回菜单..."
            read -r
            ;;
        2)
            uninstall
            echo ""
            log_input "按回车键返回菜单..."
            read -r
            ;;
        3)
            echo ""
            systemctl status argo-ss.service --no-pager
            echo ""
            systemctl status argo-tunnel.service --no-pager
            echo ""
            log_input "按回车键返回菜单..."
            read -r
            ;;
        4)
            test_connection
            echo ""
            log_input "按回车键返回菜单..."
            read -r
            ;;
        5)
            if [ -f "$CONFIG_DIR/client-config.txt" ]; then
                echo ""
                cat "$CONFIG_DIR/client-config.txt"
            else
                log_error "未找到配置文件"
            fi
            echo ""
            log_input "按回车键返回菜单..."
            read -r
            ;;
        6)
            log_info "再见！"
            exit 0
            ;;
        *)
            log_error "无效选项"
            sleep 1
            ;;
    esac
    
    show_menu
}

# ----------------------------
# 脚本入口
# ----------------------------
main() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用 root 权限运行此脚本${NC}"
        echo "例如: sudo ./argo-ss.sh"
        exit 1
    fi
    
    # 如果没有参数，显示菜单
    if [ $# -eq 0 ]; then
        show_menu
    else
        case "$1" in
            "install")
                main_install
                ;;
            "uninstall")
                uninstall
                ;;
            "status")
                systemctl status argo-tunnel.service --no-pager
                systemctl status argo-ss.service --no-pager
                ;;
            "test")
                test_connection
                ;;
            "config")
                if [ -f "$CONFIG_DIR/client-config.txt" ]; then
                    cat "$CONFIG_DIR/client-config.txt"
                else
                    echo "未找到配置文件"
                fi
                ;;
            "-h"|"--help")
                echo "使用方法:"
                echo "  sudo ./argo-ss.sh install      # 安装"
                echo "  sudo ./argo-ss.sh uninstall    # 卸载"
                echo "  sudo ./argo-ss.sh status       # 查看状态"
                echo "  sudo ./argo-ss.sh test         # 测试连接"
                echo "  sudo ./argo-ss.sh config       # 显示配置"
                echo "  sudo ./argo-ss.sh              # 显示菜单"
                ;;
            *)
                echo "未知参数: $1"
                echo "使用 --help 查看帮助"
                exit 1
                ;;
        esac
    fi
}

# 运行主函数
main "$@"