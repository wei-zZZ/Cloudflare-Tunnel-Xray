#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本 (最终修复版)
# 版本: 4.5 - 修复下载和端口问题
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

# 订阅服务器端口（使用不常用的端口）
SUBSCRIPTION_PORT="8181"

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
    echo "║    Cloudflare Tunnel 安装脚本 v4.5          ║"
    echo "║        修复下载和端口问题                   ║"
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
# 修复的安装组件函数
# ----------------------------
install_components() {
    print_info "安装必要组件..."
    
    local arch
    arch=$(uname -m)
    
    # 设置下载URL（多个备用源）
    case "$arch" in
        x86_64|amd64)
            # Xray 多个备用源
            local xray_urls=(
                "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
                "https://ghproxy.com/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
                "https://ghproxy.ghproxy.workers.dev/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
                "https://hub.yzuu.cf/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
            )
            # cloudflared 多个备用源
            local cf_urls=(
                "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
                "https://ghproxy.com/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
                "https://ghproxy.ghproxy.workers.dev/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
                "https://hub.yzuu.cf/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            )
            ;;
        aarch64|arm64)
            # Xray 多个备用源
            local xray_urls=(
                "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
                "https://ghproxy.com/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
                "https://ghproxy.ghproxy.workers.dev/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
                "https://hub.yzuu.cf/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
            )
            # cloudflared 多个备用源
            local cf_urls=(
                "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
                "https://ghproxy.com/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
                "https://ghproxy.ghproxy.workers.dev/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
                "https://hub.yzuu.cf/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            )
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    # 增强的下载函数
    download_with_retry() {
        local urls=("$@")
        local output_file="${urls[-1]}"
        unset "urls[${#urls[@]}-1]"
        
        local max_retries=3
        
        for url in "${urls[@]}"; do
            print_info "尝试下载: $(basename "$output_file")"
            print_info "来源: $url"
            
            for ((i=1; i<=max_retries; i++)); do
                if wget --timeout=45 --tries=2 --show-progress -O "$output_file" "$url" 2>&1 | grep -q "100%"; then
                    if [[ -s "$output_file" ]]; then
                        print_success "✅ 下载成功"
                        return 0
                    fi
                fi
                
                if [[ $i -lt $max_retries ]]; then
                    print_warning "下载失败，${i}秒后重试..."
                    sleep $i
                fi
            done
            
            print_warning "当前源失败，尝试下一个..."
        done
        
        print_error "❌ 所有下载源都失败"
        return 1
    }
    
    # 下载并安装 Xray
    print_info "下载 Xray..."
    if download_with_retry "${xray_urls[@]}" "/tmp/xray.zip"; then
        cd /tmp
        unzip -q xray.zip || {
            print_warning "解压失败，尝试直接查找文件..."
        }
        
        # 查找xray二进制文件
        local xray_binary=$(find /tmp -name "xray" -type f | head -1)
        if [[ -n "$xray_binary" ]]; then
            mv "$xray_binary" "$BIN_DIR/xray"
            chmod +x "$BIN_DIR/xray"
            print_success "✅ Xray 安装成功"
        else
            print_error "❌ 未找到Xray二进制文件"
            exit 1
        fi
    else
        print_error "❌ Xray 下载失败"
        exit 1
    fi
    
    # 下载并安装 cloudflared
    print_info "下载 cloudflared..."
    if download_with_retry "${cf_urls[@]}" "/tmp/cloudflared"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        print_success "✅ cloudflared 安装成功"
    else
        print_error "❌ cloudflared 下载失败"
        exit 1
    fi
    
    # 清理临时文件
    rm -rf /tmp/xray* /tmp/cloudflare* 2>/dev/null
    
    print_success "✅ 组件安装完成"
}

