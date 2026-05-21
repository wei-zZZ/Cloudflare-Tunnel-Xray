#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 管理脚本
# 版本: 6.7 - 彻底修复 JSON 生成错误
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

# 端口定义
WS_PORT=10000          # WebSocket 端口 (CF Tunnel 回源)
REALITY_PORT=10001     # Reality 直连端口

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel + Xray 管理脚本        ║"
    echo "║       版本: 6.7 - 完全修复 JSON             ║"
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
    rm -f /etc/apt/sources.list.d/*bullseye-backports* 2>/dev/null || true
    apt-get update -y || print_warning "软件源更新失败，尝试继续安装..."
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
    echo "  WebSocket 端口: $WS_PORT (CF Tunnel 回源)"
    echo "  Reality 直连端口: $REALITY_PORT"
    echo ""
}

# ----------------------------
# 系统检查及工具安装
# ----------------------------
check_system() {
    print_info "检查系统环境..."
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
    fix_apt_sources
    
    print_info "安装必要工具..."
    local tools=("curl" "wget" "unzip" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "正在安装 $tool..."
            if apt-get install -y -qq "$tool" 2>/dev/null; then
                print_success "$tool 安装成功"
            else
                print_warning "apt安装 $tool 失败，尝试其他方法..."
                case "$tool" in
                    "curl") apt-get install -y libcurl4-openssl-dev || true ;;
                    "wget") wget_direct_install || true ;;
                    "unzip") unzip_direct_install || true ;;
                    "jq") install_jq_directly || true ;;
                esac
                if ! command -v "$tool" &> /dev/null; then
                    print_error "无法安装 $tool，安装可能不完整"
                else
                    print_success "$tool 安装完成"
                fi
            fi
        else
            print_info "$tool 已安装"
        fi
    done
    print_success "系统检查完成"
}

install_jq_directly() {
    print_info "手动下载安装 jq..."
    local arch=$(uname -m)
    local jq_url=""
    case "$arch" in
        x86_64|amd64) jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64" ;;
        aarch64|arm64) jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-arm64" ;;
    esac
    if [ -n "$jq_url" ]; then
        curl -L -o /tmp/jq "$jq_url"
        chmod +x /tmp/jq
        mv /tmp/jq /usr/local/bin/jq
    fi
}

wget_direct_install() {
    print_info "手动下载安装 wget..."
    local arch=$(uname -m)
    local wget_url=""
    case "$arch" in
        x86_64|amd64) wget_url="http://ftp.debian.org/debian/pool/main/w/wget/wget_1.21-1+deb11u1_amd64.deb" ;;
        aarch64|arm64) wget_url="http://ftp.debian.org/debian/pool/main/w/wget/wget_1.21-1+deb11u1_arm64.deb" ;;
    esac
    if [ -n "$wget_url" ]; then
        curl -L -o /tmp/wget.deb "$wget_url" && dpkg -i /tmp/wget.deb || apt-get install -f -y
        rm -f /tmp/wget.deb
    fi
}

unzip_direct_install() {
    print_info "手动下载安装 unzip..."
    local arch=$(uname -m)
    local unzip_url=""
    case "$arch" in
        x86_64|amd64) unzip_url="http://ftp.debian.org/debian/pool/main/u/unzip/unzip_6.0-26_amd64.deb" ;;
        aarch64|arm64) unzip_url="http://ftp.debian.org/debian/pool/main/u/unzip/unzip_6.0-26_arm64.deb" ;;
    esac
    if [ -n "$unzip_url" ]; then
        curl -L -o /tmp/unzip.deb "$unzip_url" && dpkg -i /tmp/unzip.deb || apt-get install -f -y
        rm -f /tmp/unzip.deb
    fi
}

# ----------------------------
# 安装 Xray 和 cloudflared
# ----------------------------
install_components() {
    print_info "安装必要组件..."
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
            local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
            local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    print_info "下载 Xray..."
    if curl -L -o /tmp/xray.zip "$xray_url"; then
        if unzip -q -o /tmp/xray.zip -d /tmp/; then
            local xray_binary=$(find /tmp -name "xray" -type f | head -1)
            if [[ -n "$xray_binary" ]] && [[ -f "$xray_binary" ]]; then
                mv "$xray_binary" "$BIN_DIR/xray"
                chmod +x "$BIN_DIR/xray"
                print_success "Xray 安装成功"
            else
                print_error "Xray 解压后未找到二进制文件"
                exit 1
            fi
        else
            print_error "Xray 解压失败"
            exit 1
        fi
    else
        print_error "Xray 下载失败"
        exit 1
    fi
    
    print_info "下载 cloudflared..."
    if curl -L -o /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        print_success "cloudflared 安装成功"
    else
        print_error "cloudflared 下载失败"
        exit 1
    fi
    
    rm -rf /tmp/xray* /tmp/cloudflare* 2>/dev/null
    print_success "所有组件安装完成"
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
    "$BIN_DIR/cloudflared" tunnel login
    echo ""
    echo "=============================================="
    print_input "完成授权后按回车继续..."
    read -r
    
    local check_count=0
    while [[ $check_count -lt 10 ]]; do
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 授权成功！找到证书文件"
            if ls /root/.cloudflared/*.json 1> /dev/null 2>&1; then
                local json_file=$(ls /root/.cloudflared/*.json | head -1)
                print_success "✅ 找到凭证文件: $(basename "$json_file")"
                return 0
            else
                print_warning "⚠️  未找到JSON凭证文件，将在创建隧道时生成"
                return 0
            fi
        fi
        sleep 2
        ((check_count++))
    done
    print_error "❌ 授权失败：未找到证书文件"
    return 1
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
    
    local json_file=""
    if ls /root/.cloudflared/*.json 1> /dev/null 2>&1; then
        json_file=$(ls -t /root/.cloudflared/*.json | head -1)
        print_success "✅ 使用现有凭证文件: $(basename "$json_file")"
    else
        print_warning "⚠️  未找到凭证文件，正在创建隧道..."
        "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
        sleep 2
        print_info "创建隧道: $TUNNEL_NAME"
        if timeout 60 "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"; then
            sleep 3
            json_file=$(ls -t /root/.cloudflared/*.json 2>/dev/null | head -1)
            if [[ -n "$json_file" ]] && [[ -f "$json_file" ]]; then
                print_success "✅ 隧道创建成功，凭证文件: $(basename "$json_file")"
            else
                print_error "❌ 创建隧道后未生成凭证文件"
                exit 1
            fi
        else
            print_error "❌ 无法创建隧道"
            exit 1
        fi
    fi
    
    local tunnel_id
    tunnel_id=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    if [[ -z "$tunnel_id" ]]; then
        print_error "❌ 无法获取隧道ID"
        exit 1
    fi
    print_success "✅ 隧道就绪 (名称: ${TUNNEL_NAME}, ID: ${tunnel_id})"
    
    print_info "绑定域名: $USER_DOMAIN"
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN" > /dev/null 2>&1
    print_success "✅ 域名绑定成功"
    
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
CERT_PATH=/root/.cloudflared/cert.pem
CREDENTIALS_FILE=$json_file
CREATED_DATE=$(date +"%Y-%m-%d")
WS_PORT=$WS_PORT
REALITY_PORT=$REALITY_PORT
EOF
    print_success "隧道设置完成"
}

# ----------------------------
# 生成 Reality 密钥对
# ----------------------------
generate_reality_keypair() {
    local private_key public_key
    if command -v "$BIN_DIR/xray" &>/dev/null; then
        local output=$("$BIN_DIR/xray" x25519)
        private_key=$(echo "$output" | grep "Private key:" | awk '{print $3}')
        public_key=$(echo "$output" | grep "Public key:" | awk '{print $3}')
    else
        print_error "xray 命令不可用，无法生成密钥对"
        exit 1
    fi
    echo "$private_key|$public_key"
}

# ----------------------------
# 配置 Xray (VLESS WS + VLESS Reality) - 完全使用 jq 生成，避免字符串拼接
# ----------------------------
configure_xray() {
    print_info "配置 Xray (VLESS WebSocket + VLESS Reality) ..."
    
    # 生成 UUID
    local ws_uuid=$(cat /proc/sys/kernel/random/uuid)
    local reality_uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # 生成 Reality 密钥对
    local keypair=$(generate_reality_keypair)
    local reality_private_key=$(echo "$keypair" | cut -d'|' -f1)
    local reality_public_key=$(echo "$keypair" | cut -d'|' -f2)
    local reality_short_id=$(openssl rand -hex 8)
    
    # 保存所有参数到配置文件
    cat >> "$CONFIG_DIR/tunnel.conf" << EOF
WS_UUID=$ws_uuid
REALITY_UUID=$reality_uuid
REALITY_PRIVATE_KEY=$reality_private_key
REALITY_PUBLIC_KEY=$reality_public_key
REALITY_SHORT_ID=$reality_short_id
REALITY_SERVER_NAME=${USER_DOMAIN}
EOF
    
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # 使用 jq 生成配置文件（单次调用，避免嵌套）
    create_xray_config "$ws_uuid" "$reality_uuid" "$reality_private_key" "$reality_short_id"
    
    print_success "Xray 配置完成"
}

create_xray_config() {
    local ws_uuid=$1
    local reality_uuid=$2
    local reality_private_key=$3
    local reality_short_id=$4
    
    # 直接从配置文件读取域名，确保变量存在
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    if [[ -z "$domain" ]]; then
        print_error "无法读取域名配置"
        exit 1
    fi
    
    # 使用 jq 生成完整配置，所有数组在内部构造
    jq -n \
        --arg ws_uuid "$ws_uuid" \
        --arg ws_port "$WS_PORT" \
        --arg reality_uuid "$reality_uuid" \
        --arg reality_port "$REALITY_PORT" \
        --arg reality_private_key "$reality_private_key" \
        --arg reality_short_id "$reality_short_id" \
        --arg domain "$domain" \
        '
        {
            log: {loglevel: "warning"},
            inbounds: [
                {
                    port: ($ws_port | tonumber),
                    listen: "127.0.0.1",
                    protocol: "vless",
                    settings: {
                        clients: [{id: $ws_uuid, level: 0}],
                        decryption: "none"
                    },
                    streamSettings: {
                        network: "ws",
                        security: "none",
                        wsSettings: {path: ("/" + $ws_uuid)}
                    },
                    tag: "vless-ws-in"
                },
                {
                    port: ($reality_port | tonumber),
                    protocol: "vless",
                    settings: {
                        clients: [{id: $reality_uuid, flow: "xtls-rprx-vision", level: 0}],
                        decryption: "none"
                    },
                    streamSettings: {
                        network: "tcp",
                        security: "reality",
                        realitySettings: {
                            dest: "www.microsoft.com:443",
                            serverNames: [$domain, "www.microsoft.com", "addons.mozilla.org"],
                            privateKey: $reality_private_key,
                            shortIds: [$reality_short_id]
                        }
                    },
                    tag: "vless-reality-in"
                }
            ],
            outbounds: [{protocol: "freedom", tag: "direct"}]
        }' > "$CONFIG_DIR/xray.json"
}

# ----------------------------
# 测试 Xray 配置
# ----------------------------
test_xray_config() {
    print_info "测试 Xray 配置..."
    if "$BIN_DIR/xray" run -test -config "$CONFIG_DIR/xray.json" > /dev/null 2>&1; then
        print_success "✅ Xray 配置测试通过"
        return 0
    else
        print_error "❌ Xray 配置测试失败"
        echo "详细错误信息："
        "$BIN_DIR/xray" run -test -config "$CONFIG_DIR/xray.json" 2>&1 || true
        return 1
    fi
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
    
    local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local json_file=$(grep "^CREDENTIALS_FILE=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: $json_file
logfile: $LOG_DIR/argo.log
loglevel: info
ingress:
  - hostname: $domain
    service: http://localhost:$WS_PORT
    originRequest:
      noTLSVerify: true
      httpHostHeader: $domain
      connectTimeout: 30s
      tcpKeepAlive: 30s
      noHappyEyeballs: true
  - service: http_status:404
EOF
    
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
    
    # 先测试配置
    if ! test_xray_config; then
        print_error "Xray 配置无效，请手动检查"
        return 1
    fi
    
    systemctl stop secure-tunnel-argo.service 2>/dev/null || true
    systemctl stop secure-tunnel-xray.service 2>/dev/null || true
    sleep 2
    
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
    
    print_info "启动 Argo Tunnel..."
    systemctl enable secure-tunnel-argo.service > /dev/null 2>&1
    systemctl start secure-tunnel-argo.service
    
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
        print_warning "⚠️  隧道服务启动较慢，服务会在后台继续启动。"
    fi
    sleep 3
    return 0
}

# ----------------------------
# TCP 网络优化 (BBR+fq)
# ----------------------------
apply_tcp_tuning() {
    print_info "TCP 网络优化 (BBR + fq)"
    echo ""
    
    local mem_g_input bw_mbps_input rtt_ms_input
    if [ "$SILENT_MODE" = true ] || [ "${1:-}" = "--auto" ]; then
        mem_g_input=1
        bw_mbps_input=1000
        rtt_ms_input=150
        print_info "自动模式使用默认参数: 内存1GiB, 带宽1000Mbps, RTT 150ms"
    else
        print_input "内存大小 (GiB) [默认 1]: "
        read -r mem_g_input
        print_input "带宽 (Mbps) [默认 1000]: "
        read -r bw_mbps_input
        print_input "往返延迟 RTT (ms) [默认 150]: "
        read -r rtt_ms_input
    fi
    
    local MEM_G=${mem_g_input:-1}
    local BW_Mbps=${bw_mbps_input:-1000}
    local RTT_ms=${rtt_ms_input:-150}
    
    # 校验输入
    if ! [[ "$MEM_G" =~ ^[0-9]+([.][0-9]+)?$ ]]; then MEM_G=1; fi
    if ! [[ "$BW_Mbps" =~ ^[0-9]+$ ]]; then BW_Mbps=1000; fi
    if ! [[ "$RTT_ms" =~ ^[0-9]+([.][0-9]+)?$ ]]; then RTT_ms=150; fi
    
    local SYSCTL_TARGET="/etc/sysctl.d/999-net-bbr-fq.conf"
    local KEY_REGEX='^(net\.core\.default_qdisc|net\.core\.rmem_max|net\.core\.wmem_max|net\.core\.rmem_default|net\.core\.wmem_default|net\.ipv4\.tcp_rmem|net\.ipv4\.tcp_wmem|net\.ipv4\.tcp_congestion_control)[[:space:]]*='
    
    # 计算 BDP 和桶化最大值
    local BDP_BYTES=$(awk -v bw="$BW_Mbps" -v rtt="$RTT_ms" 'BEGIN{ printf "%.0f", bw*125*rtt }')
    local MEM_BYTES=$(awk -v g="$MEM_G" 'BEGIN{ printf "%.0f", g*1024*1024*1024 }')
    local TWO_BDP=$(( BDP_BYTES*2 ))
    local RAM3_BYTES=$(awk -v m="$MEM_BYTES" 'BEGIN{ printf "%.0f", m*0.03 }')
    local CAP64=$(( 64*1024*1024 ))
    local MAX_NUM_BYTES=$(awk -v a="$TWO_BDP" -v b="$RAM3_BYTES" -v c="$CAP64" 'BEGIN{ m=a; if(b<m)m=b; if(c<m)m=c; printf "%.0f", m }')
    
    bucket_le_mb() {
        local mb="${1:-0}"
        if   [ "$mb" -ge 64 ]; then echo 64
        elif [ "$mb" -ge 32 ]; then echo 32
        elif [ "$mb" -ge 16 ]; then echo 16
        elif [ "$mb" -ge 8 ]; then echo 8
        elif [ "$mb" -ge 4 ]; then echo 4
        else echo 4
        fi
    }
    local MAX_MB_NUM=$(( MAX_NUM_BYTES/1024/1024 ))
    local MAX_MB=$(bucket_le_mb "$MAX_MB_NUM")
    local MAX_BYTES=$(( MAX_MB*1024*1024 ))
    
    local DEF_R=131072 DEF_W=131072
    if [ "$MAX_MB" -ge 32 ]; then
        DEF_R=262144; DEF_W=524288
    elif [ "$MAX_MB" -ge 8 ]; then
        DEF_R=131072; DEF_W=262144
    else
        DEF_R=131072; DEF_W=131072
    fi
    
    local TCP_RMEM_MIN=4096 TCP_RMEM_DEF=87380 TCP_RMEM_MAX=$MAX_BYTES
    local TCP_WMEM_MIN=4096 TCP_WMEM_DEF=65536 TCP_WMEM_MAX=$MAX_BYTES
    
    # 清理冲突
    print_info "清理旧配置冲突..."
    local f="/etc/sysctl.conf"
    if [ -f "$f" ] && grep -Eq "$KEY_REGEX" "$f"; then
        print_info "注释 /etc/sysctl.conf 中的冲突键"
        awk -v re="$KEY_REGEX" '
            $0 ~ re && $0 !~ /^[[:space:]]*#/ { print "# " $0; next }
            { print $0 }
        ' "$f" > "${f}.tmp.$$"
        install -m 0644 "${f}.tmp.$$" "$f"
        rm -f "${f}.tmp.$$"
    fi
    
    # 删除 /etc/sysctl.d 下含冲突键的旧文件
    if [ -d "/etc/sysctl.d" ]; then
        shopt -s nullglob
        for cf in /etc/sysctl.d/*.conf; do
            [ "$(readlink -f "$cf")" = "$(readlink -f "$SYSCTL_TARGET")" ] && continue
            if grep -Eq "$KEY_REGEX" "$cf"; then
                rm -f -- "$cf"
                print_info "已删除冲突文件：$cf"
            fi
        done
        shopt -u nullglob
    fi
    
    # 只读提示其他目录
    for dir in /usr/local/lib/sysctl.d /usr/lib/sysctl.d /lib/sysctl.d /run/sysctl.d; do
        if [ -d "$dir" ] && grep -RIlEq "$KEY_REGEX" "$dir" 2>/dev/null; then
            print_warning "其他目录存在冲突（仅提示）: $dir"
            grep -RhnE "$KEY_REGEX" "$dir" 2>/dev/null || true
        fi
    done
    
    # 启用 BBR 模块
    if command -v modprobe >/dev/null 2>&1; then
        modprobe tcp_bbr 2>/dev/null || true
    fi
    
    # 写入新配置
    local tmpf="$(mktemp)"
    cat >"$tmpf" <<EOF
# Auto-generated by secure_tunnel (TCP tuning)
# Inputs: MEM_G=${MEM_G}GiB, BW=${BW_Mbps}Mbps, RTT=${RTT_ms}ms
# BDP: ${BDP_BYTES} bytes (~$(awk -v b="$BDP_BYTES" 'BEGIN{ printf "%.2f", b/1024/1024 }') MB)
# Caps: min(2*BDP, 3%RAM, 64MB) -> Bucket ${MAX_MB} MB

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

net.core.rmem_default = ${DEF_R}
net.core.wmem_default = ${DEF_W}
net.core.rmem_max = ${MAX_BYTES}
net.core.wmem_max = ${MAX_BYTES}

net.ipv4.tcp_rmem = ${TCP_RMEM_MIN} ${TCP_RMEM_DEF} ${TCP_RMEM_MAX}
net.ipv4.tcp_wmem = ${TCP_WMEM_MIN} ${TCP_WMEM_DEF} ${TCP_WMEM_MAX}

net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
EOF
    install -m 0644 "$tmpf" "$SYSCTL_TARGET"
    rm -f "$tmpf"
    
    sysctl --system >/dev/null
    
    # 尝试设置 qdisc
    local iface=$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -1)
    if command -v tc >/dev/null 2>&1 && [ -n "${iface:-}" ]; then
        tc qdisc replace dev "$iface" root fq 2>/dev/null || true
    fi
    
    echo ""
    print_success "TCP 优化已完成"
    echo "==== 当前生效值 ===="
    echo "内存: ${MEM_G} GiB, 带宽: ${BW_Mbps} Mbps, RTT: ${RTT_ms} ms"
    echo "桶值: ${MAX_MB} MB"
    sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null && echo -n " 拥塞控制: " && sysctl -n net.ipv4.tcp_congestion_control
    sysctl -n net.core.default_qdisc 2>/dev/null && echo -n " 默认队列: " && sysctl -n net.core.default_qdisc
    sysctl -n net.core.rmem_max 2>/dev/null && echo -n " rmem_max: " && sysctl -n net.core.rmem_max
    sysctl -n net.core.wmem_max 2>/dev/null && echo -n " wmem_max: " && sysctl -n net.core.wmem_max
    sysctl -n net.ipv4.tcp_rmem 2>/dev/null && echo -n " tcp_rmem: " && sysctl -n net.ipv4.tcp_rmem
    sysctl -n net.ipv4.tcp_wmem 2>/dev/null && echo -n " tcp_wmem: " && sysctl -n net.ipv4.tcp_wmem
    if [ -n "${iface:-}" ]; then
        echo "接口 ${iface} 的 qdisc:"
        tc qdisc show dev "$iface" 2>/dev/null || echo "  无法获取"
    fi
    echo "=================="
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
    local ws_uuid=$(grep "^WS_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local reality_uuid=$(grep "^REALITY_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local reality_public_key=$(grep "^REALITY_PUBLIC_KEY=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local reality_short_id=$(grep "^REALITY_SHORT_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    echo "═══════════════════════════════════════════════"
    print_success "🔗 域名: $domain (Cloudflare Tunnel)"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    # VLESS WebSocket (CF Tunnel)
    if [[ -n "$ws_uuid" ]]; then
        print_success "📡 协议: VLESS + WebSocket (通过 Cloudflare Tunnel)"
        print_success "🚪 端口: 443 (TLS)"
        print_success "🔑 UUID: $ws_uuid"
        print_success "🛣️  Path: /$ws_uuid"
        echo ""
        local ws_link="vless://${ws_uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${ws_uuid}&sni=${domain}#VLESS-WS-CF"
        echo "📋 VLESS-WS 链接:"
        echo "$ws_link"
        echo ""
    fi
    
    # VLESS Reality
    if [[ -n "$reality_uuid" ]] && [[ -n "$reality_public_key" ]] && [[ -n "$reality_short_id" ]]; then
        print_success "📡 协议: VLESS + Reality (直连，无需隧道)"
        print_success "🚪 端口: $REALITY_PORT (TCP)"
        print_success "🔑 UUID: $reality_uuid"
        print_success "🔐 PublicKey: $reality_public_key"
        print_success "🆔 ShortId: $reality_short_id"
        print_success "🌐 ServerName: ${domain}, www.microsoft.com (SNI 伪装)"
        echo ""
        local reality_link="vless://${reality_uuid}@${domain}:${REALITY_PORT}?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&pbk=${reality_public_key}&sid=${reality_short_id}&sni=${domain}&fp=chrome#VLESS-Reality"
        echo "📋 VLESS-Reality 链接:"
        echo "$reality_link"
        echo ""
        print_warning "⚠️  重要提示：Reality 端口 $REALITY_PORT 需要防火墙放行"
        echo "  运行以下命令开放端口:"
        echo "  ufw allow $REALITY_PORT/tcp   (如果使用 ufw)"
        echo "  iptables -I INPUT -p tcp --dport $REALITY_PORT -j ACCEPT"
        echo ""
    fi
    
    print_info "🧪 服务状态:"
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
    echo "  - 复制上面的 WS 链接到支持 VLESS+WS+TLS 的客户端"
    echo "  - 复制 Reality 链接到支持 VLESS+Reality 的客户端 (如 Xray, v2rayN, Nekoray 等)"
    echo "  - 首次连接 Reality 可能需要等待几秒，确保服务器时间同步"
    echo "  - 查看服务状态: sudo ./secure_tunnel.sh status"
    echo ""
    print_info "🔧 管理命令:"
    echo "  状态检查: sudo ./secure_tunnel.sh status"
    echo "  查看配置: sudo ./secure_tunnel.sh config"
    echo "  修改配置: sudo ./secure_tunnel.sh modify"
    echo "  TCP 优化: sudo ./secure_tunnel.sh tcp"
    echo "  重启服务: systemctl restart secure-tunnel-argo.service"
    echo "  查看日志: journalctl -u secure-tunnel-xray.service -f"
}

# ----------------------------
# 修改配置（含 WS 和 Reality）
# ----------------------------
modify_vless_config() {
    print_info "修改 VLESS 配置"
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件，请先安装"
        return 1
    fi
    
    echo ""
    print_input "请选择要修改的内容:"
    echo "  1) 修改 WebSocket 配置 (UUID/路径)"
    echo "  2) 修改 Reality 配置 (UUID/密钥对)"
    echo "  3) 同时修改 WebSocket 和 Reality"
    echo "  0) 返回"
    read -r modify_choice
    
    case "$modify_choice" in
        1) modify_ws_config ;;
        2) modify_reality_config ;;
        3) modify_ws_config; modify_reality_config ;;
        0) return 0 ;;
        *) print_error "无效选项"; return 1 ;;
    esac
}

modify_ws_config() {
    print_info "修改 WebSocket 配置"
    local current_uuid=$(grep "^WS_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local current_path=""
    if [[ -f "$CONFIG_DIR/xray.json" ]]; then
        current_path=$(grep -oP '"path": "\K[^"]+' "$CONFIG_DIR/xray.json" | head -1)
    fi
    local new_uuid=""
    local new_path=""
    
    print_input "请选择: 1) 自动生成新UUID  2) 手动输入UUID  3) 只修改路径: "
    read -r opt
    case "$opt" in
        1) new_uuid=$(cat /proc/sys/kernel/random/uuid) ;;
        2) 
            print_input "请输入新UUID: "
            read -r new_uuid
            if ! [[ "$new_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                print_error "UUID格式错误"; return 1
            fi
            ;;
        3) new_uuid="$current_uuid" ;;
        *) print_error "无效"; return 1 ;;
    esac
    print_input "请输入新的 WebSocket 路径 (回车保留原值): "
    read -r new_path_input
    if [[ -n "$new_path_input" ]]; then
        [[ "$new_path_input" != /* ]] && new_path_input="/$new_path_input"
        new_path="$new_path_input"
    else
        new_path="$current_path"
    fi
    if [[ -z "$new_path" ]]; then
        new_path="/$new_uuid"
    fi
    
    # 更新配置文件中的 UUID
    sed -i "s/^WS_UUID=.*/WS_UUID=$new_uuid/" "$CONFIG_DIR/tunnel.conf"
    
    # 重新生成完整配置（保留 Reality 部分）
    local reality_uuid=$(grep "^REALITY_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local reality_private_key=$(grep "^REALITY_PRIVATE_KEY=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local reality_short_id=$(grep "^REALITY_SHORT_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    create_xray_config "$new_uuid" "$reality_uuid" "$reality_private_key" "$reality_short_id"
    
    # 测试配置
    if ! test_xray_config; then
        print_error "新配置无效，已保留原配置"
        return 1
    fi
    
    systemctl restart secure-tunnel-xray.service
    print_success "WebSocket 配置已更新"
    echo "新 UUID: $new_uuid, 路径: $new_path"
}

modify_reality_config() {
    print_info "修改 Reality 配置"
    local current_uuid=$(grep "^REALITY_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local new_uuid=""
    print_input "请选择: 1) 自动生成新UUID  2) 手动输入UUID: "
    read -r opt
    case "$opt" in
        1) new_uuid=$(cat /proc/sys/kernel/random/uuid) ;;
        2) 
            print_input "请输入新UUID: "
            read -r new_uuid
            if ! [[ "$new_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                print_error "UUID格式错误"; return 1
            fi
            ;;
        *) new_uuid="$current_uuid" ;;
    esac
    print_input "是否重新生成 Reality 密钥对？(y/N): "
    read -r regen_key
    local new_private_key=""
    local new_short_id=""
    local new_public_key=""
    if [[ "$regen_key" == "y" || "$regen_key" == "Y" ]]; then
        local keypair=$(generate_reality_keypair)
        new_private_key=$(echo "$keypair" | cut -d'|' -f1)
        new_public_key=$(echo "$keypair" | cut -d'|' -f2)
        new_short_id=$(openssl rand -hex 8)
        sed -i "s/^REALITY_PRIVATE_KEY=.*/REALITY_PRIVATE_KEY=$new_private_key/" "$CONFIG_DIR/tunnel.conf"
        sed -i "s/^REALITY_PUBLIC_KEY=.*/REALITY_PUBLIC_KEY=$new_public_key/" "$CONFIG_DIR/tunnel.conf"
        sed -i "s/^REALITY_SHORT_ID=.*/REALITY_SHORT_ID=$new_short_id/" "$CONFIG_DIR/tunnel.conf"
    else
        new_private_key=$(grep "^REALITY_PRIVATE_KEY=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
        new_short_id=$(grep "^REALITY_SHORT_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    fi
    # 更新 UUID
    sed -i "s/^REALITY_UUID=.*/REALITY_UUID=$new_uuid/" "$CONFIG_DIR/tunnel.conf"
    
    # 重新生成完整配置
    local ws_uuid=$(grep "^WS_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    create_xray_config "$ws_uuid" "$new_uuid" "$new_private_key" "$new_short_id"
    
    # 测试配置
    if ! test_xray_config; then
        print_error "新配置无效，已保留原配置"
        return 1
    fi
    
    systemctl restart secure-tunnel-xray.service
    print_success "Reality 配置已更新"
    if [[ "$regen_key" == "y" || "$regen_key" == "Y" ]]; then
        echo "新 UUID: $new_uuid"
        echo "新 PublicKey: $new_public_key"
        echo "新 ShortId: $new_short_id"
    else
        echo "新 UUID: $new_uuid"
    fi
}

# ----------------------------
# 显示配置信息
# ----------------------------
show_config() {
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件，可能未安装"
        return 1
    fi
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local ws_uuid=$(grep "^WS_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local reality_uuid=$(grep "^REALITY_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local reality_public_key=$(grep "^REALITY_PUBLIC_KEY=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local reality_short_id=$(grep "^REALITY_SHORT_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    echo ""
    print_success "当前配置:"
    echo "  域名: $domain"
    echo "  WebSocket 端口: $WS_PORT (回源)"
    echo "  Reality 端口: $REALITY_PORT (直连)"
    echo "  WS UUID: $ws_uuid"
    echo "  Reality UUID: $reality_uuid"
    echo "  Reality PublicKey: $reality_public_key"
    echo "  Reality ShortId: $reality_short_id"
    echo ""
    # 生成链接用于快速查看
    local ws_link="vless://${ws_uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${ws_uuid}&sni=${domain}#VLESS-WS"
    local reality_link="vless://${reality_uuid}@${domain}:${REALITY_PORT}?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&pbk=${reality_public_key}&sid=${reality_short_id}&sni=${domain}&fp=chrome#VLESS-Reality"
    print_info "📡 WS 链接:"
    echo "$ws_link"
    echo ""
    print_info "📡 Reality 链接:"
    echo "$reality_link"
    echo ""
}

# ----------------------------
# 服务状态
# ----------------------------
show_status() {
    print_info "服务状态检查..."
    echo ""
    if systemctl is-active --quiet secure-tunnel-xray.service; then
        print_success "Xray 服务: 运行中"
    else
        print_error "Xray 服务: 未运行"
    fi
    echo ""
    if systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "Argo Tunnel 服务: 运行中"
        echo ""
        print_info "隧道信息:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || true
    else
        print_error "Argo Tunnel 服务: 未运行"
    fi
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    print_info "开始安装流程..."
    check_system
    install_components
    collect_user_info
    if ! direct_cloudflare_auth; then
        print_warning "授权可能有问题"
        print_input "是否继续安装？(y/N): "
        read -r continue_install
        if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
            print_error "安装中止"
            return 1
        fi
    fi
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
    print_input "是否立即应用 TCP 网络优化 (BBR+fq)？(y/N): "
    read -r apply_tcp
    if [[ "$apply_tcp" == "y" || "$apply_tcp" == "Y" ]]; then
        apply_tcp_tuning
    fi
    echo ""
    print_success "🎉 安装完成！"
    return 0
}

# ----------------------------
# 卸载
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
    systemctl stop secure-tunnel-argo.service 2>/dev/null || true
    systemctl stop secure-tunnel-xray.service 2>/dev/null || true
    systemctl disable secure-tunnel-argo.service 2>/dev/null || true
    systemctl disable secure-tunnel-xray.service 2>/dev/null || true
    rm -f /etc/systemd/system/secure-tunnel-argo.service
    rm -f /etc/systemd/system/secure-tunnel-xray.service
    rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    print_input "是否删除 Xray 和 cloudflared 二进制文件？(y/N): "
    read -r delete_bin
    if [[ "$delete_bin" == "y" || "$delete_bin" == "Y" ]]; then
        rm -f "$BIN_DIR/xray" "$BIN_DIR/cloudflared"
    fi
    userdel "$SERVICE_USER" 2>/dev/null || true
    groupdel "$SERVICE_GROUP" 2>/dev/null || true
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
# 菜单
# ----------------------------
show_menu() {
    show_title
    echo "请选择操作："
    echo ""
    echo "  1) 安装 Secure Tunnel (VLESS WS + Reality)"
    echo "  2) 卸载 Secure Tunnel"
    echo "  3) 查看服务状态"
    echo "  4) 查看配置信息"
    echo "  5) 修改 VLESS 配置 (WS / Reality)"
    echo "  6) 应用 TCP 网络优化 (BBR+fq)"
    echo "  7) 退出"
    echo ""
    print_input "请输入选项 (1-7): "
    read -r choice
    case "$choice" in
        1) SILENT_MODE=false; if main_install; then print_input "按回车返回菜单..."; read -r; fi ;;
        2) uninstall_all; print_input "按回车返回菜单..."; read -r ;;
        3) show_status; print_input "按回车返回菜单..."; read -r ;;
        4) show_config; print_input "按回车返回菜单..."; read -r ;;
        5) modify_vless_config; print_input "按回车返回菜单..."; read -r ;;
        6) apply_tcp_tuning; print_input "按回车返回菜单..."; read -r ;;
        7) print_info "再见！"; exit 0 ;;
        *) print_error "无效选项"; sleep 1 ;;
    esac
    show_menu
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    case "${1:-}" in
        "install") SILENT_MODE=false; show_title; main_install ;;
        "uninstall") show_title; uninstall_all ;;
        "config") show_title; show_config ;;
        "status") show_title; show_status ;;
        "modify") show_title; modify_vless_config ;;
        "tcp") show_title; apply_tcp_tuning ;;
        "-y"|"--silent") SILENT_MODE=true; show_title; main_install ;;
        "menu"|"") show_menu ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo ./secure_tunnel.sh menu          # 显示菜单"
            echo "  sudo ./secure_tunnel.sh install       # 安装"
            echo "  sudo ./secure_tunnel.sh uninstall     # 卸载"
            echo "  sudo ./secure_tunnel.sh status        # 查看状态"
            echo "  sudo ./secure_tunnel.sh config        # 查看配置"
            echo "  sudo ./secure_tunnel.sh modify        # 修改配置"
            echo "  sudo ./secure_tunnel.sh tcp           # TCP优化"
            echo "  sudo ./secure_tunnel.sh -y            # 静默安装"
            exit 1
            ;;
    esac
}

if [[ $EUID -ne 0 ]] && [[ "${1:-}" != "" ]]; then
    print_error "请使用root权限运行此脚本"
    exit 1
fi

main "$@"