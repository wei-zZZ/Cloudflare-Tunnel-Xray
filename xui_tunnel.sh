#!/bin/bash
# ============================================
# X-UI + Cloudflare Tunnel 修复脚本
# 完全重写版本
# ============================================

set -e

# 颜色定义
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

# 配置目录
CONFIG_DIR="/etc/xui_tunnel"
LOG_DIR="/var/log/xui_tunnel"
BIN_DIR="/usr/local/bin"
SERVICE_NAME="xui-tunnel"

# 显示标题
show_header() {
    clear
    echo ""
    echo "==============================================="
    echo "      X-UI + Cloudflare Tunnel 修复工具"
    echo "==============================================="
    echo ""
}

# 清理旧配置
cleanup_old() {
    print_info "清理旧配置..."
    
    # 停止服务
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    
    # 杀死进程
    pkill -f cloudflared 2>/dev/null || true
    
    # 删除文件
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    rm -rf "$CONFIG_DIR"
    rm -rf "$LOG_DIR"
    
    # 清理cloudflared
    rm -rf /root/.cloudflared 2>/dev/null || true
    mkdir -p /root/.cloudflared
    
    systemctl daemon-reload
    sleep 2
    print_success "清理完成"
}

# 检查系统
check_system() {
    print_info "检查系统..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "需要root权限"
        exit 1
    fi
    
    # 安装基础工具
    apt-get update -y
    apt-get install -y curl wget 2>/dev/null || true
}

# 安装X-UI
install_xui() {
    print_info "检查X-UI..."
    
    if command -v x-ui &> /dev/null; then
        print_warning "X-UI已安装"
        
        # 确保服务运行
        if systemctl restart x-ui; then
            print_success "X-UI服务已启动"
        fi
        return 0
    fi
    
    # 安装X-UI
    print_info "安装X-UI..."
    wget -O x-ui.sh https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh
    chmod +x x-ui.sh
    echo "y" | bash x-ui.sh
    rm -f x-ui.sh
    
    sleep 3
    
    if systemctl is-active --quiet x-ui; then
        print_success "X-UI安装成功"
    else
        print_warning "X-UI启动较慢"
    fi
}

# 安装Cloudflared
install_cloudflared() {
    print_info "安装Cloudflared..."
    
    if command -v cloudflared &> /dev/null; then
        print_warning "Cloudflared已安装"
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
    
    print_success "Cloudflared安装成功"
}

# 获取配置
get_config() {
    echo ""
    print_info "请输入配置信息"
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
    
    # 隧道名称
    TUNNEL_NAME="xui-$(date +%s)"
    print_info "隧道名称: $TUNNEL_NAME (自动生成)"
    
    # 保存配置
    mkdir -p "$CONFIG_DIR"
    echo "DOMAIN=$DOMAIN" > "$CONFIG_DIR/.env"
    echo "TUNNEL_NAME=$TUNNEL_NAME" >> "$CONFIG_DIR/.env"
    
    echo ""
    print_success "配置已保存"
    echo "域名: $DOMAIN"
    echo "隧道: $TUNNEL_NAME"
}

# Cloudflare授权
cloudflare_auth() {
    echo ""
    print_info "Cloudflare授权"
    echo ""
    
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
    
    # 运行授权
    "$BIN_DIR/cloudflared" tunnel login
    
    echo ""
    echo "========================================"
    read -p "完成授权后按回车继续..."
    
    # 检查证书
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
    
    # 删除旧隧道
    "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    print_info "创建隧道: $TUNNEL_NAME"
    "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"
    sleep 3
    
    # 获取隧道信息
    TUNNEL_INFO=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || true)
    
    if [[ -z "$TUNNEL_INFO" ]]; then
        print_error "隧道创建失败"
        return 1
    fi
    
    TUNNEL_ID=$(echo "$TUNNEL_INFO" | awk '{print $1}')
    print_success "隧道创建成功"
    echo "隧道ID: $TUNNEL_ID"
    
    # 获取凭证文件
    CRED_FILE=$(find /root/.cloudflared -name "*.json" -type f | head -1)
    
    if [[ -z "$CRED_FILE" ]]; then
        print_error "未找到凭证文件"
        return 1
    fi
    
    echo "TUNNEL_ID=$TUNNEL_ID" >> "$CONFIG_DIR/.env"
    echo "CRED_FILE=$CRED_FILE" >> "$CONFIG_DIR/.env"
    
    # 绑定域名
    print_info "绑定域名..."
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>/dev/null || {
        print_warning "DNS绑定可能需要手动配置"
    }
    
    return 0
}

# 创建配置文件
create_config_files() {
    print_info "创建配置文件..."
    
    source "$CONFIG_DIR/.env"
    mkdir -p "$LOG_DIR"
    
    # YAML配置
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
logfile: $LOG_DIR/cloudflared.log
ingress:
  - hostname: $DOMAIN
    service: http://localhost:54321
  - service: http_status:404
EOF
    
    print_success "配置文件创建完成"
}

# 测试隧道
test_tunnel() {
    print_info "测试隧道..."
    
    # 停止可能运行的进程
    pkill -f cloudflared 2>/dev/null || true
    sleep 2
    
    # 测试运行
    timeout 5 "$BIN_DIR/cloudflared" tunnel --config "$CONFIG_DIR/config.yaml" run 2>&1 | tee /tmp/test.log &
    PID=$!
    
    sleep 3
    
    if ps -p $PID > /dev/null 2>&1; then
        print_success "隧道测试成功"
        kill $PID 2>/dev/null || true
        return 0
    else
        print_warning "隧道测试失败"
        echo "查看日志: /tmp/test.log"
        return 1
    fi
}

