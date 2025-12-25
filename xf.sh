#!/bin/bash
# ====================================================
# Cloudflare Tunnel 代理管理脚本（最终修正版）
# 版本: 3.0 - 支持多协议、多端口、正确架构
# 修正：授权问题、架构分离、配置灵活
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
print_critical() { echo -e "${RED}[‼️]${NC} $1"; }

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/cf_tunnel"
LOG_DIR="/var/log/cf_tunnel"
BIN_DIR="/usr/local/bin"

USER_DOMAIN=""
TUNNEL_NAME="cf-proxy-tunnel"
PANEL_PORT=54321
SILENT_MODE=false
PROTOCOL_CONFIGS=()  # 存储协议配置数组
TUNNEL_ID=""
CERT_DIR="/root/.cloudflared"

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║      Cloudflare Tunnel 多协议代理管理脚本              ║"
    echo "║         支持 VLESS/VMESS/Trojan + 多端口               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

# ----------------------------
# 系统检查
# ----------------------------
check_system() {
    print_step "1. 检查系统环境"
    
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 权限运行此脚本"
        exit 1
    fi
    
    # 安装必要工具
    local tools=("curl" "wget")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_info "安装必要工具: ${missing_tools[*]}"
        apt-get update -qq
        apt-get install -y -qq "${missing_tools[@]}"
    fi
    
    print_success "系统检查完成"
}

# ----------------------------
# 收集域名和隧道信息
# ----------------------------
collect_basic_info() {
    print_step "2. 收集基本信息"
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
    print_input "请输入隧道名称 [默认: $TUNNEL_NAME]: "
    read -r input_name
    TUNNEL_NAME=${input_name:-$TUNNEL_NAME}
    
    echo ""
    print_success "基本信息收集完成"
    print_config "域名: $USER_DOMAIN"
    print_config "隧道名称: $TUNNEL_NAME"
    echo ""
}