# ----------------------------
# Cloudflare 授权（保持不变）
# ----------------------------
direct_cloudflare_auth() {
    print_warning "═══════════════════════════════════════════════"
    print_warning "    Cloudflare 授权"
    print_warning "═══════════════════════════════════════════════"
    echo ""
    
    rm -rf /root/.cloudflared
    mkdir -p /root/.cloudflared
    
    print_info "开始 Cloudflare 授权..."
    echo ""
    
    "$BIN_DIR/cloudflared" tunnel login
    
    echo ""
    print_input "请在浏览器完成授权后，按回车键继续..."
    read -r
    
    # 检查授权
    local check_count=0
    while [[ $check_count -lt 5 ]]; do
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 授权成功！"
            return 0
        fi
        sleep 3
        ((check_count++))
    done
    
    print_error "❌ 未检测到授权证书！"
    print_input "按回车键重试..."
    read -r
    direct_cloudflare_auth
}

# ----------------------------
# 创建隧道和配置（保持不变）
# ----------------------------
setup_tunnel() {
    print_info "设置 Cloudflare Tunnel..."
    
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "错误：未找到证书文件"
        exit 1
    fi
    
    export TUNNEL_ORIGIN_CERT="/root/.cloudflared/cert.pem"
    
    # 检查是否已存在同名隧道
    local existing_tunnel
    existing_tunnel=$("$BIN_DIR/cloudflared" tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -n "$existing_tunnel" ]]; then
        print_warning "发现同名隧道，使用现有隧道: $existing_tunnel"
        local tunnel_id="$existing_tunnel"
    else
        print_info "创建隧道: $TUNNEL_NAME"
        "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"
        
        local tunnel_id
        tunnel_id=$("$BIN_DIR/cloudflared" tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
        
        if [[ -z "$tunnel_id" ]]; then
            print_error "无法获取隧道ID"
            exit 1
        fi
    fi
    
    # 绑定域名
    print_info "绑定域名: $USER_DOMAIN"
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN"
    
    # 保存配置
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
CERT_PATH=/root/.cloudflared/cert.pem
CREATED_DATE=$(date +"%Y-%m-%d")
EOF
    
    print_success "✅ 隧道设置完成 (ID: ${tunnel_id})"
}

# ----------------------------
# 配置 Xray（保持不变）
# ----------------------------
configure_xray() {
    print_info "配置 Xray..."
    
    # 生成UUID和端口
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=10000
    
    echo "" >> "$CONFIG_DIR/tunnel.conf"
    echo "UUID=$uuid" >> "$CONFIG_DIR/tunnel.conf"
    echo "PORT=$port" >> "$CONFIG_DIR/tunnel.conf"
    
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # Xray配置
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
    
    # 隧道配置
    local json_file=$(find /root/.cloudflared -name "*.json" -type f | head -1)
    if [[ -z "$json_file" ]]; then
        print_error "找不到隧道凭证文件"
        exit 1
    fi
    
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: $json_file
originCert: /root/.cloudflared/cert.pem
ingress:
  - hostname: $USER_DOMAIN
    service: http://localhost:$port
    originRequest:
      noTLSVerify: true
      httpHostHeader: $USER_DOMAIN
  - service: http_status:404
EOF
    
    print_success "Xray 配置完成"
}

# ----------------------------
# 配置系统服务（保持不变）
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
    
    # Argo Tunnel 服务
    cat > /etc/systemd/system/secure-tunnel-argo.service << EOF
[Unit]
Description=Secure Tunnel Argo Service
After=network.target secure-tunnel-xray.service

[Service]
Type=simple
User=root
Group=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=always
RestartSec=5
StandardOutput=append:$LOG_DIR/argo.log
StandardError=append:$LOG_DIR/argo-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "系统服务配置完成"
}

