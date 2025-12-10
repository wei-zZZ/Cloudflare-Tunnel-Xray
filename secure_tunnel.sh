#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安全增强部署脚本 v2.1
# 完整功能版 - 包含所有必需函数
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
print_debug() { echo -e "${CYAN}[#]${NC} $1"; }

# ----------------------------
# 配置文件
# ----------------------------
readonly CONFIG_DIR="/etc/secure_tunnel"
readonly DATA_DIR="/var/lib/secure_tunnel"
readonly LOG_DIR="/var/log/secure_tunnel"
readonly CACHE_DIR="$DATA_DIR/cache"
readonly BIN_DIR="/usr/local/bin"
readonly SERVICE_USER="secure_tunnel"
readonly SERVICE_GROUP="secure_tunnel"

# 可配置参数
PROTOCOL=${PROTOCOL:-"vless"}
ARGO_IP_VERSION=${ARGO_IP_VERSION:-"4"}
ARCH=$(uname -m)

# 优选域名配置
readonly CF_TEST_DOMAINS=(
    "icook.hk"
    "cloudflare.cfgo.cc"
    "cloudflare.speedcdn.cc"
    "cdn.shanggan.ltd"
    "cdn.bestg.win"
    "cf.xiu2.xyz"
    "cloudflare.ipq.co"
    "cfip.icu"
    "cdn.cofia.xyz"
    "speed.cloudflare.com"
)

readonly CF_TEST_COUNT=3
readonly CF_TIMEOUT=2
readonly CACHE_EXPIRE=3600

# ----------------------------
# 核心基础函数（之前版本必需）
# ----------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        exit 1
    fi
}

check_system() {
    print_info "检测系统环境..."
    
    if ! command -v systemctl &> /dev/null; then
        print_error "此脚本需要systemd系统"
        exit 1
    fi
    
    for tool in curl unzip jq openssl bc; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "安装缺少的工具: $tool"
            if command -v apt-get &> /dev/null; then
                apt-get update && apt-get install -y "$tool"
            elif command -v yum &> /dev/null; then
                yum install -y "$tool"
            elif command -v apk &> /dev/null; then
                apk add --no-cache "$tool"
            else
                print_error "无法安装 $tool，请手动安装"
                exit 1
            fi
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
    
    local dirs=("$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$CACHE_DIR")
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
    local expected_hash=${3:-}
    
    print_info "下载: $(basename "$output")"
    
    if ! curl -L --progress-bar "$url" -o "$output"; then
        print_error "下载失败: $url"
        return 1
    fi
    
    if [[ -n "$expected_hash" ]]; then
        local actual_hash
        actual_hash=$(sha256sum "$output" | awk '{print $1}')
        
        if [[ "$actual_hash" != "$expected_hash" ]]; then
            print_error "文件哈希验证失败: $output"
            rm -f "$output"
            return 1
        fi
        print_success "文件哈希验证通过"
    fi
    
    chmod +x "$output"
    return 0
}

cleanup_on_fail() {
    print_warning "安装失败，执行清理..."
    systemctl stop "secure-tunnel-xray" 2>/dev/null || true
    systemctl stop "secure-tunnel-argo" 2>/dev/null || true
    rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" 2>/dev/null || true
    print_warning "清理完成"
    exit 1
}

# ----------------------------
# 新增：优选域名模块
# ----------------------------
test_domain_latency() {
    local domain=$1
    local ip_version=$2
    local total_latency=0
    local success_count=0
    
    for ((i=1; i<=CF_TEST_COUNT; i++)); do
        local latency
        local curl_cmd="curl -s -o /dev/null"
        
        [[ $ip_version == "4" ]] && curl_cmd+=" -4"
        [[ $ip_version == "6" ]] && curl_cmd+=" -6"
        
        curl_cmd+=" -w '%{time_total}' --connect-timeout $CF_TIMEOUT --max-time $((CF_TIMEOUT+1))"
        
        latency=$(eval "$curl_cmd https://$domain/cdn-cgi/trace 2>/dev/null || echo '0'")
        
        if [[ "$latency" != "0" ]] && [[ "$latency" =~ ^[0-9.]+$ ]]; then
            total_latency=$(echo "$total_latency + $latency" | bc -l)
            success_count=$((success_count + 1))
        fi
    done
    
    if [[ $success_count -gt 0 ]]; then
        echo "$(echo "scale=3; $total_latency / $success_count" | bc -l)"
        return 0
    else
        echo "999.999"
        return 1
    fi
}

