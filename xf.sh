#!/bin/bash
# ====================================================
# Cloudflare Tunnel 快速安装脚本
# 版本: 1.0 - 预设配置 + 域名设置
# 功能：仅询问域名和隧道名，其他全自动配置
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
print_config() { echo -e "${CYAN}[⚙️]${NC} $1"; }
print_step() { echo -e "${GREEN}[→]${NC} $1"; }
print_critical() { echo -e "${RED}[‼️]${NC} $1"; }

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/cf_tunnel"
LOG_DIR="/var/log/cf_tunnel"
BIN_DIR="/usr/local/bin"
CERT_DIR="/root/.cloudflared"

# 预设配置
USER_DOMAIN=""          # 用户输入
TUNNEL_NAME=""          # 用户输入
PANEL_PORT=54321

# 预设协议配置：协议:端口:路径
# 安装时会自动生成UUID和密码
PRESET_PROTOCOLS=(
    "vless:20001:/vless"
    "vmess:20002:/vmess" 
    "trojan:20003:/trojan"
)

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║      Cloudflare Tunnel 快速安装脚本                    ║"
    echo "║       仅需设置域名，其他全自动配置                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    print_info "📋 预设配置："
    echo "  • 自动创建3个代理协议：VLESS、VMESS、Trojan"
    echo "  • 端口：20001, 20002, 20003"
    echo "  • 路径：/vless, /vmess, /trojan"
    echo "  • X-UI面板端口：54321"
    echo ""
}

# ----------------------------
# 收集必要信息（仅域名和隧道名）
# ----------------------------
collect_basic_info() {
    print_step "1. 设置域名和隧道名称"
    echo ""
    
    print_critical "重要：请确保域名已添加到Cloudflare账户"
    echo ""
    
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
    
    # 获取隧道名称
    TUNNEL_NAME="cf-tunnel-$(date +%s | tail -c 4)"
    print_input "请输入隧道名称 [默认: $TUNNEL_NAME]: "
    read -r input_name
    TUNNEL_NAME=${input_name:-$TUNNEL_NAME}
    
    echo ""
    print_success "✅ 配置完成："
    print_config "域名: $USER_DOMAIN"
    print_config "隧道名称: $TUNNEL_NAME"
    echo ""
}

# ----------------------------
# 显示预设配置
# ----------------------------
show_preset_config() {
    print_step "2. 确认预设配置"
    echo ""
    
    print_info "📋 代理协议预设配置："
    echo "----------------------------------------"
    for i in "${!PRESET_PROTOCOLS[@]}"; do
        IFS=':' read -r protocol port path <<< "${PRESET_PROTOCOLS[$i]}"
        print_config "$((i+1)). $protocol - 端口: $port, 路径: $path"
    done
    echo "----------------------------------------"
    echo ""
    
    print_info "🎯 架构设计："
    echo "  • Cloudflare Tunnel 仅处理代理流量"
    echo "  • X-UI面板通过服务器IP直连访问"
    echo "  • 每个协议独立端口和路径"
    echo ""
    
    print_input "按回车开始安装，或按 Ctrl+C 取消..."
    read -r
}

# ----------------------------
# 系统检查
# ----------------------------
check_system() {
    print_step "3. 检查系统环境"
    
    # 安装必要工具
    local tools=("curl" "wget")
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "安装 $tool..."
            apt-get update -qq
            apt-get install -y -qq "$tool"
        fi
    done
    
    print_success "系统检查完成"
}

# ----------------------------
# 安装 cloudflared
# ----------------------------
install_cloudflared() {
    print_step "4. 安装 cloudflared"
    
    if [ -f "$BIN_DIR/cloudflared" ]; then
        print_info "cloudflared 已安装，跳过"
        return
    fi
    
    local arch=$(uname -m)
    local cf_url=""
    
    case "$arch" in
        x86_64|amd64)
            cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    print_info "下载 cloudflared..."
    if curl -fsSL -o /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        
        if "$BIN_DIR/cloudflared" --version &>/dev/null; then
            print_success "cloudflared 安装成功"
        else
            print_error "cloudflared 安装验证失败"
        fi
    else
        print_error "cloudflared 下载失败"
        exit 1
    fi
}

