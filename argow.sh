#!/bin/bash
# ============================================
# Argo Tunnel + Shadowsocks 一键安装脚本
# 版本: 2.0 - 完全重写版
# 特点: 稳定、简洁、自动故障修复
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
        log_success "Cloudflared 已安装"
        return 0
    fi
    
    local arch=$(uname -m)
    local version="2025.11.1"
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
    
    # 下载 cloudflared
    log_info "下载 Cloudflared..."
    if wget -q --timeout=30 --tries=3 -O /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        
        # 验证安装
        if "$BIN_DIR/cloudflared" --version &> /dev/null; then
            log_success "Cloudflared 安装成功"
            return 0
        fi
    fi
    
    # 如果下载失败，尝试备用方法
    log_warning "主下载源失败，尝试备用源..."
    
    # 备用下载源
    local alt_urls=(
        "https://ghproxy.com/${cf_url}"
        "https://download.fastgit.org/cloudflare/cloudflared/releases/download/${version}/cloudflared-linux-${arch}"
    )
    
    for alt_url in "${alt_urls[@]}"; do
        log_info "尝试备用源: $(echo "$alt_url" | cut -d'/' -f3)"
        if wget -q --timeout=30 -O /tmp/cloudflared "$alt_url"; then
            mv /tmp/cloudflared "$BIN_DIR/cloudflared"
            chmod +x "$BIN_DIR/cloudflared"
            
            if "$BIN_DIR/cloudflared" --version &> /dev/null; then
                log_success "Cloudflared 安装成功（备用源）"
                return 0
            fi
        fi
    done
    
    log_error "Cloudflared 安装失败"
    return 1
}

# ----------------------------
# 安装 Shadowsocks-rust（稳定版）
# ----------------------------
install_shadowsocks() {
    log_info "安装 Shadowsocks..."
    
    # 检查是否已安装
    if command -v ssserver &> /dev/null; then
        log_success "Shadowsocks 已安装"
        return 0
    fi
    
    local arch=$(uname -m)
    
    # 首先尝试使用系统包管理器
    log_info "尝试使用系统包安装..."
    if apt-get install -y shadowsocks-libev > /dev/null 2>&1; then
        ln -sf /usr/bin/ss-server "$BIN_DIR/ssserver"
        log_success "Shadowsocks-libev 安装成功"
        return 0
    fi
    
    # 如果系统包安装失败，尝试下载预编译版本
    log_info "下载预编译 Shadowsocks-rust..."
    
    # GitHub Releases 最新版本
    local latest_release=$(curl -s "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | 
                         grep '"tag_name":' | cut -d'"' -f4)
    
    if [ -z "$latest_release" ]; then
        latest_release="v1.20.1"  # 使用稳定版本
    fi
    
    local ss_url=""
    case "$arch" in
        x86_64|amd64)
            ss_url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${latest_release}/shadowsocks-${latest_release}.x86_64-unknown-linux-gnu.tar.xz"
            ;;
        aarch64|arm64)
            ss_url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${latest_release}/shadowsocks-${latest_release}.aarch64-unknown-linux-gnu.tar.xz"
            ;;
        *)
            log_error "不支持的架构: $arch"
            return 1
            ;;
    esac
    
    # 下载并解压
    if wget -q --timeout=30 --tries=3 -O /tmp/ss.tar.xz "$ss_url"; then
        mkdir -p /tmp/ss
        tar -xf /tmp/ss.tar.xz -C /tmp/ss --strip-components=1
        
        # 复制二进制文件
        find /tmp/ss -name "ssserver" -type f -exec cp {} "$BIN_DIR/ssserver" \;
        find /tmp/ss -name "sslocal" -type f -exec cp {} "$BIN_DIR/sslocal" \;
        
        chmod +x "$BIN_DIR/ssserver" "$BIN_DIR/sslocal"
        
        # 清理
        rm -rf /tmp/ss /tmp/ss.tar.xz
        
        if command -v ssserver &> /dev/null; then
            log_success "Shadowsocks-rust 安装成功"
            return 0
        fi
    fi
    
    # 最后的方案：编译安装
    log_warning "预编译版本下载失败，尝试编译安装..."
    compile_shadowsocks
}

