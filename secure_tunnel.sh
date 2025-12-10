#!/bin/bash
# ============================================
# Cloudflare Tunnel + Xray 安全增强部署脚本 v2.1
# 新增：智能Cloudflare节点优选功能
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

# 优选域名相关配置
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

readonly CF_TEST_COUNT=3  # 每个域名测试次数
readonly CF_TIMEOUT=2     # 测试超时时间(秒)
readonly CACHE_EXPIRE=3600 # 缓存有效期(秒)

# ----------------------------
# 新增：优选域名模块
# ----------------------------
test_domain_latency() {
    local domain=$1
    local ip_version=$2
    local total_latency=0
    local success_count=0
    
    print_debug "测试域名: $domain (IPv$ip_version)"
    
    for ((i=1; i<=CF_TEST_COUNT; i++)); do
        local latency
        local curl_cmd="curl -s -o /dev/null"
        
        # 根据IP版本设置curl参数
        if [[ $ip_version == "4" ]]; then
            curl_cmd+=" -4"
        elif [[ $ip_version == "6" ]]; then
            curl_cmd+=" -6"
        fi
        
        curl_cmd+=" -w '%{time_total}' --connect-timeout $CF_TIMEOUT --max-time $((CF_TIMEOUT+1))"
        
        # 测试延迟
        latency=$(eval "$curl_cmd https://$domain/cdn-cgi/trace 2>/dev/null || echo '0'")
        
        if [[ "$latency" != "0" ]] && [[ "$latency" =~ ^[0-9.]+$ ]]; then
            total_latency=$(echo "$total_latency + $latency" | bc -l)
            success_count=$((success_count + 1))
            print_debug "  第${i}次测试: ${latency}s"
        else
            print_debug "  第${i}次测试: 超时"
        fi
    done
    
    if [[ $success_count -gt 0 ]]; then
        local avg_latency
        avg_latency=$(echo "scale=3; $total_latency / $success_count" | bc -l)
        echo "$avg_latency"
        return 0
    else
        echo "999.999"
        return 1
    fi
}

select_best_domain() {
    local ip_version=${1:-"4"}
    local cache_file="$CACHE_DIR/best_domain_ipv${ip_version}.cache"
    
    # 检查缓存是否有效
    if [[ -f "$cache_file" ]]; then
        local cache_time
        local current_time
        local cached_domain
        
        cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
        current_time=$(date +%s)
        cached_domain=$(cat "$cache_file" 2>/dev/null | head -1)
        
        if [[ $((current_time - cache_time)) -lt $CACHE_EXPIRE ]] && \
           [[ -n "$cached_domain" ]]; then
            print_success "使用缓存的最佳域名: $cached_domain"
            echo "$cached_domain"
            return 0
        fi
    fi
    
    print_info "开始测试Cloudflare节点延迟 (IPv$ip_version)..."
    print_info "测试域名数量: ${#CF_TEST_DOMAINS[@]}个"
    
    # 创建结果数组
    declare -A domain_results
    local domain
    local latency
    
    # 并行测试所有域名
    for domain in "${CF_TEST_DOMAINS[@]}"; do
        (
            latency=$(test_domain_latency "$domain" "$ip_version")
            domain_results["$domain"]=$latency
            print_info "域名 $domain 平均延迟: ${latency}s"
        ) &
    done
    wait
    
    # 找出延迟最低的域名
    local best_domain=""
    local best_latency="999.999"
    
    for domain in "${!domain_results[@]}"; do
        latency=${domain_results["$domain"]}
        
        # 使用bc进行浮点数比较
        if (( $(echo "$latency < $best_latency" | bc -l) )); then
            best_latency=$latency
            best_domain=$domain
        fi
    done
    
    if [[ -n "$best_domain" ]] && [[ "$best_latency" != "999.999" ]]; then
        # 保存到缓存
        mkdir -p "$CACHE_DIR"
        echo "$best_domain" > "$cache_file"
        echo "$best_latency" >> "$cache_file"
        date +%s >> "$cache_file"
        
        print_success "优选完成！最佳域名: $best_domain (延迟: ${best_latency}s)"
        echo "$best_domain"
        return 0
    else
        print_error "所有域名测试失败，使用默认域名"
        echo "speed.cloudflare.com"
        return 1
    fi
}