# ----------------------------
# 启动服务（保持不变）
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    systemctl enable secure-tunnel-xray.service
    systemctl start secure-tunnel-xray.service && print_success "Xray 启动成功"
    
    sleep 2
    
    systemctl enable secure-tunnel-argo.service
    systemctl start secure-tunnel-argo.service && print_success "Argo Tunnel 启动成功"
    
    sleep 3
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
    
    if [[ -z "$domain" ]] || [[ -z "$uuid" ]]; then
        print_error "无法读取配置"
        return
    fi
    
    print_success "🔗 域名: $domain"
    print_success "🔑 UUID: $uuid"
    print_success "🚪 端口: 443 (TLS) / 80 (非TLS)"
    print_success "🛣️  路径: /$uuid"
    echo ""
    
    # VLESS链接
    local vless_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${uuid}&sni=${domain}#安全隧道"
    local vless_non_tls="vless://${uuid}@${domain}:80?encryption=none&security=none&type=ws&host=${domain}&path=%2F${uuid}#安全隧道-非TLS"
    
    echo "VLESS 链接:"
    echo "$vless_tls"
    echo ""
    
    # 生成订阅文件
    local SUB_DIR="$CONFIG_DIR/subscription"
    mkdir -p "$SUB_DIR"
    
    echo "$vless_tls" > "$SUB_DIR/vless.txt"
    echo -e "${vless_tls}\n${vless_non_tls}" | base64 -w 0 > "$SUB_DIR/base64.txt"
    
    print_success "📡 订阅文件已生成"
    echo ""
    print_info "订阅文件位置: $SUB_DIR/"
    
    # 生成URL格式订阅（您要的格式）
    local random_path=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    local url_subscription="https://${domain}:8443/${random_path}"
    echo "$url_subscription" > "$SUB_DIR/url_subscription.txt"
    
    print_info "URL格式订阅:"
    echo "$url_subscription"
    echo ""
    
    print_info "🌐 使用说明:"
    echo "1. 复制上面的VLESS链接到客户端"
    echo "2. 或使用URL订阅: $url_subscription"
    echo "3. 本地订阅服务器: sudo ./secure_tunnel_final.sh start-server"
    echo ""
    
    print_info "🔧 服务管理:"
    echo "  状态: systemctl status secure-tunnel-argo.service"
    echo "  重启: systemctl restart secure-tunnel-argo.service"
    echo "  停止: systemctl stop secure-tunnel-argo.service"
}

