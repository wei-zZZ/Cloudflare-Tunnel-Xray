#!/bin/bash
# ====================================================
# Cloudflare Tunnel + X-UI 安装脚本（带卸载功能）
# 版本: 2.1 - 修复授权问题 + 完整卸载
# ====================================================
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
print_config() { echo -e "${CYAN}[⚙️]${NC} $1"; }
print_step() { echo -e "${GREEN}[→]${NC} $1"; }

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/cf_tunnel"
LOG_DIR="/var/log/cf_tunnel"
BIN_DIR="/usr/local/bin"

USER_DOMAIN=""
TUNNEL_NAME="cf-proxy-tunnel"
PROXY_PORT=10086
PANEL_PORT=54321
WS_PATH="/proxy"
TUNNEL_ID=""
CERT_DIR="/root/.cloudflared"

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    clear
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 管理脚本                ║"
    echo "║           带完整卸载功能                    ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
    echo "1. 全新安装 Cloudflare Tunnel + X-UI"
    echo "2. 仅修复授权问题（重新授权）"
    echo "3. 完全卸载（删除所有文件和服务）"
    echo "4. 查看当前状态"
    echo "5. 退出"
    echo ""
    print_input "请选择操作 (1-5): "
    read -r choice
    echo ""
    
    case $choice in
        1) main_install ;;
        2) fix_auth_only ;;
        3) uninstall_all ;;
        4) show_status ;;
        5) exit 0 ;;
        *) print_error "无效选择"; sleep 2; show_menu ;;
    esac
}

