#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本
# 版本: 6.3 - 仅支持 VLESS
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
PROTOCOL="vless"          # 固定为 VLESS

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel + Xray 管理脚本        ║"
    echo "║             版本: 6.3 - 支持 VLESS          ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
}

# ----------------------------
# 修复软件源问题
# ----------------------------
fix_apt_sources() {
    print_info "检查软件源配置..."
    
    # 备份原有源
    cp /etc/apt/sources.list /etc/apt/sources.list.backup 2>/dev/null || true
    
    # 检测系统类型
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
    
    # 清除问题源
    rm -f /etc/apt/sources.list.d/*bullseye-backports* 2>/dev/null || true
    
    # 更新软件包列表
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
    echo "  协议: VLESS (仅支持)"
    echo ""
}

# ----------------------------
# 系统检查（修复版）
# ----------------------------
check_system() {
    print_info "检查系统环境..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    # 修复软件源
    fix_apt_sources
    
    # 安装必要工具
    print_info "安装必要工具..."
    
    local tools=("curl" "wget" "unzip" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "正在安装 $tool..."
            
            # 尝试使用apt安装
            if apt-get install -y -qq "$tool" 2>/dev/null; then
                print_success "$tool 安装成功"
            else
                print_warning "apt安装 $tool 失败，尝试其他方法..."
                
                # 尝试手动下载安装
                case "$tool" in
                    "curl")
                        apt-get install -y libcurl4-openssl-dev || true
                        ;;
                    "wget")
                        wget_direct_install || true
                        ;;
                    "unzip")
                        unzip_direct_install || true
                        ;;
                    "jq")
                        install_jq_directly || true
                        ;;
                esac
                
                # 再次检查是否安装成功
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

# 手动安装jq函数
install_jq_directly() {
    print_info "手动下载安装 jq..."
    local arch=$(uname -m)
    local jq_url=""
    
    case "$arch" in
        x86_64|amd64)
            jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64"
            ;;
        aarch64|arm64)
            jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-arm64"
            ;;
    esac
    
    if [ -n "$jq_url" ]; then
        curl -L -o /tmp/jq "$jq_url"
        chmod +x /tmp/jq
        mv /tmp/jq /usr/local/bin/jq
    fi
}

# 手动安装wget函数
wget_direct_install() {
    print_info "手动下载安装 wget..."
    local arch=$(uname -m)
    local wget_url=""
    
    case "$arch" in
        x86_64|amd64)
            wget_url="http://ftp.debian.org/debian/pool/main/w/wget/wget_1.21-1+deb11u1_amd64.deb"
            ;;
        aarch64|arm64)
            wget_url="http://ftp.debian.org/debian/pool/main/w/wget/wget_1.21-1+deb11u1_arm64.deb"
            ;;
    esac
    
    if [ -n "$wget_url" ]; then
        curl -L -o /tmp/wget.deb "$wget_url" && dpkg -i /tmp/wget.deb || apt-get install -f -y
        rm -f /tmp/wget.deb
    fi
}

# 手动安装unzip函数
unzip_direct_install() {
    print_info "手动下载安装 unzip..."
    local arch=$(uname -m)
    local unzip_url=""
    
    case "$arch" in
        x86_64|amd64)
            unzip_url="http://ftp.debian.org/debian/pool/main/u/unzip/unzip_6.0-26_amd64.deb"
            ;;
        aarch64|arm64)
            unzip_url="http://ftp.debian.org/debian/pool/main/u/unzip/unzip_6.0-26_arm64.deb"
            ;;
    esac
    
    if [ -n "$unzip_url" ]; then
        curl -L -o /tmp/unzip.deb "$unzip_url" && dpkg -i /tmp/unzip.deb || apt-get install -f -y
        rm -f /tmp/unzip.deb
    fi
}

# ----------------------------
# 安装组件（改进版）
# ----------------------------
install_components() {
    print_info "安装必要组件..."
    
    local arch
    arch=$(uname -m)
    
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
    
    # 下载安装 Xray
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
    
    # 下载安装 cloudflared
    print_info "下载 cloudflared..."
    if curl -L -o /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        print_success "cloudflared 安装成功"
    else
        print_error "cloudflared 下载失败"
        exit 1
    fi
    
    # 清理临时文件
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
    local check_count=0
    while [[ $check_count -lt 10 ]]; do
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 授权成功！找到证书文件"
            
            # 检查凭证文件
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
    
    # 检查证书文件
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "❌ 未找到证书文件，请先完成授权"
        exit 1
    fi
    
    local json_file=""
    
    # 检查是否有现有凭证文件
    if ls /root/.cloudflared/*.json 1> /dev/null 2>&1; then
        json_file=$(ls -t /root/.cloudflared/*.json | head -1)
        print_success "✅ 使用现有凭证文件: $(basename "$json_file")"
    else
        print_warning "⚠️  未找到凭证文件，正在创建隧道..."
        
        # 删除可能存在的同名隧道
        "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
        sleep 2
        
        # 创建新隧道
        print_info "创建隧道: $TUNNEL_NAME"
        if timeout 60 "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"; then
            sleep 3
            # 查找新生成的凭证文件
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
    
    # 获取隧道ID
    local tunnel_id
    tunnel_id=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -z "$tunnel_id" ]]; then
        print_error "❌ 无法获取隧道ID"
        exit 1
    fi
    
    print_success "✅ 隧道就绪 (名称: ${TUNNEL_NAME}, ID: ${tunnel_id})"
    
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
PROTOCOL=$PROTOCOL
CERT_PATH=/root/.cloudflared/cert.pem
CREDENTIALS_FILE=$json_file
CREATED_DATE=$(date +"%Y-%m-%d")
EOF
    
    print_success "隧道设置完成"
}

# ----------------------------
# 配置 Xray (VLESS)
# ----------------------------
configure_xray() {
    print_info "配置 Xray..."
    
    local vless_uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=10000   # 默认端口改为 10000
    
    # 保存UUID和端口到配置文件
    echo "VLESS_UUID=$vless_uuid" >> "$CONFIG_DIR/tunnel.conf"
    echo "PORT=$port" >> "$CONFIG_DIR/tunnel.conf"
    
    # 创建必要的目录
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    create_vless_config "$vless_uuid" "$port"
    
    print_success "Xray 配置完成"
}

# 创建 VLESS 配置
create_vless_config() {
    local uuid=$1
    local port=$2
    
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
}

# ----------------------------
# 配置系统服务
# ----------------------------
configure_services() {
    print_info "配置系统服务..."
    
    # 创建服务用户
    if ! id -u "$SERVICE_USER" &> /dev/null; then
        useradd -r -s /usr/sbin/nologin "$SERVICE_USER"
    fi
    
    # 设置目录权限
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # 从配置文件读取信息
    local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local json_file=$(grep "^CREDENTIALS_FILE=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local port=$(grep "^PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    # 创建 cloudflared 配置文件
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
    
    # 创建 Xray 服务文件
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
    
    # 创建 Argo Tunnel 服务文件
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
    
    # 重载systemd
    systemctl daemon-reload
    print_success "系统服务配置完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    # 停止可能存在的旧服务
    systemctl stop secure-tunnel-argo.service 2>/dev/null || true
    systemctl stop secure-tunnel-xray.service 2>/dev/null || true
    sleep 2
    
    # 启动Xray服务
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
    
    # 启动Argo Tunnel服务
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
# 修改 VLESS 配置（含端口修改）
# ----------------------------
modify_vless_config() {
    print_info "修改 VLESS 配置"
    
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件，请先安装"
        return 1
    fi
    
    echo ""
    print_input "请选择要修改的内容:"
    echo "  1) 修改 UUID (自动生成新UUID)"
    echo "  2) 修改 WebSocket 路径"
    echo "  3) 同时修改 UUID 和路径"
    echo "  4) 手动输入自定义 UUID"
    echo "  5) 修改监听端口 (当前端口: $(grep "^PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2))"
    echo "  0) 返回"
    echo ""
    read -r modify_choice
    
    local current_uuid=$(grep "^VLESS_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local current_path=""
    local current_port=$(grep "^PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    current_port=${current_port:-10000}
    
    # 从 xray.json 获取当前路径
    if [[ -f "$CONFIG_DIR/xray.json" ]]; then
        current_path=$(grep -oP '"path": "\K[^"]+' "$CONFIG_DIR/xray.json" | head -1)
    fi
    
    local new_uuid=""
    local new_path=""
    local new_port=""
    
    case "$modify_choice" in
        1)
            new_uuid=$(cat /proc/sys/kernel/random/uuid)
            new_path="$current_path"
            print_info "生成新 UUID: $new_uuid"
            ;;
        2)
            print_input "请输入新的 WebSocket 路径 (例如: /mynewpath, 直接回车保留原值):"
            read -r new_path_input
            if [[ -n "$new_path_input" ]]; then
                # 确保路径以 / 开头
                [[ "$new_path_input" != /* ]] && new_path_input="/$new_path_input"
                new_path="$new_path_input"
            else
                new_path="$current_path"
            fi
            new_uuid="$current_uuid"
            ;;
        3)
            new_uuid=$(cat /proc/sys/kernel/random/uuid)
            print_input "请输入新的 WebSocket 路径 (例如: /mynewpath, 直接回车使用默认路径 /$new_uuid):"
            read -r new_path_input
            if [[ -n "$new_path_input" ]]; then
                [[ "$new_path_input" != /* ]] && new_path_input="/$new_path_input"
                new_path="$new_path_input"
            else
                new_path="/$new_uuid"
            fi
            ;;
        4)
            print_input "请输入自定义 UUID (格式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx):"
            read -r custom_uuid
            if [[ "$custom_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                new_uuid="$custom_uuid"
                new_path="$current_path"
            else
                print_error "UUID 格式错误"
                return 1
            fi
            ;;
        5)
            print_input "请输入新的监听端口 (1024-65535, 当前端口: $current_port):"
            read -r port_input
            if [[ -z "$port_input" ]]; then
                print_info "端口未修改"
                return 0
            fi
            if [[ "$port_input" =~ ^[0-9]+$ ]] && [ "$port_input" -ge 1024 ] && [ "$port_input" -le 65535 ]; then
                new_port="$port_input"
            else
                print_error "端口无效，请输入 1024-65535 之间的数字"
                return 1
            fi
            # 单独处理端口修改后，更新配置并重启服务
            # 更新 tunnel.conf 中的 PORT
            sed -i "s/^PORT=.*/PORT=$new_port/" "$CONFIG_DIR/tunnel.conf"
            
            # 更新 xray.json 中的端口
            local current_uuid_for_port=$(grep "^VLESS_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
            local current_path_for_port=$(grep -oP '"path": "\K[^"]+' "$CONFIG_DIR/xray.json" | head -1)
            current_path_for_port=${current_path_for_port:-"/$current_uuid_for_port"}
            
            create_vless_config "$current_uuid_for_port" "$new_port"
            
            # 更新 cloudflared config.yaml 中的 ingress service 端口
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
    service: http://localhost:$new_port
    originRequest:
      noTLSVerify: true
      httpHostHeader: $domain
      connectTimeout: 30s
      tcpKeepAlive: 30s
      noHappyEyeballs: true
  - service: http_status:404
EOF
            
            # 重启服务
            print_info "重启 Xray 和 Argo Tunnel 服务..."
            systemctl restart secure-tunnel-xray.service
            systemctl restart secure-tunnel-argo.service
            sleep 3
            
            if systemctl is-active --quiet secure-tunnel-xray.service && systemctl is-active --quiet secure-tunnel-argo.service; then
                print_success "✅ 服务已重启，端口已改为 $new_port"
            else
                print_warning "⚠️ 服务重启可能有问题，请检查状态"
            fi
            
            # 显示新的连接信息
            local domain_show=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
            local uuid_show=$(grep "^VLESS_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
            local path_show=$(grep -oP '"path": "\K[^"]+' "$CONFIG_DIR/xray.json" | head -1)
            path_show=${path_show:-"/$uuid_show"}
            local vless_link="vless://${uuid_show}@${domain_show}:443?encryption=none&security=tls&type=ws&host=${domain_show}&path=${path_show}&sni=${domain_show}#Cloudflare-Tunnel-VLESS"
            
            echo ""
            print_success "端口修改完成！新的 VLESS 链接:"
            echo "$vless_link"
            echo ""
            return 0
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选项"
            return 1
            ;;
    esac
    
    # 如果执行到这里，说明是 UUID/路径相关的修改（非端口修改）
    # 如果路径为空或未设置，生成默认路径
    if [[ -z "$new_path" ]]; then
        new_path="/$new_uuid"
    fi
    
    # 更新配置文件中的 UUID
    sed -i "s/^VLESS_UUID=.*/VLESS_UUID=$new_uuid/" "$CONFIG_DIR/tunnel.conf"
    
    # 重新生成 xray.json
    local port=$(grep "^PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    port=${port:-10000}
    
    cat > "$CONFIG_DIR/xray.json" << EOF
{
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "vless",
        "settings": {
            "clients": [{"id": "$new_uuid", "level": 0}],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {"path": "$new_path"}
        }
    }],
    "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF
    
    # 重启 Xray 服务
    print_info "重启 Xray 服务..."
    systemctl restart secure-tunnel-xray.service
    sleep 2
    
    if systemctl is-active --quiet secure-tunnel-xray.service; then
        print_success "✅ Xray 服务已重启"
    else
        print_error "❌ Xray 服务重启失败"
        return 1
    fi
    
    echo ""
    print_success "配置已更新！"
    echo "  新 UUID: $new_uuid"
    echo "  新 WebSocket 路径: $new_path"
    echo ""
    
    # 显示新的连接链接
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local vless_link="vless://${new_uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=${new_path}&sni=${domain}#Cloudflare-Tunnel-VLESS"
    
    print_info "📡 新的 VLESS 链接:"
    echo "$vless_link"
    echo ""
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
    local vless_uuid=$(grep "^VLESS_UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    if [[ -z "$domain" ]]; then
        print_error "无法读取配置"
        return
    fi
    
    print_success "🔗 域名: $domain"
    print_success "📡 协议: VLESS"
    print_success "🚪 端口: 443 (TLS)"
    echo ""
    
    if [[ -n "$vless_uuid" ]]; then
        # 从 xray.json 获取路径
        local ws_path=""
        if [[ -f "$CONFIG_DIR/xray.json" ]]; then
            ws_path=$(grep -oP '"path": "\K[^"]+' "$CONFIG_DIR/xray.json" | head -1)
        fi
        ws_path=${ws_path:-"/$vless_uuid"}
        
        print_success "🔑 VLESS UUID: $vless_uuid"
        print_success "🛣️  VLESS 路径: $ws_path"
        echo ""
        
        local vless_tls="vless://${vless_uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=${ws_path}&sni=${domain}#Cloudflare-Tunnel-VLESS"
        
        echo "📋 VLESS 链接:"
        echo "$vless_tls"
    else
        print_error "未找到 VLESS UUID"
    fi
    
    echo ""
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
    echo "  1. 复制上面的链接到客户端"
    echo "  2. 如果连接不上，等待2-3分钟再试"
    echo "  3. 查看服务状态: sudo ./secure_tunnel.sh status"
    echo ""
    
    print_info "🔧 管理命令:"
    echo "  状态检查: sudo ./secure_tunnel.sh status"
    echo "  查看配置: sudo ./secure_tunnel.sh config"
    echo "  修改配置: sudo ./secure_tunnel.sh modify"
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
# 显示配置信息
# ----------------------------
show_config() {
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件，可能未安装"
        return 1
    fi
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local vless_uuid=$(grep "^VLESS_UUID=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local port=$(grep "^PORT=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    port=${port:-10000}
    
    if [[ -z "$domain" ]]; then
        print_error "无法读取配置"
        return 1
    fi
    
    # 获取路径
    local ws_path=""
    if [[ -f "$CONFIG_DIR/xray.json" ]]; then
        ws_path=$(grep -oP '"path": "\K[^"]+' "$CONFIG_DIR/xray.json" | head -1)
    fi
    ws_path=${ws_path:-"/$vless_uuid"}
    
    echo ""
    print_success "当前配置:"
    echo "  域名: $domain"
    echo "  协议: VLESS"
    echo "  监听端口: $port (本地, 仅用于隧道回源)"
    echo "  VLESS UUID: $vless_uuid"
    echo "  VLESS 路径: $ws_path"
    echo ""
    
    local vless_link="vless://${vless_uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=${ws_path}&sni=${domain}#Cloudflare-Tunnel-VLESS"
    
    print_info "📡 VLESS链接:"
    echo "$vless_link"
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
    echo "  5) 修改 VLESS 配置 (UUID/路径/端口)"
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
            modify_vless_config
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
        "modify")
            show_title
            modify_vless_config
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
            echo "  sudo ./secure_tunnel.sh modify        # 修改VLESS配置"
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