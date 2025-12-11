#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本
# 版本: 5.6 - 修复授权凭证问题
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
    echo "║    Cloudflare Tunnel 安装脚本 v5.6          ║"
    echo "║        修复授权凭证问题                     ║"
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
# Cloudflare 授权（完整修复版）
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
    
    print_auth "重要：请确保完成完整的授权流程！"
    echo ""
    print_info "授权步骤："
    print_info "1. 脚本运行 cloudflared tunnel login"
    print_info "2. 你会看到授权链接（类似 https://dash.cloudflare.com/...）"
    print_info "3. 复制链接到浏览器打开"
    print_info "4. 登录 Cloudflare 账号（如果未登录）"
    print_info "5. 选择要授权的域名"
    print_info "6. 点击 'Authorize' 按钮"
    print_info "7. 等待授权完成"
    print_info "8. 返回终端按回车继续"
    echo ""
    print_warning "注意：必须点击 'Authorize' 按钮！仅仅登录或选择域名是不够的。"
    echo ""
    print_input "按回车键开始授权..."
    read -r
    
    echo ""
    print_info "正在运行 cloudflared tunnel login..."
    echo "=============================================="
    
    # 运行授权命令 - 确保能看到完整输出
    "$BIN_DIR/cloudflared" tunnel login --no-autoupdate
    
    echo "=============================================="
    echo ""
    
    # 检查授权文件
    local check_count=0
    local max_checks=20
    
    echo ""
    print_info "检查授权文件生成情况..."
    
    while [[ $check_count -lt $max_checks ]]; do
        echo ""
        print_info "检查进度: $((check_count*3))秒"
        
        # 列出.cloudflared目录内容
        if [[ -d "/root/.cloudflared" ]]; then
            print_info "/root/.cloudflared/ 目录内容:"
            ls -la /root/.cloudflared/ 2>/dev/null || echo "无法列出目录"
        fi
        
        # 检查证书文件
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 找到证书文件 (cert.pem)"
            
            # 查找所有可能的凭证文件
            local json_files=()
            while IFS= read -r -d '' file; do
                json_files+=("$file")
            done < <(find /root/.cloudflared -name "*.json" -type f -print0 2>/dev/null)
            
            if [[ ${#json_files[@]} -gt 0 ]]; then
                print_success "✅ 找到凭证文件:"
                for file in "${json_files[@]}"; do
                    echo "   - $(basename "$file")"
                    
                    # 检查文件内容是否是有效的JSON
                    if head -1 "$file" | grep -q "{" && tail -1 "$file" | grep -q "}"; then
                        print_success "    文件格式: 有效的JSON"
                        local file_size=$(stat -c%s "$file")
                        if [[ $file_size -gt 100 ]]; then
                            print_success "    文件大小: ${file_size}字节（正常）"
                            
                            # 检查是否包含必要的字段
                            if grep -q "AccountTag\|TunnelID\|TunnelSecret" "$file"; then
                                print_success "    包含隧道凭证信息"
                                return 0
                            else
                                print_warning "    警告：可能不是隧道凭证文件"
                            fi
                        else
                            print_warning "    文件大小: ${file_size}字节（可能太小）"
                        fi
                    else
                        print_warning "    文件格式: 不是有效的JSON"
                    fi
                done
                
                # 如果找到文件但格式不对，继续等待
                sleep 3
                ((check_count++))
                continue
            else
                print_warning "⚠️  未找到JSON凭证文件"
                
                if [[ $check_count -lt 5 ]]; then
                    print_info "等待凭证文件生成...（这可能需要几秒钟）"
                elif [[ $check_count -eq 5 ]]; then
                    echo ""
                    print_warning "问题：有证书但没有凭证文件"
                    print_info "这可能是因为授权不完整。"
                    print_info "请确认你在浏览器中点击了 'Authorize' 按钮。"
                    echo ""
                    print_input "如果已点击Authorize，按回车键继续等待..."
                    read -r
                elif [[ $check_count -eq 10 ]]; then
                    echo ""
                    print_error "❌ 长时间未生成凭证文件"
                    print_info "可能的原因："
                    echo "  1. 未在浏览器中点击 'Authorize' 按钮"
                    echo "  2. 授权的域名不正确"
                    echo "  3. Cloudflare API 问题"
                    echo ""
                    print_info "解决方案："
                    echo "  1. 重新运行授权"
                    echo "  2. 确保完成完整的授权流程"
                    echo ""
                    print_input "按回车键重新授权..."
                    read -r
                    
                    # 重新授权
                    rm -rf /root/.cloudflared 2>/dev/null
                    mkdir -p /root/.cloudflared
                    
                    echo ""
                    print_info "重新运行 cloudflared tunnel login..."
                    "$BIN_DIR/cloudflared" tunnel login --no-autoupdate
                    echo ""
                    
                    check_count=0
                    continue
                fi
            fi
        else
            print_warning "⚠️  未找到证书文件"
            
            if [[ $check_count -eq 0 ]]; then
                echo ""
                print_input "授权完成后，按回车键开始检查..."
                read -r
            fi
        fi
        
        sleep 3
        ((check_count++))
    done
    
    print_error "❌ 授权失败：无法生成完整的凭证文件"
    echo ""
    print_info "请手动执行以下步骤："
    echo ""
    echo "1. 手动运行授权命令："
    echo "   sudo $BIN_DIR/cloudflared tunnel login"
    echo ""
    echo "2. 仔细完成浏览器授权："
    echo "   - 复制显示的链接到浏览器"
    echo "   - 登录 Cloudflare 账号"
    echo "   - 选择正确的域名"
    echo "   - 点击 'Authorize' 按钮"
    echo ""
    echo "3. 检查生成的文件："
    echo "   ls -la /root/.cloudflared/"
    echo "   # 应该看到 cert.pem 和 *.json 文件"
    echo ""
    echo "4. 重新运行安装脚本"
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
    
    # 查找正确的凭证文件
    local json_file=""
    local json_files=()
    
    while IFS= read -r -d '' file; do
        json_files+=("$file")
    done < <(find /root/.cloudflared -name "*.json" -type f -print0 2>/dev/null)
    
    if [[ ${#json_files[@]} -eq 0 ]]; then
        print_error "❌ 未找到任何凭证文件 (.json)"
        echo ""
        print_info "请重新运行授权："
        echo "  rm -rf /root/.cloudflared"
        echo "  sudo $BIN_DIR/cloudflared tunnel login"
        exit 1
    fi
    
    # 尝试找到正确的凭证文件（不是隧道创建的）
    for file in "${json_files[@]}"; do
        local filename=$(basename "$file")
        # 排除测试隧道创建的凭证文件
        if [[ "$filename" != *"test-tunnel-auth"* ]] && [[ "$filename" != *"$TUNNEL_NAME"* ]]; then
            json_file="$file"
            break
        fi
    done
    
    # 如果没找到，使用第一个
    if [[ -z "$json_file" ]] && [[ ${#json_files[@]} -gt 0 ]]; then
        json_file="${json_files[0]}"
    fi
    
    if [[ -z "$json_file" ]] || [[ ! -f "$json_file" ]]; then
        print_error "❌ 找不到有效的凭证文件"
        exit 1
    fi
    
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
    
    # 清理旧的测试隧道
    print_info "清理测试隧道..."
    "$BIN_DIR/cloudflared" tunnel delete -f "test-tunnel-auth" 2>/dev/null || true
    
    # 删除可能存在的同名隧道
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
    print_info "等待DNS配置生效（15秒）..."
    sleep 15
    
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
        exit 1
    fi
    
    # 启动Argo Tunnel
    print_info "启动 Argo Tunnel..."
    systemctl enable secure-tunnel-argo.service > /dev/null 2>&1
    systemctl start secure-tunnel-argo.service
    
    # 等待隧道连接
    local wait_time=0
    local max_wait=90
    
    print_info "等待隧道连接建立（最多90秒）..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        if systemctl is-active --quiet secure-tunnel-argo.service; then
            # 检查隧道状态
            local tunnel_info=$("$BIN_DIR/cloudflared" tunnel info "$TUNNEL_NAME" 2>/dev/null || true)
            
            if echo "$tunnel_info" | grep -q "status: connected"; then
                print_success "✅ 隧道连接成功！"
                break
            elif echo "$tunnel_info" | grep -q "status:"; then
                local status=$(echo "$tunnel_info" | grep "status:" | awk '{print $2}')
                print_info "隧道状态: $status"
            fi
        fi
        
        if [[ $((wait_time % 10)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            print_info "已等待 ${wait_time}秒..."
        fi
        
        sleep 3
        ((wait_time+=3))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        print_warning "⚠️  隧道连接时间较长"
        print_info "隧道可能需要更多时间来建立连接，服务会继续在后台运行。"
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
    else
        print_error "❌ Xray 服务: 未运行"
    fi
    
    # 检查Argo服务
    if systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "✅ Argo Tunnel 服务: 运行中"
        
        # 检查隧道详细信息
        echo ""
        print_info "隧道详细信息:"
        "$BIN_DIR/cloudflared" tunnel info "$TUNNEL_NAME" 2>/dev/null || echo "无法获取隧道信息"
    else
        print_error "❌ Argo Tunnel 服务: 未运行"
    fi
    
    echo ""
    print_info "📋 下一步操作:"
    echo "  1. 复制上面的VLESS链接到客户端"
    echo "  2. 如果连接不上，等待2-3分钟再试"
    echo "  3. 查看隧道日志: tail -f $LOG_DIR/argo.log"
    echo "  4. 重启隧道服务: systemctl restart secure-tunnel-argo.service"
    echo ""
    
    print_info "🔧 快速诊断命令:"
    echo "  # 查看隧道状态"
    echo "  sudo $BIN_DIR/cloudflared tunnel list"
    echo "  sudo $BIN_DIR/cloudflared tunnel info $TUNNEL_NAME"
    echo ""
    echo "  # 查看服务日志"
    echo "  sudo journalctl -u secure-tunnel-argo.service -f"
    echo "  sudo tail -f $LOG_DIR/argo.log"
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
    
    echo ""
    if systemctl is-active --quiet secure-tunnel-xray.service; then
        print_success "Xray 服务: 运行中"
    else
        print_error "Xray 服务: 未运行"
    fi
    
    if systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "Argo Tunnel 服务: 运行中"
        
        echo ""
        print_info "隧道列表:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || true
        
        echo ""
        print_info "当前隧道状态:"
        local tunnel_name=$(grep "^TUNNEL_NAME=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$tunnel_name" ]]; then
            "$BIN_DIR/cloudflared" tunnel info "$tunnel_name" 2>/dev/null || echo "无法获取隧道信息"
        fi
    else
        print_error "Argo Tunnel 服务: 未运行"
    fi
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
            echo "║    Cloudflare Tunnel 安装脚本 v5.6          ║"
            echo "║        修复授权凭证问题                     ║"
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