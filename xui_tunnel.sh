#!/bin/bash
# ============================================
# X-UI + Cloudflare Tunnel 安装脚本
# 版本: 7.0 - 单隧道方案
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
CONFIG_DIR="/etc/xui_tunnel"
LOG_DIR="/var/log/xui_tunnel"
BIN_DIR="/usr/local/bin"
TUNNEL_NAME="xui-tunnel"
XUI_PANEL_PORT=54321
NODE_PORTS="10000,10001,10002,10003,10004"

# 用户配置
PANEL_DOMAIN=""
NODE_DOMAIN=""
XUI_USERNAME="admin"
XUI_PASSWORD="admin"

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    X-UI + Cloudflare Tunnel 安装脚本        ║"
    echo "║       版本: 7.0 (单隧道方案)               ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
}

# ----------------------------
# 收集用户信息
# ----------------------------
collect_user_info() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           配置信息收集"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 面板域名
    while true; do
        print_input "请输入面板访问域名 (例如: kkui.9420ce.top):"
        read -r PANEL_DOMAIN
        
        if [[ -z "$PANEL_DOMAIN" ]]; then
            print_error "域名不能为空！"
            continue
        fi
        
        if [[ "$PANEL_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "域名格式不正确！"
        fi
    done
    
    # 节点域名
    echo ""
    print_input "请输入节点访问域名 (直接回车使用: proxy.$PANEL_DOMAIN):"
    read -r NODE_DOMAIN
    
    if [[ -z "$NODE_DOMAIN" ]]; then
        NODE_DOMAIN="proxy.$PANEL_DOMAIN"
    fi
    
    # 隧道名称
    echo ""
    print_input "请输入隧道名称 [默认: xui-tunnel]:"
    read -r tunnel_name
    TUNNEL_NAME=${tunnel_name:-"xui-tunnel"}
    
    # X-UI凭据
    echo ""
    print_info "设置X-UI登录凭据:"
    print_input "管理员用户名 [默认: admin]:"
    read -r XUI_USERNAME
    XUI_USERNAME=${XUI_USERNAME:-"admin"}
    
    print_input "管理员密码 [默认: admin]:"
    read -r -s XUI_PASSWORD
    echo ""
    XUI_PASSWORD=${XUI_PASSWORD:-"admin"}
    
    # 确认信息
    echo ""
    print_success "配置确认:"
    echo "  面板域名: https://$PANEL_DOMAIN"
    echo "  节点域名: $NODE_DOMAIN"
    echo "  隧道名称: $TUNNEL_NAME"
    echo "  X-UI用户名: $XUI_USERNAME"
    echo ""
    
    return 0
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
    
    # 安装必要工具
    print_info "安装必要工具..."
    apt-get update -y
    
    local tools=("curl" "wget" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            apt-get install -y "$tool" 2>/dev/null || true
        fi
    done
    
    print_success "系统检查完成"
}

# ----------------------------
# 安装 X-UI
# ----------------------------
install_xui() {
    print_info "安装 X-UI 面板..."
    
    # 检查是否已安装
    if command -v x-ui &> /dev/null; then
        print_warning "X-UI 已安装，跳过安装步骤"
        return 0
    fi
    
    # 下载安装脚本
    print_info "下载 X-UI 安装脚本..."
    curl -L -o x-ui-install.sh https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh
    chmod +x x-ui-install.sh
    
    # 安装 X-UI
    print_info "正在安装 X-UI..."
    if bash x-ui-install.sh; then
        print_success "X-UI 安装成功"
    else
        print_error "X-UI 安装失败"
        return 1
    fi
    
    # 等待启动
    print_info "等待X-UI启动..."
    for i in {1..10}; do
        if systemctl is-active --quiet x-ui; then
            print_success "X-UI 服务已启动"
            break
        fi
        echo -n "."
        sleep 2
    done
    
    rm -f x-ui-install.sh
    
    return 0
}

# ----------------------------
# 安装 Cloudflared
# ----------------------------
install_cloudflared() {
    print_info "安装 Cloudflared..."
    
    # 检查是否已安装
    if command -v cloudflared &> /dev/null; then
        print_warning "cloudflared 已安装，跳过安装步骤"
        return 0
    fi
    
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64|amd64)
            local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    # 下载安装
    print_info "下载 cloudflared..."
    if curl -L -o /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        print_success "cloudflared 安装成功"
    else
        print_error "cloudflared 下载失败"
        exit 1
    fi
}

# ----------------------------
# Cloudflare 授权
# ----------------------------
cloudflare_auth() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "        Cloudflare 账户授权"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 清理旧授权
    rm -rf /root/.cloudflared 2>/dev/null || true
    mkdir -p /root/.cloudflared
    
    echo "授权步骤："
    echo "1. 复制下面的链接到浏览器"
    echo "2. 登录 Cloudflare 账户"
    echo "3. 选择域名并授权"
    echo "4. 返回终端继续"
    echo ""
    print_input "按回车键开始授权..."
    read -r
    
    echo ""
    echo "=============================================="
    echo "请复制以下链接到浏览器："
    echo ""
    
    # 执行授权
    if "$BIN_DIR/cloudflared" tunnel login 2>&1 | tee /tmp/auth_output.txt; then
        print_success "授权命令执行成功"
    else
        print_warning "授权可能有问题，检查输出..."
        cat /tmp/auth_output.txt
    fi
    
    echo ""
    echo "=============================================="
    print_input "完成授权后按回车继续..."
    read -r
    
    # 检查授权结果
    print_info "检查授权结果..."
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "✅ 找到证书文件"
    else
        print_error "❌ 未找到证书文件"
        return 1
    fi
    
    return 0
}