# ----------------------------
# Cloudflare 授权（强制显示链接）
# ----------------------------
cloudflare_auth_simple() {
    print_step "5. Cloudflare 账户授权"
    echo ""
    
    print_critical "⚠️  重要：请准备好复制授权链接"
    echo ""
    
    # 清理旧的授权文件
    rm -rf "$CERT_DIR" 2>/dev/null
    sleep 1
    
    print_info "正在获取授权链接..."
    echo ""
    echo "=============================================="
    
    # 运行授权命令并显示输出
    print_info "运行授权命令，请查看下面的链接："
    echo ""
    
    # 运行授权命令，强制显示输出
    timeout 30 "$BIN_DIR/cloudflared" tunnel login 2>&1 | head -20 || true
    
    echo ""
    echo "=============================================="
    echo ""
    
    print_info "如果上面没有显示链接，请运行以下命令获取："
    print_config "cloudflared tunnel login --url"
    echo ""
    
    print_info "授权步骤："
    echo "1. 复制链接到浏览器打开"
    echo "2. 登录 Cloudflare 账户"
    echo "3. 选择域名: $USER_DOMAIN"
    echo "4. 点击「Authorize」按钮"
    echo "5. 授权成功后返回终端"
    echo ""
    
    print_input "完成授权后按回车继续..."
    read -r
    
    # 检查授权结果
    print_info "检查授权结果..."
    sleep 3
    
    if [ -d "$CERT_DIR" ] && [ "$(ls -A "$CERT_DIR"/*.json 2>/dev/null | wc -l)" -gt 0 ]; then
        print_success "✅ 授权成功！找到证书文件"
        local cert_file=$(ls -t "$CERT_DIR"/*.json | head -1)
        print_info "证书文件: $(basename "$cert_file")"
        return 0
    else
        print_error "❌ 未找到证书文件，授权可能失败"
        echo ""
        print_warning "继续安装，但需要手动配置证书"
        return 1
    fi
}

# ----------------------------
# 创建隧道
# ----------------------------
create_tunnel_simple() {
    print_step "6. 创建 Cloudflare 隧道"
    
    # 删除可能存在的旧隧道
    "$BIN_DIR/cloudflared" tunnel delete "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    print_info "创建隧道: $TUNNEL_NAME"
    
    # 创建新隧道
    if timeout 60 "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"; then
        print_success "✅ 隧道创建成功"
    else
        print_warning "⚠️  隧道创建可能失败，尝试使用现有隧道"
    fi
    
    sleep 3
    
    # 获取隧道ID
    local tunnel_info=$("$BIN_DIR/cloudflared" tunnel list --name "$TUNNEL_NAME" 2>/dev/null || echo "")
    local tunnel_id=""
    
    if [ -n "$tunnel_info" ]; then
        tunnel_id=$(echo "$tunnel_info" | awk '{print $1}' | head -1)
    fi
    
    # 如果无法获取，尝试从证书文件获取
    if [ -z "$tunnel_id" ]; then
        local cert_file=$(ls -t "$CERT_DIR"/*.json 2>/dev/null | head -1)
        if [ -n "$cert_file" ]; then
            tunnel_id=$(basename "$cert_file" .json)
        fi
    fi
    
    if [ -z "$tunnel_id" ]; then
        print_error "❌ 无法获取隧道ID"
        exit 1
    fi
    
    TUNNEL_ID="$tunnel_id"
    print_success "✅ 隧道ID: $TUNNEL_ID"
    
    # 配置DNS路由
    print_info "绑定域名: $USER_DOMAIN"
    if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN" 2>/dev/null; then
        print_success "✅ DNS路由配置成功"
    else
        print_warning "⚠️  DNS路由配置失败，请稍后手动配置"
    fi
    
    # 验证证书文件
    TUNNEL_CERT_FILE="$CERT_DIR/$TUNNEL_ID.json"
    if [ ! -f "$TUNNEL_CERT_FILE" ]; then
        print_error "❌ 找不到隧道证书文件"
        exit 1
    fi
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    
    print_success "✅ 隧道配置完成"
}

# ----------------------------
# 生成 config.yml（预设配置）
# ----------------------------
generate_config_yml_preset() {
    print_step "7. 生成配置文件"
    
    print_info "正在生成 config.yml..."
    
    # 开始构建 config.yml
    local yml_content="# ============================================
# Cloudflare Tunnel 预设配置文件
# 生成时间: $(date)
# 域名: $USER_DOMAIN
# 隧道ID: $TUNNEL_ID
# ============================================

tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_CERT_FILE

# ============================================
# 预设代理协议配置
# 每个协议使用独立端口和路径
# ============================================
ingress:
"
    
    # 为每个预设协议添加规则
    local rule_num=1
    for preset in "${PRESET_PROTOCOLS[@]}"; do
        IFS=':' read -r protocol port path <<< "$preset"
        
        yml_content+="  # 规则${rule_num}: ${protocol} 代理
  - hostname: $USER_DOMAIN
    path: $path
    service: http://127.0.0.1:$port
"
        ((rule_num++))
    done
    
    # 添加404规则
    yml_content+="
  # 规则${rule_num}: 其他所有流量返回404
  - service: http_status:404
"
    
    # 写入配置文件
    echo "$yml_content" > "$CONFIG_DIR/config.yml"
    
    print_success "✅ config.yml 生成完成"
    
    # 显示配置摘要
    echo ""
    print_info "配置摘要："
    echo "----------------------------------------"
    for preset in "${PRESET_PROTOCOLS[@]}"; do
        IFS=':' read -r protocol port path <<< "$preset"
        print_config "$protocol: $USER_DOMAIN$path → 127.0.0.1:$port"
    done
    echo "----------------------------------------"
    echo ""
}

# ----------------------------
# 安装 X-UI 面板
# ----------------------------
install_xui_quick() {
    print_step "8. 安装 X-UI 面板"
    
    # 检查是否已安装
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        print_info "X-UI 已安装，跳过"
        return
    fi
    
    print_info "安装 X-UI 面板..."
    
    # 使用官方安装脚本
    if bash <(curl -fsSL https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh); then
        print_success "✅ X-UI 安装成功"
    else
        print_error "❌ X-UI 安装失败"
        print_info "请手动安装: bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)"
        exit 1
    fi
    
    # 等待启动
    sleep 10
    
    if systemctl is-active --quiet x-ui; then
        print_success "✅ X-UI 服务运行正常"
    else
        print_warning "⚠️  X-UI 启动较慢，请稍后检查"
    fi
}

# ----------------------------
# 创建系统服务
# ----------------------------
create_service_simple() {
    print_step "9. 创建系统服务"
    
    # 创建服务文件
    cat > /etc/systemd/system/cloudflared-tunnel.service << EOF
[Unit]
Description=Cloudflare Tunnel Proxy Service
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yml run
Restart=always
RestartSec=5
StandardOutput=append:$LOG_DIR/cloudflared.log
StandardError=append:$LOG_DIR/cloudflared-error.log
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    # 启用并启动服务
    systemctl daemon-reload
    systemctl enable cloudflared-tunnel
    
    print_info "启动 cloudflared 服务..."
    if systemctl start cloudflared-tunnel; then
        sleep 5
        
        if systemctl is-active --quiet cloudflared-tunnel; then
            print_success "✅ cloudflared 服务启动成功"
        else
            print_error "❌ cloudflared 服务启动失败"
            print_info "查看日志: journalctl -u cloudflared-tunnel -n 20"
        fi
    fi
}

# ----------------------------
# 生成连接信息
# ----------------------------
generate_connection_info() {
    print_step "10. 生成连接信息"
    
    # 获取服务器IP
    local server_ip
    server_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s6 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' | head -1)
    
    # 生成配置信息文件
    cat > "$CONFIG_DIR/quick_guide.txt" << EOF
====================================================
Cloudflare Tunnel 快速安装配置指南
====================================================
安装时间: $(date)
服务器IP: $server_ip
域名: $USER_DOMAIN
隧道ID: $TUNNEL_ID
隧道名称: $TUNNEL_NAME

🎯 预设配置摘要
====================================================
EOF
    
    # 为每个协议生成详细配置
    local config_index=1
    for preset in "${PRESET_PROTOCOLS[@]}"; do
        IFS=':' read -r protocol port path <<< "$preset"
        
        # 生成UUID或密码
        local uuid=""
        local password=""
        
        if [ "$protocol" = "vless" ] || [ "$protocol" = "vmess" ]; then
            if [ -f /proc/sys/kernel/random/uuid ]; then
                uuid=$(cat /proc/sys/kernel/random/uuid)
            else
                uuid=$(uuidgen 2>/dev/null || echo "请手动生成UUID")
            fi
        elif [ "$protocol" = "trojan" ]; then
            password=$(head -c 12 /dev/urandom | base64 | tr -d '\n' | cut -c1-16)
        fi
        
        # 保存到数组供后续使用
        if [ "$protocol" = "vless" ]; then
            VLESS_UUID="$uuid"
        elif [ "$protocol" = "vmess" ]; then
            VMESS_UUID="$uuid"
        elif [ "$protocol" = "trojan" ]; then
            TROJAN_PASSWORD="$password"
        fi
        
        # 添加到指南文件
        cat >> "$CONFIG_DIR/quick_guide.txt" << EOF

▽ $protocol 代理配置 ($config_index/${#PRESET_PROTOCOLS[@]})
   协议: ${protocol^^}
   端口: $port
   路径: $path
EOF
        
        if [ -n "$uuid" ]; then
            echo "   UUID: $uuid" >> "$CONFIG_DIR/quick_guide.txt"
        fi
        if [ -n "$password" ]; then
            echo "   密码: $password" >> "$CONFIG_DIR/quick_guide.txt"
        fi
        
        ((config_index++))
    done
    
    cat >> "$CONFIG_DIR/quick_guide.txt" << EOF

⚙️ X-UI 面板配置
====================================================
访问地址: http://${server_ip}:54321
用户名: admin
密码: admin

配置步骤：
1. 登录 X-UI 面板
2. 为每个协议添加入站：
   - 端口: 20001 (VLESS)
   - 端口: 20002 (VMESS) 
   - 端口: 20003 (Trojan)
3. 传输协议: WebSocket
4. 路径: 与上面配置一致
5. Host: $USER_DOMAIN
6. TLS: 关闭 (由Cloudflare处理)

⚠️ 重要提醒
====================================================
1. 立即修改 X-UI 面板默认密码！
2. 客户端连接时 TLS 必须开启
3. 路径必须完全一致
4. 首次使用需等待DNS生效

📊 服务管理
====================================================
启动服务: systemctl start cloudflared-tunnel
停止服务: systemctl stop cloudflared-tunnel
查看状态: systemctl status cloudflared-tunnel
查看日志: journalctl -u cloudflared-tunnel -f
EOF
    
    print_success "✅ 配置指南生成完成: $CONFIG_DIR/quick_guide.txt"
}

# ----------------------------
# 显示安装结果
# ----------------------------
show_installation_result() {
    print_step "🎉 安装完成"
    
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_success "      Cloudflare Tunnel 快速安装完成"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 获取服务器IP
    local server_ip
    server_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s6 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    print_success "✅ 核心服务部署完成"
    echo ""
    
    print_config "🌐 代理服务信息："
    for preset in "${PRESET_PROTOCOLS[@]}"; do
        IFS=':' read -r protocol port path <<< "$preset"
        print_config "  $protocol: $USER_DOMAIN$path (端口: $port)"
    done
    echo ""
    
    print_config "🖥️  面板访问信息："
    print_config "  URL: http://$server_ip:54321"
    print_config "  账号: admin"
    print_config "  密码: admin"
    echo ""
    
    print_config "📄 详细配置："
    print_config "  cat $CONFIG_DIR/quick_guide.txt"
    echo ""
    
    print_critical "🔒 必须完成的操作："
    echo "  1. 立即访问面板修改默认密码"
    echo "  2. 按指南在X-UI中添加入站规则"
    echo "  3. 确保客户端TLS设置为开启"
    echo ""
    
    print_info "📋 配置文件位置："
    echo "  • Tunnel配置: $CONFIG_DIR/config.yml"
    echo "  • 证书文件: $TUNNEL_CERT_FILE"
    echo "  • 服务日志: $LOG_DIR/"
    echo ""
    
    echo "═══════════════════════════════════════════════"
    print_input "按回车查看快速配置摘要..."
    read -r
    
    # 显示快速摘要
    clear
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║           快速配置摘要                       ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
    
    echo "▸ 域名: $USER_DOMAIN"
    echo "▸ 隧道: $TUNNEL_NAME (ID: $TUNNEL_ID)"
    echo "▸ 服务器IP: $server_ip"
    echo ""
    
    echo "▸ 代理配置："
    for preset in "${PRESET_PROTOCOLS[@]}"; do
        IFS=':' read -r protocol port path <<< "$preset"
        echo "  $protocol:"
        echo "    端口: $port"
        echo "    路径: $path"
    done
    echo ""
    
    echo "▸ X-UI面板："
    echo "  http://$server_ip:54321"
    echo "  admin / admin"
    echo ""
    
    echo "▸ 配置文件："
    echo "  $CONFIG_DIR/quick_guide.txt"
    echo ""
    
    echo "═══════════════════════════════════════════════"
    print_critical "请立即修改面板默认密码！"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    print_input "按回车退出..."
    read -r
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    show_title
    collect_basic_info
    show_preset_config
    check_system
    install_cloudflared
    cloudflare_auth_simple
    create_tunnel_simple
    generate_config_yml_preset
    install_xui_quick
    create_service_simple
    generate_connection_info
    show_installation_result
}

# ----------------------------
# 卸载功能
# ----------------------------
uninstall_all() {
    echo ""
    print_critical "完全卸载 Cloudflare Tunnel"
    echo ""
    
    print_warning "⚠️  这将删除所有配置文件和服务！"
    print_input "确认卸载吗？(y/N): "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "卸载取消"
        return
    fi
    
    print_info "停止服务..."
    systemctl stop cloudflared-tunnel 2>/dev/null || true
    systemctl stop x-ui 2>/dev/null || true
    
    print_info "禁用服务..."
    systemctl disable cloudflared-tunnel 2>/dev/null || true
    systemctl disable x-ui 2>/dev/null || true
    
    print_info "删除服务文件..."
    rm -f /etc/systemd/system/cloudflared-tunnel.service
    rm -f /etc/systemd/system/x-ui.service 2>/dev/null
    
    print_info "删除配置文件..."
    rm -rf "$CONFIG_DIR" "$LOG_DIR"
    
    print_info "删除二进制文件..."
    rm -f "$BIN_DIR/cloudflared"
    
    print_info "清理授权文件..."
    print_input "删除Cloudflare授权证书？(y/N): "
    read -r delete_certs
    if [[ "$delete_certs" =~ ^[Yy]$ ]]; then
        rm -rf "$CERT_DIR"
    fi
    
    systemctl daemon-reload
    
    print_success "✅ 卸载完成"
}

# ----------------------------
# 显示状态
# ----------------------------
show_status() {
    echo ""
    print_info "服务状态检查"
    echo ""
    
    echo "🔧 运行状态："
    if systemctl is-active --quiet cloudflared-tunnel 2>/dev/null; then
        print_success "✓ cloudflared-tunnel: 运行中"
    else
        print_error "✗ cloudflared-tunnel: 未运行"
    fi
    
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        print_success "✓ x-ui: 运行中"
    else
        print_error "✗ x-ui: 未运行"
    fi
    echo ""
    
    echo "📁 配置文件："
    if [ -f "$CONFIG_DIR/config.yml" ]; then
        print_success "✓ config.yml: 存在"
    else
        print_error "✗ config.yml: 不存在"
    fi
    
    if [ -f "$CONFIG_DIR/quick_guide.txt" ]; then
        print_success "✓ 配置指南: 存在"
    fi
    echo ""
}

# ----------------------------
# 主菜单
# ----------------------------
show_menu() {
    clear
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 快速安装                ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
    echo "1. 一键安装（推荐）"
    echo "2. 完全卸载"
    echo "3. 查看状态"
    echo "4. 退出"
    echo ""
    
    print_input "请选择 (1-4): "
    read -r choice
    
    case $choice in
        1) main_install ;;
        2) uninstall_all ;;
        3) show_status ;;
        4) exit 0 ;;
        *) print_error "无效选择"; sleep 1; show_menu ;;
    esac
}

# ----------------------------
# 脚本入口
# ----------------------------
if [ "$#" -eq 0 ]; then
    show_menu
else
    case "$1" in
        "install") main_install ;;
        "uninstall") uninstall_all ;;
        "status") show_status ;;
        *) 
            echo "使用方法:"
            echo "  $0 install     # 安装"
            echo "  $0 uninstall   # 卸载"
            echo "  $0 status      # 查看状态"
            echo "  $0             # 显示菜单"
            ;;
    esac
fi