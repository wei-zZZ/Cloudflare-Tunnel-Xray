#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本 (Root版)
# 版本: 4.4 - 增强订阅功能
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

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/secure_tunnel"
DATA_DIR="/var/lib/secure_tunnel"
LOG_DIR="/var/log/secure_tunnel"
BIN_DIR="/usr/local/bin"
SERVICE_USER="secure_tunnel"
SERVICE_GROUP="secure_tunnel"

# 用户输入变量
USER_DOMAIN=""
TUNNEL_NAME="secure-tunnel"

# ----------------------------
# 收集用户信息
# ----------------------------
collect_user_info() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 安装脚本                ║"
    echo "║                版本 4.4                      ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    
    # 获取域名
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
    
    # 获取隧道名称
    print_input "请输入隧道名称 [默认: secure-tunnel]:"
    read -r TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"secure-tunnel"}
    
    # 显示汇总信息
    echo ""
    print_info "配置摘要:"
    echo "  ┌─────────────────────────────────────┐"
    echo "  │   域名: $USER_DOMAIN"
    echo "  │   隧道名称: $TUNNEL_NAME"
    echo "  └─────────────────────────────────────┘"
    echo ""
    
    print_input "确认以上配置是否正确？(y/N):"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_error "安装已取消"
        exit 0
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
    
    # 检查必要工具
    local required_tools=("curl" "unzip" "wget")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "安装 $tool..."
            apt-get update && apt-get install -y "$tool" || {
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
    
    # 下载并安装 Xray
    print_info "下载 Xray..."
    wget -q --show-progress -O /tmp/xray.zip "$xray_url"
    unzip -q -d /tmp /tmp/xray.zip
    find /tmp -name "xray" -type f -exec mv {} "$BIN_DIR/" \;
    chmod +x "$BIN_DIR/xray"
    
    # 下载并安装 cloudflared
    print_info "下载 cloudflared..."
    wget -q --show-progress -O "$BIN_DIR/cloudflared" "$cf_url"
    chmod +x "$BIN_DIR/cloudflared"
    
    # 清理临时文件
    rm -f /tmp/xray.zip
    
    print_success "组件安装完成"
}

# ----------------------------
# 直接服务器授权（无浏览器）
# ----------------------------
direct_cloudflare_auth() {
    print_warning "═══════════════════════════════════════════════"
    print_warning "    服务器直接授权模式"
    print_warning "═══════════════════════════════════════════════"
    echo ""
    
    # 清理旧配置
    print_info "清理旧配置..."
    rm -rf /root/.cloudflared
    mkdir -p /root/.cloudflared
    
    print_info "开始 Cloudflare 授权..."
    echo ""
    
    # 方法：直接在服务器运行授权命令
    print_info "正在启动 Cloudflare 授权..."
    print_info "这将在终端中显示一个链接，请复制到浏览器打开"
    echo ""
    print_warning "请准备好浏览器访问以下链接："
    echo ""
    
    # 运行 cloudflared tunnel login，它会自动生成链接
    "$BIN_DIR/cloudflared" tunnel login
    
    echo ""
    print_input "请在浏览器完成授权后，按回车键继续..."
    read -r
    
    # 检查授权是否成功
    check_auth_status
}

# ----------------------------
# 检查授权状态
# ----------------------------
check_auth_status() {
    print_info "检查授权状态..."
    
    local max_checks=5
    local check_count=0
    
    while [[ $check_count -lt $max_checks ]]; do
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 授权成功！证书已生成"
            print_info "证书位置: /root/.cloudflared/cert.pem"
            print_info "证书大小: $(ls -lh "/root/.cloudflared/cert.pem" | awk '{print $5}')"
            return 0
        fi
        
        print_info "等待证书生成... (${check_count}/5)"
        sleep 3
        ((check_count++))
    done
    
    # 如果还没找到证书，尝试其他位置
    print_warning "未找到标准位置的证书，尝试其他位置..."
    
    local found_cert=""
    for cert_path in "/root/.cloudflared/cert.pem" "/root/.cloudflare-warp/cert.pem" "/etc/cloudflared/cert.pem"; do
        if [[ -f "$cert_path" ]]; then
            found_cert="$cert_path"
            break
        fi
    done
    
    if [[ -n "$found_cert" ]]; then
        # 复制到标准位置
        cp "$found_cert" "/root/.cloudflared/cert.pem"
        print_success "✅ 找到证书并复制到标准位置"
        print_info "证书位置: /root/.cloudflared/cert.pem"
        return 0
    fi
    
    print_error "❌ 未检测到授权证书！"
    print_error "可能的原因："
    print_error "1. 授权未完成"
    print_error "2. 使用了错误的 Cloudflare 账户"
    print_error "3. 未选择正确的域名"
    echo ""
    
    # 提供手动选项
    print_input "按回车键重试授权，或按 Ctrl+C 退出"
    read -r
    
    # 杀掉可能还在运行的 cloudflared 进程
    pkill -f "cloudflared tunnel login" 2>/dev/null || true
    
    # 重新尝试
    direct_cloudflare_auth
}