# ----------------------------
# 编译安装 Shadowsocks-rust
# ----------------------------
compile_shadowsocks() {
    log_info "开始编译 Shadowsocks-rust..."
    
    # 安装 Rust 工具链
    if ! command -v cargo &> /dev/null; then
        log_info "安装 Rust 工具链..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    
    # 克隆源代码
    local temp_dir="/tmp/ss-build"
    rm -rf "$temp_dir"
    git clone https://github.com/shadowsocks/shadowsocks-rust.git "$temp_dir"
    cd "$temp_dir"
    
    # 编译
    cargo build --release
    
    # 安装
    cp target/release/ssserver target/release/sslocal "$BIN_DIR/"
    chmod +x "$BIN_DIR/ssserver" "$BIN_DIR/sslocal"
    
    log_success "Shadowsocks-rust 编译安装成功"
    return 0
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
    while true; do
        log_input "请输入要使用的域名（例如：example.com）："
        read -r DOMAIN
        
        if [[ -z "$DOMAIN" ]]; then
            log_error "域名不能为空"
            continue
        fi
        
        # 简单的域名格式验证
        if [[ "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            log_error "域名格式不正确，请重新输入"
        fi
    done
    
    # Shadowsocks 配置
    log_input "请输入 Shadowsocks 端口 [默认: 10000]:"
    read -r port_input
    SS_PORT=${port_input:-10000}
    
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
    
    # 生成密码
    SS_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
    
    echo ""
    log_success "配置摘要："
    echo "  域名: $DOMAIN"
    echo "  Shadowsocks 端口: $SS_PORT"
    echo "  加密方法: $SS_METHOD"
    echo "  密码: $SS_PASSWORD"
    echo ""
    
    log_input "确认配置无误？[Y/n]:"
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        get_user_config
    fi
}

# ----------------------------
# Cloudflare 授权（新方法）
# ----------------------------
cloudflare_auth() {
    echo ""
    log_info "═══════════════════════════════════════════════"
    log_info "         Cloudflare 账户授权"
    log_info "═══════════════════════════════════════════════"
    echo ""
    
    log_info "方法1：Web 界面授权（推荐）"
    echo "请按以下步骤操作："
    echo "  1. 打开 https://dash.cloudflare.com/"
    echo "  2. 登录您的 Cloudflare 账户"
    echo "  3. 进入 Zero Trust → Networks → Tunnels"
    echo "  4. 点击 'Create a tunnel'"
    echo "  5. 选择 'cloudflared' 方式"
    echo "  6. 复制 Tunnel Token"
    echo ""
    
    log_input "是否已有 Tunnel Token？[y/N]:"
    read -r has_token
    
    if [[ "$has_token" =~ ^[Yy]$ ]]; then
        log_input "请输入 Tunnel Token："
        read -r tunnel_token
        
        # 使用 Token 创建隧道
        create_tunnel_with_token "$tunnel_token"
    else
        # 方法2：命令行授权（备用）
        log_info "尝试命令行授权..."
        command_line_auth
    fi
}

# ----------------------------
# 使用 Token 创建隧道
# ----------------------------
create_tunnel_with_token() {
    local token="$1"
    
    log_info "使用 Token 创建隧道..."
    
    # 创建配置目录
    mkdir -p ~/.cloudflared
    mkdir -p "$CONFIG_DIR"
    
    # 将 Token 写入配置文件
    echo "$token" > ~/.cloudflared/token.json
    
    # 创建隧道
    if "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME" --token "$token"; then
        log_success "隧道创建成功"
        
        # 获取凭证文件
        local cred_file=$(find ~/.cloudflared -name "*.json" -type f | head -1)
        
        if [ -n "$cred_file" ]; then
            log_success "找到凭证文件: $(basename "$cred_file")"
            
            # 保存配置
            cat > "$CONFIG_DIR/tunnel.conf" << EOF
TUNNEL_NAME=$TUNNEL_NAME
TUNNEL_TOKEN=$token
CREDENTIALS_FILE=$cred_file
DOMAIN=$DOMAIN
SS_PORT=$SS_PORT
SS_METHOD=$SS_METHOD
SS_PASSWORD=$SS_PASSWORD
CREATED=$(date +"%Y-%m-%d %H:%M:%S")
EOF
            
            return 0
        fi
    fi
    
    log_error "使用 Token 创建隧道失败"
    return 1
}

# ----------------------------
# 命令行授权（备用）
# ----------------------------
command_line_auth() {
    log_info "开始命令行授权流程..."
    
    # 清理旧配置
    rm -rf ~/.cloudflared/* 2>/dev/null
    
    echo ""
    echo "================================================"
    echo "重要：请确保服务器可以访问以下地址："
    echo "  - https://api.cloudflare.com"
    echo "  - https://region*.v2.argotunnel.com"
    echo "================================================"
    echo ""
    
    log_input "按回车键开始授权..."
    read -r
    
    # 运行授权命令并显示链接
    echo ""
    echo "请复制以下链接到浏览器打开："
    echo "════════════════════════════════════════════════"
    
    # 使用 timeout 防止卡住
    if ! timeout 60 "$BIN_DIR/cloudflared" tunnel login; then
        log_error "授权超时"
        log_info "请手动创建隧道："
        echo "  1. 访问：https://dash.cloudflare.com/"
        echo "  2. Zero Trust → Networks → Tunnels"
        echo "  3. Create a tunnel → cloudflared"
        echo "  4. 复制 Tunnel Token"
        echo ""
        log_input "请输入获取到的 Token："
        read -r manual_token
        create_tunnel_with_token "$manual_token"
        return $?
    fi
    
    echo "════════════════════════════════════════════════"
    echo ""
    log_input "授权完成后按回车继续..."
    read -r
    
    # 检查授权结果
    if [ -f ~/.cloudflared/cert.pem ]; then
        log_success "授权成功"
        
        # 创建隧道
        log_info "创建隧道: $TUNNEL_NAME"
        "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"
        
        return 0
    else
        log_error "授权失败，未找到证书文件"
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
    "mode": "tcp_and_udp",
    "timeout": 300,
    "fast_open": true,
    "no_delay": true,
    "ipv6_first": false,
    "dns": "1.1.1.1",
    "plugin": "",
    "plugin_opts": ""
}
EOF
    
    log_success "Shadowsocks 配置完成"
}

# ----------------------------
# 配置 Cloudflared
# ----------------------------
configure_cloudflared() {
    log_info "配置 Cloudflared 隧道..."
    
    # 获取凭证文件
    local cred_file=$(find ~/.cloudflared -name "*.json" -type f | head -1)
    
    if [ -z "$cred_file" ]; then
        log_error "未找到隧道凭证文件"
        return 1
    fi
    
    # 创建 Cloudflared 配置文件
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_NAME
credentials-file: $cred_file
logfile: $LOG_DIR/cloudflared.log
loglevel: info

ingress:
  - hostname: $DOMAIN
    service: tcp://localhost:$SS_PORT
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
    
    # Shadowsocks 服务
    cat > /etc/systemd/system/argo-ss.service << EOF
[Unit]
Description=Argo Shadowsocks Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
ExecStart=$BIN_DIR/ssserver -c $CONFIG_DIR/shadowsocks.json
Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/ss.log
StandardError=append:$LOG_DIR/ss-error.log
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF
    
    # Cloudflared 服务
    cat > /etc/systemd/system/argo-tunnel.service << EOF
[Unit]
Description=Argo Tunnel Service
After=network.target argo-ss.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=always
RestartSec=5
StandardOutput=append:$LOG_DIR/tunnel.log
StandardError=append:$LOG_DIR/tunnel-error.log

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
    
    # 启动 Shadowsocks
    log_info "启动 Shadowsocks..."
    systemctl enable --now argo-ss.service
    
    if systemctl is-active --quiet argo-ss.service; then
        log_success "Shadowsocks 启动成功"
    else
        log_error "Shadowsocks 启动失败"
        journalctl -u argo-ss.service -n 20 --no-pager
        return 1
    fi
    
    # 启动 Cloudflared
    log_info "启动 Cloudflared 隧道..."
    systemctl enable --now argo-tunnel.service
    
    # 等待隧道连接
    local wait_time=0
    log_info "等待隧道连接（最多30秒）..."
    
    while [ $wait_time -lt 30 ]; do
        if systemctl is-active --quiet argo-tunnel.service; then
            log_success "Cloudflared 启动成功"
            break
        fi
        sleep 2
        ((wait_time+=2))
    done
    
    if [ $wait_time -ge 30 ]; then
        log_warning "隧道启动较慢，请稍后检查状态"
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
    log_success "📁 配置目录: $CONFIG_DIR"
    
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
    echo "  类型: Shadowsocks"
    echo "  地址: $DOMAIN"
    echo "  端口: 443"
    echo "  密码: $SS_PASSWORD"
    echo "  加密: $SS_METHOD"
    echo "  插件: 无"
    echo ""
    
    # 服务状态
    log_info "🔧 服务状态："
    if systemctl is-active --quiet argo-ss.service; then
        echo "  Shadowsocks: ✅ 运行中"
    else
        echo "  Shadowsocks: ❌ 未运行"
    fi
    
    if systemctl is-active --quiet argo-tunnel.service; then
        echo "  Argo Tunnel: ✅ 运行中"
    else
        echo "  Argo Tunnel: ❌ 未运行"
    fi
    
    echo ""
    log_info "📝 管理命令："
    echo "  查看状态: systemctl status argo-tunnel.service"
    echo "  查看日志: journalctl -u argo-tunnel.service -f"
    echo "  重启服务: systemctl restart argo-tunnel.service"
    echo "  卸载脚本: sudo ./argo-ss.sh uninstall"
}

# ----------------------------
# 测试连接
# ----------------------------
test_connection() {
    log_info "测试连接性..."
    
    echo ""
    log_info "1. 测试本地 Shadowsocks 服务..."
    if ss -tlnp | grep ":$SS_PORT" &> /dev/null; then
        log_success "  Shadowsocks 端口监听正常"
    else
        log_error "  Shadowsocks 端口未监听"
    fi
    
    echo ""
    log_info "2. 测试隧道状态..."
    if systemctl is-active --quiet argo-tunnel.service; then
        log_success "  Argo Tunnel 服务运行中"
    else
        log_error "  Argo Tunnel 服务未运行"
    fi
}

# ----------------------------
# 卸载脚本
# ----------------------------
uninstall() {
    echo ""
    log_warning "⚠️  确认要卸载 Argo Shadowsocks 吗？"
    log_input "这将删除所有配置和数据 [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "卸载已取消"
        return
    fi
    
    log_info "开始卸载..."
    
    # 停止服务
    systemctl stop argo-tunnel.service 2>/dev/null || true
    systemctl stop argo-ss.service 2>/dev/null || true
    
    # 禁用服务
    systemctl disable argo-tunnel.service 2>/dev/null || true
    systemctl disable argo-ss.service 2>/dev/null || true
    
    # 删除服务文件
    rm -f /etc/systemd/system/argo-tunnel.service
    rm -f /etc/systemd/system/argo-ss.service
    
    # 删除配置和日志
    rm -rf "$CONFIG_DIR" "$LOG_DIR"
    
    # 删除二进制文件（可选）
    log_input "是否删除 Cloudflared 和 Shadowsocks 二进制文件？ [y/N]: "
    read -r delete_bin
    if [[ "$delete_bin" =~ ^[Yy]$ ]]; then
        rm -f "$BIN_DIR/cloudflared" "$BIN_DIR/ssserver" "$BIN_DIR/sslocal"
    fi
    
    # 删除 Cloudflare 配置
    log_input "是否删除 Cloudflare 授权文件？ [y/N]: "
    read -r delete_auth
    if [[ "$delete_auth" =~ ^[Yy]$ ]]; then
        rm -rf ~/.cloudflared
    fi
    
    # 删除用户
    userdel "$SERVICE_USER" 2>/dev/null || true
    
    # 重载 systemd
    systemctl daemon-reload
    
    log_success "卸载完成！"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    show_banner
    
    # 检查系统
    system_check
    
    # 安装组件
    install_cloudflared
    install_shadowsocks
    
    # 获取配置
    get_user_config
    
    # Cloudflare 授权
    cloudflare_auth
    
    # 配置服务
    configure_shadowsocks
    configure_cloudflared
    configure_services
    
    # 启动服务
    if start_services; then
        test_connection
        show_connection_info
        log_success "🎉 安装完成！"
    else
        log_error "安装过程中出现问题"
    fi
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
    echo "  5) 退出"
    echo ""
    
    log_input "请输入选项 [1-5]: "
    read -r choice
    
    case "$choice" in
        1)
            main_install
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
            systemctl status argo-tunnel.service --no-pager
            systemctl status argo-ss.service --no-pager
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
            "-h"|"--help")
                echo "使用方法:"
                echo "  sudo ./argo-ss.sh install      # 安装"
                echo "  sudo ./argo-ss.sh uninstall    # 卸载"
                echo "  sudo ./argo-ss.sh status       # 查看状态"
                echo "  sudo ./argo-ss.sh test         # 测试连接"
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

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本"
    echo "例如: sudo ./argo-ss.sh"
    exit 1
fi

# 运行主函数
main "$@"