# ----------------------------
# 修复授权问题（单独功能）
# ----------------------------
fix_auth_only() {
    print_step "修复 Cloudflare 授权问题"
    echo ""
    
    # 清理所有旧的授权文件
    print_info "清理旧的授权文件..."
    rm -rf "$CERT_DIR" 2>/dev/null
    rm -rf /root/.cloudflared 2>/dev/null
    sleep 2
    
    # 检查 cloudflared 是否安装
    if [ ! -f "$BIN_DIR/cloudflared" ]; then
        print_error "cloudflared 未安装，请先运行全新安装"
        sleep 3
        show_menu
        return
    fi
    
    # 获取域名（如果已存在配置）
    if [ -f "$CONFIG_DIR/config.yml" ]; then
        USER_DOMAIN=$(grep -oP "hostname: \K[^ ]+" "$CONFIG_DIR/config.yml" | head -1)
        if [ -n "$USER_DOMAIN" ]; then
            print_info "从配置文件找到域名: $USER_DOMAIN"
        fi
    fi
    
    if [ -z "$USER_DOMAIN" ]; then
        print_input "请输入您的域名 (例如: tunnel.yourdomain.com): "
        read -r USER_DOMAIN
    fi
    
    # 运行授权命令
    echo ""
    print_info "开始 Cloudflare 授权..."
    echo "=============================================="
    print_config "重要：请确保您有 $USER_DOMAIN 域名的管理权限"
    print_config "如果域名不在当前账户，请先添加到Cloudflare"
    echo "=============================================="
    echo ""
    print_input "按回车开始授权..."
    read -r
    
    # 运行授权
    echo ""
    echo "正在打开授权页面..."
    echo "如果浏览器没有自动打开，请手动复制下面的链接："
    echo ""
    
    # 运行授权并显示链接
    if ! "$BIN_DIR/cloudflared" tunnel login; then
        echo ""
        print_error "授权命令执行失败"
        echo ""
        print_info "尝试替代方案："
        echo "1. 请访问: https://dash.cloudflare.com/"
        echo "2. 进入您的域名"
        echo "3. 在左侧菜单找到「Access」→「Tunnels」"
        echo "4. 点击「Create a tunnel」生成证书"
        echo ""
        print_input "手动操作完成后按回车继续..."
        read -r
    fi
    
    # 验证授权结果
    echo ""
    print_info "验证授权结果..."
    
    local cert_count=0
    if [ -d "$CERT_DIR" ]; then
        cert_count=$(ls "$CERT_DIR"/*.json 2>/dev/null | wc -l)
    fi
    
    if [ "$cert_count" -gt 0 ]; then
        print_success "授权成功！找到 $cert_count 个证书文件"
        
        # 显示证书文件
        echo ""
        print_info "证书文件列表:"
        ls -la "$CERT_DIR"/*.json 2>/dev/null || echo "无"
        
        # 尝试重启服务
        if systemctl is-active --quiet cloudflared 2>/dev/null; then
            print_info "重启 cloudflared 服务..."
            systemctl restart cloudflared
            sleep 3
            
            if systemctl is-active --quiet cloudflared; then
                print_success "服务重启成功"
            else
                print_warning "服务重启失败，请手动检查"
            fi
        fi
    else
        print_error "未找到证书文件，授权可能失败"
        print_info "请检查:"
        echo "1. 是否正确登录Cloudflare账户"
        echo "2. 是否选择了正确的域名"
        echo "3. 是否点击了「授权」按钮"
        
        # 提供手动解决方案
        echo ""
        print_warning "手动解决方案："
        echo "1. 访问: https://dash.cloudflare.com/"
        echo "2. 进入「Zero Trust」→「Access」→「Tunnels」"
        echo "3. 点击「Create Tunnel」"
        echo "4. 输入隧道名称，选择免费计划"
        echo "5. 保存后会显示「Install connector」"
        echo "6. 在「Run the connector」部分可以找到证书"
    fi
    
    echo ""
    print_input "按回车返回主菜单..."
    read -r
    show_menu
}

# ----------------------------
# 完全卸载功能
# ----------------------------
uninstall_all() {
    print_step "开始完全卸载"
    echo ""
    print_warning "⚠️  这将删除所有相关文件、配置和服务！"
    print_warning "   包括：Cloudflare Tunnel、X-UI、配置文件、证书等"
    echo ""
    
    print_input "确认要完全卸载吗？(y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "取消卸载"
        sleep 2
        show_menu
        return
    fi
    
    echo ""
    print_info "停止服务..."
    systemctl stop cloudflared 2>/dev/null
    systemctl stop x-ui 2>/dev/null
    
    print_info "禁用服务..."
    systemctl disable cloudflared 2>/dev/null
    systemctl disable x-ui 2>/dev/null
    
    print_info "删除服务文件..."
    rm -f /etc/systemd/system/cloudflared.service
    rm -f /etc/systemd/system/x-ui.service 2>/dev/null
    
    print_info "删除二进制文件..."
    rm -f "$BIN_DIR/cloudflared"
    rm -f "$BIN_DIR/xray" 2>/dev/null
    
    print_info "删除配置文件和目录..."
    rm -rf "$CONFIG_DIR"
    rm -rf "$LOG_DIR"
    rm -rf "$CERT_DIR"
    rm -rf /etc/x-ui 2>/dev/null
    rm -rf /usr/local/x-ui 2>/dev/null
    rm -rf /root/x-ui 2>/dev/null
    
    print_info "删除日志文件..."
    rm -rf /var/log/cloudflared* 2>/dev/null
    rm -rf /var/log/x-ui* 2>/dev/null
    
    print_info "清理系统配置..."
    systemctl daemon-reload
    
    # 检查是否删除干净
    echo ""
    print_info "验证卸载结果:"
    
    local remaining=0
    if [ -f "$BIN_DIR/cloudflared" ]; then
        print_warning "剩余文件: $BIN_DIR/cloudflared"
        remaining=1
    fi
    
    if [ -d "$CONFIG_DIR" ]; then
        print_warning "剩余目录: $CONFIG_DIR"
        remaining=1
    fi
    
    if [ -d "$CERT_DIR" ]; then
        print_warning "剩余证书: $CERT_DIR"
        remaining=1
    fi
    
    if systemctl list-unit-files | grep -q "cloudflared"; then
        print_warning "剩余服务: cloudflared"
        remaining=1
    fi
    
    if systemctl list-unit-files | grep -q "x-ui"; then
        print_warning "剩余服务: x-ui"
        remaining=1
    fi
    
    if [ "$remaining" -eq 0 ]; then
        print_success "✅ 完全卸载完成！所有文件和服务已清理。"
    else
        print_warning "⚠️  部分文件可能未完全删除，请手动检查。"
    fi
    
    echo ""
    print_input "按回车返回主菜单..."
    read -r
    show_menu
}

# ----------------------------
# 查看当前状态
# ----------------------------
show_status() {
    print_step "当前系统状态"
    echo ""
    
    echo "═══════════════════════════════════════════════"
    print_info "1. 服务状态:"
    echo "----------------------------------------"
    
    # cloudflared 状态
    if systemctl is-active --quiet cloudflared 2>/dev/null; then
        print_success "✓ cloudflared: 运行中"
    elif systemctl is-enabled --quiet cloudflared 2>/dev/null; then
        print_warning "○ cloudflared: 已启用但未运行"
    else
        print_error "✗ cloudflared: 未安装或未启用"
    fi
    
    # x-ui 状态
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        print_success "✓ x-ui: 运行中"
    elif systemctl is-enabled --quiet x-ui 2>/dev/null; then
        print_warning "○ x-ui: 已启用但未运行"
    else
        print_error "✗ x-ui: 未安装或未启用"
    fi
    
    echo ""
    print_info "2. 文件状态:"
    echo "----------------------------------------"
    
    # 检查关键文件
    local files=(
        "$BIN_DIR/cloudflared"
        "$CONFIG_DIR/config.yml"
        "$CERT_DIR/*.json"
        "/etc/systemd/system/cloudflared.service"
    )
    
    for file in "${files[@]}"; do
        if ls $file 2>/dev/null | grep -q .; then
            print_success "✓ $file: 存在"
        else
            print_error "✗ $file: 不存在"
        fi
    done
    
    echo ""
    print_info "3. 证书状态:"
    echo "----------------------------------------"
    
    if [ -d "$CERT_DIR" ]; then
        local cert_count=$(ls "$CERT_DIR"/*.json 2>/dev/null | wc -l)
        if [ "$cert_count" -gt 0 ]; then
            print_success "✓ 找到 $cert_count 个证书文件"
            echo "证书文件:"
            ls "$CERT_DIR"/*.json 2>/dev/null | head -3
        else
            print_error "✗ 证书目录存在但无证书文件"
        fi
    else
        print_error "✗ 证书目录不存在"
    fi
    
    echo ""
    print_info "4. 网络状态:"
    echo "----------------------------------------"
    
    # 检查端口
    local ports=("$PANEL_PORT" "80" "443")
    for port in "${ports[@]}"; do
        if ss -tulpn | grep -q ":$port "; then
            print_success "✓ 端口 $port: 被占用"
        else
            print_warning "○ 端口 $port: 空闲"
        fi
    done
    
    echo ""
    print_info "5. 配置文件内容:"
    echo "----------------------------------------"
    
    if [ -f "$CONFIG_DIR/config.yml" ]; then
        echo "配置文件: $CONFIG_DIR/config.yml"
        grep -E "(tunnel:|hostname:|path:|service:)" "$CONFIG_DIR/config.yml" | head -10
    else
        print_error "配置文件不存在"
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════"
    print_input "按回车返回主菜单..."
    read -r
    show_menu
}

# ----------------------------
# 改进的授权函数
# ----------------------------
cloudflare_auth_improved() {
    print_step "Cloudflare 账户授权（改进版）"
    echo ""
    
    # 先清理旧的
    print_info "清理旧授权..."
    rm -rf "$CERT_DIR" 2>/dev/null
    sleep 1
    
    # 提供详细指引
    print_info "授权指引："
    echo "1. 如果您看到链接，请复制到浏览器打开"
    echo "2. 登录您的 Cloudflare 账户"
    echo "3. 选择域名: $(print_config "$USER_DOMAIN")"
    echo "4. 点击「Authorize」或「授权」按钮"
    echo "5. 授权成功后返回终端"
    echo ""
    print_warning "注意：如果看不到链接，请按 Ctrl+C 然后选择手动方案"
    echo ""
    print_input "准备好后按回车开始..."
    read -r
    
    # 尝试授权
    echo ""
    echo "正在启动授权..."
    echo "=============================================="
    
    local auth_output
    if auth_output=$("$BIN_DIR/cloudflared" tunnel login 2>&1); then
        echo "$auth_output"
        print_success "授权命令执行成功"
    else
        print_warning "授权命令返回非零状态"
        echo "输出: $auth_output"
    fi
    
    echo "=============================================="
    echo ""
    
    # 检查结果
    print_info "检查授权结果..."
    
    local wait_time=30
    print_info "等待 $wait_time 秒让授权完成..."
    
    for i in $(seq 1 $wait_time); do
        if [ -d "$CERT_DIR" ] && [ "$(ls -A "$CERT_DIR"/*.json 2>/dev/null | wc -l)" -gt 0 ]; then
            print_success "✅ 授权成功！找到证书文件"
            local cert_file=$(ls -t "$CERT_DIR"/*.json | head -1)
            print_info "证书文件: $(basename "$cert_file")"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    
    # 如果超时还没找到证书
    print_error "授权超时，未找到证书文件"
    echo ""
    print_warning "可能的原因："
    echo "1. 没有正确点击授权按钮"
    echo "2. 域名不在当前Cloudflare账户"
    echo "3. 网络问题"
    echo ""
    print_info "手动解决方案："
    echo "1. 访问 https://dash.cloudflare.com/"
    echo "2. 进入 Zero Trust → Access → Tunnels"
    echo "3. 创建新隧道，选择「Free」计划"
    echo "4. 按提示操作，最后会显示证书位置"
    echo ""
    print_input "是否继续安装？(y/N): "
    read -r continue_install
    if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
        print_error "安装中止"
        exit 1
    fi
    
    return 1
}

# ----------------------------
# 修复证书获取逻辑
# ----------------------------
get_tunnel_certificate() {
    print_info "查找证书文件..."
    
    # 方法1：检查标准位置
    if [ -d "$CERT_DIR" ]; then
        local cert_files=($(ls "$CERT_DIR"/*.json 2>/dev/null))
        if [ ${#cert_files[@]} -gt 0 ]; then
            # 使用最新的证书文件
            local latest_cert=$(ls -t "$CERT_DIR"/*.json | head -1)
            TUNNEL_CERT_FILE="$latest_cert"
            TUNNEL_ID=$(basename "$latest_cert" .json)
            print_success "找到证书: $TUNNEL_ID"
            return 0
        fi
    fi
    
    # 方法2：检查其他可能位置
    local alt_locations=(
        "/root/.cloudflared"
        "/usr/local/etc/cloudflared"
        "/etc/cloudflared"
    )
    
    for location in "${alt_locations[@]}"; do
        if [ -d "$location" ]; then
            local certs=($(find "$location" -name "*.json" -type f 2>/dev/null))
            if [ ${#certs[@]} -gt 0 ]; then
                TUNNEL_CERT_FILE="${certs[0]}"
                TUNNEL_ID=$(basename "${certs[0]}" .json)
                print_success "在 $location 找到证书"
                return 0
            fi
        fi
    done
    
    # 方法3：手动创建证书（最后的手段）
    print_warning "未找到现有证书，尝试创建新隧道..."
    
    # 创建隧道
    local create_output
    create_output=$("$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME" 2>&1)
    echo "$create_output"
    
    # 从输出提取ID
    TUNNEL_ID=$(echo "$create_output" | grep -oP '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
    
    if [ -n "$TUNNEL_ID" ]; then
        TUNNEL_CERT_FILE="$CERT_DIR/$TUNNEL_ID.json"
        if [ -f "$TUNNEL_CERT_FILE" ]; then
            print_success "隧道创建成功: $TUNNEL_ID"
            return 0
        fi
    fi
    
    print_error "无法获取证书文件"
    return 1
}

# ----------------------------
# 主安装函数
# ----------------------------
main_install() {
    clear
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║           全新安装 Cloudflare Tunnel         ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
    
    # 检查系统
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 权限运行此脚本"
        exit 1
    fi
    
    # 收集配置
    collect_config_improved
    
    # 安装 cloudflared
    install_cloudflared_improved
    
    # 授权
    if ! cloudflare_auth_improved; then
        print_warning "授权存在问题，但继续安装流程..."
    fi
    
    # 获取证书
    if ! get_tunnel_certificate; then
        print_error "无法获取证书，安装中止"
        exit 1
    fi
    
    # 配置DNS
    setup_dns
    
    # 生成配置
    generate_config
    
    # 安装X-UI
    install_xui_improved
    
    # 创建服务
    create_services
    
    # 完成
    show_installation_complete
    
    print_input "按回车返回主菜单..."
    read -r
    show_menu
}

# ----------------------------
# 改进的收集配置
# ----------------------------
collect_config_improved() {
    print_step "收集配置信息"
    
    # 获取域名
    while [[ -z "$USER_DOMAIN" ]]; do
        print_input "请输入您的域名 (例如: tunnel.yourdomain.com): "
        read -r USER_DOMAIN
        
        if [[ -z "$USER_DOMAIN" ]]; then
            print_error "域名不能为空"
        elif [[ ! "$USER_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "域名格式不正确"
            USER_DOMAIN=""
        fi
    done
    
    echo ""
    print_success "配置完成:"
    print_config "域名: $USER_DOMAIN"
    print_config "WebSocket路径: $WS_PATH"
    print_config "代理端口: $PROXY_PORT"
    print_config "面板端口: $PANEL_PORT"
    echo ""
}

# ----------------------------
# 改进的cloudflared安装
# ----------------------------
install_cloudflared_improved() {
    print_step "安装 cloudflared"
    
    # 检查是否已安装
    if [ -f "$BIN_DIR/cloudflared" ]; then
        print_info "cloudflared 已安装，跳过"
        return
    fi
    
    local arch=$(uname -m)
    local cf_url=""
    
    case "$arch" in
        x86_64|amd64) cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
        aarch64|arm64) cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
        *) print_error "不支持的架构: $arch"; exit 1 ;;
    esac
    
    print_info "下载 cloudflared..."
    if curl -fsSL -o /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        
        # 验证
        if "$BIN_DIR/cloudflared" --version &>/dev/null; then
            print_success "安装成功"
        else
            print_error "安装验证失败"
        fi
    else
        print_error "下载失败"
        exit 1
    fi
}

# ----------------------------
# 配置DNS
# ----------------------------
setup_dns() {
    print_step "配置DNS路由"
    
    print_info "设置 DNS 记录: $USER_DOMAIN → $TUNNEL_NAME"
    
    if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN" 2>&1; then
        print_success "DNS配置成功"
    else
        print_warning "DNS配置可能失败，但继续安装"
    fi
    
    echo ""
}

# ----------------------------
# 生成配置文件
# ----------------------------
generate_config() {
    print_step "生成配置文件"
    
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    
    cat > "$CONFIG_DIR/config.yml" << EOF
# Cloudflare Tunnel 配置
# 生成时间: $(date)

tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_CERT_FILE

ingress:
  # 代理流量
  - hostname: $USER_DOMAIN
    path: $WS_PATH
    service: http://127.0.0.1:$PROXY_PORT
  
  # 其他所有流量返回404
  - service: http_status:404
EOF
    
    print_success "配置文件已生成: $CONFIG_DIR/config.yml"
}

# ----------------------------
# 改进的X-UI安装
# ----------------------------
install_xui_improved() {
    print_step "安装 X-UI 面板"
    
    # 检查是否已安装
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        print_info "X-UI 已安装，跳过"
        return
    fi
    
    print_info "下载安装脚本..."
    if bash <(curl -fsSL https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh); then
        print_success "X-UI 安装成功"
        
        # 修改端口（如果需要）
        if [ "$PANEL_PORT" != "54321" ]; then
            print_info "修改面板端口为: $PANEL_PORT"
            sed -i "s/54321/$PANEL_PORT/g" /etc/x-ui/x-ui.db 2>/dev/null || true
            systemctl restart x-ui 2>/dev/null
        fi
    else
        print_error "X-UI 安装失败"
        print_info "请手动安装: bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)"
    fi
}

# ----------------------------
# 创建服务
# ----------------------------
create_services() {
    print_step "创建系统服务"
    
    # cloudflared 服务
    cat > /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yml run
Restart=on-failure
RestartSec=5
StandardOutput=append:$LOG_DIR/cloudflared.log
StandardError=append:$LOG_DIR/cloudflared-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable cloudflared
    systemctl start cloudflared
    
    print_success "服务创建完成"
}

# ----------------------------
# 显示安装完成
# ----------------------------
show_installation_complete() {
    clear
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║           安装完成！                         ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
    
    # 获取服务器IP
    local server_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s6 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    print_success "✅ 安装完成"
    echo ""
    print_info "▸ 代理配置："
    echo "   地址: $USER_DOMAIN"
    echo "   端口: 443"
    echo "   路径: $WS_PATH"
    echo "   TLS: 开启"
    echo ""
    print_info "▸ 面板访问："
    echo "   URL: http://$server_ip:$PANEL_PORT"
    echo "   账号: admin"
    echo "   密码: admin"
    echo ""
    print_info "▸ 服务管理："
    echo "   systemctl status cloudflared"
    echo "   systemctl status x-ui"
    echo ""
    print_warning "⚠️  请立即修改面板默认密码！"
    echo ""
}

# ----------------------------
# 主程序入口
# ----------------------------
if [ "$#" -eq 1 ]; then
    case "$1" in
        "install") main_install ;;
        "uninstall") uninstall_all ;;
        "fixauth") fix_auth_only ;;
        "status") show_status ;;
        *) echo "Usage: $0 {install|uninstall|fixauth|status}"; exit 1 ;;
    esac
else
    show_menu
fi