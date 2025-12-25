#!/bin/bash
# ============================================
# Cloudflare Tunnel + X-UI 完整安装脚本
# 版本: 4.0 - 面板和节点都走Argo
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

# 隧道配置
PANEL_TUNNEL="xui-panel"
NODE_TUNNEL="xui-nodes"

# 端口配置
XUI_PANEL_PORT=54321
NODE_PORTS="10000,10001,10002,10003,10004"  # X-UI节点端口

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    X-UI + Cloudflare Tunnel 完整安装        ║"
    echo "║       版本: 4.0 (面板+节点都走Argo)        ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
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
    
    # 检查系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        print_info "系统: $OS $VERSION"
    else
        print_error "无法检测操作系统"
        exit 1
    fi
    
    # 更新系统
    print_info "更新系统包..."
    apt-get update -y
    
    # 安装必要工具
    print_info "安装必要工具..."
    local tools=("curl" "wget" "jq" "git")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "安装 $tool..."
            apt-get install -y "$tool" || print_warning "$tool 安装失败"
        fi
    done
    
    print_success "系统检查完成"
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
        print_input "请输入面板访问域名 (例如: panel.yourdomain.com):"
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
    print_input "请输入节点访问域名 (例如: nodes.yourdomain.com):"
    print_input "提示：所有代理节点都将使用此域名，按回车使用默认: proxy.yourdomain.com"
    read -r NODE_DOMAIN
    NODE_DOMAIN=${NODE_DOMAIN:-"proxy.yourdomain.com"}
    
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
    
    # 节点端口
    echo ""
    print_input "设置节点端口范围 [默认: 10000-10004]:"
    print_input "格式: 10000,10001,10002 或直接回车使用默认"
    read -r custom_ports
    if [[ -n "$custom_ports" ]]; then
        NODE_PORTS="$custom_ports"
    fi
    
    # 确认信息
    echo ""
    print_success "配置确认:"
    echo "  面板域名: https://$PANEL_DOMAIN"
    echo "  节点域名: $NODE_DOMAIN"
    echo "  节点端口: $NODE_PORTS"
    echo "  X-UI用户名: $XUI_USERNAME"
    echo "  X-UI密码: $XUI_PASSWORD"
    echo ""
    
    print_input "确认配置是否正确？(Y/n):"
    read -r confirm
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        print_info "重新输入配置..."
        collect_user_info
    fi
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
    if wget -q --show-progress -O x-ui-install.sh https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh; then
        chmod +x x-ui-install.sh
    else
        print_error "下载失败，尝试备用链接..."
        curl -L -o x-ui-install.sh https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh
        chmod +x x-ui-install.sh
    fi
    
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
    for i in {1..20}; do
        if systemctl is-active --quiet x-ui; then
            print_success "X-UI 服务已启动"
            break
        fi
        echo -n "."
        sleep 2
    done
    
    # 清理安装文件
    rm -f x-ui-install.sh
    
    print_success "X-UI 安装完成"
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
        
        # 验证版本
        local version=$("$BIN_DIR/cloudflared" --version 2>/dev/null | head -1 || echo "未知")
        print_info "cloudflared 版本: $version"
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
    echo "2. 登录您的 Cloudflare 账户"
    echo "3. 选择域名并授权"
    echo "4. 返回终端继续"
    echo ""
    print_input "按回车键开始授权..."
    read -r
    
    echo ""
    echo "=============================================="
    print_info "请复制以下链接到浏览器："
    echo ""
    
    # 执行授权
    if "$BIN_DIR/cloudflared" tunnel login; then
        print_success "授权命令执行成功"
    else
        print_error "授权命令失败"
        return 1
    fi
    
    echo ""
    echo "=============================================="
    print_input "完成授权后按回车继续..."
    read -r
    
    # 检查授权结果
    print_info "检查授权结果..."
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "✅ 授权成功！证书文件已保存"
        return 0
    else
        print_error "❌ 授权失败，未找到证书文件"
        return 1
    fi
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
    "$BIN_DIR/cloudflared" tunnel delete -f "$tunnel_name" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    print_info "正在创建隧道..."
    if timeout 60 "$BIN_DIR/cloudflared" tunnel create "$tunnel_name"; then
        print_success "隧道创建命令执行成功"
        sleep 3
    else
        print_error "隧道创建失败"
        return 1
    fi
    
    # 获取隧道ID
    local tunnel_info
    tunnel_info=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$tunnel_name" || true)
    
    if [[ -n "$tunnel_info" ]]; then
        local tunnel_id=$(echo "$tunnel_info" | awk '{print $1}')
        print_success "✅ 隧道创建成功"
        print_info "隧道ID: $tunnel_id"
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
    print_info "配置面板隧道..."
    
    # 创建隧道
    local panel_tunnel_id
    panel_tunnel_id=$(create_tunnel "$PANEL_TUNNEL" "面板")
    
    if [[ -z "$panel_tunnel_id" ]]; then
        print_error "面板隧道创建失败"
        return 1
    fi
    
    # 获取凭证文件
    local json_file=$(ls -t /root/.cloudflared/*.json 2>/dev/null | head -1)
    
    if [[ -z "$json_file" ]] || [[ ! -f "$json_file" ]]; then
        print_error "未找到凭证文件"
        return 1
    fi
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 保存配置
    cat > "$CONFIG_DIR/panel.conf" << EOF
# X-UI面板隧道配置
TUNNEL_ID=$panel_tunnel_id
TUNNEL_NAME=$PANEL_TUNNEL
DOMAIN=$PANEL_DOMAIN
CREDENTIALS_FILE=$json_file
XUI_PORT=$XUI_PANEL_PORT
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
    service: http://localhost:$XUI_PANEL_PORT
    originRequest:
      connectTimeout: 30s
      tcpKeepAlive: 30s
      httpHostHeader: $PANEL_DOMAIN
      noTLSVerify: true

  - service: http_status:404
EOF
    
    print_success "面板隧道配置完成"
    
    # 绑定DNS
    print_info "绑定域名 $PANEL_DOMAIN 到隧道..."
    "$BIN_DIR/cloudflared" tunnel route dns "$PANEL_TUNNEL" "$PANEL_DOMAIN" 2>/dev/null || {
        print_warning "DNS绑定可能失败，稍后可手动配置"
    }
    
    return 0
}

# ----------------------------
# 配置节点隧道
# ----------------------------
setup_node_tunnel() {
    print_info "配置节点隧道..."
    
    # 创建隧道
    local node_tunnel_id
    node_tunnel_id=$(create_tunnel "$NODE_TUNNEL" "节点")
    
    if [[ -z "$node_tunnel_id" ]]; then
        print_error "节点隧道创建失败"
        return 1
    fi
    
    # 获取凭证文件
    local json_file=$(ls -t /root/.cloudflared/*.json 2>/dev/null | head -1)
    
    if [[ -z "$json_file" ]] || [[ ! -f "$json_file" ]]; then
        print_error "未找到凭证文件"
        return 1
    fi
    
    # 保存配置
    cat > "$CONFIG_DIR/node.conf" << EOF
# X-UI节点隧道配置
TUNNEL_ID=$node_tunnel_id
TUNNEL_NAME=$NODE_TUNNEL
DOMAIN=$NODE_DOMAIN
CREDENTIALS_FILE=$json_file
NODE_PORTS=$NODE_PORTS
CREATED_DATE=$(date +"%Y-%m-%d %H:%M:%S")
EOF
    
    # 创建ingress规则
    local ingress_rules=""
    
    # 为每个端口创建规则
    IFS=',' read -ra PORTS <<< "$NODE_PORTS"
    for port in "${PORTS[@]}"; do
        ingress_rules="$ingress_rules
  - hostname: $NODE_DOMAIN
    path: \"/$(echo $port | tr -d ' ')(/.*)?\"
    service: http://localhost:$(echo $port | tr -d ' ')
    originRequest:
      connectTimeout: 30s
      tcpKeepAlive: 30s
      httpHostHeader: $NODE_DOMAIN
      noTLSVerify: true"
    done
    
    # 创建YAML配置文件
    cat > "$CONFIG_DIR/node-config.yaml" << EOF
tunnel: $node_tunnel_id
credentials-file: $json_file
logfile: $LOG_DIR/node-tunnel.log
loglevel: info

ingress:$ingress_rules

  - service: http_status:404
EOF
    
    print_success "节点隧道配置完成"
    
    # 绑定DNS
    print_info "绑定域名 $NODE_DOMAIN 到隧道..."
    "$BIN_DIR/cloudflared" tunnel route dns "$NODE_TUNNEL" "$NODE_DOMAIN" 2>/dev/null || {
        print_warning "DNS绑定可能失败，稍后可手动配置"
    }
    
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
        print_success "X-UI 服务启动成功"
    else
        print_error "X-UI 服务启动失败"
        return 1
    fi
    
    # 启动面板隧道
    print_info "启动面板隧道..."
    systemctl enable xui-panel-tunnel.service
    systemctl start xui-panel-tunnel.service
    
    sleep 3
    
    if systemctl is-active --quiet xui-panel-tunnel.service; then
        print_success "✅ 面板隧道启动成功"
    else
        print_error "❌ 面板隧道启动失败"
        journalctl -u xui-panel-tunnel.service -n 20 --no-pager
    fi
    
    # 启动节点隧道
    print_info "启动节点隧道..."
    systemctl enable xui-node-tunnel.service
    systemctl start xui-node-tunnel.service
    
    sleep 3
    
    if systemctl is-active --quiet xui-node-tunnel.service; then
        print_success "✅ 节点隧道启动成功"
    else
        print_error "❌ 节点隧道启动失败"
        journalctl -u xui-node-tunnel.service -n 20 --no-pager
    fi
    
    return 0
}

# ----------------------------
# 生成节点配置指南
# ----------------------------
generate_node_guide() {
    print_info "生成节点配置指南..."
    
    mkdir -p "$CONFIG_DIR/guides"
    
    # 生成详细指南
    cat > "$CONFIG_DIR/guides/NODE_SETUP.md" << EOF
# X-UI 节点配置指南

## 概述
- 面板域名: https://$PANEL_DOMAIN
- 节点域名: $NODE_DOMAIN
- 可用端口: $NODE_PORTS

## 在X-UI面板中配置节点

### 1. 登录面板
访问: https://$PANEL_DOMAIN
用户名: $XUI_USERNAME
密码: $XUI_PASSWORD

### 2. 创建入站节点
1. 进入"入站列表"
2. 点击"添加"
3. 配置示例：

#### VLESS + WS + TLS
\`\`\`
备注: VLESS节点
协议: VLESS
端口: 10000 (从 $NODE_PORTS 中选一个)
用户ID: [点击生成]
传输协议: ws
WebSocket路径: / (或自定义)
主机名: $NODE_DOMAIN
TLS: 开启
\`\`\`

#### VMESS + WS + TLS
\`\`\`
备注: VMESS节点
协议: VMESS
端口: 10001
用户ID: [点击生成]
额外ID: 0
传输协议: ws
WebSocket路径: /vmess
主机名: $NODE_DOMAIN
TLS: 开启
\`\`\`

#### Trojan + WS + TLS
\`\`\`
备注: Trojan节点
协议: Trojan
端口: 10002
密码: [设置强密码]
传输协议: ws
WebSocket路径: /trojan
主机名: $NODE_DOMAIN
TLS: 开启
\`\`\`

## 客户端连接配置

### 通用设置
\`\`\`
服务器地址: $NODE_DOMAIN
端口: 443 (所有节点)
传输协议: WebSocket (WS)
TLS: 开启
SNI: $NODE_DOMAIN
\`\`\`

### VLESS 客户端链接示例
\`\`\`
vless://[UUID]@$NODE_DOMAIN:443?type=ws&security=tls&host=$NODE_DOMAIN&path=%2F&sni=$NODE_DOMAIN#VLESS节点
\`\`\`

### VMESS 客户端链接示例
\`\`\`
vmess://ewogICJ2IjogIjIiLAogICJwcyI6ICJWTUVTUyBub2RlIiwKICAiYWRkIjogIiROT0RFX0RPTUFJTiIsCiAgInBvcnQiOiAiNDQzIiwKICAiaWQiOiAiW1VVSURdIiwKICAiYWlkIjogIjAiLAogICJuZXQiOiAid3MiLAogICJ0eXBlIjogIm5vbmUiLAogICJob3N0IjogIiROT0RFX0RPTUFJTiIsCiAgInBhdGgiOiAiL3ZtZXNzIiwKICAidGxzIjogInRscyIsCiAgInNuaSI6ICIkTk9ERV9ET01BSU4iCn0K
\`\`\`

## 注意事项
1. 所有节点都通过 Cloudflare Tunnel 连接
2. 本地端口映射到隧道443端口
3. TLS证书由Cloudflare自动管理
4. 域名需要正确解析到Cloudflare
EOF
    
    # 生成快速配置脚本
    cat > "$CONFIG_DIR/guides/quick_config.sh" << EOF
#!/bin/bash
echo "=== X-UI 节点快速配置 ==="
echo ""
echo "面板地址: https://$PANEL_DOMAIN"
echo "节点域名: $NODE_DOMAIN"
echo "可用端口: $NODE_PORTS"
echo ""
echo "VLESS配置模板:"
echo "vless://[UUID]@$NODE_DOMAIN:443"
echo "  ?type=ws"
echo "  &security=tls"
echo "  &host=$NODE_DOMAIN"
echo "  &path=%2F[路径]"
echo "  &sni=$NODE_DOMAIN"
echo ""
echo "在X-UI面板中:"
echo "1. 创建入站，使用端口 $NODE_PORTS 中的一个"
echo "2. 传输协议选择 WebSocket"
echo "3. 开启TLS"
echo "4. 主机名填写: $NODE_DOMAIN"
EOF
    
    chmod +x "$CONFIG_DIR/guides/quick_config.sh"
    
    print_success "配置指南已生成: $CONFIG_DIR/guides/"
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
    print_node "   节点端口: $NODE_PORTS"
    print_node "   连接端口: 443 (所有节点)"
    print_node "   TLS: 自动由Cloudflare提供"
    echo ""
    
    print_info "🛠️  管理命令:"
    echo "  面板隧道状态: systemctl status xui-panel-tunnel"
    echo "  节点隧道状态: systemctl status xui-node-tunnel"
    echo "  查看面板日志: journalctl -u xui-panel-tunnel -f"
    echo "  查看节点日志: journalctl -u xui-node-tunnel -f"
    echo "  重启面板隧道: systemctl restart xui-panel-tunnel"
    echo "  重启节点隧道: systemctl restart xui-node-tunnel"
    echo ""
    
    print_info "📋 使用步骤:"
    echo "  1. 访问 https://$PANEL_DOMAIN 登录X-UI面板"
    echo "  2. 在'入站列表'中创建节点，使用端口 $NODE_PORTS 之一"
    echo "  3. 客户端连接时："
    echo "     - 服务器: $NODE_DOMAIN"
    echo "     - 端口: 443"
    echo "     - 协议: VLESS/VMESS/Trojan + WS + TLS"
    echo ""
    
    print_warning "⚠️  重要提示:"
    echo "  1. 首次登录后立即修改默认密码"
    echo "  2. 确保域名 $PANEL_DOMAIN 和 $NODE_DOMAIN 已解析到Cloudflare"
    echo "  3. 如果无法访问，等待DNS生效（最多24小时）"
    echo "  4. 详细配置指南: $CONFIG_DIR/guides/"
    echo ""
    
    # 显示隧道状态
    print_info "隧道状态:"
    echo "运行: $BIN_DIR/cloudflared tunnel list"
    "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || echo "无法获取隧道列表"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    show_title
    
    print_info "开始安装 X-UI + Cloudflare Tunnel (双隧道)..."
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
    start_services
    
    # 生成配置指南
    generate_node_guide
    
    # 显示结果
    show_result
    
    print_success "🎊 安装完成！现在可以开始使用X-UI面板配置代理节点了。"
    
    return 0
}

# ----------------------------
# 卸载功能
# ----------------------------
uninstall() {
    echo ""
    print_warning "⚠️  卸载 X-UI 隧道服务"
    print_warning "此操作将删除隧道配置，但保留X-UI面板"
    echo ""
    
    print_input "确认卸载吗？(y/N): "
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "卸载已取消"
        return
    fi
    
    print_info "停止服务..."
    systemctl stop xui-panel-tunnel.service 2>/dev/null || true
    systemctl stop xui-node-tunnel.service 2>/dev/null || true
    
    systemctl disable xui-panel-tunnel.service 2>/dev/null || true
    systemctl disable xui-node-tunnel.service 2>/dev/null || true
    
    print_info "删除服务文件..."
    rm -f /etc/systemd/system/xui-panel-tunnel.service
    rm -f /etc/systemd/system/xui-node-tunnel.service
    
    print_info "删除配置..."
    rm -rf "$CONFIG_DIR" "$LOG_DIR"
    
    print_input "是否删除Cloudflare授权文件？(y/N): "
    read -r delete_auth
    if [[ "$delete_auth" == "y" || "$delete_auth" == "Y" ]]; then
        rm -rf /root/.cloudflared
    fi
    
    print_input "是否删除cloudflared二进制文件？(y/N): "
    read -r delete_bin
    if [[ "$delete_bin" == "y" || "$delete_bin" == "Y" ]]; then
        rm -f "$BIN_DIR/cloudflared"
    fi
    
    systemctl daemon-reload
    
    echo ""
    print_success "✅ 隧道服务卸载完成！"
    print_info "X-UI面板仍然保留，可以通过 http://服务器IP:54321 访问"
}

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    show_title
    
    echo "请选择操作："
    echo ""
    echo "  1) 安装 X-UI + Cloudflare Tunnel (双隧道)"
    echo "  2) 卸载隧道服务"
    echo "  3) 查看服务状态"
    echo "  4) 查看配置信息"
    echo "  5) 重启所有服务"
    echo "  6) 退出"
    echo ""
    
    print_input "请输入选项 (1-6): "
    read -r choice
    
    case "$choice" in
        1)
            if main_install; then
                echo ""
                print_input "按回车键返回菜单..."
                read -r
            fi
            ;;
        2)
            uninstall
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        3)
            echo ""
            print_info "服务状态:"
            echo "X-UI面板:"
            systemctl status x-ui --no-pager | head -10
            echo ""
            echo "面板隧道:"
            systemctl status xui-panel-tunnel.service --no-pager | head -10
            echo ""
            echo "节点隧道:"
            systemctl status xui-node-tunnel.service --no-pager | head -10
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        4)
            if [ -f "$CONFIG_DIR/panel.conf" ]; then
                echo ""
                print_info "当前配置:"
                echo "=== 面板配置 ==="
                cat "$CONFIG_DIR/panel.conf"
                echo ""
                
                if [ -f "$CONFIG_DIR/node.conf" ]; then
                    echo "=== 节点配置 ==="
                    cat "$CONFIG_DIR/node.conf"
                fi
            else
                print_error "未找到配置文件"
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
            print_info "再见！"
            exit 0
            ;;
        *)
            print_error "无效选项"
            sleep 1
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
        "uninstall")
            uninstall
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
            echo "  sudo ./xui_argo_install.sh menu        # 显示菜单"
            echo "  sudo ./xui_argo_install.sh install     # 安装"
            echo "  sudo ./xui_argo_install.sh uninstall   # 卸载"
            echo "  sudo ./xui_argo_install.sh status      # 查看状态"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"