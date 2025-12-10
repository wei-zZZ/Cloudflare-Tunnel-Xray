#!/bin/bash
# ============================================
# Cloudflare Tunnel 网络诊断脚本
# 版本: 1.0
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
BIN_DIR="/usr/local/bin"

# ----------------------------
# 检查服务状态
# ----------------------------
check_services() {
    print_info "═══════════════════════════════════════════════"
    print_info "         检查系统服务状态"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 检查 Xray 服务
    print_info "1. 检查 Xray 服务状态:"
    if systemctl is-active --quiet secure-tunnel-xray.service; then
        print_success "   ✅ Xray 服务正在运行"
        
        # 检查端口监听
        local xray_port=$(grep "^PORT=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
        xray_port=${xray_port:-10000}
        
        if netstat -tuln | grep ":$xray_port" | grep LISTEN > /dev/null; then
            print_success "   ✅ Xray 正在监听端口 $xray_port"
        else
            print_error "   ❌ Xray 未监听端口 $xray_port"
        fi
    else
        print_error "   ❌ Xray 服务未运行"
    fi
    
    echo ""
    
    # 检查 Argo Tunnel 服务
    print_info "2. 检查 Argo Tunnel 服务状态:"
    if systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "   ✅ Argo Tunnel 服务正在运行"
        
        # 检查 cloudflared 进程
        if pgrep -f "cloudflared tunnel" > /dev/null; then
            print_success "   ✅ cloudflared 进程正在运行"
            
            # 检查连接状态
            local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
            if [[ -n "$tunnel_id" ]]; then
                print_info "   📡 检查隧道连接状态..."
                "$BIN_DIR/cloudflared" tunnel info "$tunnel_id" 2>&1 | grep -E "(Status|Connections|Version)" || true
            fi
        else
            print_error "   ❌ cloudflared 进程未运行"
        fi
    else
        print_error "   ❌ Argo Tunnel 服务未运行"
    fi
    
    echo ""
    
    # 检查日志
    print_info "3. 检查服务日志:"
    print_info "   Xray 最近日志:"
    journalctl -u secure-tunnel-xray.service -n 5 --no-pager | tail -5 || true
    
    print_info "   Argo Tunnel 最近日志:"
    journalctl -u secure-tunnel-argo.service -n 5 --no-pager | tail -5 || true
}

# ----------------------------
# 检查配置文件
# ----------------------------
check_configs() {
    print_info "═══════════════════════════════════════════════"
    print_info "         检查配置文件"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 检查配置文件是否存在
    print_info "1. 检查配置文件:"
    if [[ -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_success "   ✅ 主配置文件存在"
        echo ""
        print_info "   配置内容:"
        grep -E "^(TUNNEL_ID|TUNNEL_NAME|DOMAIN|UUID|PORT|CERT_PATH)=" "$CONFIG_DIR/tunnel.conf" | while read line; do
            echo "     $line"
        done
    else
        print_error "   ❌ 主配置文件不存在"
    fi
    
    echo ""
    
    # 检查 Xray 配置
    print_info "2. 检查 Xray 配置:"
    if [[ -f "$CONFIG_DIR/xray.json" ]]; then
        print_success "   ✅ Xray 配置文件存在"
        
        # 检查配置格式
        if jq empty "$CONFIG_DIR/xray.json" 2>/dev/null; then
            print_success "   ✅ Xray 配置格式正确"
            
            # 显示关键配置
            local port=$(jq -r '.inbounds[0].port' "$CONFIG_DIR/xray.json" 2>/dev/null)
            local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/xray.json" 2>/dev/null)
            local path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$CONFIG_DIR/xray.json" 2>/dev/null)
            
            echo "    端口: $port"
            echo "    UUID: $uuid"
            echo "    路径: $path"
        else
            print_error "   ❌ Xray 配置格式错误"
        fi
    else
        print_error "   ❌ Xray 配置文件不存在"
    fi
    
    echo ""
    
    # 检查隧道配置
    print_info "3. 检查隧道配置:"
    if [[ -f "$CONFIG_DIR/config.yaml" ]]; then
        print_success "   ✅ 隧道配置文件存在"
        
        # 显示配置内容
        echo ""
        print_info "   配置内容:"
        cat "$CONFIG_DIR/config.yaml"
    else
        print_error "   ❌ 隧道配置文件不存在"
    fi
    
    echo ""
    
    # 检查证书
    print_info "4. 检查证书文件:"
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "   ✅ 证书文件存在"
        echo "    大小: $(ls -lh "/root/.cloudflared/cert.pem" | awk '{print $5}')"
        echo "    修改时间: $(stat -c %y "/root/.cloudflared/cert.pem" | cut -d'.' -f1)"
    else
        print_error "   ❌ 证书文件不存在"
    fi
    
    echo ""
    
    # 检查 JSON 凭证文件
    print_info "5. 检查隧道凭证文件:"
    local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    if [[ -n "$tunnel_id" ]]; then
        local json_file="/root/.cloudflared/${tunnel_id}.json"
        if [[ -f "$json_file" ]]; then
            print_success "   ✅ 隧道凭证文件存在: $json_file"
        else
            print_warning "   ⚠️  按隧道ID未找到文件，尝试其他位置..."
            
            # 查找其他可能的JSON文件
            local found_json=$(find /root/.cloudflared -name "*.json" -type f 2>/dev/null | head -1)
            if [[ -n "$found_json" ]]; then
                print_info "   ✅ 找到JSON文件: $found_json"
            else
                print_error "   ❌ 未找到任何JSON凭证文件"
            fi
        fi
    fi
}

# ----------------------------
# 检查网络连接
# ----------------------------
check_network() {
    print_info "═══════════════════════════════════════════════"
    print_info "         检查网络连接"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 获取域名
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -z "$domain" ]]; then
        print_error "无法获取域名信息"
        return
    fi
    
    print_info "1. DNS 解析测试:"
    print_info "   解析域名: $domain"
    
    local ip_list=$(dig +short "$domain" 2>/dev/null || nslookup "$domain" 2>/dev/null | grep Address | tail -1 | awk '{print $2}')
    
    if [[ -n "$ip_list" ]]; then
        print_success "   ✅ DNS 解析成功"
        echo "    IP地址: $ip_list"
        
        # 检查是否为Cloudflare IP
        for ip in $ip_list; do
            if [[ "$ip" =~ ^104\. || "$ip" =~ ^172\. ]]; then
                print_success "   ✅ IP $ip 是Cloudflare IP"
            else
                print_warning "   ⚠️  IP $ip 可能不是Cloudflare IP"
            fi
        done
    else
        print_error "   ❌ DNS 解析失败"
    fi
    
    echo ""
    
    print_info "2. 端口连通性测试:"
    print_info "   测试 Cloudflare 端口 (HTTPS 443):"
    
    if timeout 5 nc -z "$domain" 443; then
        print_success "   ✅ 443 端口可访问"
    else
        print_error "   ❌ 443 端口不可访问"
    fi
    
    print_info "   测试 Cloudflare 端口 (HTTP 80):"
    
    if timeout 5 nc -z "$domain" 80; then
        print_success "   ✅ 80 端口可访问"
    else
        print_warning "   ⚠️  80 端口不可访问（正常，Cloudflare可能重定向到443）"
    fi
    
    echo ""
    
    print_info "3. TLS/SSL 证书测试:"
    print_info "   检查 SSL 证书:"
    
    if timeout 5 openssl s_client -connect "$domain:443" -servername "$domain" < /dev/null 2>/dev/null | grep -q "Certificate chain"; then
        print_success "   ✅ SSL 证书有效"
        
        # 显示证书信息
        echo "   证书信息:"
        timeout 5 openssl s_client -connect "$domain:443" -servername "$domain" < /dev/null 2>/dev/null | \
            openssl x509 -noout -dates 2>/dev/null | while read line; do
            echo "     $line"
        done || true
    else
        print_error "   ❌ SSL 证书无效或无法连接"
    fi
    
    echo ""
    
    print_info "4. 本地服务测试:"
    local port=$(grep "^PORT=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    port=${port:-10000}
    
    print_info "   测试本地 Xray 端口 ($port):"
    
    if timeout 2 nc -z 127.0.0.1 "$port"; then
        print_success "   ✅ 本地端口 $port 可访问"
        
        # 测试 HTTP 响应
        print_info "   测试 HTTP 响应:"
        if timeout 2 curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$port" | grep -q "404"; then
            print_success "   ✅ Xray 服务响应正常 (返回404是正常的)"
        else
            print_warning "   ⚠️  Xray 服务响应异常"
        fi
    else
        print_error "   ❌ 本地端口 $port 不可访问"
    fi
}

# ----------------------------
# 检查 Cloudflare 配置
# ----------------------------
check_cloudflare() {
    print_info "═══════════════════════════════════════════════"
    print_info "         检查 Cloudflare 配置"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -z "$domain" ]]; then
        print_error "无法获取域名信息"
        return
    fi
    
    print_info "1. Cloudflare DNS 记录:"
    print_info "   域名: $domain"
    
    # 使用 curl 查询 Cloudflare DNS
    echo ""
    print_warning "注意：以下步骤需要您手动检查"
    echo ""
    print_info "请登录 Cloudflare 面板检查:"
    print_info "1. 进入 DNS 设置"
    print_info "2. 检查 $domain 的记录类型"
    print_info "3. 确保有 CNAME 记录指向:"
    print_info "   - 名称: $(echo "$domain" | cut -d'.' -f1)"
    print_info "   - 目标: ${TUNNEL_ID:-隧道ID}.cfargotunnel.com"
    print_info "   - 代理状态: 已代理 (橙色云朵)"
    
    echo ""
    
    print_info "2. Cloudflare Tunnel 状态:"
    print_info "   请访问: https://dash.cloudflare.com/"
    print_info "   导航到: Zero Trust → Networks → Tunnels"
    print_info "   检查隧道状态是否为 'Healthy'"
    print_info "   检查是否有活跃的连接"
    
    echo ""
    
    print_info "3. SSL/TLS 设置:"
    print_info "   请检查 SSL/TLS 设置:"
    print_info "   1. 加密模式: Full 或 Full (strict)"
    print_info "   2. 边缘证书: 确保已启用"
    print_info "   3. 始终使用 HTTPS: 建议开启"
}