select_best_domain() {
    local ip_version=${1:-"4"}
    local cache_file="$CACHE_DIR/best_domain_ipv${ip_version}.cache"
    
    if [[ -f "$cache_file" ]]; then
        local cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
        local current_time=$(date +%s)
        local cached_domain=$(head -1 "$cache_file" 2>/dev/null)
        
        if [[ $((current_time - cache_time)) -lt $CACHE_EXPIRE ]] && [[ -n "$cached_domain" ]]; then
            echo "$cached_domain"
            return 0
        fi
    fi
    
    print_info "开始测试Cloudflare节点延迟 (IPv$ip_version)..."
    
    declare -A domain_results
    local best_domain="" best_latency="999.999"
    
    for domain in "${CF_TEST_DOMAINS[@]}"; do
        (
            latency=$(test_domain_latency "$domain" "$ip_version")
            domain_results["$domain"]=$latency
            print_info "域名 $domain 平均延迟: ${latency}s"
        ) &
    done
    wait
    
    for domain in "${!domain_results[@]}"; do
        latency=${domain_results["$domain"]}
        if (( $(echo "$latency < $best_latency" | bc -l) )); then
            best_latency=$latency
            best_domain=$domain
        fi
    done
    
    if [[ -n "$best_domain" ]] && [[ "$best_latency" != "999.999" ]]; then
        mkdir -p "$(dirname "$cache_file")"
        echo "$best_domain" > "$cache_file"
        echo "$best_latency" >> "$cache_file"
        date +%s >> "$cache_file"
        
        print_success "优选完成！最佳域名: $best_domain (延迟: ${best_latency}s)"
        echo "$best_domain"
        return 0
    else
        print_warning "优选失败，使用默认域名"
        echo "speed.cloudflare.com"
        return 1
    fi
}

show_domain_test() {
    print_info "正在测试Cloudflare节点..."
    echo ""
    
    for version in 4 6; do
        print_info "IPv$version 测试结果:"
        echo "----------------------------------------"
        
        for domain in "${CF_TEST_DOMAINS[@]:0:5}"; do
            latency=$(test_domain_latency "$domain" "$version")
            if [[ "$latency" == "999.999" ]]; then
                echo -e "  ${RED}✗${NC} $domain: 超时"
            else
                printf "  ${GREEN}✓${NC} %-30s: %.3f 秒\n" "$domain" "$latency"
            fi
        done
        
        best_domain=$(select_best_domain "$version")
        echo -e "\n最佳域名: ${GREEN}$best_domain${NC}"
        echo ""
    done
}

# ----------------------------
# 安装组件函数
# ----------------------------
install_components() {
    print_info "开始安装组件..."
    
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
    
    # 下载Xray
    local xray_zip="$DATA_DIR/xray.zip"
    if safe_download "$XRAY_URL" "$xray_zip"; then
        unzip -q -d "$DATA_DIR" "$xray_zip"
        find "$DATA_DIR" -name "xray" -type f -exec mv {} "$BIN_DIR/" \;
        rm -f "$xray_zip"
        print_success "Xray 安装完成"
    fi
    
    # 下载cloudflared
    local cloudflared_bin="$BIN_DIR/cloudflared"
    if safe_download "$CLOUDFLARED_URL" "$cloudflared_bin"; then
        print_success "cloudflared 安装完成"
    fi
}

