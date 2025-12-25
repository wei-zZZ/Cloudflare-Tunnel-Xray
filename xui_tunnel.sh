#!/bin/bash
# ============================================
# Cloudflare Tunnel + X-UI 安装脚本（修复凭证问题）
# 版本: 6.0 - 修复凭证文件处理
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
PURPLE='\033[0;35m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }
print_node() { echo -e "${PURPLE}[🔗]${NC} $1"; }
print_input() { echo -e "${CYAN}[?]${NC} $1"; }

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/xui_tunnel"
LOG_DIR="/var/log/xui_tunnel"
BIN_DIR="/usr/local/bin"

# 用户配置
PANEL_DOMAIN=""
NODE_DOMAIN=""
PANEL_TUNNEL="xui-panel"
NODE_TUNNEL="xui-nodes"
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
    echo "║       版本: 6.0 (修复凭证问题)             ║"
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
    print_input "请输入面板隧道名称 [默认: xui-panel]:"
    read -r panel_tunnel
    PANEL_TUNNEL=${panel_tunnel:-"xui-panel"}
    
    print_input "请输入节点隧道名称 [默认: xui-nodes]:"
    read -r node_tunnel
    NODE_TUNNEL=${node_tunnel:-"xui-nodes"}
    
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
    echo "  面板隧道: $PANEL_TUNNEL"
    echo "  节点隧道: $NODE_TUNNEL"
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
        print_info "请确保已完成授权流程"
        return 1
    fi
    
    # 检查凭证文件
    local json_file=$(find /root/.cloudflared -name "*.json" -type f | head -1)
    if [[ -n "$json_file" && -f "$json_file" ]]; then
        print_success "✅ 找到凭证文件: $(basename "$json_file")"
        echo "CREDENTIALS_FILE=$json_file" > /tmp/cloudflare_credentials
    else
        print_warning "⚠️  未找到JSON凭证文件，将在创建隧道时生成"
        echo "CREDENTIALS_FILE=" > /tmp/cloudflare_credentials
    fi
    
    return 0
}

# ----------------------------
# 获取凭证文件
# ----------------------------
get_credentials_file() {
    local tunnel_name=$1
    
    # 首先检查是否已有该隧道的凭证文件
    local tunnel_file=$(find /root/.cloudflared -name "*${tunnel_name}*.json" -type f | head -1)
    
    if [[ -n "$tunnel_file" && -f "$tunnel_file" ]]; then
        echo "$tunnel_file"
        return 0
    fi
    
    # 如果没有特定隧道的文件，使用第一个找到的json文件
    local any_json=$(find /root/.cloudflared -name "*.json" -type f | head -1)
    
    if [[ -n "$any_json" && -f "$any_json" ]]; then
        echo "$any_json"
        return 0
    fi
    
    # 如果都没有，返回空
    echo ""
    return 1
}