# ----------------------------
# 修复的订阅服务器函数
# ----------------------------
start_subscription_server() {
    print_info "启动本地订阅服务器..."
    
    # 首先确保所有相关进程已停止
    stop_subscription_server
    
    local SUB_DIR="$CONFIG_DIR/subscription"
    
    if [[ ! -d "$SUB_DIR" ]]; then
        mkdir -p "$SUB_DIR"
    fi
    
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件"
        return 1
    fi
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local uuid=$(grep "^UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    print_success "读取配置成功"
    print_info "域名: $domain"
    print_info "UUID: $uuid"
    
    # 检查Python3
    if ! command -v python3 &> /dev/null; then
        apt-get update && apt-get install -y python3
    fi
    
    # 动态选择可用端口
    find_available_port() {
        local port=$SUBSCRIPTION_PORT
        while ss -tulpn | grep ":$port" >/dev/null; do
            print_warning "端口 $port 已被占用，尝试下一个..."
            ((port++))
            if [[ $port -gt 8200 ]]; then
                print_error "找不到可用端口"
                return 1
            fi
        done
        echo $port
    }
    
    local selected_port=$(find_available_port)
    if [[ -z "$selected_port" ]]; then
        print_error "无法找到可用端口"
        return 1
    fi
    
    print_info "使用端口: $selected_port"
    
    # 创建简化的HTTP服务器
    cat > "$SUB_DIR/simple_server.py" << PYEOF
#!/usr/bin/env python3
import http.server
import socketserver
import os
import sys

PORT = $selected_port
DIR = os.path.dirname(os.path.abspath(__file__))

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(b'<h1>订阅服务器</h1><p>订阅链接: <a href="/sub">点击下载</a></p>')
        elif self.path == '/sub':
            sub_file = os.path.join(DIR, 'base64.txt')
            if os.path.exists(sub_file):
                with open(sub_file, 'r') as f:
                    content = f.read().strip()
                self.send_response(200)
                self.send_header('Content-type', 'text/plain; charset=utf-8')
                self.end_headers()
                self.wfile.write(content.encode())
            else:
                self.send_error(404, "File not found")
        elif self.path == '/url':
            url_file = os.path.join(DIR, 'url_subscription.txt')
            if os.path.exists(url_file):
                with open(url_file, 'r') as f:
                    content = f.read().strip()
                self.send_response(200)
                self.send_header('Content-type', 'text/plain; charset=utf-8')
                self.end_headers()
                self.wfile.write(content.encode())
            else:
                self.send_error(404, "File not found")
        else:
            self.directory = DIR
            super().do_GET()
    
    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    os.chdir(DIR)
    try:
        with socketserver.TCPServer(("", PORT), Handler) as httpd:
            print(f"服务器运行在: http://0.0.0.0:{PORT}")
            print(f"订阅链接: http://服务器IP:{PORT}/sub")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n服务器已停止")
    except Exception as e:
        print(f"错误: {e}")
        sys.exit(1)
PYEOF
    
    chmod +x "$SUB_DIR/simple_server.py"
    
    # 停止旧进程
    pkill -f "simple_server.py" 2>/dev/null || true
    sleep 2
    
    # 启动服务器
    cd "$SUB_DIR"
    nohup python3 simple_server.py > server.log 2>&1 &
    local pid=$!
    echo $pid > "$SUB_DIR/server.pid"
    
    sleep 3
    
    if kill -0 $pid 2>/dev/null; then
        local server_ip=$(hostname -I | awk '{print $1}' | head -1)
        print_success "✅ 订阅服务器启动成功！"
        echo ""
        print_info "访问地址:"
        echo "  http://${server_ip}:${selected_port}"
        echo "  订阅链接: http://${server_ip}:${selected_port}/sub"
        echo "  URL格式: http://${server_ip}:${selected_port}/url"
        echo ""
    else
        print_error "❌ 服务器启动失败"
        tail -20 "$SUB_DIR/server.log"
        return 1
    fi
}

# ----------------------------
# 停止订阅服务器
# ----------------------------
stop_subscription_server() {
    print_info "停止订阅服务器..."
    
    local SUB_DIR="$CONFIG_DIR/subscription"
    
    # 停止所有可能的Python服务器
    pkill -f "simple_server.py" 2>/dev/null && print_success "✅ 服务器已停止"
    pkill -f "server.py" 2>/dev/null && print_info "停止旧版服务器"
    
    # 清理PID文件
    rm -f "$SUB_DIR/server.pid" 2>/dev/null
    
    # 释放端口
    for port in {8080..8200}; do
        if ss -tulpn | grep ":$port" >/dev/null; then
            sudo fuser -k ${port}/tcp 2>/dev/null || true
        fi
    done
    
    sleep 2
    print_success "✅ 清理完成"
}

# ----------------------------
# 显示订阅信息
# ----------------------------
show_subscription() {
    print_info "显示订阅信息..."
    
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
    
    # VLESS链接
    local vless_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${uuid}&sni=${domain}#安全隧道"
    
    print_info "📡 VLESS链接:"
    echo "$vless_tls"
    echo ""
    
    # URL格式订阅
    local SUB_DIR="$CONFIG_DIR/subscription"
    if [[ -f "$SUB_DIR/url_subscription.txt" ]]; then
        print_info "🌐 URL格式订阅:"
        cat "$SUB_DIR/url_subscription.txt"
        echo ""
    fi
    
    if [[ -f "$SUB_DIR/base64.txt" ]]; then
        print_info "🔐 Base64订阅 (前100字符):"
        head -c 100 "$SUB_DIR/base64.txt"
        echo "..."
        echo ""
    fi
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    print_info "开始安装流程..."
    
    collect_user_info
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
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 一键安装脚本 v4.5      ║"
    echo "║        修复下载和端口问题                   ║"
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
        "status")
            systemctl status secure-tunnel-xray.service
            systemctl status secure-tunnel-argo.service
            ;;
        *)
            echo "使用方法:"
            echo "  sudo ./secure_tunnel_final.sh install         # 安装"
            echo "  sudo ./secure_tunnel_final.sh start-server    # 启动订阅服务器"
            echo "  sudo ./secure_tunnel_final.sh stop-server     # 停止订阅服务器"
            echo "  sudo ./secure_tunnel_final.sh subscription    # 显示订阅信息"
            echo "  sudo ./secure_tunnel_final.sh status          # 查看服务状态"
            exit 1
            ;;
    esac
}

main "$@"