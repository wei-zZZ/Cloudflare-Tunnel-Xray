#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本
# 版本: 6.1 - 彻底修复授权问题
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
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel + Xray 管理脚本        ║"
    echo "║             版本: 6.1                       ║"
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
# Cloudflare 授权（彻底修复版）
# ----------------------------
direct_cloudflare_auth() {
    echo ""
    print_auth "═══════════════════════════════════════════════"
    print_auth "         Cloudflare 授权（关键步骤）          "
    print_auth "═══════════════════════════════════════════════"
    echo ""
    
    print_warning "⚠️  重要：授权问题是当前最常见的问题！"
    echo ""
    print_info "问题现象：只有 cert.pem 没有 .json 凭证文件"
    print_info "原因：cloudflared tunnel login 授权不完整"
    echo ""
    
    # 清理旧的授权文件
    rm -rf /root/.cloudflared 2>/dev/null
    mkdir -p /root/.cloudflared
    
    echo ""
    print_info "解决方案：使用替代授权方法"
    echo ""
    print_info "我们将使用以下步骤："
    print_info "1. 运行 cloudflared tunnel login 获取授权链接"
    print_info "2. 手动完成浏览器授权"
    print_info "3. 手动创建隧道获取凭证文件"
    echo ""
    print_input "按回车键开始..."
    read -r
    
    # 步骤1：获取授权链接
    echo ""
    print_info "步骤1：获取授权链接"
    echo "=============================================="
    
    # 运行 tunnel login 获取链接
    echo "正在获取授权链接..."
    echo ""
    
    # 创建一个临时脚本来捕获授权链接
    cat > /tmp/get_auth_url.sh << 'EOF'
#!/bin/bash
echo "请复制以下链接到浏览器打开："
echo ""
# 运行 cloudflared tunnel login 并尝试捕获URL
/usr/local/bin/cloudflared tunnel login 2>&1 | grep -o "https://[^ ]*" | head -1
if [ $? -ne 0 ]; then
    echo "https://dash.cloudflare.com/argotunnel"
fi
EOF
    
    chmod +x /tmp/get_auth_url.sh
    /tmp/get_auth_url.sh
    
    echo ""
    echo "=============================================="
    echo ""
    
    print_info "授权步骤："
    print_info "1. 复制上面的链接到浏览器"
    print_info "2. 登录 Cloudflare 账号"
    print_info "3. 选择要授权的域名"
    print_info "4. 点击 'Authorize' 按钮"
    print_info "5. 等待授权完成"
    echo ""
    print_warning "必须看到授权成功的页面！"
    print_input "完成后按回车键继续..."
    read -r
    
    # 步骤2：检查授权文件
    echo ""
    print_info "步骤2：检查授权文件"
    echo "=============================================="
    
    # 检查是否生成了文件
    local auth_success=false
    
    for i in {1..5}; do
        echo ""
        print_info "检查 ($i/5)..."
        
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 找到证书文件 (cert.pem)"
            
            # 查找JSON文件
            local json_files=()
            while IFS= read -r -d '' file; do
                json_files+=("$file")
            done < <(find /root/.cloudflared -name "*.json" -type f -print0 2>/dev/null)
            
            if [[ ${#json_files[@]} -gt 0 ]]; then
                print_success "✅ 找到凭证文件："
                for file in "${json_files[@]}"; do
                    echo "  - $(basename "$file")"
                    # 显示文件前几行
                    echo "    内容: $(head -c 50 "$file")..."
                done
                auth_success=true
                break
            else
                print_warning "⚠️  有证书但无凭证文件"
                print_info "这很常见，我们将使用替代方法..."
                auth_success=true  # 有证书就可以继续
                break
            fi
        else
            print_warning "⚠️  未找到证书文件"
        fi
        
        if [[ $i -lt 5 ]]; then
            print_info "等待3秒后重试..."
            sleep 3
        fi
    done
    
    echo "=============================================="
    
    if [[ "$auth_success" == true ]] && [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "✅ 授权检查通过"
        return 0
    else
        print_error "❌ 授权失败"
        echo ""
        print_info "手动解决方案："
        echo "  1. 手动运行: /usr/local/bin/cloudflared tunnel login"
        echo "  2. 完成完整的浏览器授权"
        echo "  3. 检查文件: ls -la /root/.cloudflared/"
        echo "  4. 应该看到 cert.pem 和 *.json 文件"
        echo ""
        print_input "按回车键尝试继续安装（可能失败）..."
        read -r
        return 1
    fi
}

# ----------------------------
# 创建隧道和配置（支持无凭证文件）
# ----------------------------
setup_tunnel() {
    print_info "设置 Cloudflare Tunnel..."
    
    # 检查证书文件
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "❌ 未找到证书文件，无法继续"
        return 1
    fi
    
    print_success "✅ 找到证书文件"
    
    # 查找凭证文件
    local json_file=""
    local json_files=()
    
    while IFS= read -r -d '' file; do
        json_files+=("$file")
    done < <(find /root/.cloudflared -name "*.json" -type f -print0 2>/dev/null)
    
    if [[ ${#json_files[@]} -eq 0 ]]; then
        print_warning "⚠️  未找到凭证文件 (.json)"
        print_info "将尝试创建隧道来生成凭证文件..."
        
        # 创建测试隧道来生成凭证文件
        local test_tunnel_name="temp-tunnel-$(date +%s)"
        print_info "创建测试隧道: $test_tunnel_name"
        
        if "$BIN_DIR/cloudflared" tunnel create "$test_tunnel_name" > /dev/null 2>&1; then
            # 重新查找凭证文件
            json_files=()
            while IFS= read -r -d '' file; do
                json_files+=("$file")
            done < <(find /root/.cloudflared -name "*.json" -type f -print0 2>/dev/null)
            
            if [[ ${#json_files[@]} -gt 0 ]]; then
                json_file="${json_files[0]}"
                print_success "✅ 通过创建隧道生成了凭证文件: $(basename "$json_file")"
                
                # 删除测试隧道
                "$BIN_DIR/cloudflared" tunnel delete -f "$test_tunnel_name" 2>/dev/null || true
            else
                print_error "❌ 创建隧道后仍未生成凭证文件"
                return 1
            fi
        else
            print_error "❌ 无法创建测试隧道"
            return 1
        fi
    else
        # 使用找到的凭证文件
        json_file="${json_files[0]}"
        print_success "✅ 使用凭证文件: $(basename "$json_file")"
    fi
    
    if [[ -z "$USER_DOMAIN" ]]; then
        if [ "$SILENT_MODE" = true ]; then
            USER_DOMAIN="tunnel.example.com"
        else
            print_error "未设置域名"
            return 1
        fi
    fi
    
    export TUNNEL_ORIGIN_CERT="/root/.cloudflared/cert.pem"
    
    # 删除可能存在的同名隧道
    print_info "清理可能存在的旧隧道..."
    "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    print_info "创建隧道: $TUNNEL_NAME"
    if ! "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME" > /dev/null 2>&1; then
        print_error "❌ 无法创建隧道"
        return 1
    fi
    
    local tunnel_id
    tunnel_id=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -z "$tunnel_id" ]]; then
        print_error "无法获取隧道ID"
        return 1
    fi
    
    print_success "✅ 隧道创建成功 (ID: ${tunnel_id})"
    
    # 绑定域名
    print_info "绑定域名: $USER_DOMAIN"
    if ! "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN" > /dev/null 2>&1; then
        print_warning "⚠️  域名绑定可能失败，请稍后在Cloudflare控制台检查"
    else
        print_success "✅ 域名绑定成功"
    fi
    
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
    
    print_success "✅ 隧道设置完成"
    return 0
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
# 配置系统服务
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
    
    # 创建隧道配置
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
      connectTimeout: 30s
      tcpKeepAlive: 30s
      noHappyEyeballs: true
  - service: http_status:404
EOF
    
    # Argo Tunnel 服务
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
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=always
RestartSec=10
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
        return 1
    fi
    
    # 启动Argo Tunnel
    print_info "启动 Argo Tunnel..."
    systemctl enable secure-tunnel-argo.service > /dev/null 2>&1
    systemctl start secure-tunnel-argo.service
    
    # 等待隧道连接
    local wait_time=0
    local max_wait=60
    
    print_info "等待隧道连接建立（最多60秒）..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        if systemctl is-active --quiet secure-tunnel-argo.service; then
            print_success "✅ Argo Tunnel 服务运行中"
            break
        fi
        
        if [[ $((wait_time % 15)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            print_info "已等待 ${wait_time}秒..."
        fi
        
        sleep 3
        ((wait_time+=3))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        print_warning "⚠️  隧道服务启动较慢"
        print_info "服务会在后台继续启动，请稍后检查状态。"
    fi
    
    sleep 3
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
    print_info "🧪 服务状态:"
    echo ""
    
    if systemctl is-active --quiet secure-tunnel-xray.service; then
        print_success "✅ Xray 服务: 运行中"
    else
        print_error "❌ Xray 服务: 未运行"
    fi
    
    if systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "✅ Argo Tunnel 服务: 运行中"
    else
        print_error "❌ Argo Tunnel 服务: 未运行"
    fi
    
    echo ""
    print_info "📋 使用说明:"
    echo "  1. 复制上面的VLESS链接到客户端"
    echo "  2. 如果连接不上，等待2-3分钟再试"
    echo "  3. 查看服务状态: sudo ./secure_tunnel.sh status"
    echo ""
    
    print_info "🔧 管理命令:"
    echo "  状态检查: sudo ./secure_tunnel.sh status"
    echo "  查看配置: sudo ./secure_tunnel.sh config"
    echo "  重启服务: systemctl restart secure-tunnel-argo.service"
    echo "  查看日志: journalctl -u secure-tunnel-argo.service -f"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    print_info "开始安装流程..."
    
    check_system
    install_components
    collect_user_info
    
    # 授权部分
    if ! direct_cloudflare_auth; then
        print_warning "授权可能有问題，继续安装可能失败"
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
    
    configure_xray
    configure_services
    
    if ! start_services; then
        print_error "服务启动失败"
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
    print_info "开始卸载 Secure Tunnel..."
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
    
    # 停止服务
    systemctl stop secure-tunnel-argo.service 2>/dev/null || true
    systemctl stop secure-tunnel-xray.service 2>/dev/null || true
    
    # 禁用服务
    systemctl disable secure-tunnel-argo.service 2>/dev/null || true
    systemctl disable secure-tunnel-xray.service 2>/dev/null || true
    
    # 删除服务文件
    rm -f /etc/systemd/system/secure-tunnel-argo.service
    rm -f /etc/systemd/system/secure-tunnel-xray.service
    
    # 删除配置文件
    rm -rf "$CONFIG_DIR"
    rm -rf "$DATA_DIR"
    rm -rf "$LOG_DIR"
    
    # 删除二进制文件（可选）
    print_input "是否删除 Xray 和 cloudflared 二进制文件？(y/N): "
    read -r delete_bin
    if [[ "$delete_bin" == "y" || "$delete_bin" == "Y" ]]; then
        rm -f "$BIN_DIR/xray"
        rm -f "$BIN_DIR/cloudflared"
    fi
    
    # 删除用户
    userdel "$SERVICE_USER" 2>/dev/null || true
    groupdel "$SERVICE_GROUP" 2>/dev/null || true
    
    # 删除Cloudflare授权文件
    print_input "是否删除 Cloudflare 授权文件？(y/N): "
    read -r delete_auth
    if [[ "$delete_auth" == "y" || "$delete_auth" == "Y" ]]; then
        rm -rf /root/.cloudflared
    fi
    
    # 重载 systemd
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
    local uuid=$(grep "^UUID=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -z "$domain" ]] || [[ -z "$uuid" ]]; then
        print_error "无法读取配置"
        return 1
    fi
    
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
    
    # 检查Xray服务
    if systemctl is-active --quiet secure-tunnel-xray.service; then
        print_success "Xray 服务: 运行中"
        
        # 显示简要状态
        echo ""
        print_info "Xray 服务状态:"
        systemctl status secure-tunnel-xray.service --no-pager -l | head -10
    else
        print_error "Xray 服务: 未运行"
    fi
    
    echo ""
    
    # 检查Argo服务
    if systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "Argo Tunnel 服务: 运行中"
        
        echo ""
        print_info "Argo 服务状态:"
        systemctl status secure-tunnel-argo.service --no-pager -l | head -10
        
        # 显示隧道信息
        echo ""
        print_info "隧道列表:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || true
    else
        print_error "Argo Tunnel 服务: 未运行"
    fi
}

# ----------------------------
# 手动修复授权
# ----------------------------
manual_auth_fix() {
    echo ""
    print_auth "═══════════════════════════════════════════════"
    print_auth "        手动修复授权问题"
    print_auth "═══════════════════════════════════════════════"
    echo ""
    
    print_info "当前问题：cloudflared tunnel login 不生成凭证文件"
    echo ""
    print_info "解决方案："
    print_info "1. 手动运行授权命令"
    print_info "2. 使用替代方法获取凭证"
    echo ""
    
    echo "请选择修复方法："
    echo ""
    echo "  1) 重新运行 cloudflared tunnel login"
    echo "  2) 使用 tunnel create 生成凭证"
    echo "  3) 检查当前授权状态"
    echo "  4) 返回主菜单"
    echo ""
    
    print_input "请输入选项 (1-4): "
    read -r fix_choice
    
    case "$fix_choice" in
        1)
            echo ""
            print_info "方法1：重新授权"
            echo "=============================================="
            rm -rf /root/.cloudflared 2>/dev/null
            mkdir -p /root/.cloudflared
            
            echo "请复制以下链接到浏览器："
            /usr/local/bin/cloudflared tunnel login 2>&1 | grep -o "https://[^ ]*" | head -1 || echo "https://dash.cloudflare.com/argotunnel"
            
            echo ""
            echo "=============================================="
            echo ""
            print_info "完成后检查文件："
            echo "  ls -la /root/.cloudflared/"
            echo "  应该看到 cert.pem 和 *.json 文件"
            echo ""
            print_input "按回车键继续..."
            read -r
            ;;
        2)
            echo ""
            print_info "方法2：创建隧道生成凭证"
            echo "=============================================="
            
            # 确保有证书文件
            if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
                print_error "未找到证书文件，请先运行方法1"
                return
            fi
            
            print_info "创建测试隧道来生成凭证..."
            local test_name="fix-tunnel-$(date +%s)"
            /usr/local/bin/cloudflared tunnel create "$test_name"
            
            echo ""
            print_info "检查生成的文件："
            ls -la /root/.cloudflared/
            
            echo ""
            print_info "删除测试隧道："
            /usr/local/bin/cloudflared tunnel delete -f "$test_name"
            ;;
        3)
            echo ""
            print_info "当前授权状态："
            echo "=============================================="
            echo "1. /root/.cloudflared/ 目录内容："
            ls -la /root/.cloudflared/ 2>/dev/null || echo "目录不存在"
            
            echo ""
            echo "2. 证书文件检查："
            if [[ -f "/root/.cloudflared/cert.pem" ]]; then
                echo "  ✅ cert.pem 存在"
                echo "  大小: $(stat -c%s /root/.cloudflared/cert.pem) 字节"
            else
                echo "  ❌ cert.pem 不存在"
            fi
            
            echo ""
            echo "3. 凭证文件检查："
            local json_count=$(find /root/.cloudflared -name "*.json" -type f 2>/dev/null | wc -l)
            if [[ $json_count -gt 0 ]]; then
                echo "  ✅ 找到 $json_count 个JSON文件"
                find /root/.cloudflared -name "*.json" -type f | while read file; do
                    echo "  - $(basename "$file")"
                done
            else
                echo "  ❌ 未找到JSON文件"
            fi
            echo "=============================================="
            ;;
        4)
            return
            ;;
        *)
            print_error "无效选项"
            ;;
    esac
    
    echo ""
    print_input "按回车键返回修复菜单..."
    read -r
    manual_auth_fix
}

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    show_title
    
    echo "请选择操作："
    echo ""
    echo "  1) 安装 Secure Tunnel"
    echo "  2) 卸载 Secure Tunnel"
    echo "  3) 查看服务状态"
    echo "  4) 查看配置信息"
    echo "  5) 手动修复授权问题"
    echo "  6) 静默安装 (使用默认值)"
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
            manual_auth_fix
            ;;
        6)
            SILENT_MODE=true
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
        7)
            print_info "再见！"
            exit 0
            ;;
        *)
            print_error "无效选项"
            sleep 1
            ;;
    esac
    
    # 返回菜单
    show_menu
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    # 检查参数
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
        "config"|"subscription")
            show_title
            show_config
            ;;
        "status")
            show_title
            show_status
            ;;
        "fix-auth")
            show_title
            manual_auth_fix
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
            echo "  sudo ./secure_tunnel.sh menu          # 显示菜单"
            echo "  sudo ./secure_tunnel.sh install       # 安装"
            echo "  sudo ./secure_tunnel.sh uninstall     # 卸载"
            echo "  sudo ./secure_tunnel.sh status        # 查看状态"
            echo "  sudo ./secure_tunnel.sh config        # 查看配置"
            echo "  sudo ./secure_tunnel.sh fix-auth      # 修复授权"
            echo "  sudo ./secure_tunnel.sh -y            # 静默安装"
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