# ----------------------------
# 创建隧道和配置
# ----------------------------
setup_tunnel() {
    print_info "设置 Cloudflare Tunnel..."
    
    # 验证证书是否存在
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "错误：未找到证书文件 /root/.cloudflared/cert.pem"
        print_error "请确保已完成 Cloudflare 授权"
        exit 1
    fi
    
    # 设置证书环境变量
    export TUNNEL_ORIGIN_CERT="/root/.cloudflared/cert.pem"
    
    # 检查是否已存在同名隧道
    print_info "检查是否已存在同名隧道..."
    local existing_tunnel
    existing_tunnel=$("$BIN_DIR/cloudflared" tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -n "$existing_tunnel" ]]; then
        print_warning "发现同名隧道，使用现有隧道: $existing_tunnel"
        local tunnel_id="$existing_tunnel"
    else
        # 创建新隧道
        print_info "创建隧道: $TUNNEL_NAME"
        "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"
        
        # 获取隧道ID
        local tunnel_id
        tunnel_id=$("$BIN_DIR/cloudflared" tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
        
        if [[ -z "$tunnel_id" ]]; then
            print_error "无法获取隧道ID"
            print_info "尝试直接列出所有隧道："
            "$BIN_DIR/cloudflared" tunnel list
            exit 1
        fi
    fi
    
    # 查找JSON文件（可能以隧道ID命名）
    local json_file="/root/.cloudflared/${tunnel_id}.json"
    if [[ ! -f "$json_file" ]]; then
        # 尝试查找以隧道名命名的文件
        json_file="/root/.cloudflared/${TUNNEL_NAME}.json"
        if [[ ! -f "$json_file" ]]; then
            # 查找所有JSON文件
            json_file=$(find /root/.cloudflared -name "*.json" -type f | head -1)
        fi
    fi
    
    # 绑定域名
    print_info "绑定域名: $USER_DOMAIN"
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN"
    
    # 保存隧道配置（使用安全的方式）
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
# Cloudflare Tunnel 配置
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
CERT_PATH=/root/.cloudflared/cert.pem
CREATED_DATE=$(date +"%Y-%m-%d")
EOF
    
    # 如果找到了JSON文件，记录路径
    if [[ -f "$json_file" ]]; then
        echo "TUNNEL_JSON=$json_file" >> "$CONFIG_DIR/tunnel.conf"
        print_info "隧道凭证文件: $json_file"
    fi
    
    print_success "✅ 隧道设置完成 (ID: ${tunnel_id})"
}

# ----------------------------
# 安全读取配置文件
# ----------------------------
read_config() {
    local config_file="$CONFIG_DIR/tunnel.conf"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "配置文件不存在: $config_file"
        exit 1
    fi
    
    # 使用while循环读取，避免source命令解析问题
    while IFS='=' read -r key value; do
        # 跳过注释行和空行
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # 去除空格
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        # 设置变量
        declare -g "$key"="$value"
    done < "$config_file"
}

