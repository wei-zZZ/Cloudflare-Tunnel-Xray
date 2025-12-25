#!/bin/bash
# ============================================
# X-UI + Cloudflare Tunnel 一键修复安装脚本
# 版本: 8.0 - 修复隧道状态问题
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
SERVICE_NAME="xui-tunnel"

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    X-UI 隧道修复安装脚本                    ║"
    echo "║             版本: 8.0                        ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
}

# ----------------------------
# 清理环境
# ----------------------------
clean_environment() {
    print_info "清理环境..."
    
    # 停止服务
    systemctl stop $SERVICE_NAME.service 2>/dev/null || true
    systemctl stop x-ui 2>/dev/null || true
    
    # 杀死进程
    pkill -f cloudflared 2>/dev/null || true
    pkill -f x-ui 2>/dev/null || true
    
    sleep 2
    
    # 清理旧配置
    rm -rf "$CONFIG_DIR" 2>/dev/null || true
    rm -rf "$LOG_DIR" 2>/dev/null || true
    rm -f /etc/systemd/system/$SERVICE_NAME.service 2>/dev/null || true
    
    # 清理Cloudflare旧数据
    rm -rf /root/.cloudflared 2>/dev/null || true
    mkdir -p /root/.cloudflared
    
    systemctl daemon-reload
    print_success "环境清理完成"
}

# ----------------------------
# 系统检查
# ----------------------------
check_system() {
    print_info "检查系统..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行"
        exit 1
    fi
    
    # 安装基础工具
    apt-get update -y
    apt-get install -y curl wget 2>/dev/null || true
}

# ----------------------------
# 安装 X-UI
# ----------------------------
install_xui() {
    print_info "安装 X-UI 面板..."
    
    # 检查是否已安装
    if systemctl is-active --quiet x-ui; then
        print_warning "X-UI 已安装且运行中"
        return 0
    fi
    
    # 如果x-ui命令存在但服务没运行
    if command -v x-ui &> /dev/null; then
        print_info "启动X-UI服务..."
        systemctl start x-ui
        sleep 2
        if systemctl is-active --quiet x-ui; then
            print_success "X-UI 启动成功"
            return 0
        fi
    fi
    
    # 安装X-UI
    print_info "下载安装X-UI..."
    curl -L -o x-ui-install.sh https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh
    chmod +x x-ui-install.sh
    
    # 自动安装（不交互）
    echo "y" | bash x-ui-install.sh
    
    # 等待启动
    for i in {1..10}; do
        if systemctl is-active --quiet x-ui; then
            print_success "X-UI 启动成功"
            rm -f x-ui-install.sh
            return 0
        fi
        echo -n "."
        sleep 2
    done
    
    print_warning "X-UI 启动较慢"
    rm -f x-ui-install.sh
    return 0
}

# ----------------------------
# 安装 Cloudflared
# ----------------------------
install_cloudflared() {
    print_info "安装 Cloudflared..."
    
    if command -v cloudflared &> /dev/null; then
        print_warning "cloudflared 已安装"
        VERSION=$("$BIN_DIR/cloudflared" --version 2>/dev/null | head -1 || echo "未知")
        print_info "当前版本: $VERSION"
        return 0
    fi
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)
            print_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    curl -L -o /tmp/cloudflared "$URL"
    mv /tmp/cloudflared "$BIN_DIR/cloudflared"
    chmod +x "$BIN_DIR/cloudflared"
    print_success "cloudflared 安装成功"
    
    VERSION=$("$BIN_DIR/cloudflared" --version 2>/dev/null | head -1 || echo "未知")
    print_info "版本: $VERSION"
}

# ----------------------------
# 获取用户输入
# ----------------------------
get_user_input() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           配置信息"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 域名
    while true; do
        print_input "请输入面板访问域名 (例如: hk2xui.9420ce.top):"
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
    
    # 隧道名称
    TUNNEL_NAME="xui-tunnel-$(date +%s)"  # 使用时间戳避免冲突
    print_info "隧道名称: $TUNNEL_NAME (自动生成)"
    
    echo ""
    print_success "配置确认:"
    echo "  域名: https://$DOMAIN"
    echo "  隧道: $TUNNEL_NAME"
    echo ""
    
    # 保存配置
    mkdir -p "$CONFIG_DIR"
    echo "DOMAIN=$DOMAIN" > "$CONFIG_DIR/config"
    echo "TUNNEL_NAME=$TUNNEL_NAME" >> "$CONFIG_DIR/config"
}