# ----------------------------
# 收集多协议配置信息
# ----------------------------
collect_protocol_configs() {
    print_step "3. 配置代理协议和端口"
    echo ""
    
    print_info "您可以配置多个协议，每个协议使用不同的端口和路径"
    echo ""
    
    local continue_add=true
    local protocol_count=0
    
    while [ "$continue_add" = true ]; do
        ((protocol_count++))
        
        echo ""
        print_info "=== 配置第 $protocol_count 个代理协议 ==="
        
        # 选择协议类型
        print_input "请选择协议类型:"
        echo "  1) VLESS (推荐)"
        echo "  2) VMESS"
        echo "  3) Trojan"
        echo "  4) 完成配置"
        echo ""
        print_input "请输入选项 (1-4): "
        read -r protocol_choice
        
        if [ "$protocol_choice" = "4" ]; then
            if [ $protocol_count -eq 1 ]; then
                print_error "至少需要配置一个协议"
                continue
            else
                print_success "协议配置完成"
                continue_add=false
                break
            fi
        fi
        
        # 获取协议名称
        local protocol_name=""
        case "$protocol_choice" in
            "1") protocol_name="vless" ;;
            "2") protocol_name="vmess" ;;
            "3") protocol_name="trojan" ;;
            *) 
                print_error "无效选项"
                ((protocol_count--))
                continue
                ;;
        esac
        
        # 获取端口
        local default_port=$((20000 + protocol_count))
        print_input "请输入 $protocol_name 代理端口 [默认: $default_port]: "
        read -r proxy_port
        proxy_port=${proxy_port:-$default_port}
        
        # 检查端口是否已使用
        if ss -tulpn | grep -q ":$proxy_port "; then
            print_warning "端口 $proxy_port 已被占用，请选择其他端口"
            ((protocol_count--))
            continue
        fi
        
        # 获取WebSocket路径
        local default_path="/$protocol_name"
        print_input "请输入 $protocol_name 的WebSocket路径 [默认: $default_path]: "
        read -r ws_path
        ws_path=${ws_path:-$default_path}
        
        # 确保路径以斜杠开头
        [[ ! "$ws_path" =~ ^/ ]] && ws_path="/$ws_path"
        
        # 生成UUID（VLESS和VMESS需要）
        local uuid=""
        if [ "$protocol_name" = "vless" ] || [ "$protocol_name" = "vmess" ]; then
            if command -v uuidgen &> /dev/null; then
                uuid=$(uuidgen)
            else
                # 备用方法生成UUID
                uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "")
                if [ -z "$uuid" ]; then
                    uuid=$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)
                    uuid="${uuid:0:8}-${uuid:8:4}-${uuid:12:4}-${uuid:16:4}-${uuid:20:12}"
                fi
            fi
            print_success "$protocol_name UUID: $uuid"
        fi
        
        # Trojan密码
        local trojan_password=""
        if [ "$protocol_name" = "trojan" ]; then
            trojan_password=$(head -c 12 /dev/urandom | base64 | tr -d '\n' | cut -c1-16)
            print_success "Trojan密码: $trojan_password"
        fi
        
        # 保存配置到数组
        PROTOCOL_CONFIGS+=("$protocol_name:$proxy_port:$ws_path:$uuid:$trojan_password")
        
        echo ""
        print_success "✅ $protocol_name 配置完成:"
        print_config "端口: $proxy_port"
        print_config "路径: $ws_path"
        if [ -n "$uuid" ]; then
            print_config "UUID: $uuid"
        fi
        if [ -n "$trojan_password" ]; then
            print_config "密码: $trojan_password"
        fi
        echo ""
        
        # 询问是否继续添加
        if [ $protocol_count -lt 10 ]; then
            print_input "是否继续添加其他协议？(y/N): "
            read -r add_more
            if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
                continue_add=false
            fi
        else
            print_warning "已达到最大协议数量限制 (10个)"
            continue_add=false
        fi
    done
    
    if [ ${#PROTOCOL_CONFIGS[@]} -eq 0 ]; then
        print_error "未配置任何协议，脚本退出"
        exit 1
    fi
    
    echo ""
    print_success "共配置 ${#PROTOCOL_CONFIGS[@]} 个代理协议"
}

# ----------------------------
# 改进的授权函数 - 强制显示链接
# ----------------------------
cloudflare_auth_forced() {
    print_step "4. Cloudflare 账户授权（强制显示链接）"
    echo ""
    
    print_critical "重要：此步骤将强制显示授权链接，请仔细操作"
    echo ""
    
    # 清理旧的授权文件
    rm -rf "$CERT_DIR" 2>/dev/null
    sleep 1
    
    print_info "授权准备完成，正在获取链接..."
    echo ""
    print_warning "如果看不到链接，请按 Ctrl+C 然后运行以下命令手动获取："
    print_warning "cloudflared tunnel login 2>&1 | grep -o 'https://[^ ]*'"
    echo ""
    
    print_input "按回车开始获取授权链接..."
    read -r
    
    # 方法1：尝试使用标准命令并过滤输出
    print_info "方法1：运行标准授权命令..."
    echo "=============================================="
    
    # 运行命令并实时显示输出
    local auth_output=""
    local auth_pid
    
    # 在后台运行授权命令
    ( "$BIN_DIR/cloudflared" tunnel login 2>&1 ) &
    auth_pid=$!
    
    # 等待3秒获取初始输出
    sleep 3
    
    # 尝试从进程输出中获取链接
    if ps -p $auth_pid > /dev/null; then
        # 获取进程输出
        local tmp_output
        tmp_output=$(timeout 5 "$BIN_DIR/cloudflared" tunnel login --url 2>&1 || true)
        
        # 查找链接
        local auth_url=$(echo "$tmp_output" | grep -o 'https://[^ ]*' | head -1)
        
        if [ -n "$auth_url" ]; then
            echo ""
            print_success "✅ 找到授权链接："
            echo ""
            print_config "$auth_url"
            echo ""
            print_info "请复制此链接到浏览器打开"
        else
            echo ""
            print_warning "未自动提取到链接，请查看上方输出手动查找"
        fi
    fi
    
    echo "=============================================="
    echo ""
    
    # 方法2：提供备用获取方式
    print_info "方法2：备用获取方式..."
    echo "运行以下命令获取链接："
    print_config "cd /tmp && timeout 30 $BIN_DIR/cloudflared tunnel login 2>&1 | tee /tmp/cf_login.txt"
    echo "然后在输出中查找 'https://' 开头的链接"
    echo ""
    
    # 等待用户操作
    print_input "请在浏览器中完成授权，然后返回终端按回车继续..."
    read -r
    
    # 检查授权结果
    print_info "检查授权结果..."
    local max_wait=60
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        if [ -d "$CERT_DIR" ] && [ "$(ls -A "$CERT_DIR"/*.json 2>/dev/null | wc -l)" -gt 0 ]; then
            print_success "✅ 授权成功！找到证书文件"
            
            # 显示证书文件
            local cert_files=($(ls "$CERT_DIR"/*.json 2>/dev/null))
            for cert in "${cert_files[@]}"; do
                print_info "证书: $(basename "$cert")"
            done
            
            return 0
        fi
        
        if [ $((waited % 10)) -eq 0 ] && [ $waited -gt 0 ]; then
            print_info "已等待 ${waited}秒，继续等待..."
        fi
        
        sleep 2
        ((waited+=2))
    done
    
    # 授权失败处理
    print_error "❌ 授权超时，未找到证书文件"
    echo ""
    print_warning "手动解决方案："
    echo "1. 访问 https://dash.cloudflare.com/"
    echo "2. 进入 Zero Trust → Access → Tunnels"
    echo "3. 点击「Create Tunnel」创建新隧道"
    echo "4. 选择「Free」计划，输入隧道名称"
    echo "5. 保存后会显示「Install connector」步骤"
    echo "6. 下载证书文件到 /root/.cloudflared/"
    echo ""
    
    print_input "是否跳过授权继续安装？(y/N): "
    read -r skip_auth
    if [[ "$skip_auth" =~ ^[Yy]$ ]]; then
        print_warning "跳过授权，后续需要手动配置证书"
        return 1
    else
        print_error "安装中止"
        exit 1
    fi
}

# ----------------------------
# 安装必要组件
# ----------------------------
install_components() {
    print_step "5. 安装必要组件"
    
    # 检查是否已安装
    if [ -f "$BIN_DIR/cloudflared" ]; then
        print_info "cloudflared 已安装，跳过"
    else
        print_info "安装 cloudflared..."
        
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
        
        if curl -fsSL -o /tmp/cloudflared "$cf_url"; then
            mv /tmp/cloudflared "$BIN_DIR/cloudflared"
            chmod +x "$BIN_DIR/cloudflared"
            
            # 验证安装
            if "$BIN_DIR/cloudflared" --version &>/dev/null; then
                print_success "cloudflared 安装成功"
            else
                print_error "cloudflared 安装验证失败"
            fi
        else
            print_error "cloudflared 下载失败"
            exit 1
        fi
    fi
}

# ----------------------------
# 创建隧道并获取配置
# ----------------------------
create_tunnel_config() {
    print_step "6. 创建 Cloudflare 隧道"
    
    # 删除可能存在的旧隧道
    "$BIN_DIR/cloudflared" tunnel delete "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    print_info "创建隧道: $TUNNEL_NAME"
    echo "----------------------------------------"
    
    local create_output
    if ! create_output=$("$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME" 2>&1); then
        print_error "隧道创建失败"
        echo "错误信息: $create_output"
        
        # 尝试使用现有隧道
        print_warning "尝试使用现有隧道..."
        local existing_tunnel=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}' | head -1)
        
        if [ -n "$existing_tunnel" ]; then
            TUNNEL_ID="$existing_tunnel"
            print_success "使用现有隧道: $TUNNEL_ID"
        else
            print_error "无法创建或找到隧道"
            exit 1
        fi
    else
        # 从输出中提取Tunnel ID
        TUNNEL_ID=$(echo "$create_output" | grep -oP '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
        
        if [ -z "$TUNNEL_ID" ]; then
            # 备用方法：从证书文件获取
            local cert_file=$(ls -t "$CERT_DIR"/*.json 2>/dev/null | head -1)
            if [ -n "$cert_file" ]; then
                TUNNEL_ID=$(basename "$cert_file" .json)
            fi
        fi
    fi
    
    if [ -z "$TUNNEL_ID" ]; then
        print_error "无法获取 Tunnel ID"
        exit 1
    fi
    
    print_success "隧道创建成功"
    print_critical "Tunnel ID: $TUNNEL_ID"
    
    # 配置DNS路由
    print_info "配置DNS路由: $USER_DOMAIN → $TUNNEL_NAME"
    if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN"; then
        print_success "DNS路由配置成功"
    else
        print_warning "DNS路由配置可能失败，请稍后手动配置"
    fi
    
    # 验证证书文件
    TUNNEL_CERT_FILE="$CERT_DIR/$TUNNEL_ID.json"
    if [ ! -f "$TUNNEL_CERT_FILE" ]; then
        print_error "找不到隧道证书文件"
        print_info "现有证书文件:"
        ls -la "$CERT_DIR"/*.json 2>/dev/null || echo "无"
        exit 1
    fi
    
    print_success "证书文件: $TUNNEL_CERT_FILE"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
}

# ----------------------------
# 生成 config.yml 配置文件（用户输入驱动）
# ----------------------------
generate_config_yml() {
    print_step "7. 生成 config.yml 配置文件"
    
    print_info "正在生成配置文件..."
    
    # 开始构建 config.yml 内容
    local yml_content="# ============================================
# Cloudflare Tunnel 配置文件
# 生成时间: $(date)
# 域名: $USER_DOMAIN
# 隧道ID: $TUNNEL_ID
# ============================================

tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_CERT_FILE

# ============================================
# Ingress 规则配置
# 注意：规则按顺序匹配，第一个匹配即停止
# ============================================
ingress:
"
    
    # 为每个协议添加入口规则
    local rule_count=0
    for config in "${PROTOCOL_CONFIGS[@]}"; do
        ((rule_count++))
        
        IFS=':' read -r protocol_name proxy_port ws_path uuid password <<< "$config"
        
        yml_content+="  # 规则${rule_count}: ${protocol_name} 代理
  - hostname: $USER_DOMAIN
    path: $ws_path
    service: http://127.0.0.1:$proxy_port
"
    done
    
    # 添加404规则
    yml_content+="
  # 规则$((rule_count + 1)): 其他所有流量返回404
  - service: http_status:404
"
    
    # 写入配置文件
    echo "$yml_content" > "$CONFIG_DIR/config.yml"
    
    print_success "配置文件已生成: $CONFIG_DIR/config.yml"
    
    # 显示配置摘要
    echo ""
    print_info "配置摘要:"
    echo "----------------------------------------"
    for config in "${PROTOCOL_CONFIGS[@]}"; do
        IFS=':' read -r protocol_name proxy_port ws_path uuid password <<< "$config"
        print_config "$protocol_name: $USER_DOMAIN$ws_path → 127.0.0.1:$proxy_port"
    done
    echo "----------------------------------------"
    echo ""
}

# ----------------------------
# 安装 X-UI 面板
# ----------------------------
install_xui_panel() {
    print_step "8. 安装 X-UI 面板"
    
    # 检查是否已安装
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        print_info "X-UI 已安装，跳过"
        return
    fi
    
    print_info "安装 X-UI 面板..."
    
    # 使用官方安装脚本
    if bash <(curl -fsSL https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh); then
        print_success "X-UI 安装成功"
    else
        print_error "X-UI 安装失败"
        print_info "请手动安装: bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)"
        exit 1
    fi
    
    # 等待X-UI启动
    print_info "等待X-UI启动..."
    sleep 10
    
    # 验证服务状态
    if systemctl is-active --quiet x-ui; then
        print_success "X-UI 服务运行正常"
    else
        print_warning "X-UI 启动较慢，请稍后检查: systemctl status x-ui"
    fi
}

# ----------------------------
# 创建系统服务
# ----------------------------
create_system_service() {
    print_step "9. 创建系统服务"
    
    # 创建服务文件
    cat > /etc/systemd/system/cloudflared-tunnel.service << EOF
[Unit]
Description=Cloudflare Tunnel Proxy Service
After=network.target
Wants=network-online.target
Documentation=https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/

[Service]
Type=simple
User=root
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yml run
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=5
StandardOutput=append:$LOG_DIR/cloudflared.log
StandardError=append:$LOG_DIR/cloudflared-error.log
Environment="GODEBUG=netdns=go"
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
            print_success "cloudflared 服务启动成功"
            
            # 显示隧道状态
            print_info "隧道状态检查:"
            if timeout 10 "$BIN_DIR/cloudflared" tunnel info "$TUNNEL_ID" 2>/dev/null; then
                print_success "隧道连接正常"
            else
                print_warning "隧道状态检查超时，但服务正在运行"
            fi
        else
            print_error "cloudflared 服务启动失败"
            print_info "查看日志: journalctl -u cloudflared-tunnel -n 20 --no-pager"
        fi
    else
        print_error "启动命令执行失败"
    fi
}

# ----------------------------
# 生成用户配置指南
# ----------------------------
generate_user_guide() {
    print_step "10. 生成配置指南"
    
    # 获取服务器IP
    local server_ip
    server_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s6 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' | head -1)
    
    # 创建配置指南文件
    cat > "$CONFIG_DIR/user_guide.txt" << EOF
====================================================
Cloudflare Tunnel 多协议代理配置指南
====================================================
安装完成时间: $(date)
服务器IP: $server_ip
域名: $USER_DOMAIN
隧道ID: $TUNNEL_ID

🎯 架构说明
====================================================
1. Cloudflare Tunnel 只处理代理流量
2. X-UI 面板通过服务器IP直连访问
3. 支持多协议、多端口配置

📡 Cloudflare Tunnel 配置
====================================================
配置文件: $CONFIG_DIR/config.yml
隧道ID: $TUNNEL_ID
证书文件: $TUNNEL_CERT_FILE

流量规则:
EOF
    
    # 添加流量规则
    local rule_num=1
    for config in "${PROTOCOL_CONFIGS[@]}"; do
        IFS=':' read -r protocol_name proxy_port ws_path uuid password <<< "$config"
        echo "规则${rule_num}: $USER_DOMAIN$ws_path → 127.0.0.1:$proxy_port ($protocol_name)" >> "$CONFIG_DIR/user_guide.txt"
        ((rule_num++))
    done
    
    cat >> "$CONFIG_DIR/user_guide.txt" << EOF
规则$((rule_num)): 其他所有流量 → 404

⚙️ X-UI 面板配置步骤
====================================================
1. 访问面板: http://${server_ip}:54321
   用户名: admin
   密码: admin

2. 为每个协议添加入站规则：
EOF
    
    # 为每个协议添加入站配置说明
    for config in "${PROTOCOL_CONFIGS[@]}"; do
        IFS=':' read -r protocol_name proxy_port ws_path uuid password <<< "$config"
        
        cat >> "$CONFIG_DIR/user_guide.txt" << EOF
▽ $protocol_name 配置 ($proxy_port 端口)
   备注: CF-Tunnel-$protocol_name
   端口: $proxy_port
   协议: ${protocol_name^^}
EOF
        
        if [ "$protocol_name" = "vless" ] || [ "$protocol_name" = "vmess" ]; then
            echo "   用户ID: $uuid" >> "$CONFIG_DIR/user_guide.txt"
        elif [ "$protocol_name" = "trojan" ]; then
            echo "   密码: $password" >> "$CONFIG_DIR/user_guide.txt"
        fi
        
        cat >> "$CONFIG_DIR/user_guide.txt" << EOF
   传输协议: WebSocket
   WebSocket 路径: $ws_path
   Host: $USER_DOMAIN
   TLS: 关闭 (由Cloudflare处理)
EOF
    done
    
    cat >> "$CONFIG_DIR/user_guide.txt" << EOF

🔗 客户端配置示例
====================================================
EOF
    
    # 为每个协议添加客户端配置
    for config in "${PROTOCOL_CONFIGS[@]}"; do
        IFS=':' read -r protocol_name proxy_port ws_path uuid password <<< "$config"
        
        cat >> "$CONFIG_DIR/user_guide.txt" << EOF
▽ $protocol_name 客户端配置:
   地址: $USER_DOMAIN
   端口: 443
EOF
        
        case "$protocol_name" in
            "vless")
                echo "   用户ID: $uuid" >> "$CONFIG_DIR/user_guide.txt"
                echo "   加密: none" >> "$CONFIG_DIR/user_guide.txt"
                echo "   传输协议: ws" >> "$CONFIG_DIR/user_guide.txt"
                echo "   路径: $ws_path" >> "$CONFIG_DIR/user_guide.txt"
                echo "   TLS: 开启" >> "$CONFIG_DIR/user_guide.txt"
                echo "   SNI: $USER_DOMAIN" >> "$CONFIG_DIR/user_guide.txt"
                echo "" >> "$CONFIG_DIR/user_guide.txt"
                echo "   VLESS链接:" >> "$CONFIG_DIR/user_guide.txt"
                echo "   vless://$uuid@$USER_DOMAIN:443?type=ws&security=tls&encryption=none&host=$USER_DOMAIN&path=$(echo "$ws_path" | sed 's/\//%2F/g')&sni=$USER_DOMAIN#CF-Tunnel-$protocol_name" >> "$CONFIG_DIR/user_guide.txt"
                ;;
            "vmess")
                cat >> "$CONFIG_DIR/user_guide.txt" << EOF
   用户ID: $uuid
   传输协议: ws
   路径: $ws_path
   TLS: 开启
   SNI: $USER_DOMAIN
   跳过证书验证: false

   VMESS链接:
   vmess://$(echo -n '{"v":"2","ps":"CF-Tunnel-vmess","add":"'"$USER_DOMAIN"'","port":"443","id":"'"$uuid"'","aid":"0","scy":"none","net":"ws","type":"none","host":"'"$USER_DOMAIN"'","path":"'"$ws_path"'","tls":"tls","sni":"'"$USER_DOMAIN"'","alpn":""}' | base64 -w 0)
EOF
                ;;
            "trojan")
                cat >> "$CONFIG_DIR/user_guide.txt" << EOF
   密码: $password
   传输协议: ws
   路径: $ws_path
   TLS: 开启
   SNI: $USER_DOMAIN

   Trojan链接:
   trojan://$password@$USER_DOMAIN:443?type=ws&host=$USER_DOMAIN&path=$(echo "$ws_path" | sed 's/\//%2F/g')&sni=$USER_DOMAIN#CF-Tunnel-trojan
EOF
                ;;
        esac
        
        echo "" >> "$CONFIG_DIR/user_guide.txt"
        echo "═══════════════════════════════════════════════" >> "$CONFIG_DIR/user_guide.txt"
        echo "" >> "$CONFIG_DIR/user_guide.txt"
    done
    
    cat >> "$CONFIG_DIR/user_guide.txt" << EOF
⚠️ 重要提醒
====================================================
1. 客户端必须设置 security=tls (不是none)
2. X-UI 入站中必须关闭 TLS
3. 路径必须完全一致: 客户端、config.yml、X-UI入站
4. X-UI 面板通过 http://${server_ip}:54321 访问
5. 首次连接可能需要等待DNS传播（1-10分钟）

📊 服务管理命令
====================================================
# 查看服务状态
systemctl status cloudflared-tunnel
systemctl status x-ui

# 查看日志
tail -f $LOG_DIR/cloudflared.log
journalctl -u x-ui -f

# 重启服务
systemctl restart cloudflared-tunnel
systemctl restart x-ui

🔍 故障排查
====================================================
1. 面板无法访问?
   - 检查: systemctl status x-ui
   - 直接访问: http://127.0.0.1:54321

2. 客户端连接失败?
   - 检查: tail -f $LOG_DIR/cloudflared.log
   - 验证路径是否完全一致
   - 验证X-UI入站是否已启用

3. 隧道断开?
   - 重启: systemctl restart cloudflared-tunnel
   - 查看日志: journalctl -u cloudflared-tunnel -n 30
EOF
    
    print_success "配置指南已生成: $CONFIG_DIR/user_guide.txt"
}

# ----------------------------
# 显示安装完成信息
# ----------------------------
show_installation_complete() {
    print_step "🎉 安装完成"
    
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_success "      Cloudflare Tunnel 部署完成"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 获取服务器IP
    local server_ip
    server_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s6 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' | head -1)
    
    print_success "✅ 核心服务部署完成"
    echo ""
    
    print_config "🌐 代理服务信息:"
    for config in "${PROTOCOL_CONFIGS[@]}"; do
        IFS=':' read -r protocol_name proxy_port ws_path uuid password <<< "$config"
        print_config "  $protocol_name: $USER_DOMAIN$ws_path (端口: $proxy_port)"
    done
    echo ""
    
    print_config "🖥️  面板访问信息:"
    print_config "  URL: http://$server_ip:54321"
    print_config "  账号: admin"
    print_config "  密码: admin"
    echo ""
    
    print_config "📄 详细配置指南:"
    print_config "  cat $CONFIG_DIR/user_guide.txt"
    echo ""
    
    print_warning "🔒 重要安全提醒:"
    echo "  1. 立即修改X-UI面板默认密码"
    echo "  2. 配置防火墙限制面板端口访问"
    echo "  3. 确保X-UI入站中TLS设置为关闭"
    echo ""
    
    print_info "下一步操作:"
    echo "  1. 访问面板 http://$server_ip:54321"
    echo "  2. 按指南添加所有入站规则"
    echo "  3. 使用生成的客户端配置连接"
    echo ""
    
    print_input "按回车查看配置摘要..."
    read -r
    
    # 显示配置摘要
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║           快速配置摘要                       ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
    
    echo "▸ 服务器IP: $server_ip"
    echo "▸ 域名: $USER_DOMAIN"
    echo "▸ Tunnel ID: $TUNNEL_ID"
    echo ""
    
    echo "▸ 代理配置:"
    for config in "${PROTOCOL_CONFIGS[@]}"; do
        IFS=':' read -r protocol_name proxy_port ws_path uuid password <<< "$config"
        echo "  $protocol_name:"
        echo "    端口: $proxy_port"
        echo "    路径: $ws_path"
        if [ "$protocol_name" = "vless" ] || [ "$protocol_name" = "vmess" ]; then
            echo "    UUID: $uuid"
        elif [ "$protocol_name" = "trojan" ]; then
            echo "    密码: $password"
        fi
        echo ""
    done
    
    echo "▸ X-UI面板:"
    echo "  http://$server_ip:54321"
    echo "  admin / admin"
    echo ""
    echo "═══════════════════════════════════════════════"
    print_critical "请立即修改面板默认密码！"
    echo "═══════════════════════════════════════════════"
}

# ----------------------------
# 验证安装结果
# ----------------------------
verify_installation() {
    print_step "11. 验证安装结果"
    
    echo ""
    print_info "🔍 安装验证:"
    echo "----------------------------------------"
    
    local all_ok=true
    
    # 验证服务状态
    if systemctl is-active --quiet cloudflared-tunnel; then
        print_success "✓ cloudflared 服务运行正常"
    else
        print_error "✗ cloudflared 服务未运行"
        all_ok=false
    fi
    
    if systemctl is-active --quiet x-ui; then
        print_success "✓ X-UI 服务运行正常"
    else
        print_warning "⚠ X-UI 服务未运行（可能需要手动启动）"
    fi
    
    # 验证配置文件
    if [ -f "$CONFIG_DIR/config.yml" ]; then
        print_success "✓ config.yml 配置文件存在"
    else
        print_error "✗ config.yml 配置文件缺失"
        all_ok=false
    fi
    
    if [ -f "$TUNNEL_CERT_FILE" ]; then
        print_success "✓ 隧道证书文件存在"
    else
        print_error "✗ 隧道证书文件缺失"
        all_ok=false
    fi
    
    # 验证配置内容
    if grep -q "tunnel: $TUNNEL_ID" "$CONFIG_DIR/config.yml"; then
        print_success "✓ config.yml 使用正确的 Tunnel ID"
    else
        print_error "✗ config.yml 中 Tunnel ID 不正确"
        all_ok=false
    fi
    
    # 验证是否有正确的ingress规则
    local rule_count=$(grep -c "hostname: $USER_DOMAIN" "$CONFIG_DIR/config.yml")
    if [ "$rule_count" -ge "${#PROTOCOL_CONFIGS[@]}" ]; then
        print_success "✓ 所有协议规则已配置"
    else
        print_error "✗ 协议规则配置不完整"
        all_ok=false
    fi
    
    echo "----------------------------------------"
    
    if [ "$all_ok" = true ]; then
        print_success "✅ 所有核心组件验证通过"
    else
        print_warning "⚠️  部分验证未通过，请检查上述问题"
    fi
    
    echo ""
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    show_title
    check_system
    collect_basic_info
    collect_protocol_configs
    install_components
    cloudflare_auth_forced
    create_tunnel_config
    generate_config_yml
    install_xui_panel
    create_system_service
    generate_user_guide
    verify_installation
    show_installation_complete
    
    echo ""
    print_input "按回车键退出..."
    read -r
}

# ----------------------------
# 卸载功能
# ----------------------------
uninstall_all() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_critical "          完全卸载 Cloudflare Tunnel"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    print_warning "⚠️  警告：此操作将删除所有配置文件和数据！"
    echo ""
    print_input "确认要卸载吗？(y/N): "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "卸载已取消"
        return
    fi
    
    echo ""
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
    
    print_info "删除授权文件（可选）..."
    print_input "是否删除 Cloudflare 授权文件？(y/N): "
    read -r delete_certs
    if [[ "$delete_certs" =~ ^[Yy]$ ]]; then
        rm -rf "$CERT_DIR"
    fi
    
    print_info "清理系统配置..."
    systemctl daemon-reload
    
    echo ""
    print_success "✅ 完全卸载完成！"
}

# ----------------------------
# 显示状态信息
# ----------------------------
show_status() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           当前服务状态"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    echo "🔧 服务状态:"
    echo "----------------------------------------"
    if systemctl is-active --quiet cloudflared-tunnel; then
        print_success "✓ cloudflared-tunnel: 运行中"
    else
        print_error "✗ cloudflared-tunnel: 未运行"
    fi
    
    if systemctl is-active --quiet x-ui; then
        print_success "✓ x-ui: 运行中"
    else
        print_error "✗ x-ui: 未运行"
    fi
    echo ""
    
    echo "📁 配置文件:"
    echo "----------------------------------------"
    if [ -f "$CONFIG_DIR/config.yml" ]; then
        print_success "✓ config.yml: 存在"
        echo "  位置: $CONFIG_DIR/config.yml"
    else
        print_error "✗ config.yml: 不存在"
    fi
    
    if [ -d "$CERT_DIR" ] && [ "$(ls -A "$CERT_DIR"/*.json 2>/dev/null | wc -l)" -gt 0 ]; then
        print_success "✓ 证书文件: 存在"
        echo "  数量: $(ls "$CERT_DIR"/*.json 2>/dev/null | wc -l) 个"
    else
        print_error "✗ 证书文件: 不存在"
    fi
    echo ""
    
    echo "📊 隧道信息:"
    echo "----------------------------------------"
    if command -v "$BIN_DIR/cloudflared" &> /dev/null; then
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || echo "无法获取隧道列表"
    else
        echo "cloudflared 未安装"
    fi
}

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    clear
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel 多协议管理脚本          ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
    echo "1. 全新安装（推荐）"
    echo "2. 完全卸载"
    echo "3. 查看状态"
    echo "4. 退出"
    echo ""
    
    print_input "请选择操作 (1-4): "
    read -r choice
    echo ""
    
    case $choice in
        1) main_install ;;
        2) uninstall_all ;;
        3) show_status ;;
        4) exit 0 ;;
        *) print_error "无效选择"; sleep 2; show_menu ;;
    esac
}

# ----------------------------
# 主程序入口
# ----------------------------
if [ "$#" -eq 0 ]; then
    show_menu
else
    case "$1" in
        "install") main_install ;;
        "uninstall") uninstall_all ;;
        "status") show_status ;;
        "menu") show_menu ;;
        *)
            echo "使用方法:"
            echo "  $0 install     # 安装"
            echo "  $0 uninstall   # 卸载"
            echo "  $0 status      # 查看状态"
            echo "  $0 menu        # 显示菜单"
            ;;
    esac
fi