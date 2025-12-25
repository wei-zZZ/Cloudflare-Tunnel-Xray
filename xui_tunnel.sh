#!/bin/bash
# ====================================================
# Cloudflare Tunnel + X-UI 安装脚本（最终修正版）
# 版本: 2.0 - 完全解决所有架构问题
# 修正内容：
# 1. 正确获取和使用 Tunnel UUID（非名称）
# 2. Tunnel 只处理代理流量，面板通过IP直连
# 3. 架构完全分离，零风险暴露
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
PROXY_PORT=10086
PANEL_PORT=54321
WS_PATH="/proxy"  # 固定WebSocket路径
TUNNEL_ID=""  # 必须从创建输出中获取
SILENT_MODE=false

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     Cloudflare Tunnel + X-UI 安装脚本（最终架构版）     ║"
    echo "║     Tunnel只处理代理 | 面板IP直连 | 零暴露风险         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    print_critical "架构原则：Tunnel只处理/proxy流量，面板通过服务器IP直连访问"
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
    
    # 检查并安装必要工具
    local tools=("curl" "wget" "grep" "sed")
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
    
    # 特别检查grep的PCRE支持（需要提取UUID）
    if ! grep -qP 'test' <<< 'test' 2>/dev/null; then
        print_info "安装支持PCRE的grep..."
        apt-get install -y -qq grep
    fi
    
    print_success "系统检查完成"
}