# ----------------------------
# Cloudflare 授权
# ----------------------------
cloudflare_auth() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "        Cloudflare 授权"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 确保目录存在
    mkdir -p /root/.cloudflared
    
    echo "授权步骤："
    echo "1. 复制下面的链接到浏览器"
    echo "2. 登录 Cloudflare 账户"
    echo "3. 选择域名并授权"
    echo "4. 返回终端继续"
    echo ""
    read -p "按回车开始授权..." -r
    
    echo ""
    echo "=============================================="
    echo "授权链接:"
    echo ""
    
    # 执行授权
    "$BIN_DIR/cloudflared" tunnel login
    
    echo ""
    echo "=============================================="
    read -p "完成授权后按回车继续..." -r
    
    # 验证授权
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "✅ 授权成功"
        return 0
    else
        print_error "❌ 授权失败，证书文件未生成"
        return 1
    fi
}

# ----------------------------
# 创建并配置隧道
# ----------------------------
setup_tunnel() {
    print_info "创建隧道..."
    
    # 获取配置
    source "$CONFIG_DIR/config" 2>/dev/null || {
        print_error "无法加载配置"
        return 1
    }
    
    # 1. 删除可能存在的同名隧道
    print_info "清理旧隧道..."
    "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 2. 创建新隧道
    print_info "创建新隧道: $TUNNEL_NAME"
    if ! "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"; then
        print_error "隧道创建失败"
        return 1
    fi
    sleep 3
    
    # 3. 获取隧道ID
    TUNNEL_INFO=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || true)
    
    if [[ -z "$TUNNEL_INFO" ]]; then
        print_error "无法找到新创建的隧道"
        return 1
    fi
    
    TUNNEL_ID=$(echo "$TUNNEL_INFO" | awk '{print $1}')
    print_success "✅ 隧道创建成功"
    print_info "隧道ID: $TUNNEL_ID"
    
    # 4. 获取凭证文件
    CREDENTIALS_FILE=$(find /root/.cloudflared -name "*.json" -type f | head -1)
    
    if [[ -z "$CREDENTIALS_FILE" ]] || [[ ! -f "$CREDENTIALS_FILE" ]]; then
        print_error "未找到凭证文件"
        return 1
    fi
    
    print_success "凭证文件: $(basename "$CREDENTIALS_FILE")"
    
    # 5. 保存隧道信息
    echo "TUNNEL_ID=$TUNNEL_ID" >> "$CONFIG_DIR/config"
    echo "CREDENTIALS_FILE=$CREDENTIALS_FILE" >> "$CONFIG_DIR/config"
    
    # 6. 绑定域名
    print_info "绑定域名到隧道..."
    if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>&1 | tee /tmp/dns_bind.log; then
        print_success "✅ 域名绑定成功"
    else
        print_warning "⚠️  域名绑定可能需要手动配置"
        echo "请在Cloudflare DNS中添加CNAME记录:"
        echo "  名称: $DOMAIN"
        echo "  目标: $TUNNEL_ID.cfargotunnel.com"
        echo "  TTL: 自动"
        echo "  代理状态: 开启 (橙色云)"
    fi
    
    return 0
}

# ----------------------------
# 创建配置文件
# ----------------------------
create_config() {
    print_info "创建配置文件..."
    
    source "$CONFIG_DIR/config" 2>/dev/null || {
        print_error "无法加载配置"
        return 1
    }
    
    mkdir -p "$LOG_DIR"
    
    # 创建极简YAML配置
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE
logfile: $LOG_DIR/cloudflared.log
ingress:
  - hostname: $DOMAIN
    service: http://localhost:54321
  - service: http_status:404
EOF
    
    print_success "配置文件创建完成"
    echo "配置文件: $CONFIG_DIR/config.yaml"
}

