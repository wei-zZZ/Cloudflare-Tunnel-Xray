#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安装脚本 (Root版)
# 版本: 4.2 - 修复隧道检查bug
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
    echo "║                版本 4.2                      ║"
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
    local required_tools=("curl" "unzip" "wget" "jq")
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
    
    # 保存隧道配置
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
# Cloudflare Tunnel 配置
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
CERT_PATH=/root/.cloudflared/cert.pem
CREATED_TIME=$(date +"%Y-%m-%d %H:%M:%S")
EOF
    
    # 如果找到了JSON文件，记录路径
    if [[ -f "$json_file" ]]; then
        echo "TUNNEL_JSON=$json_file" >> "$CONFIG_DIR/tunnel.conf"
        print_info "隧道凭证文件: $json_file"
    fi
    
    print_success "✅ 隧道设置完成 (ID: ${tunnel_id})"
}

# ----------------------------
# 配置 Xray
# ----------------------------
configure_xray() {
    print_info "配置 Xray..."
    
    # 读取隧道ID
    local tunnel_id
    if [[ -f "$CONFIG_DIR/tunnel.conf" ]]; then
        source "$CONFIG_DIR/tunnel.conf"
    else
        print_error "未找到隧道配置文件"
        exit 1
    fi
    
    # 生成UUID和端口
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=10000  # 固定端口，便于管理
    
    # 追加到配置文件
    echo "UUID=$uuid" >> "$CONFIG_DIR/tunnel.conf"
    echo "PORT=$port" >> "$CONFIG_DIR/tunnel.conf"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # 生成Xray配置文件
    cat > "$CONFIG_DIR/xray.json" << EOF
{
    "log": {
        "loglevel": "warning",
        "access": "$LOG_DIR/xray-access.log",
        "error": "$LOG_DIR/xray-error.log"
    },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "vless",
        "settings": {
            "clients": [{
                "id": "$uuid",
                "flow": ""
            }],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
                "path": "/$uuid"
            }
        }
    }],
    "outbounds": [{
        "protocol": "freedom",
        "settings": {}
    }]
}
EOF
    
    # 创建隧道配置文件
    # 使用正确的JSON文件路径
    local json_path="/root/.cloudflared/${tunnel_id}.json"
    if [[ ! -f "$json_path" ]]; then
        json_path="/root/.cloudflared/${TUNNEL_NAME}.json"
    fi
    
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: $json_path
originCert: /root/.cloudflared/cert.pem

ingress:
  - hostname: $USER_DOMAIN
    service: http://localhost:$port
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      tlsTimeout: 30s
      tcpKeepAlive: 30s
      noHappyEyeballs: false
      keepAliveConnections: 100
      keepAliveTimeout: 90s
      httpHostHeader: $USER_DOMAIN
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
# 显示连接信息
# ----------------------------
show_connection_info() {
    print_info "═══════════════════════════════════════════════"
    print_info "           安装完成！连接信息"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 读取配置
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件"
        return
    fi
    
    source "$CONFIG_DIR/tunnel.conf" 2>/dev/null
    
    print_success "🔗 域名: $DOMAIN"
    print_success "🔑 UUID: $UUID"
    print_success "🚪 端口: 443 (TLS) / 80 (非TLS)"
    print_success "🛣️  路径: /$UUID"
    echo ""
    
    print_info "📋 VLESS 连接配置:"
    echo ""
    echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/${UUID}#安全隧道"
    echo ""
    
    print_info "⚙️  Clash 配置:"
    echo ""
    echo "- name: 安全隧道"
    echo "  type: vless"
    echo "  server: ${DOMAIN}"
    echo "  port: 443"
    echo "  uuid: ${UUID}"
    echo "  network: ws"
    echo "  tls: true"
    echo "  udp: true"
    echo "  ws-opts:"
    echo "    path: /${UUID}"
    echo "    headers:"
    echo "      Host: ${DOMAIN}"
    echo ""
    
    print_info "🔧 服务管理命令:"
    echo "  启动: systemctl start secure-tunnel-{xray,argo}"
    echo "  停止: systemctl stop secure-tunnel-{xray,argo}"
    echo "  状态: systemctl status secure-tunnel-{xray,argo}"
    echo "  重启: systemctl restart secure-tunnel-{xray,argo}"
    echo "  日志: journalctl -u secure-tunnel-argo.service -f"
    echo ""
    
    print_info "📁 配置文件位置:"
    echo "  Xray配置: $CONFIG_DIR/xray.json"
    echo "  隧道配置: $CONFIG_DIR/config.yaml"
    echo "  连接信息: $CONFIG_DIR/tunnel.conf"
    echo "  证书位置: /root/.cloudflared/cert.pem"
    echo ""
    
    print_warning "⚠️ 重要提示:"
    print_warning "1. 请等待几分钟让DNS生效"
    print_warning "2. 在Cloudflare DNS中确认 $DOMAIN 已正确解析"
    print_warning "3. 首次连接可能需要等待证书签发"
    print_warning "4. 检查防火墙是否开放端口"
}