# ----------------------------
# 常见问题解决方案
# ----------------------------
suggest_fixes() {
    print_info "═══════════════════════════════════════════════"
    print_info "         常见问题解决方案"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    print_warning "如果网络不通，请尝试以下解决方案:"
    echo ""
    
    print_info "方案 1: 重启服务"
    echo "  systemctl restart secure-tunnel-xray.service"
    echo "  systemctl restart secure-tunnel-argo.service"
    echo ""
    
    print_info "方案 2: 检查防火墙"
    echo "  # 检查防火墙状态"
    echo "  ufw status"
    echo "  firewall-cmd --list-all"
    echo ""
    echo "  # 如果需要开放端口"
    echo "  ufw allow 443/tcp"
    echo "  ufw allow 80/tcp"
    echo ""
    
    print_info "方案 3: 重新绑定域名"
    local tunnel_name=$(grep "^TUNNEL_NAME=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -n "$tunnel_name" ]] && [[ -n "$domain" ]]; then
        echo "  $BIN_DIR/cloudflared tunnel route dns $tunnel_name $domain"
    fi
    echo ""
    
    print_info "方案 4: 检查 Cloudflare DNS 配置"
    echo "  1. 登录 Cloudflare 面板"
    echo "  2. 检查 DNS 记录是否正确"
    echo "  3. 确保代理状态为橙色云朵"
    echo "  4. 检查 SSL/TLS 设置为 Full"
    echo ""
    
    print_info "方案 5: 查看详细日志"
    echo "  # 查看 Xray 日志"
    echo "  journalctl -u secure-tunnel-xray.service -f"
    echo ""
    echo "  # 查看 Argo Tunnel 日志"
    echo "  journalctl -u secure-tunnel-argo.service -f"
    echo ""
    echo "  # 实时查看隧道连接"
    echo "  $BIN_DIR/cloudflared tunnel info <tunnel-id>"
    echo ""
    
    print_info "方案 6: 重新创建隧道"
    echo "  # 删除旧隧道"
    echo "  $BIN_DIR/cloudflared tunnel delete <tunnel-name>"
    echo ""
    echo "  # 重新运行安装脚本"
    echo "  sudo $0 reinstall"
}

# ----------------------------
# 快速修复命令
# ----------------------------
quick_fix() {
    print_info "执行快速修复..."
    echo ""
    
    # 1. 重启服务
    print_info "1. 重启服务..."
    systemctl restart secure-tunnel-xray.service
    sleep 2
    systemctl restart secure-tunnel-argo.service
    sleep 3
    
    # 2. 检查服务状态
    print_info "2. 检查服务状态..."
    if systemctl is-active --quiet secure-tunnel-xray.service && systemctl is-active --quiet secure-tunnel-argo.service; then
        print_success "✅ 服务重启成功"
    else
        print_error "❌ 服务重启失败"
    fi
    
    # 3. 重新绑定域名
    local tunnel_name=$(grep "^TUNNEL_NAME=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -n "$tunnel_name" ]] && [[ -n "$domain" ]]; then
        print_info "3. 重新绑定域名..."
        "$BIN_DIR/cloudflared" tunnel route dns "$tunnel_name" "$domain"
    fi
    
    print_success "快速修复完成！"
    echo "等待1-2分钟让配置生效..."
}

# ----------------------------
# 重新安装
# ----------------------------
reinstall() {
    print_warning "⚠️  即将重新安装，这会删除现有配置并重新开始"
    print_input "确认要继续吗？(y/N): "
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_error "已取消"
        exit 0
    fi
    
    # 停止服务
    systemctl stop secure-tunnel-xray.service secure-tunnel-argo.service 2>/dev/null || true
    systemctl disable secure-tunnel-xray.service secure-tunnel-argo.service 2>/dev/null || true
    
    # 删除配置
    rm -rf "$CONFIG_DIR" "/root/.cloudflared"
    
    print_info "重新安装准备完成，请重新运行安装脚本"
}

# ----------------------------
# 主诊断函数
# ----------------------------
main_diagnose() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 网络诊断工具            ║"
    echo "║                版本 1.0                       ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    
    # 检查配置文件是否存在
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件，可能未安装或配置路径错误"
        exit 1
    fi
    
    print_info "开始诊断..."
    echo ""
    
    check_services
    check_configs
    check_network
    check_cloudflare
    suggest_fixes
    
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "         诊断完成"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    print_input "是否执行快速修复？(y/N): "
    read -r fix_confirm
    
    if [[ "$fix_confirm" == "y" || "$fix_confirm" == "Y" ]]; then
        quick_fix
    fi
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    case "${1:-}" in
        "diagnose")
            main_diagnose
            ;;
        "quick-fix")
            quick_fix
            ;;
        "reinstall")
            reinstall
            ;;
        "check-services")
            check_services
            ;;
        "check-configs")
            check_configs
            ;;
        "check-network")
            check_network
            ;;
        *)
            echo "使用方法:"
            echo "  sudo $0 diagnose      # 完整诊断"
            echo "  sudo $0 quick-fix     # 快速修复"
            echo "  sudo $0 reinstall     # 重新安装"
            echo "  sudo $0 check-services # 检查服务"
            echo "  sudo $0 check-configs  # 检查配置"
            echo "  sudo $0 check-network  # 检查网络"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"