# ----------------------------
# 创建单隧道
# ----------------------------
create_single_tunnel() {
    print_info "创建 Cloudflare 隧道: $TUNNEL_NAME"
    
    # 检查证书
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "未找到证书文件"
        return 1
    fi
    
    # 删除可能存在的旧隧道
    print_info "清理旧隧道..."
    "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    print_info "正在创建隧道..."
    if "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME" 2>&1 | tee /tmp/tunnel_create.log; then
        print_success "隧道创建命令执行成功"
        sleep 3
    else
        print_error "隧道创建失败"
        cat /tmp/tunnel_create.log
        return 1
    fi
    
    # 获取隧道ID
    local tunnel_info
    tunnel_info=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || true)
    
    if [[ -n "$tunnel_info" ]]; then
        local tunnel_id=$(echo "$tunnel_info" | awk '{print $1}')
        print_success "✅ 隧道创建成功: $tunnel_id"
        echo "$tunnel_id"
        return 0
    else
        print_error "❌ 隧道创建后未找到"
        return 1
    fi
}

# ----------------------------
# 配置单隧道（处理面板+节点）
# ----------------------------
setup_single_tunnel() {
    print_info "配置单隧道..."
    
    # 创建隧道
    local tunnel_id
    tunnel_id=$(create_single_tunnel)
    
    if [[ -z "$tunnel_id" ]]; then
        print_error "隧道创建失败"
        return 1
    fi
    
    # 获取凭证文件
    local json_file=$(find /root/.cloudflared -name "*.json" -type f | head -1)
    
    if [[ -z "$json_file" ]] || [[ ! -f "$json_file" ]]; then
        print_error "❌ 未找到凭证文件"
        echo "当前凭证文件:"
        find /root/.cloudflared -name "*.json" -type f | xargs -I {} echo "  {}" || echo "  无"
        return 1
    fi
    
    print_success "使用凭证文件: $(basename "$json_file")"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 保存配置
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
# X-UI 隧道配置
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
PANEL_DOMAIN=$PANEL_DOMAIN
NODE_DOMAIN=$NODE_DOMAIN
CREDENTIALS_FILE=$json_file
XUI_PANEL_PORT=$XUI_PANEL_PORT
NODE_PORTS=$NODE_PORTS
XUI_USERNAME=$XUI_USERNAME
XUI_PASSWORD=$XUI_PASSWORD
CREATED_DATE=$(date +"%Y-%m-%d %H:%M:%S")
EOF
    
    # 创建多域名ingress配置
    cat > "$CONFIG_DIR/tunnel-config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: $json_file
logfile: $LOG_DIR/tunnel.log
loglevel: info

# ingress规则 - 支持多个域名
ingress:
  # 面板访问
  - hostname: $PANEL_DOMAIN
    service: http://localhost:$XUI_PANEL_PORT
  
  # 节点访问 - 主域名
  - hostname: $NODE_DOMAIN
    service: http://localhost:10000
  
  # 节点访问 - 子域名（备用）
  - hostname: "*.${NODE_DOMAIN#*.}"
    service: http://localhost:10001
  
  # 默认404
  - service: http_status:404
EOF
    
    print_success "隧道配置完成"
    
    # 绑定DNS
    print_info "绑定域名到隧道..."
    
    # 绑定面板域名
    if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$PANEL_DOMAIN" 2>&1 | tee /tmp/dns_panel.log; then
        print_success "✅ 面板域名绑定成功"
    else
        print_warning "⚠️  面板域名绑定可能失败"
    fi
    
    # 绑定节点域名
    if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$NODE_DOMAIN" 2>&1 | tee /tmp/dns_node.log; then
        print_success "✅ 节点域名绑定成功"
    else
        print_warning "⚠️  节点域名绑定可能失败"
    fi
    
    return 0
}

