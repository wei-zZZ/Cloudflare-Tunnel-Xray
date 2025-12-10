#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安全增强部署脚本
# 版本: 2.0
# 特性: 安全权限、文件校验、systemd服务、配置分离
# ============================================

set -e  # 遇到任何错误立即退出

# ----------------------------
# 颜色输出函数
# ----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }

# ----------------------------
# 配置文件
# ----------------------------
readonly CONFIG_DIR="/etc/secure_tunnel"
readonly DATA_DIR="/var/lib/secure_tunnel"
readonly LOG_DIR="/var/log/secure_tunnel"
readonly BIN_DIR="/usr/local/bin"
readonly SERVICE_USER="secure_tunnel"
readonly SERVICE_GROUP="secure_tunnel"

# 可配置参数（可通过环境变量覆盖）
PROTOCOL=${PROTOCOL:-"vless"}  # vless 或 vmess
ARGO_IP_VERSION=${ARGO_IP_VERSION:-"4"}  # 4 或 6
TUNNEL_NAME=${TUNNEL_NAME:-"secure_tunnel_$(hostname)"}
ARCH=$(uname -m)

# ----------------------------
# 预定义文件哈希值 (请定期从官方发布页更新)
# ----------------------------
declare -A FILE_HASHES
FILE_HASHES=(
    ["xray-linux-64.zip"]="请从 https://github.com/XTLS/Xray-core/releases 获取最新哈希"
    ["cloudflared-linux-amd64"]="请从 https://github.com/cloudflare/cloudflared/releases 获取最新哈希"
    # 其他架构的哈希值需要时补充
)

# ----------------------------
# 辅助函数
# ----------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        exit 1
    fi
}

check_system() {
    print_info "检测系统环境..."
    
    # 检测systemd
    if ! command -v systemctl &> /dev/null; then
        print_error "此脚本需要systemd系统"
        exit 1
    fi
    
    # 检测必要工具
    for tool in curl unzip jq openssl; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "安装缺少的工具: $tool"
            apt-get update && apt-get install -y "$tool" || \
            yum install -y "$tool" || \
            apk add --no-cache "$tool"
        fi
    done
    
    print_success "系统环境检查完成"
}

setup_user() {
    if ! id -u "$SERVICE_USER" &> /dev/null; then
        print_info "创建系统用户和组: $SERVICE_USER"
        groupadd -r "$SERVICE_GROUP" 2>/dev/null || true
        useradd -r -s /usr/sbin/nologin -g "$SERVICE_GROUP" "$SERVICE_USER"
    fi
    
    # 创建目录并设置权限
    local dirs=("$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR")
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chown -R "$SERVICE_USER:$SERVICE_GROUP" "$dir"
        chmod 750 "$dir"
    done
    
    print_success "用户和目录设置完成"
}

safe_download() {
    local url=$1
    local output=$2
    local expected_hash=$3
    
    print_info "下载: $(basename "$output")"
    
    # 使用curl下载，显示进度
    if ! curl -L --progress-bar "$url" -o "$output"; then
        print_error "下载失败: $url"
        return 1
    fi
    
    # 如果提供了哈希值则验证
    if [[ -n "$expected_hash" ]]; then
        local actual_hash
        actual_hash=$(sha256sum "$output" | awk '{print $1}')
        
        if [[ "$actual_hash" != "$expected_hash" ]]; then
            print_error "文件哈希验证失败: $output"
            print_error "期望: $expected_hash"
            print_error "实际: $actual_hash"
            rm -f "$output"
            return 1
        fi
        print_success "文件哈希验证通过"
    fi
    
    return 0
}

cleanup_on_fail() {
    print_warning "安装失败，执行清理..."
    
    # 停止服务
    systemctl stop "secure-tunnel-xray" 2>/dev/null || true
    systemctl stop "secure-tunnel-argo" 2>/dev/null || true
    
    # 移除用户（如果刚刚创建）
    if id -u "$SERVICE_USER" &> /dev/null; then
        # 检查是否还有其他进程使用
        if ! pgrep -u "$SERVICE_USER" > /dev/null; then
            userdel "$SERVICE_USER" 2>/dev/null || true
            groupdel "$SERVICE_GROUP" 2>/dev/null || true
        fi
    fi
    
    # 清理目录
    rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" 2>/dev/null || true
    
    print_warning "清理完成"
    exit 1
}

# 设置失败时的清理
trap cleanup_on_fail ERR

# ----------------------------
# 主安装函数
# ----------------------------
install_components() {
    check_root
    check_system
    setup_user
    
    print_info "开始部署安全隧道"
    
    # 检测架构并设置下载URL
    case "$ARCH" in
        "x86_64"|"amd64")
            XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        "aarch64"|"arm64")
            XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)
            print_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    # 下载 Xray
    local xray_zip="$DATA_DIR/xray.zip"
    if safe_download "$XRAY_URL" "$xray_zip" "${FILE_HASHES["xray-linux-64.zip"]:-}"; then
        unzip -q -d "$DATA_DIR" "$xray_zip"
        mv "$DATA_DIR/xray" "$BIN_DIR/"
        chmod +x "$BIN_DIR/xray"
        rm -f "$xray_zip"
        print_success "Xray 安装完成"
    else
        print_error "Xray 下载失败"
        exit 1
    fi
    
    # 下载 cloudflared
    local cloudflared_bin="$BIN_DIR/cloudflared"
    if safe_download "$CLOUDFLARED_URL" "$cloudflared_bin" "${FILE_HASHES["cloudflared-linux-amd64"]:-}"; then
        chmod +x "$cloudflared_bin"
        print_success "cloudflared 安装完成"
    else
        print_error "cloudflared 下载失败"
        exit 1
    fi
}