# ----------------------------
# 创建隧道
# ----------------------------
create_tunnel() {
    local tunnel_name=$1
    local description=$2
    
    print_info "创建 $description 隧道: $tunnel_name"
    
    # 检查证书
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "未找到证书文件"
        return 1
    fi
    
    # 删除可能存在的同名隧道
    print_info "清理旧隧道..."
    "$BIN_DIR/cloudflared" tunnel delete -f "$tunnel_name" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    print_info "正在创建隧道..."
    if "$BIN_DIR/cloudflared" tunnel create "$tunnel_name" 2>&1 | tee /tmp/tunnel_create.log; then
        print_success "隧道创建命令执行成功"
        sleep 3
    else
        print_error "隧道创建失败"
        cat /tmp/tunnel_create.log
        return 1
    fi
    
    # 获取隧道ID
    local tunnel_info
    tunnel_info=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$tunnel_name" || true)
    
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
# 配置面板隧道
# ----------------------------
setup_panel_tunnel() {
    print_info "配置面板隧道: $PANEL_TUNNEL"
    
    # 创建隧道
    local panel_tunnel_id
    panel_tunnel_id=$(create_tunnel "$PANEL_TUNNEL" "面板")
    
    if [[ -z "$panel_tunnel_id" ]]; then
        print_error "面板隧道创建失败"
        return 1
    fi
    
    # 获取凭证文件
    local json_file
    json_file=$(get_credentials_file "$PANEL_TUNNEL")
    
    if [[ -z "$json_file" ]] || [[ ! -f "$json_file" ]]; then
        print_error "未找到凭证文件，尝试查找其他凭证..."
        
        # 列出所有凭证文件
        echo "当前凭证文件:"
        find /root/.cloudflared -name "*.json" -type f | xargs -I {} basename {} || echo "无"
        
        # 使用最新创建的凭证文件
        json_file=$(find /root/.cloudflared -name "*.json" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")
        
        if [[ -z "$json_file" ]] || [[ ! -f "$json_file" ]]; then
            print_error "❌ 无法找到任何凭证文件"
            return 1
        fi
    fi
    
    print_success "使用凭证文件: $(basename "$json_file")"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 保存配置
    cat > "$CONFIG_DIR/panel.conf" << EOF
# X-UI面板隧道配置
TUNNEL_ID=$panel_tunnel_id
TUNNEL_NAME=$PANEL_TUNNEL
DOMAIN=$PANEL_DOMAIN
CREDENTIALS_FILE=$json_file
XUI_PORT=54321
CREATED_DATE=$(date +"%Y-%m-%d %H:%M:%S")
EOF
    
    # 创建YAML配置文件
    cat > "$CONFIG_DIR/panel-config.yaml" << EOF
tunnel: $panel_tunnel_id
credentials-file: $json_file
logfile: $LOG_DIR/panel-tunnel.log
loglevel: info
ingress:
  - hostname: $PANEL_DOMAIN
    service: http://localhost:54321
  - service: http_status:404
EOF
    
    print_success "面板隧道配置完成"
    
    # 绑定DNS
    print_info "绑定域名 $PANEL_DOMAIN 到隧道..."
    if "$BIN_DIR/cloudflared" tunnel route dns "$PANEL_TUNNEL" "$PANEL_DOMAIN" 2>&1 | tee /tmp/dns_panel.log; then
        print_success "✅ DNS绑定成功"
    else
        print_warning "⚠️  DNS绑定可能失败，稍后可手动配置"
        cat /tmp/dns_panel.log | tail -5
    fi
    
    return 0
}

# ----------------------------
# 配置节点隧道
# ----------------------------
setup_node_tunnel() {
    print_info "配置节点隧道: $NODE_TUNNEL"
    
    # 创建隧道
    local node_tunnel_id
    node_tunnel_id=$(create_tunnel "$NODE_TUNNEL" "节点")
    
    if [[ -z "$node_tunnel_id" ]]; then
        print_error "节点隧道创建失败"
        return 1
    fi
    
    # 获取凭证文件
    local json_file
    json_file=$(get_credentials_file "$NODE_TUNNEL")
    
    if [[ -z "$json_file" ]] || [[ ! -f "$json_file" ]]; then
        print_error "未找到凭证文件，尝试查找其他凭证..."
        
        # 使用最新创建的凭证文件
        json_file=$(find /root/.cloudflared -name "*.json" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")
        
        if [[ -z "$json_file" ]] || [[ ! -f "$json_file" ]]; then
            print_error "❌ 无法找到任何凭证文件"
            return 1
        fi
    fi
    
    print_success "使用凭证文件: $(basename "$json_file")"
    
    # 保存配置
    cat > "$CONFIG_DIR/node.conf" << EOF
# X-UI节点隧道配置
TUNNEL_ID=$node_tunnel_id
TUNNEL_NAME=$NODE_TUNNEL
DOMAIN=$NODE_DOMAIN
CREDENTIALS_FILE=$json_file
NODE_PORTS=10000,10001,10002,10003,10004
CREATED_DATE=$(date +"%Y-%m-%d %H:%M:%S")
EOF
    
    # 创建YAML配置文件
    cat > "$CONFIG_DIR/node-config.yaml" << EOF
tunnel: $node_tunnel_id
credentials-file: $json_file
logfile: $LOG_DIR/node-tunnel.log
loglevel: info
ingress:
  - hostname: $NODE_DOMAIN
    service: http://localhost:10000
  - service: http_status:404
EOF
    
    print_success "节点隧道配置完成"
    
    # 绑定DNS
    print_info "绑定域名 $NODE_DOMAIN 到隧道..."
    if "$BIN_DIR/cloudflared" tunnel route dns "$NODE_TUNNEL" "$NODE_DOMAIN" 2>&1 | tee /tmp/dns_node.log; then
        print_success "✅ DNS绑定成功"
    else
        print_warning "⚠️  DNS绑定可能失败，稍后可手动配置"
        cat /tmp/dns_node.log | tail -5
    fi
    
    return 0
}

# ----------------------------
# 创建系统服务
# ----------------------------
create_services() {
    print_info "创建系统服务..."
    
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    
    # 面板隧道服务
    cat > /etc/systemd/system/xui-panel-tunnel.service << EOF
[Unit]
Description=X-UI Panel Cloudflare Tunnel
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/panel-config.yaml run
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/panel-service.log
StandardError=append:$LOG_DIR/panel-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # 节点隧道服务
    cat > /etc/systemd/system/xui-node-tunnel.service << EOF
[Unit]
Description=X-UI Nodes Cloudflare Tunnel
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/node-config.yaml run
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/node-service.log
StandardError=append:$LOG_DIR/node-error.log

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
    
    # 启动面板隧道服务
    print_info "启动面板隧道服务..."
    systemctl enable xui-panel-tunnel.service
    systemctl start xui-panel-tunnel.service
    
    sleep 2
    
    if systemctl is-active --quiet xui-panel-tunnel.service; then
        print_success "✅ 面板隧道服务启动成功"
    else
        print_error "❌ 面板隧道服务启动失败"
        journalctl -u xui-panel-tunnel.service -n 20 --no-pager
        return 1
    fi
    
    # 启动节点隧道服务
    print_info "启动节点隧道服务..."
    systemctl enable xui-node-tunnel.service
    systemctl start xui-node-tunnel.service
    
    sleep 2
    
    if systemctl is-active --quiet xui-node-tunnel.service; then
        print_success "✅ 节点隧道服务启动成功"
    else
        print_error "❌ 节点隧道服务启动失败"
        journalctl -u xui-node-tunnel.service -n 20 --no-pager
        return 1
    fi
    
    # 检查隧道状态
    print_info "检查隧道状态..."
    sleep 2
    
    echo ""
    print_info "隧道列表:"
    "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || {
        print_warning "无法获取隧道列表"
        echo "运行: $BIN_DIR/cloudflared tunnel list"
    }
    
    return 0
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
    
    print_node "🔗 节点配置信息:"
    print_node "   节点域名: $NODE_DOMAIN"
    print_node "   节点隧道: $NODE_TUNNEL"
    print_node "   连接端口: 443"
    print_node "   TLS: 自动由Cloudflare提供"
    echo ""
    
    print_info "🛠️  管理命令:"
    echo "  查看隧道状态: systemctl status xui-panel-tunnel"
    echo "  重启隧道服务: systemctl restart xui-panel-tunnel"
    echo "  查看隧道日志: journalctl -u xui-panel-tunnel -f"
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
    echo ""
    
    return 0
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    show_title
    
    print_info "开始安装 X-UI + Cloudflare Tunnel..."
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
    
    # 配置面板隧道
    print_info "配置面板隧道..."
    if ! setup_panel_tunnel; then
        print_error "面板隧道配置失败"
        return 1
    fi
    
    # 配置节点隧道
    print_info "配置节点隧道..."
    if ! setup_node_tunnel; then
        print_error "节点隧道配置失败"
        return 1
    fi
    
    # 创建系统服务
    create_services
    
    # 启动服务
    if ! start_services; then
        print_error "服务启动失败"
        return 1
    fi
    
    # 显示结果
    show_result
    
    print_success "🎊 安装完成！"
    
    return 0
}

# ----------------------------
# 手动修复函数
# ----------------------------
manual_fix() {
    echo ""
    print_info "手动修复隧道配置..."
    
    # 显示当前凭证文件
    echo ""
    print_info "当前凭证文件:"
    find /root/.cloudflared -name "*.json" -type f | xargs -I {} echo "  {}" || echo "  无"
    
    # 显示当前隧道
    echo ""
    print_info "当前隧道:"
    "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || echo "  无"
    
    # 询问用户凭证文件路径
    echo ""
    print_input "请输入凭证文件完整路径 (例如: /root/.cloudflared/xxx.json):"
    read -r json_file
    
    if [[ -z "$json_file" ]] || [[ ! -f "$json_file" ]]; then
        print_error "凭证文件不存在"
        return 1
    fi
    
    print_success "使用凭证文件: $json_file"
    
    # 询问隧道名称
    echo ""
    print_input "请输入面板隧道名称 [默认: xui-panel]:"
    read -r panel_tunnel
    PANEL_TUNNEL=${panel_tunnel:-"xui-panel"}
    
    print_input "请输入节点隧道名称 [默认: xui-nodes]:"
    read -r node_tunnel
    NODE_TUNNEL=${node_tunnel:-"xui-nodes"}
    
    # 询问域名
    echo ""
    print_input "请输入面板域名 (例如: kkui.9420ce.top):"
    read -r PANEL_DOMAIN
    
    print_input "请输入节点域名 (例如: proxy.kkui.9420ce.top):"
    read -r NODE_DOMAIN
    
    # 重新配置
    setup_panel_tunnel
    setup_node_tunnel
    
    # 重启服务
    systemctl daemon-reload
    systemctl restart xui-panel-tunnel.service
    systemctl restart xui-node-tunnel.service
    
    sleep 3
    
    if systemctl is-active --quiet xui-panel-tunnel.service; then
        print_success "✅ 修复成功！面板隧道已启动"
    else
        print_error "❌ 面板隧道仍然失败"
    fi
    
    if systemctl is-active --quiet xui-node-tunnel.service; then
        print_success "✅ 修复成功！节点隧道已启动"
    else
        print_error "❌ 节点隧道仍然失败"
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
    echo "  2) 手动修复凭证问题"
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
            manual_fix
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
            echo "面板隧道:"
            systemctl status xui-panel-tunnel.service --no-pager | head -5
            echo ""
            echo "节点隧道:"
            systemctl status xui-node-tunnel.service --no-pager | head -5
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        4)
            echo ""
            print_info "配置文件:"
            if [ -f "$CONFIG_DIR/panel.conf" ]; then
                echo "=== 面板配置 ==="
                cat "$CONFIG_DIR/panel.conf" 2>/dev/null || echo "无"
                echo ""
            fi
            
            if [ -f "$CONFIG_DIR/node.conf" ]; then
                echo "=== 节点配置 ==="
                cat "$CONFIG_DIR/node.conf" 2>/dev/null || echo "无"
            fi
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        5)
            print_info "重启所有服务..."
            systemctl restart x-ui
            systemctl restart xui-panel-tunnel.service
            systemctl restart xui-node-tunnel.service
            sleep 2
            print_success "服务已重启"
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        6)
            print_info "卸载隧道服务..."
            systemctl stop xui-panel-tunnel.service 2>/dev/null || true
            systemctl stop xui-node-tunnel.service 2>/dev/null || true
            systemctl disable xui-panel-tunnel.service 2>/dev/null || true
            systemctl disable xui-node-tunnel.service 2>/dev/null || true
            rm -f /etc/systemd/system/xui-panel-tunnel.service
            rm -f /etc/systemd/system/xui-node-tunnel.service
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
            manual_fix
            ;;
        "status")
            show_title
            echo "服务状态:"
            systemctl status x-ui --no-pager
            echo ""
            systemctl status xui-panel-tunnel.service --no-pager
            echo ""
            systemctl status xui-node-tunnel.service --no-pager
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo ./xui_fix.sh menu        # 显示菜单"
            echo "  sudo ./xui_fix.sh install     # 安装"
            echo "  sudo ./xui_fix.sh fix         # 手动修复"
            echo "  sudo ./xui_fix.sh status      # 查看状态"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"