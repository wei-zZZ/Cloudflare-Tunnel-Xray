#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安全增强部署脚本
# 修复版本 - 确保无BOM和格式问题
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

# 清理可能存在的BOM
LC_ALL=C
export LC_ALL

# ----------------------------
# 检查并修复原始脚本
# ----------------------------
check_and_fix_script() {
    local script_file="$1"
    
    # 检查文件编码
    if file "$script_file" | grep -q "with BOM"; then
        print_warning "检测到BOM头，正在清理..."
        sed -i '1s/^\xEF\xBB\xBF//' "$script_file"
    fi
    
    # 移除Windows换行符
    if grep -q $'\r' "$script_file"; then
        print_warning "检测到Windows换行符，正在转换..."
        sed -i 's/\r//g' "$script_file"
    fi
    
    # 检查脚本语法
    if ! bash -n "$script_file"; then
        print_error "脚本语法错误"
        exit 1
    fi
    
    print_success "脚本检查通过"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    print_info "开始安全隧道安装流程..."
    
    # 检查系统
    check_system
    
    # 创建目录结构
    create_directories
    
    # 下载组件
    download_components
    
    # 配置服务
    configure_services
    
    # 启动服务
    start_services
    
    print_success "安装完成！"
}

check_system() {
    print_info "检查系统环境..."
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    # 检查必要工具
    local required_tools=("curl" "unzip" "jq" "systemctl")
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

create_directories() {
    print_info "创建目录结构..."
    
    local dirs=(
        "/etc/secure_tunnel"
        "/var/lib/secure_tunnel"
        "/var/log/secure_tunnel"
        "/usr/local/bin"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chmod 755 "$dir"
    done
    
    print_success "目录创建完成"
}

download_components() {
    print_info "下载必要组件..."
    
    # 获取系统架构
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
    
    # 下载Xray
    print_info "下载 Xray..."
    if ! curl -L --progress-bar "$xray_url" -o /tmp/xray.zip; then
        print_error "Xray下载失败"
        exit 1
    fi
    
    # 下载cloudflared
    print_info "下载 cloudflared..."
    if ! curl -L --progress-bar "$cf_url" -o /tmp/cloudflared; then
        print_error "cloudflared下载失败"
        exit 1
    fi
    
    # 解压和安装
    unzip -q -d /tmp /tmp/xray.zip
    mv /tmp/xray /usr/local/bin/
    mv /tmp/cloudflared /usr/local/bin/
    
    chmod +x /usr/local/bin/xray /usr/local/bin/cloudflared
    
    # 清理临时文件
    rm -f /tmp/xray.zip
    
    print_success "组件下载完成"
}

configure_services() {
    print_info "配置系统服务..."
    
    # 生成配置
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    local port=$((20000 + RANDOM % 10000))
    
    # Xray配置
    cat > /etc/secure_tunnel/xray.json << EOF
{
    "log": {
        "loglevel": "warning",
        "access": "/var/log/secure_tunnel/xray-access.log",
        "error": "/var/log/secure_tunnel/xray-error.log"
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
    
    # Xray服务文件
    cat > /etc/systemd/system/secure-tunnel-xray.service << EOF
[Unit]
Description=Secure Tunnel Xray Service
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/xray run -config /etc/secure_tunnel/xray.json
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    # cloudflared服务文件（简化版，需要后续配置）
    cat > /etc/systemd/system/secure-tunnel-argo.service << EOF
[Unit]
Description=Secure Tunnel Argo Service
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/cloudflared tunnel run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # 保存连接信息
    cat > /etc/secure_tunnel/client-info.txt << EOF
# ============================================
# 安全隧道连接信息
# ============================================

协议: vless
UUID: $uuid
端口: 443 (TLS) / 80 (非TLS)
路径: /$uuid

注意: 需要配置Cloudflare Tunnel并绑定域名
EOF
    
    print_success "服务配置完成"
}

start_services() {
    print_info "启动服务..."
    
    systemctl daemon-reload
    
    # 启动Xray
    if systemctl start secure-tunnel-xray.service; then
        systemctl enable secure-tunnel-xray.service
        print_success "Xray服务启动成功"
    else
        print_error "Xray服务启动失败"
        journalctl -u secure-tunnel-xray.service -n 10 --no-pager
    fi
    
    print_info ""
    print_info "下一步操作:"
    print_info "1. 配置Cloudflare Tunnel:"
    print_info "   cloudflared tunnel login"
    print_info "   cloudflared tunnel create secure-tunnel"
    print_info "   cloudflared tunnel route dns secure-tunnel 你的域名"
    print_info ""
    print_info "2. 查看连接信息:"
    print_info "   cat /etc/secure_tunnel/client-info.txt"
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    clear
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║    安全隧道快速安装脚本              ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    
    case "${1:-}" in
        "install")
            main_install
            ;;
        "status")
            systemctl status secure-tunnel-xray.service --no-pager
            ;;
        "uninstall")
            print_warning "卸载服务..."
            systemctl stop secure-tunnel-xray.service 2>/dev/null || true
            systemctl stop secure-tunnel-argo.service 2>/dev/null || true
            systemctl disable secure-tunnel-xray.service 2>/dev/null || true
            systemctl disable secure-tunnel-argo.service 2>/dev/null || true
            rm -f /etc/systemd/system/secure-tunnel-*.service
            rm -rf /etc/secure_tunnel /var/lib/secure_tunnel /var/log/secure_tunnel
            print_success "卸载完成"
            ;;
        *)
            echo "使用方法:"
            echo "  sudo $0 install     # 安装服务"
            echo "  sudo $0 status      # 查看状态"
            echo "  sudo $0 uninstall   # 卸载服务"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
