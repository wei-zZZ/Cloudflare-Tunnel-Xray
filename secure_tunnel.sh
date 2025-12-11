#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本 (增强版)
# 版本: 5.0 - 支持URL格式订阅
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

# 订阅服务器端口（可自定义）
SUBSCRIPTION_PORT="8081"  # 改为8081避免冲突

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
    echo "║    Cloudflare Tunnel 安装脚本 v5.0          ║"
    echo "║        支持URL格式订阅                      ║"
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
    wget -q --show-progress -O /tmp/xray.zip "$xray_url" || {
        print_warning "下载失败，尝试备用链接..."
        wget -q --show-progress -O /tmp/xray.zip "https://ghproxy.com/$xray_url" || {
            print_error "Xray下载失败"
            exit 1
        }
    }
    
    unzip -q -d /tmp /tmp/xray.zip
    find /tmp -name "xray" -type f -exec mv {} "$BIN_DIR/" \;
    chmod +x "$BIN_DIR/xray"
    
    # 下载并安装 cloudflared
    print_info "下载 cloudflared..."
    wget -q --show-progress -O "$BIN_DIR/cloudflared" "$cf_url" || {
        print_warning "下载失败，尝试备用链接..."
        wget -q --show-progress -O "$BIN_DIR/cloudflared" "https://ghproxy.com/$cf_url" || {
            print_error "cloudflared下载失败"
            exit 1
        }
    }
    chmod +x "$BIN_DIR/cloudflared"
    
    # 清理临时文件
    rm -f /tmp/xray.zip
    
    print_success "组件安装完成"
}

# ----------------------------
# Cloudflare 授权
# ----------------------------
direct_cloudflare_auth() {
    print_warning "═══════════════════════════════════════════════"
    print_warning "    Cloudflare 授权"
    print_warning "═══════════════════════════════════════════════"
    echo ""
    
    # 清理旧配置
    print_info "清理旧配置..."
    rm -rf /root/.cloudflared
    mkdir -p /root/.cloudflared
    
    print_info "开始 Cloudflare 授权..."
    echo ""
    
    # 运行 cloudflared tunnel login
    "$BIN_DIR/cloudflared" tunnel login
    
    echo ""
    print_input "请在浏览器完成授权后，按回车键继续..."
    read -r
    
    # 检查授权是否成功
    local max_checks=5
    local check_count=0
    
    while [[ $check_count -lt $max_checks ]]; do
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 授权成功！证书已生成"
            return 0
        fi
        sleep 3
        ((check_count++))
    done
    
    print_error "❌ 未检测到授权证书！"
    print_input "按回车键重试授权，或按 Ctrl+C 退出"
    read -r
    pkill -f "cloudflared tunnel login" 2>/dev/null || true
    direct_cloudflare_auth
}

# ----------------------------
# 创建隧道和配置
# ----------------------------
setup_tunnel() {
    print_info "设置 Cloudflare Tunnel..."
    
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "错误：未找到证书文件"
        exit 1
    fi
    
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
            exit 1
        fi
    fi
    
    # 查找JSON文件
    local json_file="/root/.cloudflared/${tunnel_id}.json"
    if [[ ! -f "$json_file" ]]; then
        json_file="/root/.cloudflared/${TUNNEL_NAME}.json"
        if [[ ! -f "$json_file" ]]; then
            json_file=$(find /root/.cloudflared -name "*.json" -type f | head -1)
        fi
    fi
    
    # 绑定域名
    print_info "绑定域名: $USER_DOMAIN"
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN"
    
    # 保存隧道配置
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
# Cloudflare Tunnel 配置
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
CERT_PATH=/root/.cloudflared/cert.pem
CREATED_DATE=$(date +"%Y-%m-%d")
EOF
    
    if [[ -f "$json_file" ]]; then
        echo "TUNNEL_JSON=$json_file" >> "$CONFIG_DIR/tunnel.conf"
    fi
    
    print_success "✅ 隧道设置完成 (ID: ${tunnel_id})"
}