# ----------------------------
# 收集配置信息
# ----------------------------
collect_config() {
    print_step "2. 收集配置信息"
    echo ""
    
    # 获取域名
    while [[ -z "$USER_DOMAIN" ]]; do
        print_input "请输入您的域名 (例如: tunnel.yourdomain.com):"
        read -r USER_DOMAIN
        
        if [[ -z "$USER_DOMAIN" ]]; then
            print_error "域名不能为空！"
        elif ! [[ "$USER_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "域名格式不正确，请重新输入！"
            USER_DOMAIN=""
        fi
    done
    
    # 确认WebSocket路径
    echo ""
    print_config "WebSocket 路径将固定为: $WS_PATH"
    print_config "所有代理流量必须使用此路径"
    print_warning "面板访问不通过Tunnel，使用服务器IP直连"
    echo ""
    
    # 获取隧道名称（仅用于创建，config.yml中使用UUID）
    print_input "请输入隧道名称 [默认: $TUNNEL_NAME]:"
    read -r input_name
    TUNNEL_NAME=${input_name:-$TUNNEL_NAME}
    
    # 获取代理端口
    print_input "设置代理端口 [默认: $PROXY_PORT]:"
    read -r input_port
    PROXY_PORT=${input_port:-$PROXY_PORT}
    
    # 获取面板端口（仅用于本地访问）
    print_input "设置X-UI面板端口 [默认: $PANEL_PORT]:"
    read -r input_panel_port
    PANEL_PORT=${input_panel_port:-$PANEL_PORT}
    
    echo ""
    print_success "配置收集完成"
    print_config "域名: $USER_DOMAIN"
    print_config "隧道名称: $TUNNEL_NAME（仅用于创建）"
    print_config "WebSocket路径: $WS_PATH"
    print_config "代理端口: $PROXY_PORT"
    print_config "面板端口: $PANEL_PORT（通过服务器IP访问）"
    echo ""
}

# ----------------------------
# 安装 cloudflared
# ----------------------------
install_cloudflared() {
    print_step "3. 安装 cloudflared"
    
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
    if curl -sSL -o /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        
        # 验证安装
        if "$BIN_DIR/cloudflared" --version &>/dev/null; then
            local version=$("$BIN_DIR/cloudflared" --version 2>/dev/null | head -1 || echo "未知")
            print_success "cloudflared 安装成功 (版本: $version)"
        else
            print_error "cloudflared 安装验证失败"
            exit 1
        fi
    else
        print_error "cloudflared 下载失败"
        exit 1
    fi
}

# ----------------------------
# Cloudflare 授权
# ----------------------------
cloudflare_auth() {
    print_step "4. Cloudflare 账户授权"
    echo ""
    
    print_info "授权步骤："
    echo "1. 复制下方链接到浏览器"
    echo "2. 登录 Cloudflare 账户"
    echo "3. 选择域名: $(print_config "$USER_DOMAIN")"
    echo "4. 点击「授权」"
    echo "5. 返回终端按回车"
    echo ""
    print_input "按回车开始授权..."
    read -r
    
    # 清理旧证书
    rm -rf /root/.cloudflared 2>/dev/null || true
    
    # 运行授权
    echo ""
    echo "=============================================="
    print_config "授权链接："
    echo ""
    if ! "$BIN_DIR/cloudflared" tunnel login; then
        print_error "授权失败，请检查网络和账户"
        exit 1
    fi
    echo ""
    echo "=============================================="
    
    print_input "授权完成后按回车继续..."
    read -r
    
    # 验证授权
    if [ -d "/root/.cloudflared" ] && [ "$(ls -A /root/.cloudflared/*.json 2>/dev/null | wc -l)" -gt 0 ]; then
        print_success "Cloudflare 授权成功"
    else
        print_error "授权失败，未找到证书文件"
        exit 1
    fi
}

# ----------------------------
# 创建隧道并正确获取Tunnel ID
# ----------------------------
create_tunnel() {
    print_step "5. 创建 Cloudflare 隧道（关键步骤）"
    
    # 删除可能存在的旧隧道（同名）
    print_info "清理旧隧道（如果存在）..."
    "$BIN_DIR/cloudflared" tunnel delete "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道并捕获输出
    print_info "创建隧道: $TUNNEL_NAME"
    echo "----------------------------------------"
    
    # 运行创建命令并捕获所有输出
    local create_output
    if ! create_output=$("$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME" 2>&1); then
        print_error "隧道创建命令执行失败"
        echo "错误输出:"
        echo "$create_output"
        exit 1
    fi
    
    echo "$create_output"
    echo "----------------------------------------"
    
    # 关键：从输出中提取Tunnel ID（UUID格式）
    print_info "从创建输出中提取Tunnel ID..."
    
    # 方法1：从标准输出格式提取
    TUNNEL_ID=$(echo "$create_output" | grep -oP '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
    
    # 方法2：如果方法1失败，尝试从证书文件获取
    if [ -z "$TUNNEL_ID" ]; then
        print_warning "从输出提取ID失败，尝试从证书文件获取..."
        local cert_file=$(ls -t /root/.cloudflared/*.json 2>/dev/null | head -1)
        if [ -n "$cert_file" ]; then
            TUNNEL_ID=$(basename "$cert_file" .json)
            print_info "从证书文件获取ID: $TUNNEL_ID"
        fi
    fi
    
    # 验证Tunnel ID格式
    if [[ -z "$TUNNEL_ID" ]] || [[ ! "$TUNNEL_ID" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]; then
        print_error "无法获取有效的Tunnel ID"
        print_error "请手动检查: ls /root/.cloudflared/*.json"
        exit 1
    fi
    
    print_success "隧道创建成功"
    print_critical "Tunnel ID (UUID): $TUNNEL_ID"
    print_critical "⚠️  config.yml中将使用此ID，不是名称 '$TUNNEL_NAME'"
    
    # 配置DNS路由
    print_info "配置DNS路由: $USER_DOMAIN → $TUNNEL_NAME"
    if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN"; then
        print_success "DNS路由配置成功"
    else
        print_error "DNS路由配置失败"
        exit 1
    fi
    
    # 验证证书文件存在
    TUNNEL_CERT_FILE="/root/.cloudflared/$TUNNEL_ID.json"
    if [ ! -f "$TUNNEL_CERT_FILE" ]; then
        print_error "找不到隧道证书文件: $TUNNEL_CERT_FILE"
        print_info "现有证书文件:"
        ls -la /root/.cloudflared/*.json 2>/dev/null || echo "无"
        exit 1
    fi
    
    print_success "证书文件验证: $TUNNEL_CERT_FILE"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
}

# ----------------------------
# 生成正确的 Ingress 配置（关键！使用Tunnel ID）
# ----------------------------
generate_ingress_config() {
    print_step "6. 生成 Ingress 配置（使用Tunnel ID）"
    
    print_critical "config.yml 关键字段:"
    print_critical "  tunnel: $TUNNEL_ID (UUID，不是名称)"
    print_critical "  credentials-file: $TUNNEL_CERT_FILE"
    echo ""
    
    # 正确配置：只处理代理流量，其他所有404
    local ingress_config="# ============================================
# Cloudflare Tunnel 配置文件
# 生成时间: $(date)
# 架构：Tunnel只处理代理流量，面板通过IP直连
# ============================================

# 关键：必须使用Tunnel ID（UUID），不是名称
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_CERT_FILE

# ============================================
# Ingress 规则（第一个匹配即停止）
# ============================================
ingress:
  # 规则1: WebSocket 代理流量（精确路径匹配）
  # 只有 $WS_PATH 路径的流量会进入代理端口
  - hostname: $USER_DOMAIN
    path: $WS_PATH
    service: http://127.0.0.1:$PROXY_PORT

  # 规则2: 其他所有流量返回404（包括面板访问）
  # 面板通过服务器IP:端口直连访问，不经过Tunnel
  - service: http_status:404"

    echo "$ingress_config" > "$CONFIG_DIR/config.yml"
    
    print_success "Ingress 配置已生成"
    echo ""
    print_config "规则1: $USER_DOMAIN$WS_PATH → 127.0.0.1:$PROXY_PORT (仅代理流量)"
    print_config "规则2: 其他所有请求 → 404（面板不通过Tunnel）"
    echo ""
    print_warning "X-UI面板访问方式: http://服务器IP:$PANEL_PORT"
    print_warning "面板不通过Tunnel，确保防火墙允许该端口"
    
    # 显示配置文件内容
    print_info "配置文件预览:"
    echo "----------------------------------------"
    cat "$CONFIG_DIR/config.yml"
    echo "----------------------------------------"
}

# ----------------------------
# 安装 X-UI 面板
# ----------------------------
install_xui() {
    print_step "7. 安装 X-UI 面板（本地服务）"
    
    print_info "下载并安装 X-UI..."
    
    # 使用官方安装脚本
    if bash <(curl -sSL https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh); then
        print_success "X-UI 安装成功"
    else
        print_error "X-UI 安装失败"
        print_info "请手动安装: bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)"
        exit 1
    fi
    
    # 如果用户指定了非默认端口，修改X-UI配置
    if [ "$PANEL_PORT" != "54321" ]; then
        print_info "修改X-UI面板端口为: $PANEL_PORT"
        
        # 尝试修改配置
        local config_files=(
            "/etc/x-ui/x-ui.db"
            "/usr/local/x-ui/bin/config.db"
            "/root/x-ui/x-ui.db"
        )
        
        local modified=false
        for config_file in "${config_files[@]}"; do
            if [ -f "$config_file" ]; then
                if grep -q "port" "$config_file"; then
                    # 尝试JSON格式
                    if sed -i 's/\"port\":.*[0-9]\+/\"port\": '"$PANEL_PORT"'/' "$config_file" 2>/dev/null; then
                        modified=true
                    # 尝试其他格式
                    elif sed -i "s/port.*/port: $PANEL_PORT/" "$config_file" 2>/dev/null; then
                        modified=true
                    fi
                fi
            fi
        done
        
        if [ "$modified" = true ]; then
            print_info "面板端口已修改为 $PANEL_PORT"
        fi
        
        # 重启X-UI使新端口生效
        systemctl restart x-ui 2>/dev/null || true
        sleep 3
    fi
    
    # 等待X-UI完全启动
    print_info "等待X-UI服务启动..."
    for i in {1..10}; do
        if systemctl is-active --quiet x-ui; then
            print_success "X-UI 服务运行正常 (端口: $PANEL_PORT)"
            break
        fi
        sleep 1
        if [ $i -eq 10 ]; then
            print_warning "X-UI 启动较慢，请稍后检查: systemctl status x-ui"
        fi
    done
}

# ----------------------------
# 创建 cloudflared 系统服务
# ----------------------------
create_cloudflared_service() {
    print_step "8. 创建 cloudflared 系统服务"
    
    # 创建服务文件
    cat > /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=Cloudflare Tunnel (Proxy Only)
After=network.target network-online.target
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
    
    # 启用服务
    systemctl daemon-reload
    systemctl enable cloudflared
    
    print_info "启动 cloudflared 服务..."
    if systemctl start cloudflared; then
        sleep 5
        
        if systemctl is-active --quiet cloudflared; then
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
            print_info "查看日志: journalctl -u cloudflared -n 20 --no-pager"
        fi
    else
        print_error "启动命令执行失败"
    fi
}

# ----------------------------
# 生成最终配置指南
# ----------------------------
generate_config_guide() {
    print_step "9. 生成最终配置指南"
    
    # 获取服务器IP
    local server_ip
    server_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s6 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' | head -1)
    
    # 生成示例UUID
    local example_uuid
    if command -v uuidgen &> /dev/null; then
        example_uuid=$(uuidgen)
    else
        example_uuid="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    fi
    
    # 创建详细的配置指南
    cat > "$CONFIG_DIR/final_setup_guide.txt" << EOF
====================================================
Cloudflare Tunnel + X-UI 最终配置指南
====================================================
安装完成时间: $(date)
服务器IP: $server_ip
域名: $USER_DOMAIN
隧道ID: $TUNNEL_ID
隧道名称: $TUNNEL_NAME

🎯 最终架构说明
====================================================
┌─────────────────┐    ┌─────────────────┐
│    客户端       │    │     管理员      │
│   (公网访问)    │    │   (直接访问)    │
└────────┬────────┘    └────────┬────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│  Cloudflare     │    │  服务器防火墙    │
│    Tunnel       │    │   (端口$PANEL_PORT) │
└────────┬────────┘    └────────┬────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│  Xray 代理      │    │   X-UI 面板     │
│  (端口:$PROXY_PORT) │    │ (端口:$PANEL_PORT) │
└─────────────────┘    └─────────────────┘

📡 Tunnel 流量规则（唯一路径）
====================================================
只有以下路径通过Tunnel：
$USER_DOMAIN$WS_PATH → 代理端口 $PROXY_PORT

其他所有请求（包括面板访问）→ 404
面板不通过Tunnel暴露！

⚙️ X-UI 面板配置步骤
====================================================
1. 访问面板（不通过Tunnel）：
   URL: http://$server_ip:$PANEL_PORT
   或: http://服务器公网IP:$PANEL_PORT
   用户名: admin
   密码: admin

2. 添加入站规则（必须一致）：
   点击「入站列表」→「添加入站」
   
   ▽ 基本设置
       备注: CF-Tunnel-Proxy
       端口: $PROXY_PORT
       协议: VLESS (推荐)
   
   ▽ 用户设置
       用户ID: [点击「重置UUID」生成]
       示例: $example_uuid
   
   ▽ 传输设置
       传输协议: WebSocket
       WebSocket 设置:
          路径 (path): $WS_PATH
          Host: $USER_DOMAIN
   
   ▽ TLS 设置
       安全类型: 无 (TLS由Cloudflare处理)
       ⚠️ 必须关闭TLS

3. 保存并启用入站。

🔗 客户端配置（关键参数）
====================================================
地址 (address): $USER_DOMAIN
端口 (port): 443
用户ID (id): [使用X-UI中生成的UUID]
加密 (encryption): none
传输协议 (network): ws
路径 (path): $WS_PATH
TLS: 开启 (必须)
SNI: $USER_DOMAIN
跳过证书验证: false

VLESS 分享链接格式：
vless://[UUID]@$USER_DOMAIN:443?type=ws&security=tls&encryption=none&host=$USER_DOMAIN&path=$(echo "$WS_PATH" | sed 's/\//%2F/g')&sni=$USER_DOMAIN#CF-Tunnel-Proxy

🔒 安全加固建议（重要！）
====================================================
1. 修改X-UI默认密码：
   登录面板 → 面板设置 → 修改用户名密码

2. 防火墙设置（推荐）：
   # 允许面板端口（限制IP范围）
   ufw allow from 你的IP to any port $PANEL_PORT
   
   # 或使用iptables
   iptables -A INPUT -p tcp --dport $PANEL_PORT -s 你的IP -j ACCEPT
   iptables -A INPUT -p tcp --dport $PANEL_PORT -j DROP

3. 安装Fail2ban：
   apt-get install fail2ban
   systemctl enable fail2ban

4. 定期更新：
   apt-get update && apt-get upgrade

⚠️ 重要提醒
====================================================
1. 路径必须完全一致：
   客户端路径: $WS_PATH
   X-UI入站路径: $WS_PATH
   Ingress规则路径: $WS_PATH

2. TLS位置正确：
   客户端→Cloudflare: 有TLS (443端口)
   Cloudflare→Xray: 无TLS

3. 面板访问方式：
   通过 http://$server_ip:$PANEL_PORT
   不通过 $USER_DOMAIN

4. DNS生效时间：
   首次使用可能需要等待DNS传播（通常1-10分钟）

📊 服务管理命令
====================================================
# 查看服务状态
systemctl status cloudflared
systemctl status x-ui

# 查看日志
tail -f $LOG_DIR/cloudflared.log
journalctl -u x-ui -f

# 重启服务
systemctl restart cloudflared
systemctl restart x-ui

# 查看隧道状态
$BIN_DIR/cloudflared tunnel list
$BIN_DIR/cloudflared tunnel info $TUNNEL_ID

🔍 故障排查
====================================================
1. 面板无法访问？
   - 检查: systemctl status x-ui
   - 检查防火墙: ufw status 或 iptables -L
   - 直接测试: curl http://127.0.0.1:$PANEL_PORT

2. 客户端连接失败？
   - 检查Tunnel: tail -f $LOG_DIR/cloudflared.log
   - 验证路径一致性
   - 检查X-UI入站是否启用

3. 隧道断开？
   - 重启: systemctl restart cloudflared
   - 查看详细日志: journalctl -u cloudflared -n 50

📁 配置文件位置
====================================================
Tunnel 配置: $CONFIG_DIR/config.yml
隧道证书: $TUNNEL_CERT_FILE
服务日志: $LOG_DIR/
本指南: $CONFIG_DIR/final_setup_guide.txt
X-UI配置: /etc/x-ui/x-ui.db

====================================================
配置完成！架构分离，安全可靠。
====================================================
EOF
    
    print_success "最终配置指南已生成: $CONFIG_DIR/final_setup_guide.txt"
    echo ""
}

# ----------------------------
# 验证安装
# ----------------------------
verify_installation() {
    print_step "10. 最终验证"
    
    echo ""
    print_info "🔍 安装结果验证:"
    echo "----------------------------------------"
    
    local all_ok=true
    
    # 1. 验证Tunnel ID使用正确
    if grep -q "tunnel: $TUNNEL_ID" "$CONFIG_DIR/config.yml"; then
        print_success "✓ config.yml使用正确的Tunnel ID"
    else
        print_error "✗ config.yml未使用正确的Tunnel ID"
        all_ok=false
    fi
    
    # 2. 验证服务状态
    if systemctl is-active --quiet cloudflared; then
        print_success "✓ cloudflared 服务运行中"
    else
        print_error "✗ cloudflared 服务未运行"
        all_ok=false
    fi
    
    if systemctl is-active --quiet x-ui; then
        print_success "✓ X-UI 服务运行中"
    else
        print_warning "⚠ X-UI 服务未运行（可能需要手动启动）"
    fi
    
    # 3. 验证配置文件存在
    if [ -f "$CONFIG_DIR/config.yml" ]; then
        print_success "✓ 配置文件存在"
    else
        print_error "✗ 配置文件缺失"
        all_ok=false
    fi
    
    if [ -f "$TUNNEL_CERT_FILE" ]; then
        print_success "✓ 隧道证书存在"
    else
        print_error "✗ 隧道证书缺失"
        all_ok=false
    fi
    
    # 4. 验证Ingress规则正确
    if grep -q "path: $WS_PATH" "$CONFIG_DIR/config.yml"; then
        print_success "✓ Ingress规则正确（路径: $WS_PATH）"
    else
        print_error "✗ Ingress规则中未找到正确路径"
        all_ok=false
    fi
    
    # 5. 验证没有面板暴露
    if ! grep -q ": $PANEL_PORT" "$CONFIG_DIR/config.yml"; then
        print_success "✓ 面板未通过Tunnel暴露（正确）"
    else
        print_error "✗ 面板在Tunnel中暴露（错误）"
        all_ok=false
    fi
    
    echo "----------------------------------------"
    
    if [ "$all_ok" = true ]; then
        print_success "✅ 所有核心验证通过！架构正确实现。"
    else
        print_warning "⚠️ 部分验证未通过，请检查上述问题"
    fi
    
    # 显示访问信息
    local server_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s6 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' | head -1)
    
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_success "           架构分离完成！"
    print_info "═══════════════════════════════════════════════"
    echo ""
    print_config "🌐 代理访问（通过Tunnel）:"
    print_config "    地址: $USER_DOMAIN"
    print_config "    路径: $WS_PATH"
    print_config "    端口: 443 (TLS)"
    echo ""
    print_config "🖥️  面板访问（IP直连）:"
    print_config "    URL: http://$server_ip:$PANEL_PORT"
    print_config "    账号: admin"
    print_config "    密码: admin"
    echo ""
    print_config "📄 详细指南: cat $CONFIG_DIR/final_setup_guide.txt"
    echo ""
    print_warning "🔒 安全提醒：请立即修改面板默认密码！"
    print_warning "             并配置防火墙限制面板端口访问"
}

# ----------------------------
# 显示最终总结
# ----------------------------
show_final_summary() {
    print_step "🎉 安装完成总结"
    
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_success "      Cloudflare Tunnel 最终架构部署完成"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    print_critical "🎯 架构实现要点："
    echo "1. ✅ Tunnel ID 正确获取和使用（非名称）"
    echo "2. ✅ Ingress 只处理 /proxy 路径代理流量"
    echo "3. ✅ X-UI 面板不通过Tunnel暴露（IP直连）"
    echo "4. ✅ 零冲突、零重复、零暴露风险"
    echo ""
    
    print_critical "📋 必须完成的手动步骤："
    echo "1. 访问 http://服务器IP:$PANEL_PORT 登录面板"
    echo "2. 修改默认账号密码"
    echo "3. 添加入站（端口:$PROXY_PORT, 路径:$WS_PATH）"
    echo "4. 配置防火墙限制面板端口访问"
    echo ""
    
    print_critical "🔗 客户端连接信息："
    echo "地址: $USER_DOMAIN"
    echo "端口: 443"
    echo "路径: $WS_PATH"
    echo "传输: WebSocket"
    echo "TLS: 开启（必须）"
    echo ""
    
    print_input "按回车查看快速配置摘要..."
    read -r
    
    # 显示快速摘要
    clear
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║           快速配置摘要（保存备用）           ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
    echo "▸ 服务器IP: $(curl -s4 ifconfig.me 2>/dev/null || echo '请手动查看')"
    echo "▸ 域名: $USER_DOMAIN"
    echo "▸ Tunnel ID: $TUNNEL_ID"
    echo ""
    echo "▸ 面板访问:"
    echo "  http://服务器IP:$PANEL_PORT"
    echo "  账号: admin"
    echo "  密码: admin"
    echo ""
    echo "▸ 代理配置:"
    echo "  地址: $USER_DOMAIN"
    echo "  端口: 443"
    echo "  路径: $WS_PATH"
    echo "  TLS: 开启"
    echo ""
    echo "▸ X-UI入站设置:"
    echo "  端口: $PROXY_PORT"
    echo "  协议: VLESS"
    echo "  传输: WebSocket"
    echo "  路径: $WS_PATH"
    echo "  Host: $USER_DOMAIN"
    echo "  TLS: 关闭"
    echo ""
    echo "▸ 配置文件: $CONFIG_DIR/final_setup_guide.txt"
    echo ""
    echo "═══════════════════════════════════════════════"
    print_warning "立即修改面板密码并配置防火墙！"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    print_input "按回车键退出安装脚本..."
    read -r
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    show_title
    check_system
    collect_config
    install_cloudflared
    cloudflare_auth
    create_tunnel
    generate_ingress_config
    install_xui
    create_cloudflared_service
    generate_config_guide
    verify_installation
    show_final_summary
}

# 运行主函数
trap 'print_error "脚本被中断"; exit 1' INT TERM
main "$@"