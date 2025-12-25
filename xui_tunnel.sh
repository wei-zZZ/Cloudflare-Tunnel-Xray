#!/bin/bash
# ============================================
# X-UI + Cloudflare Tunnel 正确配置脚本
# 修复ingress配置问题
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
    echo "      X-UI 隧道正确配置工具"
    echo "==============================================="
    echo ""
}

# 获取配置
get_config() {
    echo ""
    print_info "配置信息"
    echo ""
    
    # 面板域名
    while true; do
        print_input "请输入面板访问域名 (例如: panel.9420ce.top):"
        read -r PANEL_DOMAIN
        
        if [[ -z "$PANEL_DOMAIN" ]]; then
            print_error "域名不能为空"
            continue
        fi
        
        if [[ "$PANEL_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "域名格式错误"
        fi
    done
    
    # 节点域名
    echo ""
    print_input "请输入节点访问域名 (例如: proxy.9420ce.top 或直接回车使用: $PANEL_DOMAIN):"
    read -r NODE_DOMAIN
    
    if [[ -z "$NODE_DOMAIN" ]]; then
        NODE_DOMAIN="$PANEL_DOMAIN"
    fi
    
    # 节点端口
    echo ""
    print_input "请输入节点端口 [默认: 10086]:"
    read -r NODE_PORT
    NODE_PORT=${NODE_PORT:-"10086"}
    
    # 节点路径
    echo ""
    print_input "请输入节点WebSocket路径 [默认: /ws]:"
    read -r NODE_PATH
    NODE_PATH=${NODE_PATH:-"/ws"}
    
    # 隧道名称
    TUNNEL_NAME="xui-$(date +%s)"
    
    # 保存配置
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/.env" << EOF
PANEL_DOMAIN=$PANEL_DOMAIN
NODE_DOMAIN=$NODE_DOMAIN
NODE_PORT=$NODE_PORT
NODE_PATH=$NODE_PATH
TUNNEL_NAME=$TUNNEL_NAME
EOF
    
    echo ""
    print_success "配置已保存:"
    echo "  面板域名: $PANEL_DOMAIN"
    echo "  节点域名: $NODE_DOMAIN"
    echo "  节点端口: $NODE_PORT"
    echo "  节点路径: $NODE_PATH"
    echo "  隧道名称: $TUNNEL_NAME"
    echo ""
}

# Cloudflare授权
cloudflare_auth() {
    echo ""
    print_info "Cloudflare授权"
    echo ""
    
    # 清理旧授权
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
    echo "凭证文件: $(basename "$CRED_FILE")"
    
    # 绑定域名（面板）
    print_info "绑定面板域名..."
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$PANEL_DOMAIN" 2>/dev/null || {
        print_warning "面板域名绑定可能需要手动配置"
    }
    
    # 绑定域名（节点）
    if [[ "$PANEL_DOMAIN" != "$NODE_DOMAIN" ]]; then
        print_info "绑定节点域名..."
        "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$NODE_DOMAIN" 2>/dev/null || {
            print_warning "节点域名绑定可能需要手动配置"
        }
    fi
    
    return 0
}

# 创建正确的ingress配置
create_correct_config() {
    print_info "创建正确的ingress配置..."
    
    source "$CONFIG_DIR/.env"
    mkdir -p "$LOG_DIR"
    
    # 创建正确的ingress配置
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
logfile: $LOG_DIR/cloudflared.log

ingress:
  # X-UI 面板
  - hostname: $PANEL_DOMAIN
    service: http://127.0.0.1:54321

  # 代理节点 - WebSocket
  - hostname: $NODE_DOMAIN
    path: $NODE_PATH
    service: http://127.0.0.1:$NODE_PORT

  # 代理节点 - 备用路径
  - hostname: $NODE_DOMAIN
    path: /vless
    service: http://127.0.0.1:$NODE_PORT

  - hostname: $NODE_DOMAIN
    path: /vmess
    service: http://127.0.0.1:$NODE_PORT

  # 默认404
  - service: http_status:404
EOF
    
    print_success "ingress配置创建完成"
    echo ""
    echo "配置文件内容:"
    echo "========================================"
    cat "$CONFIG_DIR/config.yaml"
    echo "========================================"
    echo ""
}

# 创建X-UI节点配置指南
create_xui_guide() {
    print_info "创建X-UI配置指南..."
    
    source "$CONFIG_DIR/.env"
    
    cat > "$CONFIG_DIR/xui-setup.md" << EOF
# X-UI 节点配置指南

## 1. 登录X-UI面板
访问: http://服务器IP:54321
用户名: admin
密码: admin

## 2. 创建入站节点

### VLESS + WebSocket + TLS
\`\`\`
备注: VLESS节点
协议: VLESS
端口: $NODE_PORT
用户ID: [点击生成]
传输协议: WebSocket (ws)
WebSocket路径: $NODE_PATH
主机名: $NODE_DOMAIN
TLS: 开启
\`\`\`

### VMESS + WebSocket + TLS
\`\`\`
备注: VMESS节点
协议: VMESS
端口: $NODE_PORT
用户ID: [点击生成]
额外ID: 0
传输协议: WebSocket (ws)
WebSocket路径: $NODE_PATH
主机名: $NODE_DOMAIN
TLS: 开启
\`\`\`

## 3. 客户端连接配置

### VLESS 客户端链接
\`\`\`
vless://[UUID]@$NODE_DOMAIN:443?type=ws&security=tls&host=$NODE_DOMAIN&path=${NODE_PATH//\//%2F}&sni=$NODE_DOMAIN#VLESS节点
\`\`\`

### VMESS 客户端链接
\`\`\`
vmess://ewogICJ2IjogIjIiLAogICJwcyI6ICJWTUVTUyBub2RlIiwKICAiYWRkIjogIiROT0RFX0RPTUFJTiIsCiAgInBvcnQiOiAiNDQzIiwKICAiaWQiOiAiW1VVSURdIiwKICAiYWlkIjogIjAiLAogICJuZXQiOiAid3MiLAogICJ0eXBlIjogIm5vbmUiLAogICJob3N0IjogIiROT0RFX0RPTUFJTiIsCiAgInBhdGgiOiAiJE5PREVfUEFUSCIsCiAgInRsczoiOiAidGxzIiwKICAic25pIjogIiROT0RFX0RPTUFJTiIKfQ==
\`\`\`

## 4. Cloudflare 设置检查
1. DNS 记录:
   - $PANEL_DOMAIN → $TUNNEL_ID.cfargotunnel.com
   - $NODE_DOMAIN → $TUNNEL_ID.cfargotunnel.com

2. SSL/TLS 设置:
   - 加密模式: Full
   - 始终使用HTTPS: 开启
   - WebSocket: 开启
EOF
    
    print_success "配置指南已创建: $CONFIG_DIR/xui-setup.md"
}

# 测试配置
test_config() {
    print_info "测试配置..."
    
    # 停止可能运行的进程
    pkill -f cloudflared 2>/dev/null || true
    sleep 2
    
    echo "测试运行隧道 (5秒)..."
    timeout 5 "$BIN_DIR/cloudflared" tunnel --config "$CONFIG_DIR/config.yaml" run 2>&1 | tee /tmp/test.log &
    PID=$!
    
    sleep 3
    
    if ps -p $PID > /dev/null 2>&1; then
        print_success "✅ 配置测试成功"
        kill $PID 2>/dev/null || true
        return 0
    else
        print_warning "⚠️ 配置测试失败"
        echo "错误信息:"
        tail -10 /tmp/test.log
        return 1
    fi
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
    echo "  面板: https://$PANEL_DOMAIN"
    echo "  节点: $NODE_DOMAIN:443"
    echo ""
    
    print_success "🔧 节点配置:"
    echo "  端口: $NODE_PORT"
    echo "  路径: $NODE_PATH"
    echo "  协议: WebSocket + TLS"
    echo ""
    
    print_success "📋 X-UI设置:"
    echo "  1. 创建入站，端口: $NODE_PORT"
    echo "  2. 传输协议: WebSocket"
    echo "  3. 路径: $NODE_PATH"
    echo "  4. 主机名: $NODE_DOMAIN"
    echo "  5. 开启TLS"
    echo ""
    
    print_info "🛠️  管理命令:"
    echo "  状态: systemctl status $SERVICE_NAME"
    echo "  日志: journalctl -u $SERVICE_NAME -f"
    echo "  重启: systemctl restart $SERVICE_NAME"
    echo ""
    
    print_warning "⚠️  重要提示:"
    echo "  1. 检查Cloudflare DNS设置"
    echo "  2. SSL/TLS模式设为 Full"
    echo "  3. 开启WebSocket支持"
    echo "  4. 等待DNS生效"
    echo ""
}

# 主安装流程
main_install() {
    show_title
    
    print_info "开始正确配置X-UI隧道..."
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
    
    # 创建配置指南
    create_xui_guide
    
    # 测试配置
    test_config
    
    # 创建服务
    create_service
    
    # 启动服务
    if ! start_services; then
        print_error "服务启动失败"
        return 1
    fi
    
    # 显示结果
    show_result
    
    print_success "✅ 配置完成！现在可以在X-UI面板创建节点了。"
    
    return 0
}

# 快速修复配置
quick_fix_config() {
    echo ""
    print_info "快速修复ingress配置..."
    
    if [ ! -f "$CONFIG_DIR/.env" ]; then
        print_error "未找到配置文件"
        return 1
    fi
    
    source "$CONFIG_DIR/.env"
    
    # 重新创建正确的ingress配置
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
logfile: $LOG_DIR/cloudflared.log

ingress:
  # X-UI 面板
  - hostname: $PANEL_DOMAIN
    service: http://127.0.0.1:54321

  # 代理节点 - WebSocket
  - hostname: $NODE_DOMAIN
    path: $NODE_PATH
    service: http://127.0.0.1:$NODE_PORT

  # 默认404
  - service: http_status:404
EOF
    
    print_success "ingress配置已修复"
    
    # 重启服务
    systemctl daemon-reload
    systemctl restart $SERVICE_NAME
    
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_success "✅ 服务重启成功"
        
        echo ""
        print_info "新的ingress配置:"
        cat "$CONFIG_DIR/config.yaml"
    else
        print_error "❌ 服务重启失败"
    fi
}

# 显示菜单
show_menu() {
    show_title
    
    echo "请选择操作："
    echo ""
    echo "  1) 正确配置隧道"
    echo "  2) 修复ingress配置"
    echo "  3) 查看配置"
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
            quick_fix_config
            read -p "按回车继续..."
            ;;
        3)
            echo ""
            if [ -f "$CONFIG_DIR/.env" ]; then
                print_info "当前配置:"
                cat "$CONFIG_DIR/.env"
                echo ""
                
                if [ -f "$CONFIG_DIR/config.yaml" ]; then
                    print_info "ingress配置:"
                    cat "$CONFIG_DIR/config.yaml"
                fi
            else
                echo "未找到配置"
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
            quick_fix_config
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo $0 menu       # 显示菜单"
            echo "  sudo $0 install    # 安装配置"
            echo "  sudo $0 fix        # 修复配置"
            exit 1
            ;;
    esac
}

# 运行
main "$@"