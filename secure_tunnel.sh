#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 交互式安装脚本
# 版本: 3.0 (交互式增强版)
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
TUNNEL_NAME=""
PROTOCOL="vless"
ARGO_IP_VERSION="4"

# ----------------------------
# 收集用户信息
# ----------------------------
collect_user_info() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 交互式安装向导          ║"
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
    
    # 选择协议
    print_input "选择协议 (1=vless, 2=vmess) [默认: 1]:"
    read -r protocol_choice
    case "$protocol_choice" in
        2) PROTOCOL="vmess" ;;
        *) PROTOCOL="vless" ;;
    esac
    
    # 选择IP版本
    print_input "选择IP版本 (1=IPv4, 2=IPv6) [默认: 1]:"
    read -r ip_choice
    case "$ip_choice" in
        2) ARGO_IP_VERSION="6" ;;
        *) ARGO_IP_VERSION="4" ;;
    esac
    
    # 显示汇总信息
    echo ""
    print_info "配置摘要:"
    echo "  ┌─────────────────────────────────────┐"
    echo "  │   域名: $USER_DOMAIN"
    echo "  │   隧道名称: $TUNNEL_NAME"
    echo "  │   协议: $PROTOCOL"
    echo "  │   IP版本: IPv$ARGO_IP_VERSION"
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
# 系统检查与准备
# ----------------------------
check_system() {
    print_info "检查系统环境..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    # 检查必要工具
    local required_tools=("curl" "unzip" "jq")
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

setup_user_and_dirs() {
    print_info "设置用户和目录..."
    
    # 创建系统用户
    if ! id -u "$SERVICE_USER" &> /dev/null; then
        useradd -r -s /usr/sbin/nologin "$SERVICE_USER"
        print_success "创建用户: $SERVICE_USER"
    fi
    
    # 创建目录
    local dirs=("$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR")
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chown -R "$SERVICE_USER:$SERVICE_GROUP" "$dir"
        chmod 750 "$dir"
    done
    
    print_success "目录设置完成"
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
    curl -L --progress-bar "$xray_url" -o /tmp/xray.zip
    unzip -q -d /tmp /tmp/xray.zip
    find /tmp -name "xray" -type f -exec mv {} "$BIN_DIR/" \;
    chmod +x "$BIN_DIR/xray"
    
    # 下载并安装 cloudflared
    print_info "下载 cloudflared..."
    curl -L --progress-bar "$cf_url" -o "$BIN_DIR/cloudflared"
    chmod +x "$BIN_DIR/cloudflared"
    
    # 清理临时文件
    rm -f /tmp/xray.zip
    
    print_success "组件安装完成"
}

# ----------------------------
# 配置 Cloudflare Tunnel
# ----------------------------
configure_cloudflare_tunnel() {
    print_info "配置 Cloudflare Tunnel..."
    
    # 第一步：登录（会打开浏览器）
    print_warning "请在浏览器中完成 Cloudflare 登录授权..."
    sudo -u "$SERVICE_USER" "$BIN_DIR/cloudflared" tunnel login
    
    # 第二步：创建隧道
    print_info "创建隧道: $TUNNEL_NAME"
    sudo -u "$SERVICE_USER" "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"
    
    # 第三步：绑定域名
    print_info "绑定域名: $USER_DOMAIN"
    sudo -u "$SERVICE_USER" "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN"
    
    # 第四步：获取并保存Token
    print_info "获取隧道Token..."
    sudo -u "$SERVICE_USER" "$BIN_DIR/cloudflared" tunnel token "$TUNNEL_NAME" > "$CONFIG_DIR/argo-token.txt"
    chown "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR/argo-token.txt"
    chmod 600 "$CONFIG_DIR/argo-token.txt"
    
    print_success "Cloudflare Tunnel 配置完成"
}

# ----------------------------
# 配置 Xray
# ----------------------------
configure_xray() {
    print_info "配置 Xray 代理..."
    
    # 生成UUID和端口
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=$((20000 + RANDOM % 10000))
    
    # 保存基础信息
    echo "DOMAIN=$USER_DOMAIN" > "$CONFIG_DIR/tunnel.conf"
    echo "TUNNEL_NAME=$TUNNEL_NAME" >> "$CONFIG_DIR/tunnel.conf"
    echo "UUID=$uuid" >> "$CONFIG_DIR/tunnel.conf"
    echo "PORT=$port" >> "$CONFIG_DIR/tunnel.conf"
    echo "PROTOCOL=$PROTOCOL" >> "$CONFIG_DIR/tunnel.conf"
    
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
        "protocol": "$PROTOCOL",
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
    
    # 设置权限
    chown "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR"/*
    chmod 640 "$CONFIG_DIR"/*
    
    print_success "Xray 配置完成"
}

# ----------------------------
# 配置系统服务
# ----------------------------
configure_services() {
    print_info "配置系统服务..."
    
    # 创建 Argo Tunnel 配置文件
    cat > "$CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_NAME
credentials-file: /home/$SERVICE_USER/.cloudflared/$(ls /home/$SERVICE_USER/.cloudflared/ | grep .json | head -1)
ingress:
  - hostname: $USER_DOMAIN
    service: http://localhost:\$(grep '^PORT=' $CONFIG_DIR/tunnel.conf | cut -d= -f2)
  - service: http_status:404
EOF
    
    # Xray 服务文件
    cat > /etc/systemd/system/secure-tunnel-xray.service << EOF
[Unit]
Description=Secure Tunnel Xray Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$BIN_DIR/xray run -config $CONFIG_DIR/xray.json
Restart=on-failure
RestartSec=3
LimitNPROC=512
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    
    # Argo Tunnel 服务文件
    cat > /etc/systemd/system/secure-tunnel-argo.service << EOF
[Unit]
Description=Secure Tunnel Argo Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
Environment="TUNNEL_TRANSPORT_PROTOCOL=http2"
ExecStart=$BIN_DIR/cloudflared tunnel --edge-ip-version $ARGO_IP_VERSION run $TUNNEL_NAME
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
# 启动服务并生成客户端配置
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    # 启动Xray服务
    systemctl enable secure-tunnel-xray.service
    systemctl start secure-tunnel-xray.service
    
    # 启动Argo Tunnel服务
    systemctl enable secure-tunnel-argo.service
    systemctl start secure-tunnel-argo.service
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet secure-tunnel-xray.service && \
       systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "所有服务启动成功"
    else
        print_warning "部分服务启动异常，请检查日志"
        systemctl status secure-tunnel-xray.service secure-tunnel-argo.service --no-pager
    fi
}

generate_client_config() {
    print_info "生成客户端配置文件..."
    
    # 读取配置
    source "$CONFIG_DIR/tunnel.conf"
    
    # 生成客户端配置文件
    cat > "$CONFIG_DIR/client-config.txt" << EOF
# ============================================
# 安全隧道客户端配置信息
# 生成时间: $(date)
# ============================================

## 基本配置
域名: $DOMAIN
协议: $PROTOCOL
UUID: $UUID
端口: 443 (TLS) / 80 (非TLS)
路径: /$UUID

## VLESS 配置链接 (TLS)
vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=ws&path=/$UUID#安全隧道

## VLESS 配置链接 (非TLS)
vless://$UUID@$DOMAIN:80?encryption=none&security=none&type=ws&path=/$UUID#安全隧道

## 订阅链接 (Base64编码)
$(echo -e "vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=ws&path=/$UUID#安全隧道" | base64 -w 0)

## 配置步骤:
1. 下载客户端 (v2rayN, Qv2ray, Clash等)
2. 导入 VLESS 链接或订阅链接
3. 选择服务器: $DOMAIN
4. 启用 TLS (推荐)

## 服务状态检查:
sudo systemctl status secure-tunnel-xray.service
sudo systemctl status secure-tunnel-argo.service
sudo journalctl -u secure-tunnel-argo.service -f

## 配置文件位置:
Xray配置: $CONFIG_DIR/xray.json
隧道配置: $CONFIG_DIR/config.yml
连接信息: $CONFIG_DIR/client-config.txt
EOF
    
    # 显示重要信息
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║           安装完成！                         ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    print_success "域名: $DOMAIN"
    print_success "UUID: $UUID"
    print_success "路径: /$UUID"
    echo ""
    print_info "客户端配置文件已保存至:"
    echo "  $CONFIG_DIR/client-config.txt"
    echo ""
    print_info "查看完整配置:"
    echo "  cat $CONFIG_DIR/client-config.txt"
    echo ""
    print_info "服务管理命令:"
    echo "  启动服务: systemctl start secure-tunnel-{xray,argo}"
    echo "  停止服务: systemctl stop secure-tunnel-{xray,argo}"
    echo "  查看状态: systemctl status secure-tunnel-{xray,argo}"
    echo "  查看日志: journalctl -u secure-tunnel-argo.service -f"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    print_info "开始交互式安装..."
    
    # 收集用户信息
    collect_user_info
    
    # 执行安装步骤
    check_system
    setup_user_and_dirs
    install_components
    configure_cloudflare_tunnel
    configure_xray
    configure_services
    start_services
    generate_client_config
    
    echo ""
    print_success "🎉 安装全部完成！"
    print_info "请使用上面的配置信息设置您的客户端。"
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 交互式安装脚本          ║"
    echo "║                版本 3.0                      ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    
    case "${1:-}" in
        "install")
            main_install
            ;;
        "status")
            systemctl status secure-tunnel-xray.service secure-tunnel-argo.service --no-pager
            ;;
        "uninstall")
            print_warning "正在卸载..."
            systemctl stop secure-tunnel-xray.service secure-tunnel-argo.service 2>/dev/null || true
            systemctl disable secure-tunnel-xray.service secure-tunnel-argo.service 2>/dev/null || true
            rm -f /etc/systemd/system/secure-tunnel-*.service
            systemctl daemon-reload
            rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
            userdel "$SERVICE_USER" 2>/dev/null || true
            print_success "卸载完成"
            ;;
        "config")
            if [[ -f "$CONFIG_DIR/client-config.txt" ]]; then
                cat "$CONFIG_DIR/client-config.txt"
            else
                print_error "未找到配置文件，请先运行安装"
            fi
            ;;
        *)
            echo "使用方法:"
            echo "  sudo $0 install    # 交互式安装"
            echo "  sudo $0 status     # 查看服务状态"
            echo "  sudo $0 config     # 查看客户端配置"
            echo "  sudo $0 uninstall  # 卸载所有组件"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"