# ----------------------------
# 创建系统服务
# ----------------------------
create_service() {
    print_info "创建系统服务..."
    
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    
    # 隧道服务
    cat > /etc/systemd/system/xui-tunnel.service << EOF
[Unit]
Description=X-UI Cloudflare Tunnel (Panel + Nodes)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/tunnel-config.yaml run
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/tunnel-service.log
StandardError=append:$LOG_DIR/tunnel-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载systemd
    systemctl daemon-reload
    
    print_success "系统服务创建完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    # 启动X-UI
    if systemctl start x-ui; then
        print_success "✅ X-UI 服务启动成功"
    else
        print_error "❌ X-UI 服务启动失败"
        return 1
    fi
    
    # 启动隧道服务
    print_info "启动隧道服务..."
    systemctl enable xui-tunnel.service
    systemctl start xui-tunnel.service
    
    sleep 3
    
    if systemctl is-active --quiet xui-tunnel.service; then
        print_success "✅ 隧道服务启动成功"
    else
        print_error "❌ 隧道服务启动失败"
        journalctl -u xui-tunnel.service -n 20 --no-pager
        return 1
    fi
    
    # 检查隧道状态
    print_info "检查隧道状态..."
    sleep 2
    
    echo ""
    print_info "隧道列表:"
    "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || {
        print_warning "无法获取隧道列表"
    }
    
    return 0
}

# ----------------------------
# 测试连接
# ----------------------------
test_connections() {
    print_info "测试连接..."
    
    # 测试X-UI面板
    print_info "1. 测试X-UI面板本地连接..."
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:$XUI_PANEL_PORT; then
        print_success "✅ X-UI面板本地连接正常"
    else
        print_warning "⚠️  X-UI面板本地连接失败"
    fi
    
    # 测试隧道进程
    print_info "2. 检查隧道进程..."
    if pgrep -f "cloudflared.*tunnel" > /dev/null; then
        print_success "✅ 隧道进程运行中"
    else
        print_error "❌ 隧道进程未运行"
    fi
    
    echo ""
}

# ----------------------------
# 显示安装结果
# ----------------------------
show_result() {
    echo ""
    print_success "═══════════════════════════════════════════════"
    print_success "           安装完成！"
    print_success "═══════════════════════════════════════════════"
    echo ""
    
    print_success "🎉 面板访问地址:"
    print_success "   https://$PANEL_DOMAIN"
    echo ""
    
    print_success "🔐 面板登录凭据:"
    print_success "   用户名: $XUI_USERNAME"
    print_success "   密码: $XUI_PASSWORD"
    echo ""
    
    print_success "🔗 节点配置信息:"
    print_success "   节点域名: $NODE_DOMAIN"
    print_success "   可用端口: $NODE_PORTS"
    print_success "   连接端口: 443"
    print_success "   TLS: 自动由Cloudflare提供"
    echo ""
    
    print_info "🛠️  管理命令:"
    echo "  查看隧道状态: systemctl status xui-tunnel"
    echo "  重启隧道服务: systemctl restart xui-tunnel"
    echo "  查看隧道日志: journalctl -u xui-tunnel -f"
    echo ""
    
    print_info "📋 X-UI面板配置:"
    echo "  1. 访问 https://$PANEL_DOMAIN 登录"
    echo "  2. 在'入站列表'中创建节点"
    echo "  3. 使用端口: 10000-10004"
    echo "  4. 协议: VLESS/VMESS/Trojan + WS + TLS"
    echo "  5. 主机名: $NODE_DOMAIN"
    echo ""
    
    print_warning "⚠️  重要提示:"
    echo "  1. 首次登录后立即修改默认密码"
    echo "  2. 确保域名已正确解析到Cloudflare"
    echo "  3. 如果无法访问，等待DNS生效"
    echo "  4. 所有流量通过同一个隧道"
    echo ""
    
    return 0
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    show_title
    
    print_info "开始安装 X-UI + Cloudflare Tunnel (单隧道)..."
    echo ""
    
    # 执行安装步骤
    check_system
    collect_user_info
    install_xui
    install_cloudflared
    
    # Cloudflare授权
    print_info "进行Cloudflare授权..."
    if ! cloudflare_auth; then
        print_error "授权失败，安装中止"
        return 1
    fi
    
    # 配置单隧道
    print_info "配置单隧道..."
    if ! setup_single_tunnel; then
        print_error "隧道配置失败"
        return 1
    fi
    
    # 创建系统服务
    create_service
    
    # 启动服务
    if ! start_services; then
        print_error "服务启动失败"
        return 1
    fi
    
    # 测试连接
    test_connections
    
    # 显示结果
    show_result
    
    print_success "🎊 安装完成！"
    
    return 0
}

