#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本
# 版本: 5.5 - 修复隧道连接问题
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
# 收集用户信息
# ----------------------------
collect_user_info() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 安装脚本 v5.5          ║"
    echo "║        修复隧道连接问题                     ║"
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
# Cloudflare 授权
# ----------------------------
direct_cloudflare_auth() {
    echo ""
    print_auth "═══════════════════════════════════════════════"
    print_auth "         Cloudflare 授权（请按提示操作）       "
    print_auth "═══════════════════════════════════════════════"
    echo ""
    
    # 清理旧的授权文件
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
    
    # 直接运行授权命令
    "$BIN_DIR/cloudflared" tunnel login
    
    echo "=============================================="
    echo ""
    
    # 检查授权文件
    local check_count=0
    local max_checks=30
    
    while [[ $check_count -lt $max_checks ]]; do
        # 检查证书文件
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 检测到证书文件 (cert.pem)"
            
            # 查找凭证文件
            local json_files=()
            while IFS= read -r -d '' file; do
                json_files+=("$file")
            done < <(find /root/.cloudflared -name "*.json" -type f -print0 2>/dev/null)
            
            if [[ ${#json_files[@]} -gt 0 ]]; then
                local json_file="${json_files[0]}"
                print_success "✅ 检测到凭证文件: $(basename "$json_file")"
                return 0
            else
                print_warning "⚠️  未找到JSON凭证文件"
                
                # 尝试创建测试隧道来生成凭证
                print_info "尝试创建测试隧道来生成凭证..."
                "$BIN_DIR/cloudflared" tunnel create "test-tunnel-auth" > /dev/null 2>&1 || true
                
                # 再次检查
                json_files=()
                while IFS= read -r -d '' file; do
                    json_files+=("$file")
                done < <(find /root/.cloudflared -name "*.json" -type f -print0 2>/dev/null)
                
                if [[ ${#json_files[@]} -gt 0 ]]; then
                    print_success "✅ 通过创建隧道生成了凭证文件"
                    return 0
                fi
            fi
        fi
        
        if [[ $check_count -eq 0 ]]; then
            echo ""
            print_input "授权完成后，按回车键继续检查..."
            read -r
        fi
        
        print_info "等待授权文件生成... ($((check_count*2))秒)"
        sleep 2
        ((check_count++))
    done
    
    print_error "❌ 授权失败或凭证文件缺失"
    echo ""
    print_info "请手动运行授权:"
    echo "  sudo $BIN_DIR/cloudflared tunnel login"
    echo ""
    print_input "按回车键退出脚本，手动解决问题后再运行..."
    read -r
    exit 1
}

# ----------------------------
# 创建隧道和配置
# ----------------------------
setup_tunnel() {
    print_info "设置 Cloudflare Tunnel..."
    
    # 检查证书文件
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "未找到证书文件"
        exit 1
    fi
    
    # 查找凭证文件
    local json_file=""
    local json_files=()
    
    while IFS= read -r -d '' file; do
        json_files+=("$file")
    done < <(find /root/.cloudflared -name "*.json" -type f -print0 2>/dev/null)
    
    if [[ ${#json_files[@]} -eq 0 ]]; then
        print_error "❌ 未找到任何凭证文件 (.json)"
        exit 1
    fi
    
    # 使用第一个找到的凭证文件
    json_file="${json_files[0]}"
    print_success "✅ 使用凭证文件: $(basename "$json_file")"
    
    if [[ -z "$USER_DOMAIN" ]]; then
        if [ "$SILENT_MODE" = true ]; then
            USER_DOMAIN="tunnel.example.com"
        else
            print_error "未设置域名"
            exit 1
        fi
    fi
    
    export TUNNEL_ORIGIN_CERT="/root/.cloudflared/cert.pem"
    
    # 删除可能存在的同名隧道
    print_info "清理可能存在的旧隧道..."
    "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    print_info "创建隧道: $TUNNEL_NAME"
    "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME" > /dev/null 2>&1
    
    local tunnel_id
    tunnel_id=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -z "$tunnel_id" ]]; then
        print_error "无法获取隧道ID"
        exit 1
    fi
    
    print_success "✅ 隧道创建成功 (ID: ${tunnel_id})"
    
    # 绑定域名
    print_info "绑定域名: $USER_DOMAIN"
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN" > /dev/null 2>&1
    print_success "✅ 域名绑定成功"
    
    # 等待DNS传播
    print_info "等待DNS配置生效（10秒）..."
    sleep 10
    
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
CERT_PATH=/root/.cloudflared/cert.pem
CREDENTIALS_FILE=$json_file
CREATED_DATE=$(date +"%Y-%m-%d")
EOF
    
    print_success "隧道设置完成"
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
    
    print_success "Xray 配置完成"
}

# ----------------------------
# 配置系统服务（修复版）
# ----------------------------
configure_services() {
    print_info "配置系统服务..."
    
    if ! id -u "$SERVICE_USER" &> /dev/null; then
        useradd -r -s /usr/sbin/nologin "$SERVICE_USER"
    fi
    
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # Xray 服务
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
    
    # 从配置文件读取信息
    local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local json_file=$(grep "^CREDENTIALS_FILE=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local port=$(grep "^PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    # 创建修复版的隧道配置
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: $json_file
logfile: $LOG_DIR/argo.log
loglevel: info
ingress:
  - hostname: $domain
    service: http://localhost:$port
    originRequest:
      noTLSVerify: true
      httpHostHeader: $domain
      keepAliveConnections: 10
      keepAliveTimeout: 30s
      connectTimeout: 30s
      tcpKeepAlive: 10s
      noHappyEyeballs: true
  - service: http_status:404
EOF
    
    # Argo Tunnel 服务 - 修复版
    cat > /etc/systemd/system/secure-tunnel-argo.service << EOF
[Unit]
Description=Secure Tunnel Argo Service
After=network.target secure-tunnel-xray.service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
Environment="TUNNEL_METRICS=localhost:49555"
Environment="TUNNEL_TRANSPORT_LOGLEVEL=info"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run $tunnel_id
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=5
StandardOutput=append:$LOG_DIR/argo.log
StandardError=append:$LOG_DIR/argo-error.log
ExecReload=/bin/kill -HUP \$MAINPID
KillSignal=SIGQUIT
KillMode=mixed
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "系统服务配置完成"
}

# ----------------------------
# 启动服务（修复版）
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    # 先停止可能存在的服务
    systemctl stop secure-tunnel-argo.service 2>/dev/null || true
    systemctl stop secure-tunnel-xray.service 2>/dev/null || true
    sleep 2
    
    # 启动Xray
    systemctl enable secure-tunnel-xray.service > /dev/null 2>&1
    systemctl start secure-tunnel-xray.service
    sleep 3
    
    if systemctl is-active --quiet secure-tunnel-xray.service; then
        print_success "✅ Xray 启动成功"
    else
        print_error "❌ Xray 启动失败"
        journalctl -u secure-tunnel-xray.service -n 20 --no-pager
        exit 1
    fi
    
    # 测试Xray是否在监听
    if ss -tulpn | grep -q ":10000"; then
        print_success "✅ Xray 正在监听端口 10000"
    else
        print_error "❌ Xray 未监听端口 10000"
    fi
    
    # 启动Argo Tunnel
    print_info "启动 Argo Tunnel（这可能需要30-60秒）..."
    systemctl enable secure-tunnel-argo.service > /dev/null 2>&1
    systemctl start secure-tunnel-argo.service
    
    # 等待隧道连接
    local wait_time=0
    local max_wait=60
    
    while [[ $wait_time -lt $max_wait ]]; do
        if systemctl is-active --quiet secure-tunnel-argo.service; then
            if "$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep -q "RUNNING"; then
                print_success "✅ Argo Tunnel 启动成功并已连接"
                break
            elif [[ $wait_time -gt 30 ]]; then
                print_warning "⚠️  隧道服务已启动但未显示RUNNING状态"
                print_info "正在检查隧道状态..."
                "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || true
                break
            fi
        fi
        
        if [[ $wait_time -eq 10 ]]; then
            print_info "等待隧道连接... (10秒)"
        elif [[ $wait_time -eq 30 ]]; then
            print_info "等待隧道连接... (30秒)"
        elif [[ $wait_time -eq 45 ]]; then
            print_warning "隧道连接时间较长，检查日志中..."
            tail -5 "$LOG_DIR/argo-error.log" 2>/dev/null || true
        fi
        
        sleep 2
        ((wait_time+=2))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        print_error "❌ Argo Tunnel 连接超时"
        echo ""
        print_info "请检查日志:"
        journalctl -u secure-tunnel-argo.service -n 30 --no-pager
        echo ""
        print_warning "注意：隧道可能需要更长时间来建立连接"
        print_info "可以等待几分钟后检查状态: systemctl status secure-tunnel-argo.service"
    fi
    
    sleep 3
}

# ----------------------------
# 显示连接信息和测试
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
    local port=$(grep "^PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    if [[ -z "$domain" ]] || [[ -z "$uuid" ]]; then
        print_error "无法读取配置"
        return
    fi
    
    print_success "🔗 域名: $domain"
    print_success "🔑 UUID: $uuid"
    print_success "🚪 端口: 443 (TLS) / 80 (非TLS)"
    print_success "🛣️  路径: /$uuid"
    print_success "🔧 本地端口: $port"
    echo ""
    
    local vless_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${uuid}&sni=${domain}#安全隧道"
    
    echo "VLESS 链接:"
    echo "$vless_tls"
    echo ""
    
    # 测试服务状态
    print_info "🧪 服务状态测试..."
    echo ""
    
    # 检查Xray服务
    if systemctl is-active --quiet secure-tunnel-xray.service; then
        print_success "✅ Xray 服务: 运行中"
        
        # 测试Xray本地连接
        if timeout 2 curl -s http://localhost:${port}/${uuid} > /dev/null; then
            print_success "✅ Xray 本地服务可达"
        else
            print_warning "⚠️  Xray 本地服务不可达（可能正常）"
        fi
    else
        print_error "❌ Xray 服务: 未运行"
    fi
    
    echo ""
    
    # 检查Argo服务
    if systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "✅ Argo Tunnel 服务: 运行中"
        
        # 检查隧道状态
        print_info "检查隧道状态..."
        local tunnel_status=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || true)
        
        if echo "$tunnel_status" | grep -q "RUNNING"; then
            print_success "✅ 隧道状态: RUNNING"
            
            # 测试域名解析
            print_info "测试域名解析..."
            if dig +short "$domain" | grep -q -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
                print_success "✅ 域名解析正常"
            else
                print_warning "⚠️  域名解析异常，请检查Cloudflare DNS设置"
            fi
            
            # 测试HTTPS连接（简单测试）
            print_info "测试HTTPS连接..."
            if timeout 5 curl -s -I "https://${domain}" | grep -q -E "(200|301|302|403|404)"; then
                print_success "✅ HTTPS 连接正常"
            else
                print_warning "⚠️  HTTPS 连接测试失败（可能正常，需要客户端测试）"
            fi
            
        elif echo "$tunnel_status" | grep -q "STARTING"; then
            print_info "🔄 隧道状态: STARTING（正在启动）"
            print_info "请等待1-2分钟后隧道会自动连接"
        elif echo "$tunnel_status" | grep -q "RECONNECTING"; then
            print_info "🔄 隧道状态: RECONNECTING（重新连接中）"
            print_info "这通常会自动恢复"
        elif [[ -n "$tunnel_status" ]]; then
            print_warning "⚠️  隧道状态: $(echo "$tunnel_status" | awk '{print $3}')"
        else
            print_warning "⚠️  未找到隧道状态信息"
            print_info "隧道可能需要更多时间来启动，请稍后检查"
        fi
    else
        print_error "❌ Argo Tunnel 服务: 未运行"
    fi
    
    echo ""
    print_info "📋 故障排除指南:"
    echo "  1. 查看隧道日志: tail -f $LOG_DIR/argo.log"
    echo "  2. 查看错误日志: tail -f $LOG_DIR/argo-error.log"
    echo "  3. 重启隧道服务: systemctl restart secure-tunnel-argo.service"
    echo "  4. 检查DNS设置: 确保 $domain 在Cloudflare管理且代理开启（橙色云朵）"
    echo "  5. 等待DNS传播: DNS更改可能需要几分钟生效"
    echo ""
    
    print_info "🔧 服务管理命令:"
    echo "  状态: systemctl status secure-tunnel-argo.service"
    echo "  重启: systemctl restart secure-tunnel-argo.service"
    echo "  停止: systemctl stop secure-tunnel-argo.service"
    echo "  日志: journalctl -u secure-tunnel-argo.service -f"
    echo ""
    
    print_info "🌐 客户端测试:"
    echo "  1. 复制上面的VLESS链接到客户端"
    echo "  2. 如果连接不上，等待2-3分钟再试"
    echo "  3. 确保客户端配置正确（VLESS + WS + TLS）"
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
    echo ""
    print_info "💡 提示：如果连接不上，请等待2-3分钟让隧道完全建立连接。"
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
    
    echo ""
    if systemctl is-active --quiet secure-tunnel-xray.service; then
        print_success "Xray 服务: 运行中"
    else
        print_error "Xray 服务: 未运行"
    fi
    
    if systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "Argo Tunnel 服务: 运行中"
        
        echo ""
        print_info "隧道状态:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || true
    else
        print_error "Argo Tunnel 服务: 未运行"
    fi
    
    echo ""
    print_info "最近日志:"
    journalctl -u secure-tunnel-argo.service -n 10 --no-pager
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
            echo "║    Cloudflare Tunnel 安装脚本 v5.5          ║"
            echo "║        修复隧道连接问题                     ║"
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