# ----------------------------
# 配置 Xray
# ----------------------------
configure_xray() {
    print_info "配置 Xray..."
    
    # 安全读取配置文件
    read_config
    
    if [[ -z "$TUNNEL_ID" ]]; then
        print_error "无法读取隧道ID"
        exit 1
    fi
    
    # 生成UUID和端口
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=10000  # 固定端口，便于管理
    
    # 追加到配置文件（使用安全的方式）
    echo "" >> "$CONFIG_DIR/tunnel.conf"
    echo "# Xray 配置" >> "$CONFIG_DIR/tunnel.conf"
    echo "UUID=$uuid" >> "$CONFIG_DIR/tunnel.conf"
    echo "PORT=$port" >> "$CONFIG_DIR/tunnel.conf"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # 生成Xray配置文件（适配 Xray-core 25.x 版本）
    cat > "$CONFIG_DIR/xray.json" << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $port,
            "listen": "127.0.0.1",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "level": 0
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {
                    "path": "/$uuid"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        }
    ]
}
EOF
    
    # 创建隧道配置文件
    # 使用正确的JSON文件路径
    local json_path="/root/.cloudflared/${TUNNEL_ID}.json"
    if [[ ! -f "$json_path" ]]; then
        json_path="/root/.cloudflared/${TUNNEL_NAME}.json"
        if [[ ! -f "$json_path" ]]; then
            # 最后尝试查找任意JSON文件
            json_path=$(find /root/.cloudflared -name "*.json" -type f | head -1)
        fi
    fi
    
    if [[ ! -f "$json_path" ]]; then
        print_error "找不到隧道凭证JSON文件"
        print_info "请在 /root/.cloudflared/ 目录下查找JSON文件"
        exit 1
    fi
    
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $json_path
originCert: /root/.cloudflared/cert.pem

ingress:
  - hostname: $DOMAIN
    service: http://localhost:$port
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      tlsTimeout: 30s
      tcpKeepAlive: 30s
      noHappyEyeballs: false
      keepAliveConnections: 100
      keepAliveTimeout: 90s
      httpHostHeader: $DOMAIN
  - service: http_status:404
EOF
    
    print_success "Xray 配置完成"
}

# ----------------------------
# 配置系统服务
# ----------------------------
configure_services() {
    print_info "配置系统服务..."
    
    # 创建专用用户（用于运行服务）
    if ! id -u "$SERVICE_USER" &> /dev/null; then
        useradd -r -s /usr/sbin/nologin "$SERVICE_USER"
    fi
    
    # 转移文件所有权
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # Xray 服务文件
    cat > /etc/systemd/system/secure-tunnel-xray.service << EOF
[Unit]
Description=Secure Tunnel Xray Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$BIN_DIR/xray run -config $CONFIG_DIR/xray.json
Restart=on-failure
RestartSec=3
StandardOutput=append:$LOG_DIR/xray.log
StandardError=append:$LOG_DIR/xray-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Argo Tunnel 服务文件
    cat > /etc/systemd/system/secure-tunnel-argo.service << EOF
[Unit]
Description=Secure Tunnel Argo Service
After=network.target secure-tunnel-xray.service
Wants=network.target

[Service]
Type=simple
User=root
Group=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
Environment="TUNNEL_METRICS=0.0.0.0:8080"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=on-failure
RestartSec=5
StandardOutput=append:$LOG_DIR/argo.log
StandardError=append:$LOG_DIR/argo-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd
    systemctl daemon-reload
    
    print_success "系统服务配置完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    # 启动Xray
    systemctl enable secure-tunnel-xray.service
    if systemctl start secure-tunnel-xray.service; then
        print_success "Xray 服务启动成功"
    else
        print_error "Xray 服务启动失败"
        journalctl -u secure-tunnel-xray.service -n 10 --no-pager
    fi
    
    # 等待Xray启动
    sleep 2
    
    # 启动Argo Tunnel
    systemctl enable secure-tunnel-argo.service
    if systemctl start secure-tunnel-argo.service; then
        print_success "Argo Tunnel 服务启动成功"
    else
        print_error "Argo Tunnel 服务启动失败"
        journalctl -u secure-tunnel-argo.service -n 10 --no-pager
    fi
    
    # 等待服务稳定
    sleep 3
}

