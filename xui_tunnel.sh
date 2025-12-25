#!/bin/bash
# ============================================
# X-UI + Cloudflare Tunnel 正确TLS配置脚本
# 解决TLS冲突问题
# ============================================

set -e

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

# 配置
CONFIG_DIR="/etc/xui_tunnel"
LOG_DIR="/var/log/xui_tunnel"
BIN_DIR="/usr/local/bin"
SERVICE_NAME="xui-tunnel"

# 显示标题
show_title() {
    clear
    echo ""
    echo "==============================================="
    echo "      X-UI 正确TLS配置"
    echo "==============================================="
    echo ""
}

# 获取配置
get_config() {
    echo ""
    print_info "配置信息"
    echo ""
    
    # 域名
    while true; do
        print_input "请输入域名 (例如: hk2xui.9420ce.top):"
        read -r DOMAIN
        
        if [[ -z "$DOMAIN" ]]; then
            print_error "域名不能为空"
            continue
        fi
        
        if [[ "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "域名格式错误"
        fi
    done
    
    # X-UI面板端口
    echo ""
    print_input "请输入X-UI面板端口 [默认: 54321]:"
    read -r PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-"54321"}
    
    # Xray监听端口（X-UI入站端口）
    echo ""
    print_input "请输入Xray监听端口 [默认: 10000]:"
    print_input "⚠️ 重要：Xray必须关闭TLS，只监听HTTP"
    read -r XRAY_PORT
    XRAY_PORT=${XRAY_PORT:-"10000"}
    
    # 隧道名称
    TUNNEL_NAME="xui-$(date +%s)"
    
    # 保存配置
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/.env" << EOF
DOMAIN=$DOMAIN
PANEL_PORT=$PANEL_PORT
XRAY_PORT=$XRAY_PORT
TUNNEL_NAME=$TUNNEL_NAME
EOF
    
    echo ""
    print_success "配置已保存:"
    echo "  域名: $DOMAIN"
    echo "  面板端口: $PANEL_PORT"
    echo "  Xray端口: $XRAY_PORT"
    echo "  ⚠️  Xray必须: TLS关闭，只监听HTTP"
    echo "  隧道名称: $TUNNEL_NAME"
    echo ""
}

# Cloudflare授权
cloudflare_auth() {
    echo ""
    print_info "Cloudflare授权"
    echo ""
    
    rm -rf /root/.cloudflared 2>/dev/null || true
    mkdir -p /root/.cloudflared
    
    echo "请按以下步骤操作:"
    echo "1. 复制下面的链接到浏览器"
    echo "2. 登录Cloudflare账户"
    echo "3. 选择域名授权"
    echo "4. 返回终端继续"
    echo ""
    read -p "按回车开始授权..."
    
    echo ""
    echo "========================================"
    echo "授权链接:"
    echo ""
    
    "$BIN_DIR/cloudflared" tunnel login
    
    echo ""
    echo "========================================"
    read -p "完成授权后按回车继续..."
    
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "授权成功"
        return 0
    else
        print_error "授权失败"
        return 1
    fi
}

# 创建隧道
create_tunnel() {
    print_info "创建隧道..."
    
    source "$CONFIG_DIR/.env"
    
    # 清理旧隧道
    "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"
    sleep 3
    
    # 获取隧道信息
    TUNNEL_INFO=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || true)
    
    if [[ -z "$TUNNEL_INFO" ]]; then
        print_error "隧道创建失败"
        return 1
    fi
    
    TUNNEL_ID=$(echo "$TUNNEL_INFO" | awk '{print $1}')
    CRED_FILE=$(find /root/.cloudflared -name "*.json" -type f | head -1)
    
    if [[ -z "$CRED_FILE" ]]; then
        print_error "未找到凭证文件"
        return 1
    fi
    
    echo "TUNNEL_ID=$TUNNEL_ID" >> "$CONFIG_DIR/.env"
    echo "CRED_FILE=$CRED_FILE" >> "$CONFIG_DIR/.env"
    
    print_success "隧道创建成功"
    echo "隧道ID: $TUNNEL_ID"
    
    # 绑定域名
    print_info "绑定域名..."
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>/dev/null || {
        print_warning "DNS绑定可能需要手动配置"
    }
    
    return 0
}