show_domain_test() {
    print_info "正在测试Cloudflare节点..."
    echo ""
    
    local ip_versions=("4" "6")
    local best_domains=()
    
    for version in "${ip_versions[@]}"; do
        print_info "IPv$version 测试结果:"
        echo "----------------------------------------"
        
        for domain in "${CF_TEST_DOMAINS[@]:0:5}"; do # 只测试前5个显示
            latency=$(test_domain_latency "$domain" "$version")
            if [[ "$latency" == "999.999" ]]; then
                echo -e "  ${RED}✗${NC} $domain: 超时"
            else
                printf "  ${GREEN}✓${NC} %-30s: %.3f 秒\n" "$domain" "$latency"
            fi
        done
        
        best_domain=$(select_best_domain "$version")
        best_domains+=("$best_domain")
        
        echo ""
    done
    
    print_success "IPv4最佳域名: ${best_domains[0]}"
    print_success "IPv6最佳域名: ${best_domains[1]:-未测试}"
    
    # 生成优选配置文件
    cat > "$CONFIG_DIR/optimized_domains.conf" << EOF
# Cloudflare优选域名配置
# 生成时间: $(date)
# 
# 自动优选的最佳域名 (IPv4): ${best_domains[0]}
# 自动优选的最佳域名 (IPv6): ${best_domains[1]:-未测试}
# 
# 如需手动指定，请修改下面的 DOMAIN_IPV4 和 DOMAIN_IPV6

DOMAIN_IPV4="${best_domains[0]}"
DOMAIN_IPV6="${best_domains[1]:-${best_domains[0]}}"
EOF
    
    print_success "优选配置已保存至: $CONFIG_DIR/optimized_domains.conf"
}

# ----------------------------
# 修改配置生成函数以使用优选域名
# ----------------------------
configure_tunnel() {
    print_info "配置隧道参数..."
    
    # 生成UUID和端口
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)
    local path="${uuid%%-*}"
    local port=$((RANDOM % 10000 + 20000))
    
    # 获取优选域名
    local optimized_domain
    if [[ -f "$CONFIG_DIR/optimized_domains.conf" ]]; then
        optimized_domain=$(grep '^DOMAIN_IPV4=' "$CONFIG_DIR/optimized_domains.conf" | cut -d'"' -f2)
    fi
    
    # 如果没有优选域名，则自动优选一个
    if [[ -z "$optimized_domain" ]]; then
        print_info "未找到优选域名，开始自动优选..."
        optimized_domain=$(select_best_domain "4")
    fi
    
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
    
    # 保存连接信息（使用优选域名）
    cat > "$CONFIG_DIR/client-info.txt" << EOF
# ============================================
# 安全隧道客户端连接信息
# 生成时间: $(date)
# 优选域名: $optimized_domain (延迟最低)
# ============================================

协议: $PROTOCOL
UUID: $uuid
端口: 443 (TLS) / 80 (非TLS)
路径: /$path
优选域名: $optimized_domain

EOF
    
    # 生成客户端配置链接
    if [[ "$PROTOCOL" == "vless" ]]; then
        cat >> "$CONFIG_DIR/client-info.txt" << EOF
VLESS 链接 (TLS):
vless://$uuid@$optimized_domain:443?encryption=none&security=tls&type=ws&path=/$path#安全隧道_优选

VLESS 链接 (非TLS):
vless://$uuid@$optimized_domain:80?encryption=none&security=none&type=ws&path=/$path#安全隧道_优选
EOF
    elif [[ "$PROTOCOL" == "vmess" ]]; then
        local vmess_config
        vmess_config=$(cat <<EOF
{
  "v": "2",
  "ps": "安全隧道_优选",
  "add": "$optimized_domain",
  "port": "443",
  "id": "$uuid",
  "aid": "0",
  "scy": "none",
  "net": "ws",
  "type": "none",
  "host": "",
  "path": "/$path",
  "tls": "tls",
  "sni": ""
}
EOF
        )
        local vmess_base64
        vmess_base64=$(echo "$vmess_config" | base64 -w 0)
        cat >> "$CONFIG_DIR/client-info.txt" << EOF