# 创建系统服务
create_system_service() {
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
    systemctl restart x-ui
    sleep 2
    
    # 启动隧道服务
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME
    
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_success "隧道服务启动成功"
        
        # 显示隧道状态
        echo ""
        print_info "隧道状态:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || echo "无法获取隧道列表"
        
        return 0
    else
        print_error "隧道服务启动失败"
        journalctl -u $SERVICE_NAME -n 10 --no-pager
        return 1
    fi
}

# 显示安装结果
show_result() {
    echo ""
    print_success "安装完成！"
    echo ""
    
    source "$CONFIG_DIR/.env" 2>/dev/null || return
    
    print_success "访问地址:"
    echo "  https://$DOMAIN"
    echo ""
    
    print_success "管理命令:"
    echo "  状态: systemctl status $SERVICE_NAME"
    echo "  重启: systemctl restart $SERVICE_NAME"
    echo "  日志: journalctl -u $SERVICE_NAME -f"
    echo ""
    
    print_info "配置检查:"
    echo "  1. 确保Cloudflare DNS正确"
    echo "  2. SSL/TLS模式设为 Full"
    echo "  3. 等待DNS生效"
    echo ""
    
    print_info "X-UI配置:"
    echo "  本地访问: http://服务器IP:54321"
    echo "  用户名: admin"
    echo "  密码: admin"
    echo ""
}

# 主安装流程
main_install() {
    show_header
    
    print_info "开始修复安装..."
    echo ""
    
    # 清理环境
    cleanup_old
    
    # 检查系统
    check_system
    
    # 安装组件
    install_xui
    install_cloudflared
    
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
    
    # 创建配置
    create_config_files
    
    # 测试隧道
    test_tunnel
    
    # 创建服务
    create_system_service
    
    # 启动服务
    if ! start_services; then
        print_error "服务启动失败"
        return 1
    fi
    
    # 显示结果
    show_result
    
    print_success "完成！"
    return 0
}

# 快速修复
quick_fix() {
    echo ""
    print_info "快速修复..."
    
    # 停止服务
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    pkill -f cloudflared 2>/dev/null || true
    sleep 2
    
    if [ -f "$CONFIG_DIR/.env" ]; then
        source "$CONFIG_DIR/.env"
        
        # 重新创建配置文件
        cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
logfile: $LOG_DIR/cloudflared.log
ingress:
  - hostname: $DOMAIN
    service: http://localhost:54321
  - service: http_status:404
EOF
        
        print_success "配置文件已修复"
        
        # 重启服务
        systemctl daemon-reload
        systemctl restart $SERVICE_NAME
        
        sleep 3
        
        if systemctl is-active --quiet $SERVICE_NAME; then
            print_success "修复成功"
        else
            print_error "修复失败"
        fi
    else
        print_error "未找到配置文件"
    fi
}

# 查看状态
show_status() {
    echo ""
    print_info "服务状态:"
    echo ""
    
    echo "X-UI状态:"
    systemctl status x-ui --no-pager | head -8
    echo ""
    
    echo "隧道状态:"
    systemctl status $SERVICE_NAME --no-pager | head -8
    echo ""
    
    echo "隧道列表:"
    "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || echo "无法获取隧道列表"
    echo ""
}

# 卸载
uninstall_all() {
    echo ""
    print_warning "卸载所有配置..."
    echo ""
    
    read -p "确认卸载？(y/N): " -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "取消卸载"
        return
    fi
    
    # 停止服务
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    systemctl stop x-ui 2>/dev/null || true
    
    # 删除文件
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    rm -rf "$CONFIG_DIR"
    rm -rf "$LOG_DIR"
    rm -rf /root/.cloudflared 2>/dev/null || true
    
    # 删除二进制文件
    rm -f "$BIN_DIR/cloudflared"
    
    systemctl daemon-reload
    
    print_success "卸载完成"
    echo "X-UI面板仍然保留，可以通过 http://服务器IP:54321 访问"
}

# 显示菜单
show_menu() {
    show_header
    
    echo "请选择操作："
    echo ""
    echo "  1) 一键修复安装"
    echo "  2) 快速修复"
    echo "  3) 查看状态"
    echo "  4) 重启服务"
    echo "  5) 卸载"
    echo "  6) 退出"
    echo ""
    
    print_input "请选择 (1-6): "
    read -r choice
    
    case "$choice" in
        1)
            if main_install; then
                read -p "按回车继续..."
            fi
            ;;
        2)
            quick_fix
            read -p "按回车继续..."
            ;;
        3)
            show_status
            read -p "按回车继续..."
            ;;
        4)
            systemctl restart $SERVICE_NAME
            systemctl restart x-ui
            print_success "服务已重启"
            read -p "按回车继续..."
            ;;
        5)
            uninstall_all
            read -p "按回车继续..."
            ;;
        6)
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
    
    case "${1:-}" in
        "install")
            main_install
            ;;
        "fix")
            quick_fix
            ;;
        "status")
            show_header
            show_status
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_header
            echo "使用方法:"
            echo "  sudo $0 menu       # 显示菜单"
            echo "  sudo $0 install    # 安装"
            echo "  sudo $0 fix        # 修复"
            echo "  sudo $0 status     # 状态"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"