configure_tunnel() {
    print_info "配置隧道参数..."
    
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local path="${uuid%%-*}"
    local port=$((RANDOM % 10000 + 20000))
    
    # 获取优选域名
    local optimized_domain=$(select_best_domain "4")
    
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
    
    # 生成连接信息
    cat > "$CONFIG_DIR/client-info.txt" << EOF
# ============================================
# 安全隧道客户端连接信息
# 生成时间: $(date)
# 优选域名: $optimized_domain
# ============================================

协议: $PROTOCOL
UUID: $uuid
端口: 443 (TLS) / 80 (非TLS)
路径: /$path
优选域名: $optimized_domain

EOF
    
    if [[ "$PROTOCOL" == "vless" ]]; then
        cat >> "$CONFIG_DIR/client-info.txt" << EOF
VLESS 链接 (TLS):
vless://$uuid@$optimized_domain:443?encryption=none&security=tls&type=ws&path=/$path#安全隧道_优选

VLESS 链接 (非TLS):
vless://$uuid@$optimized_domain:80?encryption=none&security=none&type=ws&path=/$path#安全隧道_优选
EOF
    fi
    
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR"
    chmod 640 "$CONFIG_DIR"/*
    
    print_success "隧道配置完成 (使用优选域名: $optimized_domain)"
}

setup_services() {
    print_info "配置系统服务..."
    
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

[Install]
WantedBy=multi-user.target
EOF
    
    cat > /etc/systemd/system/secure-tunnel-argo.service << EOF
[Unit]
Description=Secure Tunnel Argo Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$BIN_DIR/cloudflared tunnel --edge-ip-version $ARGO_IP_VERSION run --token \$(cat $CONFIG_DIR/argo-token.txt 2>/dev/null || echo "")
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable secure-tunnel-xray.service
    
    print_success "系统服务配置完成"
    print_info "请手动获取Argo Token并保存到 $CONFIG_DIR/argo-token.txt"
    print_info "运行: sudo -u $SERVICE_USER cloudflared tunnel token <隧道ID>"
}

# ----------------------------
# 管理函数
# ----------------------------
show_status() {
    echo -e "\n${BLUE}=== 服务状态 ===${NC}"
    systemctl status secure-tunnel-xray.service --no-pager 2>/dev/null || echo "Xray服务未运行"
    
    echo -e "\n${BLUE}=== 连接信息 ===${NC}"
    if [[ -f "$CONFIG_DIR/client-info.txt" ]]; then
        cat "$CONFIG_DIR/client-info.txt"
    else
        echo "未找到连接信息"
    fi
    
    echo -e "\n${BLUE}=== 优选域名缓存 ===${NC}"
    if ls "$CACHE_DIR"/*.cache 2>/dev/null; then
        for cache in "$CACHE_DIR"/*.cache; do
            echo "$(basename "$cache"): $(head -1 "$cache")"
        done
    else
        echo "无缓存"
    fi
}

uninstall_all() {
    print_warning "准备卸载所有组件..."
    
    read -r -p "确定要完全卸载吗？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0
    
    systemctl stop secure-tunnel-xray.service 2>/dev/null || true
    systemctl stop secure-tunnel-argo.service 2>/dev/null || true
    systemctl disable secure-tunnel-xray.service 2>/dev/null || true
    systemctl disable secure-tunnel-argo.service 2>/dev/null || true
    
    rm -f /etc/systemd/system/secure-tunnel-*.service
    systemctl daemon-reload
    
    rm -f "$BIN_DIR/xray" "$BIN_DIR/cloudflared" 2>/dev/null || true
    rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" 2>/dev/null || true
    
    if id -u "$SERVICE_USER" &> /dev/null; then
        if ! pgrep -u "$SERVICE_USER" > /dev/null; then
            userdel "$SERVICE_USER" 2>/dev/null || true
            groupdel "$SERVICE_GROUP" 2>/dev/null || true
        fi
    fi
    
    print_success "卸载完成"
}

# ----------------------------
# 主菜单和主函数
# ----------------------------
show_menu() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════╗"
    echo "║    安全隧道部署与管理工具 v2.1           ║"
    echo "║    🔥 新增Cloudflare节点优选功能        ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "1. 完整安装 (包含优选域名)"
    echo "2. 测试并优选域名"
    echo "3. 查看状态和连接信息"
    echo "4. 清理优选缓存"
    echo "5. 卸载所有组件"
    echo "0. 退出"
    echo ""
}

optimize_domain_action() {
    local action=${1:-"test"}
    
    case "$action" in
        "test") show_domain_test ;;
        "auto") select_best_domain "4" > /dev/null ;;
        "clean") rm -rf "$CACHE_DIR"/*.cache 2>/dev/null ;;
        "list") for domain in "${CF_TEST_DOMAINS[@]}"; do echo "  $domain"; done ;;
        *) print_error "未知操作" ;;
    esac
}

main() {
    trap cleanup_on_fail ERR
    
    case "${1:-}" in
        "install")
            check_root
            check_system
            setup_user
            install_components
            optimize_domain_action "auto"
            configure_tunnel
            setup_services
            show_status
            ;;
        "optimize")
            optimize_domain_action "${2:-test}"
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
                read -r -p "请选择操作: " choice
                
                case $choice in
                    1) 
                        check_root
                        check_system
                        setup_user
                        install_components
                        optimize_domain_action "auto"
                        configure_tunnel
                        setup_services
                        show_status
                        ;;
                    2) 
                        optimize_domain_action "test"
                        ;;
                    3) 
                        show_status
                        ;;
                    4) 
                        optimize_domain_action "clean"
                        print_success "缓存已清理"
                        ;;
                    5) 
                        uninstall_all
                        exit 0
                        ;;
                    0) 
                        print_info "退出"
                        exit 0
                        ;;
                    *) 
                        print_error "无效选择"
                        ;;
                esac
                
                echo "" && read -r -p "按回车键继续..."
            done
            ;;
    esac
}

# 运行主函数
main "$@"