# ----------------------------
# 配置 Xray
# ----------------------------
configure_xray() {
    print_info "配置 Xray..."
    
    # 读取配置
    local config_file="$CONFIG_DIR/tunnel.conf"
    if [[ ! -f "$config_file" ]]; then
        print_error "配置文件不存在"
        exit 1
    fi
    
    local tunnel_id=$(grep "^TUNNEL_ID=" "$config_file" | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$config_file" | cut -d'=' -f2)
    
    if [[ -z "$tunnel_id" ]]; then
        print_error "无法读取隧道ID"
        exit 1
    fi
    
    # 生成UUID和端口
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=10000
    
    # 追加到配置文件
    echo "" >> "$CONFIG_DIR/tunnel.conf"
    echo "# Xray 配置" >> "$CONFIG_DIR/tunnel.conf"
    echo "UUID=$uuid" >> "$CONFIG_DIR/tunnel.conf"
    echo "PORT=$port" >> "$CONFIG_DIR/tunnel.conf"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # 生成Xray配置文件
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
    local json_path="/root/.cloudflared/${tunnel_id}.json"
    if [[ ! -f "$json_path" ]]; then
        json_path="/root/.cloudflared/${TUNNEL_NAME}.json"
        if [[ ! -f "$json_path" ]]; then
            json_path=$(find /root/.cloudflared -name "*.json" -type f | head -1)
        fi
    fi
    
    if [[ ! -f "$json_path" ]]; then
        print_error "找不到隧道凭证JSON文件"
        exit 1
    fi
    
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: $json_path
originCert: /root/.cloudflared/cert.pem

ingress:
  - hostname: $domain
    service: http://localhost:$port
    originRequest:
      noTLSVerify: true
      httpHostHeader: $domain
  - service: http_status:404
EOF
    
    print_success "Xray 配置完成"
}

# ----------------------------
# 配置系统服务
# ----------------------------
configure_services() {
    print_info "配置系统服务..."
    
    # 创建专用用户
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
Restart=always
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
    
    sleep 2
    
    # 启动Argo Tunnel
    systemctl enable secure-tunnel-argo.service
    if systemctl start secure-tunnel-argo.service; then
        print_success "Argo Tunnel 服务启动成功"
    else
        print_error "Argo Tunnel 服务启动失败"
        journalctl -u secure-tunnel-argo.service -n 10 --no-pager
    fi
    
    sleep 3
}

# ----------------------------
# 生成URL格式订阅
# ----------------------------
generate_url_subscription() {
    print_info "生成URL格式订阅..."
    
    local SUB_DIR="$CONFIG_DIR/subscription"
    mkdir -p "$SUB_DIR"
    
    # 读取配置
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local uuid=$(grep "^UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    if [[ -z "$domain" ]] || [[ -z "$uuid" ]]; then
        print_error "无法读取配置信息"
        return 1
    fi
    
    # 生成随机路径（类似您示例中的格式）
    local random_path=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
    local short_uuid=$(echo "$uuid" | cut -d'-' -f1)
    
    # 1. 标准VLESS链接
    local vless_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${uuid}&sni=${domain}#安全隧道"
    local vless_non_tls="vless://${uuid}@${domain}:80?encryption=none&security=none&type=ws&host=${domain}&path=%2F${uuid}#安全隧道-非TLS"
    
    # 2. 生成URL格式订阅
    cat > "$SUB_DIR/url_subscription.txt" << EOF
# ============================================
# URL格式订阅 - 安全隧道
# 生成时间: $(date)
# ============================================

# 标准订阅链接（Base64编码）:
$(echo -e "${vless_tls}\n${vless_non_tls}" | base64 -w 0)

# ============================================
# URL格式订阅（用于支持URL订阅的客户端）:
# ============================================

# 格式1: 标准HTTPS URL
https://${domain}/proxy
https://${domain}/vless
https://${domain}/ws-proxy

# 格式2: 带端口的URL
https://${domain}:443/vless-proxy
https://${domain}:8443/${random_path}

# 格式3: 带UUID的URL
https://${domain}/proxy/${short_uuid}
https://${domain}/v2ray/${uuid}

# 格式4: WebSocket格式
wss://${domain}/${uuid}
ws://${domain}/${uuid}

# 格式5: 自定义路径（推荐使用）
https://${domain}:8443/${random_path}
https://${domain}/subscribe/${random_path}

# ============================================
# 节点详细配置:
# ============================================
地址: ${domain}
端口: 443 (TLS) / 80 (非TLS)
用户ID: ${uuid}
传输协议: WebSocket
路径: /${uuid}
TLS: 启用

# ============================================
# 客户端配置示例:
# ============================================
1. V2rayN: 使用标准VLESS链接
2. Clash: 使用Clash配置格式
3. Shadowrocket: 使用标准VLESS链接
4. 其他支持URL订阅的客户端: 使用上面的任意URL格式
EOF
    
    # 3. 创建简化的URL文件（一行一个URL）
    cat > "$SUB_DIR/url_links.txt" << EOF
https://${domain}/proxy
https://${domain}:8443/${random_path}
https://${domain}/subscribe/${short_uuid}
wss://${domain}/${uuid}
$(echo -e "${vless_tls}\n${vless_non_tls}" | base64 -w 0)
EOF
    
    # 4. 创建单个URL文件（最简格式）
    echo "https://${domain}:8443/${random_path}" > "$SUB_DIR/single_url.txt"
    echo "https://${domain}/proxy/${short_uuid}" > "$SUB_DIR/simple_url.txt"
    
    # 5. 创建Base64订阅文件
    echo -e "${vless_tls}\n${vless_non_tls}" | base64 -w 0 > "$SUB_DIR/base64.txt"
    
    print_success "✅ URL格式订阅已生成"
    print_info "订阅文件保存在: $SUB_DIR/"
    
    # 显示生成的URL
    echo ""
    print_info "📡 生成的订阅URL:"
    echo "1. 标准URL: https://${domain}/proxy"
    echo "2. 带端口URL: https://${domain}:8443/${random_path}"
    echo "3. 简化URL: https://${domain}/proxy/${short_uuid}"
    echo ""
    print_info "📁 订阅文件:"
    echo "  URL列表: $SUB_DIR/url_links.txt"
    echo "  单个URL: $SUB_DIR/single_url.txt"
    echo "  Base64: $SUB_DIR/base64.txt"
}

# ----------------------------
# 启动HTTP订阅服务器
# ----------------------------
start_http_server() {
    print_info "启动HTTP订阅服务器..."
    
    local SUB_DIR="$CONFIG_DIR/subscription"
    
    # 检查目录
    if [[ ! -d "$SUB_DIR" ]]; then
        print_error "订阅目录不存在，请先生成订阅"
        return 1
    fi
    
    # 检查端口是否被占用
    if ss -tulpn | grep ":$SUBSCRIPTION_PORT" >/dev/null; then
        print_warning "端口 $SUBSCRIPTION_PORT 已被占用，尝试释放..."
        pkill -f "python3.*$SUBSCRIPTION_PORT" 2>/dev/null || true
        sleep 2
        sudo fuser -k $SUBSCRIPTION_PORT/tcp 2>/dev/null || true
        sleep 2
    fi
    
    # 创建简单的HTTP服务器
    cat > "$SUB_DIR/simple_server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server
import socketserver
import os
import sys

PORT = 8081  # 使用8081端口避免冲突
DIR = os.path.dirname(os.path.abspath(__file__))

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(b'<h1>订阅服务器</h1><p><a href="/sub">获取订阅</a></p>')
        elif self.path == '/sub':
            # 返回base64订阅
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
            # 返回URL格式订阅
            url_file = os.path.join(DIR, 'single_url.txt')
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
            # 静态文件服务
            self.directory = DIR
            super().do_GET()
    
    def log_message(self, format, *args):
        pass  # 禁用日志

if __name__ == '__main__':
    os.chdir(DIR)
    try:
        with socketserver.TCPServer(("", PORT), Handler) as httpd:
            print(f"订阅服务器运行在: http://0.0.0.0:{PORT}")
            print(f"订阅链接: http://服务器IP:{PORT}/sub")
            print(f"URL订阅: http://服务器IP:{PORT}/url")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n服务器已停止")
    except Exception as e:
        print(f"错误: {e}")
        sys.exit(1)
PYEOF
    
    chmod +x "$SUB_DIR/simple_server.py"
    
    # 停止可能存在的旧服务器
    pkill -f "simple_server.py" 2>/dev/null || true
    sleep 2
    
    # 启动新服务器
    cd "$SUB_DIR"
    nohup python3 simple_server.py > server.log 2>&1 &
    local pid=$!
    echo $pid > "$SUB_DIR/server.pid"
    
    sleep 3
    
    if kill -0 $pid 2>/dev/null; then
        local server_ip=$(hostname -I | awk '{print $1}' | head -1)
        print_success "✅ HTTP订阅服务器启动成功！"
        echo ""
        print_info "访问地址:"
        echo "  http://${server_ip}:${SUBSCRIPTION_PORT}"
        echo "  订阅链接: http://${server_ip}:${SUBSCRIPTION_PORT}/sub"
        echo "  URL格式: http://${server_ip}:${SUBSCRIPTION_PORT}/url"
        echo ""
        print_info "服务器PID: $pid"
        print_info "日志文件: $SUB_DIR/server.log"
    else
        print_error "❌ 服务器启动失败"
        tail -20 "$SUB_DIR/server.log"
        return 1
    fi
}

# ----------------------------
# 停止HTTP服务器
# ----------------------------
stop_http_server() {
    print_info "停止HTTP订阅服务器..."
    
    local SUB_DIR="$CONFIG_DIR/subscription"
    local pid_file="$SUB_DIR/server.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            sleep 2
            print_success "✅ 服务器已停止"
        fi
        rm -f "$pid_file"
    else
        pkill -f "simple_server.py" 2>/dev/null && print_success "✅ 服务器已停止"
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
    
    # 生成URL格式订阅
    generate_url_subscription
    
    echo ""
    print_info "🌐 使用方法:"
    echo "1. 标准VLESS链接:"
    echo "   vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=/${uuid}#安全隧道"
    echo ""
    echo "2. URL格式订阅（推荐）:"
    echo "   https://${domain}/proxy"
    echo "   https://${domain}:8443/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)"
    echo ""
    echo "3. 启动本地订阅服务器:"
    echo "   sudo ./secure_tunnel_v2.sh start-server"
    echo ""
    
    print_info "🔧 服务管理:"
    echo "  启动隧道: systemctl start secure-tunnel-{xray,argo}"
    echo "  停止隧道: systemctl stop secure-tunnel-{xray,argo}"
    echo "  查看状态: systemctl status secure-tunnel-argo.service"
    echo "  查看日志: journalctl -u secure-tunnel-argo.service -f"
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
# 显示订阅信息
# ----------------------------
show_subscription() {
    print_info "显示订阅信息..."
    
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未安装，请先运行: sudo ./secure_tunnel_v2.sh install"
        return 1
    fi
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local uuid=$(grep "^UUID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    echo ""
    print_success "当前配置:"
    echo "  域名: $domain"
    echo "  UUID: $uuid"
    echo ""
    
    # 重新生成订阅
    generate_url_subscription
    
    # 显示订阅内容
    local SUB_DIR="$CONFIG_DIR/subscription"
    if [[ -f "$SUB_DIR/single_url.txt" ]]; then
        print_info "📡 订阅URL:"
        cat "$SUB_DIR/single_url.txt"
        echo ""
    fi
    
    if [[ -f "$SUB_DIR/base64.txt" ]]; then
        print_info "🔐 Base64订阅:"
        head -c 100 "$SUB_DIR/base64.txt"
        echo "..."
        echo ""
    fi
    
    print_info "📁 订阅文件位置: $SUB_DIR/"
    ls -la "$SUB_DIR/" 2>/dev/null || echo "目录不存在"
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 一键安装脚本 v5.0      ║"
    echo "║        支持URL格式订阅                      ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    
    case "${1:-}" in
        "install")
            main_install
            ;;
        "start-server")
            start_http_server
            ;;
        "stop-server")
            stop_http_server
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
            echo "  sudo ./secure_tunnel_v2.sh install         # 安装"
            echo "  sudo ./secure_tunnel_v2.sh start-server    # 启动订阅服务器"
            echo "  sudo ./secure_tunnel_v2.sh stop-server     # 停止订阅服务器"
            echo "  sudo ./secure_tunnel_v2.sh subscription    # 显示订阅信息"
            echo "  sudo ./secure_tunnel_v2.sh status          # 查看服务状态"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"