# ----------------------------
# 快速修复
# ----------------------------
quick_fix() {
    echo ""
    print_info "快速修复隧道问题..."
    
    # 停止服务
    systemctl stop xui-tunnel.service 2>/dev/null || true
    pkill -f cloudflared 2>/dev/null || true
    sleep 2
    
    # 检查证书
    if [ ! -f "/root/.cloudflared/cert.pem" ]; then
        print_error "未找到证书文件"
        print_info "重新授权..."
        cloudflare_auth
    fi
    
    # 重新配置
    if [ -f "$CONFIG_DIR/tunnel.conf" ]; then
        source "$CONFIG_DIR/tunnel.conf"
        
        # 重新创建配置文件
        cat > "$CONFIG_DIR/tunnel-config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE
logfile: $LOG_DIR/tunnel.log
loglevel: info
ingress:
  - hostname: $PANEL_DOMAIN
    service: http://localhost:$XUI_PANEL_PORT
  - hostname: $NODE_DOMAIN
    service: http://localhost:10000
  - service: http_status:404
EOF
        print_success "配置文件已修复"
    fi
    
    # 重启服务
    systemctl daemon-reload
    systemctl restart xui-tunnel.service
    
    sleep 3
    
    if systemctl is-active --quiet xui-tunnel.service; then
        print_success "✅ 修复成功！隧道服务已启动"
    else
        print_error "❌ 修复失败"
        journalctl -u xui-tunnel.service -n 20 --no-pager
    fi
}

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    show_title
    
    echo "请选择操作："
    echo ""
    echo "  1) 安装 X-UI + Cloudflare Tunnel"
    echo "  2) 快速修复隧道问题"
    echo "  3) 查看服务状态"
    echo "  4) 查看配置信息"
    echo "  5) 重启所有服务"
    echo "  6) 卸载隧道服务"
    echo "  7) 退出"
    echo ""
    
    print_input "请输入选项 (1-7): "
    read -r choice
    
    case "$choice" in
        1)
            if main_install; then
                echo ""
                print_input "按回车键返回菜单..."
                read -r
            else
                echo ""
                print_error "安装失败"
                print_input "按回车键返回菜单..."
                read -r
            fi
            ;;
        2)
            quick_fix
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        3)
            echo ""
            print_info "服务状态:"
            echo "X-UI面板:"
            systemctl status x-ui --no-pager | head -5
            echo ""
            echo "隧道服务:"
            systemctl status xui-tunnel.service --no-pager | head -5
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        4)
            echo ""
            print_info "配置文件:"
            if [ -f "$CONFIG_DIR/tunnel.conf" ]; then
                cat "$CONFIG_DIR/tunnel.conf"
                echo ""
                echo "YAML配置:"
                cat "$CONFIG_DIR/tunnel-config.yaml" 2>/dev/null || echo "无"
            else
                echo "未找到配置文件"
            fi
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        5)
            print_info "重启所有服务..."
            systemctl restart x-ui
            systemctl restart xui-tunnel.service
            sleep 2
            print_success "服务已重启"
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        6)
            print_info "卸载隧道服务..."
            systemctl stop xui-tunnel.service 2>/dev/null || true
            systemctl disable xui-tunnel.service 2>/dev/null || true
            rm -f /etc/systemd/system/xui-tunnel.service
            systemctl daemon-reload
            print_success "隧道服务已卸载"
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        7)
            print_info "再见！"
            exit 0
            ;;
        *)
            print_error "无效选项"
            sleep 1
            show_menu
            ;;
    esac
    
    show_menu
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    case "${1:-}" in
        "install")
            main_install
            ;;
        "fix")
            quick_fix
            ;;
        "status")
            show_title
            echo "服务状态:"
            systemctl status x-ui --no-pager
            echo ""
            systemctl status xui-tunnel.service --no-pager
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo ./xui_single.sh menu        # 显示菜单"
            echo "  sudo ./xui_single.sh install     # 安装"
            echo "  sudo ./xui_single.sh fix         # 快速修复"
            echo "  sudo ./xui_single.sh status      # 查看状态"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"