# ----------------------------
# 显示连接信息（包含订阅）
# ----------------------------
show_connection_info() {
    print_info "═══════════════════════════════════════════════"
    print_info "           安装完成！连接信息"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 安全读取配置
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件"
        return
    fi
    
    # 直接读取关键变量
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local uuid=$(grep "^UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    if [[ -z "$domain" ]] || [[ -z "$uuid" ]]; then
        print_error "无法读取配置信息"
        return
    fi
    
    print_success "🔗 域名: $domain"
    print_success "🔑 UUID: $uuid"
    print_success "🚪 端口: 443 (TLS) / 80 (非TLS)"
    print_success "🛣️  路径: /$uuid"
    echo ""
    
    print_info "📋 VLESS 连接配置:"
    echo ""
    echo "vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=/${uuid}#安全隧道"
    echo ""
    
    print_info "⚙️  Clash 配置:"
    echo ""
    echo "- name: 安全隧道"
    echo "  type: vless"
    echo "  server: ${domain}"
    echo "  port: 443"
    echo "  uuid: ${uuid}"
    echo "  network: ws"
    echo "  tls: true"
    echo "  udp: true"
    echo "  ws-opts:"
    echo "    path: /${uuid}"
    echo "    headers:"
    echo "      Host: ${domain}"
    echo ""
    
    # 生成订阅信息
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           订阅链接"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 生成订阅目录
    local SUB_DIR="$CONFIG_DIR/subscription"
    mkdir -p "$SUB_DIR"
    
    # 生成VLESS链接
    local vless_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${uuid}&sni=${domain}#安全隧道"
    local vless_non_tls="vless://${uuid}@${domain}:80?encryption=none&security=none&type=ws&host=${domain}&path=%2F${uuid}#安全隧道-非TLS"
    
    # 保存到文件
    echo "$vless_tls" > "$SUB_DIR/vless_tls.txt"
    echo "$vless_non_tls" > "$SUB_DIR/vless_non_tls.txt"
    
    # 生成base64订阅
    local combined_links="${vless_tls}\n${vless_non_tls}"
    local base64_sub=$(echo -e "$combined_links" | base64 -w 0)
    echo "$base64_sub" > "$SUB_DIR/base64.txt"
    
    print_success "📡 订阅链接已生成:"
    echo ""
    echo "通用订阅 (Base64, 用于V2rayN/NekoBox):"
    echo "$base64_sub"
    echo ""
    echo "原始链接:"
    echo "TLS: $vless_tls"
    echo "非TLS: $vless_non_tls"
    echo ""
    
    # 获取服务器IP
    local server_ip=$(hostname -I | awk '{print $1}' | head -1)
    
    print_info "🌐 快速使用方法:"
    echo ""
    if [[ -n "$server_ip" ]]; then
        echo "1. 启动订阅服务器:"
        echo "   sudo ./secure_tunnel.sh start-server"
        echo ""
        echo "2. 然后访问:"
        echo "   http://${server_ip}:8080/sub"
        echo "  或直接使用上面的base64订阅链接"
    else
        echo "1. 复制上面的base64订阅链接"
        echo "2. 在V2rayN/NekoBox客户端中导入"
    fi
    echo ""
    
    print_info "🔧 服务管理命令:"
    echo "  启动: systemctl start secure-tunnel-{xray,argo}"
    echo "  停止: systemctl stop secure-tunnel-{xray,argo}"
    echo "  状态: systemctl status secure-tunnel-{xray,argo}"
    echo "  日志: journalctl -u secure-tunnel-argo.service -f"
    echo ""
    
    print_info "📁 配置文件位置:"
    echo "  Xray配置: $CONFIG_DIR/xray.json"
    echo "  隧道配置: $CONFIG_DIR/config.yaml"
    echo "  连接信息: $CONFIG_DIR/tunnel.conf"
    echo "  订阅目录: $CONFIG_DIR/subscription/"
    echo ""
    
    print_warning "⚠️ 重要提示:"
    print_warning "1. 请等待几分钟让DNS生效"
    print_warning "2. 在Cloudflare DNS中确认 $domain 已正确解析"
    print_warning "3. 首次连接可能需要等待证书签发"
}

# ----------------------------
# 启动本地订阅服务器
# ----------------------------
start_subscription_server() {
    print_info "启动本地订阅服务器..."
    
    # 首先停止可能已经在运行的服务
    stop_subscription_server
    
    local SUB_DIR="$CONFIG_DIR/subscription"
    
    # 创建订阅目录
    if [[ ! -d "$SUB_DIR" ]]; then
        print_info "创建订阅目录..."
        mkdir -p "$SUB_DIR"
    fi
    
    # 确保有配置文件
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "错误：未找到配置文件 $CONFIG_DIR/tunnel.conf"
        print_error "请先运行安装命令：sudo ./secure_tunnel.sh install"
        return 1
    fi
    
    # 读取配置信息
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local uuid=$(grep "^UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    if [[ -z "$domain" ]] || [[ -z "$uuid" ]]; then
        print_error "无法读取域名或UUID，请检查配置文件"
        return 1
    fi
    
    print_success "读取配置成功"
    print_info "域名: $domain"
    print_info "UUID: $uuid"
    
    # 生成订阅内容
    local vless_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${uuid}&sni=${domain}#安全隧道"
    local vless_non_tls="vless://${uuid}@${domain}:80?encryption=none&security=none&type=ws&host=${domain}&path=%2F${uuid}#安全隧道-非TLS"
    
    # 生成base64订阅
    local combined_links="${vless_tls}\n${vless_non_tls}"
    local base64_sub=$(echo -e "$combined_links" | base64 -w 0)
    
    # 保存到文件
    echo "$vless_tls" > "$SUB_DIR/vless_tls.txt"
    echo "$vless_non_tls" > "$SUB_DIR/vless_non_tls.txt"
    echo "$base64_sub" > "$SUB_DIR/base64.txt"
    
    print_success "✅ 订阅文件已生成"
    
    # 检查Python3是否可用
    if ! command -v python3 &> /dev/null; then
        print_info "安装Python3..."
        apt-get update && apt-get install -y python3 python3-pip
    fi
    
    # 检查端口是否被占用
    if ss -tulpn | grep ":8080" >/dev/null; then
        print_warning "端口 8080 已被占用，正在释放..."
        pkill -f "server.py" 2>/dev/null || true
        sleep 2
    fi
    
    # 创建更稳定的HTTP服务器脚本
    cat > "$SUB_DIR/server.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import os
import sys
import time
from urllib.parse import urlparse

PORT = 8080
SUB_DIR = os.path.dirname(os.path.abspath(__file__))

class SubscriptionHandler(http.server.SimpleHTTPRequestHandler):
    
    def do_GET(self):
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 访问路径: {path}")
        
        if path == '/':
            # 显示欢迎页面
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <title>订阅服务器</title>
                <style>
                    body { font-family: Arial, sans-serif; margin: 40px; }
                    .container { max-width: 800px; margin: 0 auto; }
                    h1 { color: #333; }
                    .link { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 5px; }
                    .btn { display: inline-block; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; }
                    .btn:hover { background: #0056b3; }
                </style>
            </head>
            <body>
                <div class="container">
                    <h1>📡 订阅服务器</h1>
                    <p>请选择您需要的订阅格式：</p>
                    
                    <div class="link">
                        <h3>📋 通用订阅 (Base64)</h3>
                        <p>适用于 V2rayN/NekoBox 等客户端</p>
                        <a class="btn" href="/sub">获取订阅链接</a>
                        <a class="btn" href="/base64.txt" download>下载文件</a>
                    </div>
                    
                    <div class="link">
                        <h3>🔗 VLESS 链接</h3>
                        <p>单个VLESS配置链接</p>
                        <a class="btn" href="/vless">获取VLESS链接</a>
                        <a class="btn" href="/vless_tls.txt" download>下载文件</a>
                    </div>
                    
                    <div class="link">
                        <h3>📁 文件列表</h3>
                        <p>查看所有可用文件</p>
                        <a class="btn" href="/list">查看文件</a>
                    </div>
                </div>
            </body>
            </html>
            """
            self.wfile.write(html.encode('utf-8'))
            
        elif path == '/sub':
            # 通用订阅
            base64_file = os.path.join(SUB_DIR, 'base64.txt')
            if os.path.exists(base64_file):
                with open(base64_file, 'r') as f:
                    encoded = f.read().strip()
                
                self.send_response(200)
                self.send_header('Content-type', 'text/plain; charset=utf-8')
                self.send_header('Content-Disposition', 'attachment; filename="subscription.txt"')
                self.send_header('Subscription-Userinfo', 'upload=0; download=0; total=10737418240000000; expire=2546246231')
                self.end_headers()
                self.wfile.write(encoded.encode('utf-8'))
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 发送订阅内容，长度: {len(encoded)}")
            else:
                self.send_error(404, "File not found: base64.txt")
                
        elif path == '/vless':
            # VLESS链接
            vless_file = os.path.join(SUB_DIR, 'vless_tls.txt')
            if os.path.exists(vless_file):
                with open(vless_file, 'r') as f:
                    content = f.read().strip()
                
                self.send_response(200)
                self.send_header('Content-type', 'text/plain; charset=utf-8')
                self.send_header('Content-Disposition', 'attachment; filename="vless.txt"')
                self.end_headers()
                self.wfile.write(content.encode('utf-8'))
            else:
                self.send_error(404, "File not found: vless_tls.txt")
                
        elif path == '/list':
            # 文件列表
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            
            files = os.listdir(SUB_DIR)
            html = f"<h1>文件列表</h1><ul>"
            for file in files:
                if os.path.isfile(os.path.join(SUB_DIR, file)):
                    html += f'<li><a href="/{file}">{file}</a></li>'
            html += "</ul>"
            self.wfile.write(html.encode('utf-8'))
            
        else:
            # 静态文件服务
            file_path = os.path.join(SUB_DIR, path.lstrip('/'))
            if os.path.exists(file_path) and os.path.isfile(file_path):
                self.directory = SUB_DIR
                super().do_GET()
            else:
                self.send_error(404, "File not found")

    def log_message(self, format, *args):
        # 禁用默认日志
        pass

if __name__ == '__main__':
    # 设置工作目录
    os.chdir(SUB_DIR)
    
    try:
        with socketserver.TCPServer(("", PORT), SubscriptionHandler) as httpd:
            print(f"=" * 50)
            print(f"订阅服务器已启动!")
            print(f"=" * 50)
            print(f"服务器地址: http://0.0.0.0:{PORT}")
            print(f"可用链接:")
            print(f"  1. 首页: http://0.0.0.0:{PORT}/")
            print(f"  2. 通用订阅: http://0.0.0.0:{PORT}/sub")
            print(f"  3. VLESS链接: http://0.0.0.0:{PORT}/vless")
            print(f"  4. 文件列表: http://0.0.0.0:{PORT}/list")
            print(f"=" * 50)
            print("按 Ctrl+C 停止服务器")
            print(f"=" * 50)
            
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n服务器已停止")
    except Exception as e:
        print(f"服务器错误: {e}")
        sys.exit(1)
PYTHON_EOF
    
    # 设置权限
    chmod +x "$SUB_DIR/server.py"
    
    # 确保在正确目录启动
    cd "$SUB_DIR"
    
    # 启动服务器（后台运行）
    print_info "启动订阅服务器..."
    nohup python3 server.py > "$SUB_DIR/server.log" 2>&1 &
    
    local server_pid=$!
    echo "$server_pid" > "$SUB_DIR/server.pid"
    
    sleep 3
    
    # 检查服务器是否启动成功
    if kill -0 "$server_pid" 2>/dev/null; then
        # 获取服务器IP
        local server_ip=$(hostname -I | awk '{print $1}' | head -1)
        if [ -z "$server_ip" ]; then
            server_ip="127.0.0.1"
        fi
        
        print_success "✅ 订阅服务器启动成功！"
        echo ""
        print_info "🌐 访问地址:"
        echo "  http://${server_ip}:8080"
        echo ""
        print_info "📡 重要链接:"
        echo "  通用订阅: http://${server_ip}:8080/sub"
        echo "  VLESS链接: http://${server_ip}:8080/vless"
        echo "  文件列表: http://${server_ip}:8080/list"
        echo ""
        print_info "📋 使用方法:"
        echo "  1. 在客户端中导入: http://${server_ip}:8080/sub"
        echo "  2. 或在浏览器中访问上面的链接获取配置"
        echo ""
        print_info "📊 服务器状态:"
        echo "  PID: $server_pid"
        echo "  日志: $SUB_DIR/server.log"
        echo "  配置文件: $SUB_DIR/"
        
        # 测试服务器是否响应
        print_info "测试服务器响应..."
        if curl -s "http://${server_ip}:8080/" > /dev/null 2>&1; then
            print_success "✅ 服务器响应正常"
        else
            print_warning "⚠️ 服务器启动但无法访问，请检查防火墙"
            echo "  检查命令: sudo ufw allow 8080/tcp"
        fi
    else
        print_error "❌ 服务器启动失败"
        print_info "查看错误日志:"
        tail -20 "$SUB_DIR/server.log"
        return 1
    fi
}

# ----------------------------
# 停止本地订阅服务器
# ----------------------------
stop_subscription_server() {
    print_info "停止订阅服务器..."
    
    local SUB_DIR="$CONFIG_DIR/subscription"
    local pid_file="$SUB_DIR/server.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        print_info "找到服务器进程 PID: $pid"
        
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            sleep 2
            
            if kill -0 "$pid" 2>/dev/null; then
                print_warning "进程未正常退出，强制终止..."
                kill -9 "$pid" 2>/dev/null || true
            fi
            
            print_success "✅ 订阅服务器已停止"
        else
            print_warning "⚠️ 进程 $pid 已不存在"
        fi
        
        rm -f "$pid_file"
    else
        print_info "未找到PID文件，尝试查找并停止相关进程..."
    fi
    
    # 清理所有相关的Python进程
    local pids=$(pgrep -f "server.py" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        print_info "清理残留进程..."
        for pid in $pids; do
            kill "$pid" 2>/dev/null || true
        done
        sleep 1
        pkill -f "server.py" 2>/dev/null && print_info "清理完成"
    fi
    
    # 检查端口是否释放
    if ss -tulpn | grep ":8080" >/dev/null; then
        print_warning "端口 8080 仍被占用"
    else
        print_success "端口 8080 已释放"
    fi
}
# ----------------------------
# 调试订阅服务器
# ----------------------------
debug_subscription() {
    print_info "═══════════════════════════════════════════════"
    print_info "           调试订阅服务器"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 检查安装状态
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未安装，请先运行: sudo ./secure_tunnel.sh install"
        return 1
    fi
    
    # 读取配置
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local uuid=$(grep "^UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    print_info "当前配置:"
    echo "  域名: ${domain:-未设置}"
    echo "  UUID: ${uuid:-未设置}"
    echo ""
    
    # 检查订阅目录
    local SUB_DIR="$CONFIG_DIR/subscription"
    print_info "订阅目录状态: $SUB_DIR"
    if [[ -d "$SUB_DIR" ]]; then
        ls -la "$SUB_DIR/"
        echo ""
        
        # 检查订阅文件
        if [[ -f "$SUB_DIR/base64.txt" ]]; then
            print_success "✅ 找到订阅文件"
            echo "文件大小: $(wc -c < "$SUB_DIR/base64.txt") bytes"
            echo "前100字符: $(head -c 100 "$SUB_DIR/base64.txt")..."
        else
            print_error "❌ 未找到订阅文件"
        fi
    else
        print_error "❌ 订阅目录不存在"
    fi
    
    echo ""
    
    # 检查服务器进程
    local pid_file="$SUB_DIR/server.pid"
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        print_info "服务器进程: PID $pid"
        
        if kill -0 "$pid" 2>/dev/null; then
            print_success "✅ 服务器正在运行"
            
            # 检查端口
            if ss -tulpn | grep ":8080" | grep "$pid" >/dev/null; then
                print_success "✅ 端口 8080 被正确占用"
            else
                print_error "❌ 端口 8080 未被占用"
            fi
            
            # 测试访问
            local server_ip=$(hostname -I | awk '{print $1}' | head -1)
            if [[ -n "$server_ip" ]]; then
                print_info "测试访问 http://${server_ip}:8080/ ..."
                if curl -s -o /dev/null -w "%{http_code}" "http://${server_ip}:8080/" | grep -q "200"; then
                    print_success "✅ 服务器可访问 (HTTP 200)"
                else
                    print_error "❌ 服务器无法访问"
                fi
            fi
        else
            print_error "❌ 服务器进程不存在"
        fi
    else
        print_info "服务器未运行"
        echo "启动命令: sudo ./secure_tunnel.sh start-server"
    fi
    
    echo ""
    print_info "防火墙状态:"
    if command -v ufw &> /dev/null; then
        ufw status | grep "8080" || echo "  端口8080未在防火墙规则中"
    else
        echo "  UFW未安装"
    fi
    
    echo ""
    print_info "网络连接测试:"
    netstat -tlnp | grep ":8080" || echo "  无8080端口监听"
    
    echo ""
    print_info "日志文件:"
    if [[ -f "$SUB_DIR/server.log" ]]; then
        echo "最后10行日志:"
        tail -10 "$SUB_DIR/server.log"
    else
        echo "  无日志文件"
    fi
}

# ----------------------------
# 显示订阅信息
# ----------------------------
show_subscription() {
    print_info "═══════════════════════════════════════════════"
    print_info "           订阅链接信息"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 检查是否已安装
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件，请先安装"
        return
    fi
    
    # 读取配置
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local uuid=$(grep "^UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    if [[ -z "$domain" ]] || [[ -z "$uuid" ]]; then
        print_error "无法读取配置信息"
        return
    fi
    
    # 生成链接
    local vless_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${uuid}&sni=${domain}#安全隧道"
    local vless_non_tls="vless://${uuid}@${domain}:80?encryption=none&security=none&type=ws&host=${domain}&path=%2F${uuid}#安全隧道-非TLS"
    local base64_sub=$(echo -e "${vless_tls}\n${vless_non_tls}" | base64 -w 0)
    
    print_success "📡 订阅链接:"
    echo ""
    echo "通用订阅 (Base64):"
    echo "$base64_sub"
    echo ""
    echo "VLESS TLS 链接:"
    echo "$vless_tls"
    echo ""
    echo "VLESS 非TLS 链接:"
    echo "$vless_non_tls"
    echo ""
    
    # 检查订阅服务器状态
    local SUB_DIR="$CONFIG_DIR/subscription"
    local pid_file="$SUB_DIR/server.pid"
    local server_ip=$(hostname -I | awk '{print $1}' | head -1)
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            print_success "✅ 订阅服务器正在运行"
            echo ""
            print_info "访问地址:"
            echo "  订阅链接: http://${server_ip}:8080/sub"
            echo "  VLESS链接: http://${server_ip}:8080/vless"
        else
            print_info "订阅服务器未运行"
            echo "  启动命令: sudo ./secure_tunnel.sh start-server"
        fi
    else
        print_info "订阅服务器未运行"
        echo "  启动命令: sudo ./secure_tunnel.sh start-server"
    fi
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    print_info "开始安装流程..."
    
    # 收集用户信息
    collect_user_info
    
    # 执行安装步骤
    check_system
    install_components
    direct_cloudflare_auth
    setup_tunnel
    configure_xray
    configure_services
    start_services
    show_connection_info
    
    echo ""
    print_success "🎉 安装全部完成！"
    echo ""
    print_info "要启动订阅服务器，请运行:"
    echo "  sudo ./secure_tunnel.sh start-server"
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 一键安装脚本            ║"
    echo "║                版本4.4 (增强订阅功能)        ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    
    case "${1:-}" in
    "install")
        main_install
        ;;
    "start-server")
        start_subscription_server
        ;;
    "stop-server")
        stop_subscription_server
        ;;
    "subscription")
        show_subscription
        ;;
    "debug-sub")
        debug_subscription
        ;;
    *)
        echo "使用方法:"
        echo "  sudo ./secure_tunnel.sh install         # 安装"
        echo "  sudo ./secure_tunnel.sh start-server    # 启动订阅服务器"
        echo "  sudo ./secure_tunnel.sh stop-server     # 停止订阅服务器"
        echo "  sudo ./secure_tunnel.sh subscription    # 显示订阅链接"
        echo "  sudo ./secure_tunnel.sh debug-sub       # 调试订阅服务器"
        exit 1
        ;;
    esac
}

# 运行主函数
main "$@"
