#!/bin/bash
# ====================================================
# Cloudflare Tunnel 快速安装脚本（修复版）
# 版本: 1.1 - 修复函数定义问题
# ====================================================
set -e

# ----------------------------
# 颜色输出（确保所有函数都在前面定义）
# ----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 函数定义必须放在最前面
print_info() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }
print_input() { echo -e "${CYAN}[?]${NC} $1"; }
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
USER_DOMAIN=""
TUNNEL_NAME=""
TUNNEL_ID=""
TUNNEL_CERT_FILE=""
PANEL_PORT=54321

# 预设协议配置：协议:端口:路径
PRESET_PROTOCOLS=(
    "vless:20001:/vless"
    "vmess:20002:/vmess" 
    "trojan:20003:/trojan"
)

# 存储生成的UUID和密码
VLESS_UUID=""
VMESS_UUID=""
TROJAN_PASSWORD=""

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
# 收集必要信息
# ----------------------------
collect_basic_info() {
    print_step "1. 设置域名和隧道名称"
    echo ""
    
    print_critical "重要：请确保域名已添加到Cloudflare账户"
    echo ""
    
    # 获取域名
    while [[ -z "$USER_DOMAIN" ]]; do
        echo -e "${CYAN}[?]${NC} 请输入您的域名 (例如: tunnel.yourdomain.com): "
        read -r USER_DOMAIN
        
        if [[ -z "$USER_DOMAIN" ]]; then
            echo -e "${RED}[-]${NC} 域名不能为空"
        elif [[ ! "$USER_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo -e "${RED}[-]${NC} 域名格式不正确"
            USER_DOMAIN=""
        fi
    done
    
    # 生成默认隧道名称
    TUNNEL_NAME="cf-tunnel-$(date +%s | tail -c 4)"
    echo -e "${CYAN}[?]${NC} 请输入隧道名称 [默认: $TUNNEL_NAME]: "
    read -r input_name
    TUNNEL_NAME=${input_name:-$TUNNEL_NAME}
    
    echo ""
    echo -e "${GREEN}[+]${NC} 配置完成："
    echo -e "${CYAN}[⚙️]${NC} 域名: $USER_DOMAIN"
    echo -e "${CYAN}[⚙️]${NC} 隧道名称: $TUNNEL_NAME"
    echo ""
}

# ----------------------------
# 显示预设配置
# ----------------------------
show_preset_config() {
    print_step "2. 确认预设配置"
    echo ""
    
    echo -e "${BLUE}[*]${NC} 代理协议预设配置："
    echo "----------------------------------------"
    for i in "${!PRESET_PROTOCOLS[@]}"; do
        IFS=':' read -r protocol port path <<< "${PRESET_PROTOCOLS[$i]}"
        echo -e "${CYAN}[⚙️]${NC} $((i+1)). $protocol - 端口: $port, 路径: $path"
    done
    echo "----------------------------------------"
    echo ""
    
    echo -e "${BLUE}[*]${NC} 架构设计："
    echo "  • Cloudflare Tunnel 仅处理代理流量"
    echo "  • X-UI面板通过服务器IP直连访问"
    echo "  • 每个协议独立端口和路径"
    echo ""
    
    echo -e "${CYAN}[?]${NC} 按回车开始安装，或按 Ctrl+C 取消..."
    read -r
}

# ----------------------------
# 系统检查
# ----------------------------
check_system() {
    print_step "3. 检查系统环境"
    
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[-]${NC} 请使用 root 权限运行此脚本"
        exit 1
    fi
    
    # 安装必要工具
    if ! command -v curl &> /dev/null; then
        echo -e "${BLUE}[*]${NC} 安装 curl..."
        apt-get update -qq
        apt-get install -y -qq curl
    fi
    
    if ! command -v wget &> /dev/null; then
        echo -e "${BLUE}[*]${NC} 安装 wget..."
        apt-get install -y -qq wget
    fi
    
    echo -e "${GREEN}[+]${NC} 系统检查完成"
}

# ----------------------------
# 安装 cloudflared
# ----------------------------
install_cloudflared() {
    print_step "4. 安装 cloudflared"
    
    if [ -f "$BIN_DIR/cloudflared" ]; then
        echo -e "${BLUE}[*]${NC} cloudflared 已安装，跳过"
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
            echo -e "${RED}[-]${NC} 不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    echo -e "${BLUE}[*]${NC} 下载 cloudflared..."
    if curl -fsSL -o /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        
        if "$BIN_DIR/cloudflared" --version &>/dev/null; then
            echo -e "${GREEN}[+]${NC} cloudflared 安装成功"
        else
            echo -e "${RED}[-]${NC} cloudflared 安装验证失败"
        fi
    else
        echo -e "${RED}[-]${NC} cloudflared 下载失败"
        exit 1
    fi
}

# ----------------------------
# Cloudflare 授权
# ----------------------------
cloudflare_auth_simple() {
    print_step "5. Cloudflare 账户授权"
    echo ""
    
    echo -e "${RED}[‼️]${NC} 重要：请准备好复制授权链接"
    echo ""
    
    # 清理旧的授权文件
    rm -rf "$CERT_DIR" 2>/dev/null
    sleep 1
    
    echo -e "${BLUE}[*]${NC} 正在获取授权链接..."
    echo ""
    echo "=============================================="
    
    # 运行授权命令
    echo -e "${BLUE}[*]${NC} 运行授权命令，请查看下面的链接："
    echo ""
    
    # 显示授权命令输出
    timeout 30 "$BIN_DIR/cloudflared" tunnel login 2>&1 | head -20 || true
    
    echo ""
    echo "=============================================="
    echo ""
    
    echo -e "${BLUE}[*]${NC} 如果上面没有显示链接，请运行以下命令获取："
    echo -e "${CYAN}[⚙️]${NC} cloudflared tunnel login --url"
    echo ""
    
    echo -e "${BLUE}[*]${NC} 授权步骤："
    echo "1. 复制链接到浏览器打开"
    echo "2. 登录 Cloudflare 账户"
    echo "3. 选择域名: $USER_DOMAIN"
    echo "4. 点击「Authorize」按钮"
    echo "5. 授权成功后返回终端"
    echo ""
    
    echo -e "${CYAN}[?]${NC} 完成授权后按回车继续..."
    read -r
    
    # 检查授权结果
    echo -e "${BLUE}[*]${NC} 检查授权结果..."
    sleep 3
    
    if [ -d "$CERT_DIR" ] && [ "$(ls -A "$CERT_DIR"/*.json 2>/dev/null | wc -l)" -gt 0 ]; then
        echo -e "${GREEN}[+]${NC} 授权成功！找到证书文件"
        local cert_file=$(ls -t "$CERT_DIR"/*.json | head -1)
        echo -e "${BLUE}[*]${NC} 证书文件: $(basename "$cert_file")"
        return 0
    else
        echo -e "${RED}[-]${NC} 未找到证书文件，授权可能失败"
        echo ""
        echo -e "${YELLOW}[!]${NC} 继续安装，但需要手动配置证书"
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
    
    echo -e "${BLUE}[*]${NC} 创建隧道: $TUNNEL_NAME"
    
    # 创建新隧道
    if timeout 60 "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"; then
        echo -e "${GREEN}[+]${NC} 隧道创建成功"
    else
        echo -e "${YELLOW}[!]${NC} 隧道创建可能失败，尝试使用现有隧道"
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
        echo -e "${RED}[-]${NC} 无法获取隧道ID"
        exit 1
    fi
    
    TUNNEL_ID="$tunnel_id"
    echo -e "${GREEN}[+]${NC} 隧道ID: $TUNNEL_ID"
    
    # 配置DNS路由
    echo -e "${BLUE}[*]${NC} 绑定域名: $USER_DOMAIN"
    if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN" 2>/dev/null; then
        echo -e "${GREEN}[+]${NC} DNS路由配置成功"
    else
        echo -e "${YELLOW}[!]${NC} DNS路由配置失败，请稍后手动配置"
    fi
    
    # 验证证书文件
    TUNNEL_CERT_FILE="$CERT_DIR/$TUNNEL_ID.json"
    if [ ! -f "$TUNNEL_CERT_FILE" ]; then
        echo -e "${RED}[-]${NC} 找不到隧道证书文件"
        exit 1
    fi
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    
    echo -e "${GREEN}[+]${NC} 隧道配置完成"
}

# ----------------------------
# 生成 config.yml
# ----------------------------
generate_config_yml_preset() {
    print_step "7. 生成配置文件"
    
    echo -e "${BLUE}[*]${NC} 正在生成 config.yml..."
    
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
    
    echo -e "${GREEN}[+]${NC} config.yml 生成完成"
    
    # 显示配置摘要
    echo ""
    echo -e "${BLUE}[*]${NC} 配置摘要："
    echo "----------------------------------------"
    for preset in "${PRESET_PROTOCOLS[@]}"; do
        IFS=':' read -r protocol port path <<< "$preset"
        echo -e "${CYAN}[⚙️]${NC} $protocol: $USER_DOMAIN$path → 127.0.0.1:$port"
    done
    echo "----------------------------------------"
    echo ""
}

# ----------------------------
# 生成UUID和密码
# ----------------------------
generate_credentials() {
    print_step "8. 生成UUID和密码"
    
    # 生成VLESS UUID
    if [ -f /proc/sys/kernel/random/uuid ]; then
        VLESS_UUID=$(cat /proc/sys/kernel/random/uuid)
    else
        VLESS_UUID=$(uuidgen 2>/dev/null || echo "")
        if [ -z "$VLESS_UUID" ]; then
            VLESS_UUID=$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)
            VLESS_UUID="${VLESS_UUID:0:8}-${VLESS_UUID:8:4}-${VLESS_UUID:12:4}-${VLESS_UUID:16:4}-${VLESS_UUID:20:12}"
        fi
    fi
    
    # 生成VMESS UUID
    if [ -f /proc/sys/kernel/random/uuid ]; then
        VMESS_UUID=$(cat /proc/sys/kernel/random/uuid)
    else
        VMESS_UUID=$(uuidgen 2>/dev/null || echo "")
        if [ -z "$VMESS_UUID" ]; then
            VMESS_UUID=$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)
            VMESS_UUID="${VMESS_UUID:0:8}-${VMESS_UUID:8:4}-${VMESS_UUID:12:4}-${VMESS_UUID:16:4}-${VMESS_UUID:20:12}"
        fi
    fi
    
    # 生成Trojan密码
    TROJAN_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -d '\n' | cut -c1-16)
    
    echo -e "${GREEN}[+]${NC} 凭证生成完成："
    echo -e "${CYAN}[⚙️]${NC} VLESS UUID: $VLESS_UUID"
    echo -e "${CYAN}[⚙️]${NC} VMESS UUID: $VMESS_UUID"
    echo -e "${CYAN}[⚙️]${NC} Trojan密码: $TROJAN_PASSWORD"
    echo ""
}

# ----------------------------
# 安装 X-UI 面板
# ----------------------------
install_xui_quick() {
    print_step "9. 安装 X-UI 面板"
    
    # 检查是否已安装
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        echo -e "${BLUE}[*]${NC} X-UI 已安装，跳过"
        return
    fi
    
    echo -e "${BLUE}[*]${NC} 安装 X-UI 面板..."
    
    # 使用官方安装脚本
    if bash <(curl -fsSL https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh); then
        echo -e "${GREEN}[+]${NC} X-UI 安装成功"
    else
        echo -e "${RED}[-]${NC} X-UI 安装失败"
        echo -e "${BLUE}[*]${NC} 请手动安装: bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)"
        exit 1
    fi
    
    # 等待启动
    sleep 10
    
    if systemctl is-active --quiet x-ui; then
        echo -e "${GREEN}[+]${NC} X-UI 服务运行正常"
    else
        echo -e "${YELLOW}[!]${NC} X-UI 启动较慢，请稍后检查"
    fi
}

# ----------------------------
# 创建系统服务
# ----------------------------
create_service_simple() {
    print_step "10. 创建系统服务"
    
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
    
    echo -e "${BLUE}[*]${NC} 启动 cloudflared 服务..."
    if systemctl start cloudflared-tunnel; then
        sleep 5
        
        if systemctl is-active --quiet cloudflared-tunnel; then
            echo -e "${GREEN}[+]${NC} cloudflared 服务启动成功"
        else
            echo -e "${RED}[-]${NC} cloudflared 服务启动失败"
            echo -e "${BLUE}[*]${NC} 查看日志: journalctl -u cloudflared-tunnel -n 20"
        fi
    fi
}

# ----------------------------
# 生成连接信息
# ----------------------------
generate_connection_info() {
    print_step "11. 生成连接信息"
    
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
        
        cat >> "$CONFIG_DIR/quick_guide.txt" << EOF

▽ $protocol 代理配置 ($config_index/${#PRESET_PROTOCOLS[@]})
   协议: ${protocol^^}
   端口: $port
   路径: $path
EOF
        
        if [ "$protocol" = "vless" ]; then
            echo "   UUID: $VLESS_UUID" >> "$CONFIG_DIR/quick_guide.txt"
        elif [ "$protocol" = "vmess" ]; then
            echo "   UUID: $VMESS_UUID" >> "$CONFIG_DIR/quick_guide.txt"
        elif [ "$protocol" = "trojan" ]; then
            echo "   密码: $TROJAN_PASSWORD" >> "$CONFIG_DIR/quick_guide.txt"
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
   - 端口: 20001 (VLESS), UUID: $VLESS_UUID
   - 端口: 20002 (VMESS), UUID: $VMESS_UUID
   - 端口: 20003 (Trojan), 密码: $TROJAN_PASSWORD
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
    
    echo -e "${GREEN}[+]${NC} 配置指南生成完成: $CONFIG_DIR/quick_guide.txt"
}

# ----------------------------
# 显示安装结果
# ----------------------------
show_installation_result() {
    print_step "🎉 安装完成"
    
    echo ""
    echo "═══════════════════════════════════════════════"
    echo -e "${GREEN}[+]${NC} Cloudflare Tunnel 快速安装完成"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    # 获取服务器IP
    local server_ip
    server_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s6 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}[+]${NC} 核心服务部署完成"
    echo ""
    
    echo -e "${CYAN}[⚙️]${NC} 代理服务信息："
    for preset in "${PRESET_PROTOCOLS[@]}"; do
        IFS=':' read -r protocol port path <<< "$preset"
        echo -e "${CYAN}[⚙️]${NC}   $protocol: $USER_DOMAIN$path (端口: $port)"
    done
    echo ""
    
    echo -e "${CYAN}[⚙️]${NC} 面板访问信息："
    echo -e "${CYAN}[⚙️]${NC}   URL: http://$server_ip:54321"
    echo -e "${CYAN}[⚙️]${NC}   账号: admin"
    echo -e "${CYAN}[⚙️]${NC}   密码: admin"
    echo ""
    
    echo -e "${CYAN}[⚙️]${NC} 详细配置："
    echo -e "${CYAN}[⚙️]${NC}   cat $CONFIG_DIR/quick_guide.txt"
    echo ""
    
    echo -e "${RED}[‼️]${NC} 必须完成的操作："
    echo "  1. 立即访问面板修改默认密码"
    echo "  2. 按指南在X-UI中添加入站规则"
    echo "  3. 确保客户端TLS设置为开启"
    echo ""
    
    echo -e "${BLUE}[*]${NC} 配置文件位置："
    echo "  • Tunnel配置: $CONFIG_DIR/config.yml"
    echo "  • 证书文件: $TUNNEL_CERT_FILE"
    echo "  • 服务日志: $LOG_DIR/"
    echo ""
    
    echo "═══════════════════════════════════════════════"
    echo -e "${CYAN}[?]${NC} 按回车查看快速配置摘要..."
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
        if [ "$protocol" = "vless" ]; then
            echo "    UUID: $VLESS_UUID"
        elif [ "$protocol" = "vmess" ]; then
            echo "    UUID: $VMESS_UUID"
        elif [ "$protocol" = "trojan" ]; then
            echo "    密码: $TROJAN_PASSWORD"
        fi
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
    echo -e "${RED}[‼️]${NC} 请立即修改面板默认密码！"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    echo -e "${CYAN}[?]${NC} 按回车退出..."
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
    generate_credentials
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
    echo "═══════════════════════════════════════════════"
    echo -e "${RED}[‼️]${NC} 完全卸载 Cloudflare Tunnel"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    echo -e "${YELLOW}[!]${NC} 这将删除所有配置文件和服务！"
    echo ""
    echo -e "${CYAN}[?]${NC} 确认卸载吗？(y/N): "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "卸载取消"
        return
    fi
    
    echo -e "${BLUE}[*]${NC} 停止服务..."
    systemctl stop cloudflared-tunnel 2>/dev/null || true
    systemctl stop x-ui 2>/dev/null || true
    
    echo -e "${BLUE}[*]${NC} 禁用服务..."
    systemctl disable cloudflared-tunnel 2>/dev/null || true
    systemctl disable x-ui 2>/dev/null || true
    
    echo -e "${BLUE}[*]${NC} 删除服务文件..."
    rm -f /etc/systemd/system/cloudflared-tunnel.service
    rm -f /etc/systemd/system/x-ui.service 2>/dev/null
    
    echo -e "${BLUE}[*]${NC} 删除配置文件..."
    rm -rf "$CONFIG_DIR" "$LOG_DIR"
    
    echo -e "${BLUE}[*]${NC} 删除二进制文件..."
    rm -f "$BIN_DIR/cloudflared"
    
    echo -e "${BLUE}[*]${NC} 清理授权文件..."
    echo -e "${CYAN}[?]${NC} 删除Cloudflare授权证书？(y/N): "
    read -r delete_certs
    if [[ "$delete_certs" =~ ^[Yy]$ ]]; then
        rm -rf "$CERT_DIR"
    fi
    
    systemctl daemon-reload
    
    echo -e "${GREEN}[+]${NC} 卸载完成"
}

# ----------------------------
# 显示状态
# ----------------------------
show_status() {
    echo ""
    echo "═══════════════════════════════════════════════"
    echo -e "${BLUE}[*]${NC} 服务状态检查"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    echo "🔧 运行状态："
    if systemctl is-active --quiet cloudflared-tunnel 2>/dev/null; then
        echo -e "${GREEN}[+]${NC} cloudflared-tunnel: 运行中"
    else
        echo -e "${RED}[-]${NC} cloudflared-tunnel: 未运行"
    fi
    
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        echo -e "${GREEN}[+]${NC} x-ui: 运行中"
    else
        echo -e "${RED}[-]${NC} x-ui: 未运行"
    fi
    echo ""
    
    echo "📁 配置文件："
    if [ -f "$CONFIG_DIR/config.yml" ]; then
        echo -e "${GREEN}[+]${NC} config.yml: 存在"
    else
        echo -e "${RED}[-]${NC} config.yml: 不存在"
    fi
    
    if [ -f "$CONFIG_DIR/quick_guide.txt" ]; then
        echo -e "${GREEN}[+]${NC} 配置指南: 存在"
    fi
    echo ""
}

# ----------------------------
# 显示菜单
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
    
    echo -e "${CYAN}[?]${NC} 请选择 (1-4): "
    read -r choice
    
    case $choice in
        1) main_install ;;
        2) uninstall_all ;;
        3) show_status ;;
        4) exit 0 ;;
        *) 
            echo -e "${RED}[-]${NC} 无效选择"
            sleep 1
            show_menu
            ;;
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