# ----------------------------
# 测试隧道
# ----------------------------
test_tunnel() {
    print_info "测试隧道连接..."
    
    source "$CONFIG_DIR/config" 2>/dev/null || return 1
    
    echo "测试运行隧道 (5秒)..."
    timeout 5 "$BIN_DIR/cloudflared" tunnel --config "$CONFIG_DIR/config.yaml" run 2>&1 | tee /tmp/tunnel_test.log &
    TEST_PID=$!
    
    sleep 3
    
    if ps -p $TEST_PID > /dev/null 2>&1; then
        print_success "✅ 隧道测试成功"
        kill $TEST_PID 2>/dev/null || true
        return 0
    else
        print_error "❌ 隧道测试失败"
        echo ""
        echo "错误信息:"
        tail -10 /tmp/tunnel_test.log
        return 1
    fi
}

# ----------------------------
# 创建系统服务
# ----------------------------
create_service() {
    print_info "创建系统服务..."
    
    cat > /etc/systemd/system/$SERVICE_NAME.service << 'EOF'
[Unit]
Description=X-UI Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/xui_tunnel/config.yaml run
Restart=always
RestartSec=5s
StandardOutput=journal
StandardError=journal

# 防止日志过大
StandardOutput=append:/var/log/xui_tunnel/tunnel.log
StandardError=append:/var/log/xui_tunnel/tunnel-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "系统服务创建完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_service() {
    print_info "启动服务..."
    
    # 确保X-UI运行
    if ! systemctl is-active --quiet x-ui; then
        print_info "启动X-UI服务..."
        systemctl start x-ui
        sleep 2
    fi
    
    # 启动隧道服务
    systemctl enable $SERVICE_NAME.service
    systemctl start $SERVICE_NAME.service
    
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME.service; then
        print_success "✅ 隧道服务启动成功"
        
        # 显示隧道状态
        echo ""
        print_info "隧道状态:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || echo "无法获取隧道列表"
        
        return 0
    else
        print_error "❌ 隧道服务启动失败"
        echo ""
        print_info "查看错误日志:"
        journalctl -u $SERVICE_NAME.service -n 10 --no-pager
        return 1
    fi
}

# ----------------------------
# 显示结果
# ----------------------------
show_result() {
    echo ""
    print_success "═══════════════════════════════════════════════"
    print_success "           安装完成！"
    print_success "═══════════════════════════════════════════════"
    echo ""
    
    source "$CONFIG_DIR/config" 2>/dev/null || {
        print_error "无法加载配置"
        return
    }
    
    print_success "🎉 面板访问地址:"
    print_success "   https://$DOMAIN"
    echo ""
    
    print_success "🔐 默认登录凭据:"
    print_success "   用户名: admin"
    print_success "   密码: admin"
    echo ""
    
    print_info "🛠️  管理命令:"
    echo "  状态: systemctl status $SERVICE_NAME"
    echo "  重启: systemctl restart $SERVICE_NAME"
    echo "  日志: journalctl -u $SERVICE_NAME -f"
    echo "  停止: systemctl stop $SERVICE_NAME"
    echo ""
    
    print_info "📋 X-UI配置步骤:"
    echo "  1. 访问 http://服务器IP:54321 登录X-UI"
    echo "  2. 创建入站节点，端口: 10000-20000"
    echo "  3. 协议: VLESS + WS + TLS"
    echo "  4. 主机名: $DOMAIN"
    echo "  5. 客户端连接: $DOMAIN:443"
    echo ""
    
    print_warning "⚠️  重要提示:"
    echo "  1. 首次登录后立即修改密码"
    echo "  2. 检查Cloudflare DNS设置"
    echo "  3. SSL/TLS模式设置为 Full"
    echo "  4. 等待DNS生效 (最多24小时)"
    echo ""
    
    print_info "🔧 故障排除:"
    echo "  查看隧道状态: /usr/local/bin/cloudflared tunnel list"
    echo "  测试隧道: /usr/local/bin/cloudflared tunnel --config $CONFIG_DIR/config.yaml run"
    echo "  查看日志: tail -f /var/log/xui_tunnel/tunnel.log"
    echo ""
}