VMESS 链接 (TLS):
vmess://$vmess_base64
EOF
    fi
    
    # 生成客户端配置文件
    cat > "$CONFIG_DIR/client.json" << EOF
{
    "备注": "安全隧道客户端配置 - 使用优选域名: $optimized_domain",
    "协议": "$PROTOCOL",
    "地址": "$optimized_domain",
    "端口": 443,
    "用户ID": "$uuid",
    "传输协议": "ws",
    "路径": "/$path",
    "底层传输安全": "tls",
    "允许不安全": false,
    "备注": "自动生成于 $(date)"
}
EOF
    
    # 设置权限
    chown "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR"/*
    chmod 640 "$CONFIG_DIR"/*
    
    print_success "隧道配置完成 (使用优选域名: $optimized_domain)"
}

# ----------------------------
# 新增管理命令
# ----------------------------
optimize_domain() {
    print_info "执行Cloudflare域名优选..."
    
    local action=${1:-"test"}
    
    case "$action" in
        "test")
            show_domain_test
            ;;
        "auto")
            local best_domain
            best_domain=$(select_best_domain "4")
            print_success "自动优选完成: $best_domain"
            echo "$best_domain"
            ;;
        "clean")
            rm -rf "$CACHE_DIR"/*.cache 2>/dev/null
            print_success "优选缓存已清理"
            ;;
        "list")
            print_info "当前测试域名列表:"
            for domain in "${CF_TEST_DOMAINS[@]}"; do
                echo "  $domain"
            done
            ;;
        *)
            print_error "未知操作: $action"
            print_info "可用操作: test, auto, clean, list"
            ;;
    esac
}

# ----------------------------
# 修改主菜单
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
    echo "2. 仅测试并优选域名"
    echo "3. 重新测试域名"
    echo "4. 查看状态和连接信息"
    echo "5. 查看优选域名列表"
    echo "6. 清理优选缓存"
    echo "7. 卸载所有组件"
    echo "0. 退出"
    echo ""
}

# ----------------------------
# 修改主函数
# ----------------------------
main() {
    # 创建必要的目录
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$CACHE_DIR"
    
    case "${1:-}" in
        "install")
            check_root
            check_system
            setup_user
            install_components
            optimize_domain "auto"
            configure_tunnel
            setup_services
            show_status
            ;;
        "optimize")
            optimize_domain "${2:-test}"
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
                        print_info "开始优选域名..."
                        optimize_domain "auto"
                        configure_tunnel
                        setup_services
                        show_status
                        ;;
                    2) 
                        show_domain_test
                        ;;
                    3)
                        rm -f "$CACHE_DIR"/*.cache 2>/dev/null
                        optimize_domain "auto"
                        ;;
                    4) 
                        show_status
                        ;;
                    5)
                        optimize_domain "list"
                        ;;
                    6)
                        optimize_domain "clean"
                        ;;
                    7)
                        uninstall_all
                        ;;
                    0) 
                        print_info "退出"
                        exit 0
                        ;;
                    *) 
                        print_error "无效选择"
                        ;;
                esac
                
                echo ""
                read -r -p "按回车键继续..."
            done
            ;;
    esac
}

# 以下函数保持不变（需要从之前的脚本复制）：
# check_root(), check_system(), setup_user(), 
# safe_download(), cleanup_on_fail(), install_components(),
# setup_services(), show_status(), uninstall_all()

# 确保所有需要的函数都存在
if ! declare -f check_root > /dev/null; then
    # 这里需要你补充之前版本的其他函数
    # 由于篇幅限制，我假设你保留了之前版本的所有函数
    print_warning "注意：需要从之前的脚本版本复制所有辅助函数"
fi

# 运行主函数
main "$@"