# 创建正确的ingress配置
create_correct_config() {
    print_info "创建正确的ingress配置..."
    
    source "$CONFIG_DIR/.env"
    mkdir -p "$LOG_DIR"
    
    # 创建正确的ingress配置
    # 使用通配符路径匹配所有UUID
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
logfile: $LOG_DIR/cloudflared.log

ingress:
  # X-UI 面板
  - hostname: $DOMAIN
    service: http://127.0.0.1:$PANEL_PORT

  # 代理节点 - 通配符路径匹配所有UUID
  # 路径格式: /[UUID]
  - hostname: $DOMAIN
    path: /*  # 匹配所有路径
    service: http://127.0.0.1:$XRAY_PORT

  # 默认404
  - service: http_status:404
EOF
    
    print_success "ingress配置创建完成"
    echo ""
    echo "✅ 配置特点:"
    echo "  1. 通配符路径 /* 匹配所有UUID"
    echo "  2. Xray监听HTTP端口: $XRAY_PORT"
    echo "  3. Cloudflare提供TLS加密"
    echo ""
}

# 生成X-UI配置指南
create_xui_guide() {
    print_info "生成X-UI配置指南..."
    
    source "$CONFIG_DIR/.env"
    
    cat > "$CONFIG_DIR/xui-guide.md" << EOF
# X-UI 正确配置指南
# ⚠️ 重要：解决TLS冲突问题

## 1. 核心原则
❌ 错误：Cloudflare TLS + Xray TLS = 双TLS = 握手失败
✅ 正确：Cloudflare TLS + Xray HTTP = 单TLS = 正常工作

## 2. X-UI入站配置

### VLESS + WebSocket (正确配置)
\`\`\`
备注: VLESS节点
协议: VLESS
端口: $XRAY_PORT          # 必须与隧道配置一致
用户ID: [点击生成]        # 每个用户不同UUID
传输协议: WebSocket (ws)
WebSocket路径: /[UUID]    # 使用用户ID作为路径
                           # 例如: /a1b2c3d4-e5f6-7890-abcd-ef1234567890
主机名: $DOMAIN
TLS: ❌ 关闭              # ⚠️ 必须关闭！
安全: none
\`\`\`

### VMESS + WebSocket (正确配置)
\`\`\`
备注: VMESS节点
协议: VMESS
端口: $XRAY_PORT          # 必须与隧道配置一致
用户ID: [点击生成]        # 每个用户不同UUID
额外ID: 0
传输协议: WebSocket (ws)
WebSocket路径: /[UUID]    # 使用用户ID作为路径
主机名: $DOMAIN
TLS: ❌ 关闭              # ⚠️ 必须关闭！
\`\`\`

## 3. 客户端连接

### VLESS链接格式
\`\`\`
vless://[UUID]@$DOMAIN:443
  ?type=ws
  &security=none          # ⚠️ 不是tls！
  &host=$DOMAIN
  &path=%2F[UUID]         # URL编码的斜杠 + UUID
  &sni=$DOMAIN
\`\`\`

### 示例UUID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
\`\`\`
vless://a1b2c3d4-e5f6-7890-abcd-ef1234567890@$DOMAIN:443
  ?type=ws
  &security=none
  &host=$DOMAIN
  &path=%2Fa1b2c3d4-e5f6-7890-abcd-ef1234567890
  &sni=$DOMAIN
\`\`\`

## 4. Cloudflare设置
1. DNS记录:
   - 名称: $DOMAIN
   - 类型: CNAME
   - 目标: $TUNNEL_ID.cfargotunnel.com
   - 代理状态: ✅ 开启 (橙色云)

2. SSL/TLS:
   - 加密模式: Full
   - 始终使用HTTPS: ✅ 开启
   - 自动HTTPS重写: ✅ 开启

3. 网络:
   - WebSocket: ✅ 开启
   - IPv6兼容性: ✅ 开启

## 5. 工作原理
客户端 → HTTPS/TLS → Cloudflare → HTTP → Tunnel → HTTP → Xray → 目标网站
                    │
                    └─ Cloudflare提供TLS加密
                       Xray只处理HTTP流量
EOF
    
    print_success "配置指南已创建: $CONFIG_DIR/xui-guide.md"
}

# 创建系统服务
create_service() {
    print_info "创建系统服务..."
    
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=X-UI Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=always
RestartSec=5s
StandardOutput=append:$LOG_DIR/service.log
StandardError=append:$LOG_DIR/error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "系统服务创建完成"
}

# 启动服务
start_services() {
    print_info "启动服务..."
    
    # 确保X-UI运行
    if ! systemctl is-active --quiet x-ui; then
        print_info "启动X-UI服务..."
        systemctl start x-ui
        sleep 2
    fi
    
    # 启动隧道服务
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME
    
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_success "✅ 隧道服务启动成功"
        
        # 显示状态
        echo ""
        print_info "隧道状态:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || echo "无法获取隧道列表"
        
        return 0
    else
        print_error "❌ 隧道服务启动失败"
        journalctl -u $SERVICE_NAME -n 10 --no-pager
        return 1
    fi
}

# 显示结果
show_result() {
    echo ""
    print_success "═══════════════════════════════════════════════"
    print_success "           配置完成！"
    print_success "═══════════════════════════════════════════════"
    echo ""
    
    source "$CONFIG_DIR/.env" 2>/dev/null || return
    
    print_success "🎯 访问地址:"
    echo "  面板: https://$DOMAIN"
    echo "  节点: $DOMAIN:443"
    echo ""
    
    print_success "⚙️  配置要点:"
    echo "  ✅ Cloudflare提供TLS加密"
    echo "  ❌ Xray必须关闭TLS"
    echo "  🔗 路径使用UUID: /[用户ID]"
    echo "  📡 Xray端口: $XRAY_PORT"
    echo ""
    
    print_success "📋 X-UI设置步骤:"
    echo "  1. 创建入站，端口: $XRAY_PORT"
    echo "  2. 协议: VLESS/VMESS + WebSocket"
    echo "  3. 路径: /[生成的UUID]"
    echo "  4. 主机名: $DOMAIN"
    echo "  5. TLS: ❌ 关闭 (最重要！)"
    echo ""
    
    print_warning "⚠️  常见错误:"
    echo "  1. Xray开启TLS → 双TLS冲突"
    echo "  2. 路径不匹配 → 连接失败"
    echo "  3. Cloudflare DNS未生效 → 无法访问"
    echo ""
}

# 主安装流程
main_install() {
    show_title
    
    print_info "开始配置X-UI隧道 (解决TLS冲突)..."
    echo ""
    
    # 获取配置
    get_config
    
    # Cloudflare授权
    if ! cloudflare_auth; then
        print_error "授权失败"
        return 1
    fi
    
    # 创建隧道
    if ! create_tunnel; then
        print_error "隧道创建失败"
        return 1
    fi
    
    # 创建正确配置
    create_correct_config
    
    # 生成配置指南
    create_xui_guide
    
    # 创建服务
    create_service
    
    # 启动服务
    if ! start_services; then
        print_error "服务启动失败"
        return 1
    fi
    
    # 显示结果
    show_result
    
    print_success "✅ 配置完成！请严格按照指南设置X-UI。"
    
    return 0
}

# 快速修复TLS配置
fix_tls_config() {
    echo ""
    print_info "修复TLS配置..."
    
    if [ ! -f "$CONFIG_DIR/.env" ]; then
        print_error "未找到配置文件"
        return 1
    fi
    
    source "$CONFIG_DIR/.env"
    
    # 重新创建正确配置
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
logfile: $LOG_DIR/cloudflared.log

ingress:
  # X-UI 面板
  - hostname: $DOMAIN
    service: http://127.0.0.1:$PANEL_PORT

  # 代理节点 - 通配符路径
  - hostname: $DOMAIN
    path: /*
    service: http://127.0.0.1:$XRAY_PORT

  - service: http_status:404
EOF
    
    print_success "TLS配置已修复"
    echo ""
    echo "⚠️ 重要：Xray必须关闭TLS！"
    echo ""
    
    # 重启服务
    systemctl daemon-reload
    systemctl restart $SERVICE_NAME
    
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_success "✅ 服务重启成功"
    else
        print_error "❌ 服务重启失败"
    fi
}

# 显示菜单
show_menu() {
    show_title
    
    echo "请选择操作："
    echo ""
    echo "  1) 配置X-UI隧道 (解决TLS冲突)"
    echo "  2) 修复TLS配置"
    echo "  3) 查看配置指南"
    echo "  4) 重启服务"
    echo "  5) 退出"
    echo ""
    
    print_input "请选择: "
    read -r choice
    
    case "$choice" in
        1)
            if main_install; then
                read -p "按回车继续..."
            fi
            ;;
        2)
            fix_tls_config
            read -p "按回车继续..."
            ;;
        3)
            echo ""
            if [ -f "$CONFIG_DIR/xui-guide.md" ]; then
                cat "$CONFIG_DIR/xui-guide.md"
            else
                echo "未找到配置指南"
            fi
            read -p "按回车继续..."
            ;;
        4)
            systemctl restart $SERVICE_NAME
            systemctl restart x-ui
            print_success "服务已重启"
            read -p "按回车继续..."
            ;;
        5)
            echo "再见！"
            exit 0
            ;;
        *)
            echo "无效选择"
            sleep 1
            ;;
    esac
    
    show_menu
}

# 主函数
main() {
    if [[ $EUID -ne 0 ]]; then
        print_error "需要root权限"
        exit 1
    fi
    
    # 检查cloudflared
    if ! command -v cloudflared &> /dev/null; then
        print_error "请先安装cloudflared"
        echo "运行: curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared"
        exit 1
    fi
    
    case "${1:-}" in
        "install")
            main_install
            ;;
        "fix")
            fix_tls_config
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo $0 menu       # 显示菜单"
            echo "  sudo $0 install    # 安装配置"
            echo "  sudo $0 fix        # 修复TLS"
            exit 1
            ;;
    esac
}

# 运行
main "$@"