# ----------------------------
# 快速修复
# ----------------------------
quick_fix() {
    echo ""
    print_info "快速修复隧道..."
    
    # 停止服务
    systemctl stop $SERVICE_NAME.service 2>/dev/null || true
    pkill -f cloudflared 2>/dev/null || true
    sleep 2
    
    # 检查配置
    if [ -f "$CONFIG_DIR/config" ]; then
        source "$CONFIG_DIR/config"
        
        # 重新创建配置文件
        cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE
logfile: $LOG_DIR/cloudflared.log
ingress:
  - hostname: $DOMAIN
    service: http://localhost:54321
  - service: http_status:404
EOF
        
        print_success "配置文件已修复"
    else
        print_error "未找到配置文件"
        return 1
    fi
    
    # 重启服务
    systemctl daemon-reload
    systemctl restart $SERVICE_NAME.service
    
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME.service; then
        print_success "✅ 修复成功"
        return 0
    else
        print_error "❌ 修复失败"
        journalctl -u $SERVICE_NAME.service -n 10 --no-pager
        return 1
    fi
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    show_title
    
    print_info "开始修复安装..."
    echo ""
    
    # 清理环境
    clean_environment
    
    # 系统检查
    check_system
    
    # 安装组件
    install_xui
    install_cloudflared
    
    # 获取配置
    get_user_input
    
    # Cloudflare授权
    if ! cloudflare_auth; then
        print_error "授权失败，安装中止"
        return 1
    fi
    
    # 创建隧道
    if ! setup_tunnel; then
        print_error "隧道创建失败"
        return 1
    fi
    
    # 创建配置
    create_config
    
    # 测试隧道
    if ! test_tunnel; then
        print_warning "隧道测试失败，但继续安装..."
    fi
    
    # 创建服务
    create_service
    
    # 启动服务
    if ! start_service; then
        print_error "服务启动失败"
        return 1
    fi
    
    # 显示结果
    show_result
    
    print_success "🎊 安装完成！"
    
    return 0
}

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    show_title
    
    echo "请选择操作："
    echo ""
    echo "  1) 一键修复安装"
    echo "  2) 快速修复隧道"
    echo "  3) 查看服务状态"
    echo "  4) 查看隧道信息"
    echo "  5) 重启所有服务"
    echo "  6) 卸载清理"
    echo "  7) 退出"
    echo ""
    
    print_input "请输入选项 (1-7): "
    read -r choice
    
    case "$choice" in
        1)
            if main_install; then
                read -p "按回车返回菜单..." -r
            fi
            ;;
        2)
            quick_fix
            read -p "按回车返回菜单..." -r
            ;;
        3)
            echo ""
            print_info "服务状态:"
            echo "X-UI面板:"
            systemctl status x-ui --no-pager | head -8
            echo ""
            echo "隧道服务:"
            systemctl status $SERVICE_NAME.service --no-pager | head -8
            read -p "按回车返回菜单..." -r
            ;;
        4)
            echo ""
            print_info "隧道信息:"
            /usr/local/bin/cloudflared tunnel list 2>/dev/null || echo "无法获取隧道列表"
            echo ""
            if [ -f "$CONFIG_DIR/config" ]; then
                print_info "配置文件:"
                cat "$CONFIG_DIR/config"
                echo ""
                print_info "YAML配置:"
                cat "$CONFIG_DIR/config.yaml" 2>/dev/null || echo "未找到YAML配置"
            fi
            read -p "按回车返回菜单..." -r
            ;;
        5)
            print_info "重启所有服务..."
            systemctl restart x-ui
            systemctl restart $SERVICE_NAME.service
            sleep 2
            print_success "服务已重启"
            read -p "按回车返回菜单..." -r
            ;;
        6)
            print_warning "卸载清理..."
            systemctl stop $SERVICE_NAME.service 2>/dev/null || true
            systemctl disable $SERVICE_NAME.service 2>/dev/null || true
            systemctl stop x-ui 2>/dev/null || true
            pkill -f cloudflared 2>/dev/null || true
            rm -f /etc/systemd/system/$SERVICE_NAME.service
            rm -rf "$CONFIG_DIR" "$LOG_DIR"
            rm -rf /root/.cloudflared 2>/dev/null || true
            systemctl daemon-reload
            print_success "已清理"
            read -p "按回车返回菜单..." -r
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
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行"
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
            systemctl status $SERVICE_NAME.service --no-pager
            echo ""
            echo "隧道列表:"
            /usr/local/bin/cloudflared tunnel list 2>/dev/null || echo "无法获取隧道列表"
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo ./xui_fix.sh menu        # 显示菜单"
            echo "  sudo ./xui_fix.sh install     # 修复安装"
            echo "  sudo ./xui_fix.sh fix         # 快速修复"
            echo "  sudo ./xui_fix.sh status      # 查看状态"
            exit 1
            ;;
    esac
}

main "$@"