configure_tunnel() {
    print_info "配置隧道参数..."
    
    # 生成UUID
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    local path="${uuid%%-*}"
    local port=$((RANDOM % 10000 + 20000))
    
    # 生成Xray配置
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
                "path": "/$path"
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
    chown "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR/xray.json"
    chmod 640 "$CONFIG_DIR/xray.json"
    
    # 保存连接信息
    cat > "$CONFIG_DIR/client-info.txt" << EOF
# ============================================
# 安全隧道客户端连接信息
# 生成时间: $(date)
# ============================================

协议: $PROTOCOL
UUID: $uuid
端口: 443 (TLS) / 80 (非TLS)
路径: /$path
TLS Host: 您的域名
EOF
    
    # 如果是vless协议
    if [[ "$PROTOCOL" == "vless" ]]; then
        cat >> "$CONFIG_DIR/client-info.txt" << EOF

VLESS 链接 (TLS):
vless://$uuid@您的域名:443?encryption=none&security=tls&type=ws&host=您的域名&path=/$path#安全隧道

VLESS 链接 (非TLS):
vless://$uuid@您的域名:80?encryption=none&security=none&type=ws&host=您的域名&path=/$path#安全隧道
EOF
    fi
    
    print_success "隧道配置完成"
    print_info "连接信息保存在: $CONFIG_DIR/client-info.txt"
}

setup_services() {
    print_info "配置系统服务..."
    
    # Xray 服务
    cat > /etc/systemd/system/secure-tunnel-xray.service << EOF
[Unit]
Description=Secure Tunnel Xray Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
ExecStart=$BIN_DIR/xray run -config $CONFIG_DIR/xray.json
Restart=on-failure
RestartSec=3
LimitNPROC=512
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    
    # Argo Tunnel 服务 (需要手动授权后配置)
    cat > /etc/systemd/system/secure-tunnel-argo.service << EOF
[Unit]
Description=Secure Tunnel Argo Service
After=network.target secure-tunnel-xray.service
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
    
    # 启用Xray服务
    systemctl enable secure-tunnel-xray.service
    systemctl start secure-tunnel-xray.service
    
    print_success "系统服务配置完成"
    print_info "需要手动完成以下步骤:"
    print_info "1. 运行: sudo -u $SERVICE_USER $BIN_DIR/cloudflared tunnel login"
    print_info "2. 运行: sudo -u $SERVICE_USER $BIN_DIR/cloudflared tunnel create $TUNNEL_NAME"
    print_info "3. 绑定域名后编辑: $CONFIG_DIR/argo-config.yaml"
}

# ----------------------------
# 管理函数
# ----------------------------
show_status() {
    echo -e "\n${BLUE}=== 服务状态 ===${NC}"
    systemctl status secure-tunnel-xray.service --no-pager || true
    echo ""
    systemctl status secure-tunnel-argo.service --no-pager 2>/dev/null || echo "Argo服务未配置"
    
    echo -e "\n${BLUE}=== 连接信息 ===${NC}"
    if [[ -f "$CONFIG_DIR/client-info.txt" ]]; then
        cat "$CONFIG_DIR/client-info.txt"
    else
        echo "未找到连接信息"
    fi
}

uninstall_all() {
    print_warning "准备卸载所有组件..."
    
    read -p "确定要完全卸载吗？(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消卸载"
        exit 0
    fi
    
    # 停止服务
    systemctl stop secure-tunnel-xray.service 2>/dev/null || true
    systemctl stop secure-tunnel-argo.service 2>/dev/null || true
    
    # 禁用服务
    systemctl disable secure-tunnel-xray.service 2>/dev/null || true
    systemctl disable secure-tunnel-argo.service 2>/dev/null || true
    
    # 删除服务文件
    rm -f /etc/systemd/system/secure-tunnel-*.service
    systemctl daemon-reload
    
    # 删除二进制文件
    rm -f "$BIN_DIR/xray" "$BIN_DIR/cloudflared" 2>/dev/null || true
    
    # 删除配置和数据
    rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" 2>/dev/null || true
    
    # 删除用户（如果没有其他进程）
    if id -u "$SERVICE_USER" &> /dev/null; then
        if ! pgrep -u "$SERVICE_USER" > /dev/null; then
            userdel "$SERVICE_USER" 2>/dev/null || true
            groupdel "$SERVICE_GROUP" 2>/dev/null || true
        fi
    fi
    
    print_success "卸载完成"
}

# ----------------------------
# 主菜单
# ----------------------------
show_menu() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════╗"
    echo "║    安全隧道部署与管理工具            ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"
    echo "1. 完整安装 (包含所有组件)"
    echo "2. 仅安装二进制文件"
    echo "3. 仅配置服务"
    echo "4. 查看状态和连接信息"
    echo "5. 卸载所有组件"
    echo "6. 清理临时文件"
    echo "0. 退出"
    echo ""
}

main() {
    case "$1" in
        "install")
            install_components
            configure_tunnel
            setup_services
            show_status
            ;;
        "status")
            show_status
            ;;
        "uninstall")
            uninstall_all
            ;;
        *)
            while true; do
                show_menu
                read -p "请选择操作: " choice
                case $choice in
                    1) install_components; configure_tunnel; setup_services;;
                    2) install_components;;
                    3) configure_tunnel; setup_services;;
                    4) show_status;;
                    5) uninstall_all;;
                    6) rm -rf /tmp/secure_tunnel_* 2>/dev/null; print_success "临时文件已清理";;
                    0) print_info "退出"; exit 0;;
                    *) print_error "无效选择";;
                esac
                echo ""
                read -p "按回车键继续..."
            done
            ;;
    esac
}

# 运行主函数
main "$@"