# ----------------------------
# 显示状态
# ----------------------------
show_status() {
    print_info "系统服务状态:"
    systemctl status secure-tunnel-xray.service secure-tunnel-argo.service --no-pager
    
    echo ""
    print_info "隧道状态:"
    "$BIN_DIR/cloudflared" tunnel list || true
    
    echo ""
    print_info "证书状态:"
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "✅ 证书存在"
        ls -lh "/root/.cloudflared/cert.pem"
    else
        print_error "❌ 证书不存在"
    fi
    
    echo ""
    print_info "JSON文件状态:"
    if [[ -f "/root/.cloudflared/${TUNNEL_NAME}.json" ]]; then
        print_success "✅ 找到隧道JSON文件: /root/.cloudflared/${TUNNEL_NAME}.json"
    elif [[ -f "/root/.cloudflared/*.json" ]]; then
        print_info "找到JSON文件: $(ls /root/.cloudflared/*.json 2>/dev/null | head -1)"
    else
        print_error "❌ 未找到隧道JSON文件"
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
    print_info "请使用上面的VLESS链接配置您的客户端。"
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 一键安装脚本            ║"
    echo "║                版本4.2 (修复版)              ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    
    case "${1:-}" in
        "install")
            main_install
            ;;
        "status")
            show_status
            ;;
        "restart")
            systemctl restart secure-tunnel-xray.service secure-tunnel-argo.service
            print_success "服务已重启"
            ;;
        "uninstall")
            print_warning "正在卸载..."
            systemctl stop secure-tunnel-xray.service secure-tunnel-argo.service 2>/dev/null || true
            systemctl disable secure-tunnel-xray.service secure-tunnel-argo.service 2>/dev/null || true
            rm -f /etc/systemd/system/secure-tunnel-*.service
            systemctl daemon-reload
            rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "/root/.cloudflared"
            userdel "$SERVICE_USER" 2>/dev/null || true
            print_success "卸载完成"
            ;;
        "config")
            if [[ -f "$CONFIG_DIR/tunnel.conf" ]]; then
                print_info "当前配置:"
                cat "$CONFIG_DIR/tunnel.conf"
            else
                print_error "未找到配置文件"
            fi
            ;;
        "auth")
            print_info "重新授权..."
            direct_cloudflare_auth
            ;;
        "fix-json")
            print_info "修复JSON文件..."
            if [[ -f "$CONFIG_DIR/tunnel.conf" ]]; then
                source "$CONFIG_DIR/tunnel.conf"
                if [[ -n "$TUNNEL_ID" ]]; then
                    echo "隧道ID: $TUNNEL_ID"
                    # 查找JSON文件
                    find /root/.cloudflared -name "*.json" -exec ls -la {} \;
                fi
            fi
            ;;
        *)
            echo "使用方法:"
            echo "  sudo $0 install      # 安装"
            echo "  sudo $0 status       # 查看状态"
            echo "  sudo $0 restart      # 重启服务"
            echo "  sudo $0 config       # 查看配置"
            echo "  sudo $0 auth         # 重新授权"
            echo "  sudo $0 fix-json     # 修复JSON文件"
            echo "  sudo $0 uninstall    # 卸载"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"