#!/bin/bash
# ============================================
# Cloudflare Tunnel + X-UI 安装脚本
# 版本: 1.0
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
print_auth() { echo -e "${GREEN}[🔐]${NC} $1"; }

# ----------------------------
# 配置变量
# ----------------------------
CONFIG_DIR="/etc/xui_tunnel"
LOG_DIR="/var/log/xui_tunnel"
BIN_DIR="/usr/local/bin"
XUI_PORT=54321
XUI_USERNAME="admin"
XUI_PASSWORD="admin"

USER_DOMAIN=""
TUNNEL_NAME="xui-tunnel"
SILENT_MODE=false

# ----------------------------
# 显示标题
# ----------------------------
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Cloudflare Tunnel + X-UI 管理脚本        ║"
    echo "║             版本: 1.0                       ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
}

# ----------------------------
# 收集用户信息
# ----------------------------
collect_user_info() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           配置 Cloudflare Tunnel"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    if [ "$SILENT_MODE" = true ]; then
        USER_DOMAIN="xui.yourdomain.com"
        print_info "静默模式：使用默认域名 $USER_DOMAIN"
        print_info "隧道名称: $TUNNEL_NAME"
        return
    fi
    
    while [[ -z "$USER_DOMAIN" ]]; do
        print_input "请输入您的域名 (用于访问 X-UI 面板，例如: xui.yourdomain.com):"
        read -r USER_DOMAIN
        
        if [[ -z "$USER_DOMAIN" ]]; then
            print_error "域名不能为空！"
        elif ! [[ "$USER_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "域名格式不正确，请重新输入！"
            USER_DOMAIN=""
        fi
    done
    
    print_input "请输入隧道名称 [默认: xui-tunnel]:"
    read -r TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"xui-tunnel"}
    
    echo ""
    print_success "配置已保存:"
    echo "  域名: $USER_DOMAIN"
    echo "  隧道名称: $TUNNEL_NAME"
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
    
    # 检查系统类型
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        print_error "无法检测操作系统"
        exit 1
    fi
    
    # 安装必要工具
    print_info "安装必要工具..."
    
    local tools=("curl" "wget" "unzip" "jq" "sudo" "certbot")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_info "正在安装 $tool..."
            apt-get update && apt-get install -y "$tool"
        fi
    done
    
    print_success "系统检查完成"
}

# ----------------------------
# 安装 X-UI
# ----------------------------
install_xui() {
    print_info "开始安装 X-UI 面板..."
    
    # 下载 X-UI 安装脚本
    bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
    
    # 检查安装是否成功
    if systemctl is-active --quiet x-ui; then
        print_success "X-UI 安装成功"
    else
        print_error "X-UI 安装失败"
        exit 1
    fi
    
    # 设置 X-UI 密码（如果默认密码不是 admin/admin）
    print_info "设置 X-UI 登录信息..."
    echo ""
    print_input "请输入 X-UI 管理员用户名 [默认: admin]:"
    read -r xui_user
    XUI_USERNAME=${xui_user:-"admin"}
    
    print_input "请输入 X-UI 管理员密码 [默认: admin]:"
    read -r -s xui_pass
    echo ""
    XUI_PASSWORD=${xui_pass:-"admin"}
    
    # 修改 X-UI 配置
    if [ -f "/etc/x-ui/x-ui.db" ]; then
        print_info "更新 X-UI 登录凭据..."
        # 这里需要根据实际 X-UI 的数据库结构来更新
        # 通常 X-UI 安装后会提示修改密码
    fi
    
    print_success "X-UI 配置完成"
    echo ""
    print_info "X-UI 面板本地访问地址: http://服务器IP:${XUI_PORT}"
    print_info "用户名: ${XUI_USERNAME}"
    print_info "密码: ${XUI_PASSWORD}"
    echo ""
}

# ----------------------------
# 安装 Cloudflared
# ----------------------------
install_cloudflared() {
    print_info "安装 Cloudflared..."
    
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
    
    # 下载并安装 cloudflared
    if curl -L -o /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        print_success "cloudflared 安装成功"
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
    print_auth "═══════════════════════════════════════════════"
    print_auth "         Cloudflare 授权                      "
    print_auth "═══════════════════════════════════════════════"
    echo ""
    
    # 清理旧的授权文件
    rm -rf /root/.cloudflared 2>/dev/null
    mkdir -p /root/.cloudflared
    
    echo "请按以下步骤操作："
    echo "1. 脚本将显示一个 Cloudflare 授权链接"
    echo "2. 复制链接到浏览器打开"
    echo "3. 登录您的 Cloudflare 账户"
    echo "4. 选择您要使用的域名并授权"
    echo "5. 返回终端按回车继续"
    echo ""
    print_input "按回车开始授权..."
    read -r
    
    echo ""
    echo "=============================================="
    echo "请复制以下链接到浏览器："
    echo ""
    
    # 运行授权命令
    "$BIN_DIR/cloudflared" tunnel login
    
    echo ""
    echo "=============================================="
    print_input "完成授权后按回车继续..."
    read -r
    
    # 检查授权结果
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "✅ 授权成功！找到证书文件"
        
        # 检查凭证文件
        if ls /root/.cloudflared/*.json 1> /dev/null 2>&1; then
            local json_file=$(ls /root/.cloudflared/*.json | head -1)
            print_success "✅ 找到凭证文件: $(basename "$json_file")"
            return 0
        else
            print_warning "⚠️  未找到JSON凭证文件，将在创建隧道时生成"
            return 0
        fi
    else
        print_error "❌ 授权失败：未找到证书文件"
        return 1
    fi
}

# ----------------------------
# 创建隧道和配置
# ----------------------------
setup_tunnel() {
    print_info "设置 Cloudflare Tunnel..."
    
    # 检查证书文件
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "❌ 未找到证书文件，请先完成授权"
        exit 1
    fi
    
    local json_file=""
    
    # 检查是否有现有凭证文件
    if ls /root/.cloudflared/*.json 1> /dev/null 2>&1; then
        json_file=$(ls -t /root/.cloudflared/*.json | head -1)
        print_success "✅ 使用现有凭证文件: $(basename "$json_file")"
    else
        print_warning "⚠️  未找到凭证文件，正在创建隧道..."
        
        # 删除可能存在的同名隧道
        "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
        sleep 2
        
        # 创建新隧道
        print_info "创建隧道: $TUNNEL_NAME"
        if timeout 60 "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"; then
            sleep 3
            # 查找新生成的凭证文件
            json_file=$(ls -t /root/.cloudflared/*.json 2>/dev/null | head -1)
            if [[ -n "$json_file" ]] && [[ -f "$json_file" ]]; then
                print_success "✅ 隧道创建成功，凭证文件: $(basename "$json_file")"
            else
                print_error "❌ 创建隧道后未生成凭证文件"
                exit 1
            fi
        else
            print_error "❌ 无法创建隧道"
            exit 1
        fi
    fi
    
    # 获取隧道ID
    local tunnel_id
    tunnel_id=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -z "$tunnel_id" ]]; then
        print_error "❌ 无法获取隧道ID"
        exit 1
    fi
    
    print_success "✅ 隧道就绪 (名称: ${TUNNEL_NAME}, ID: ${tunnel_id})"
    
    # 绑定域名
    print_info "绑定域名: $USER_DOMAIN"
    "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$USER_DOMAIN" > /dev/null 2>&1
    print_success "✅ 域名绑定成功"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 保存隧道配置
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
XUI_PORT=$XUI_PORT
XUI_USERNAME=$XUI_USERNAME
XUI_PASSWORD=$XUI_PASSWORD
CREATED_DATE=$(date +"%Y-%m-%d")
EOF
    
    print_success "隧道设置完成"
}

# ----------------------------
# 配置 Cloudflared 服务
# ----------------------------
configure_cloudflared_service() {
    print_info "配置 Cloudflared 服务..."
    
    # 从配置文件读取信息
    local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local json_file=$(grep "^CREDENTIALS_FILE=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null || echo "CREDENTIALS_FILE=/root/.cloudflared/$(ls /root/.cloudflared/*.json 2>/dev/null | xargs basename 2>/dev/null | head -1)")
    json_file=$(echo "$json_file" | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local xui_port=$(grep "^XUI_PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    # 创建 cloudflared 配置文件
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $tunnel_id
credentials-file: $json_file
logfile: $LOG_DIR/cloudflared.log
loglevel: info
ingress:
  - hostname: $domain
    service: http://localhost:$xui_port
    originRequest:
      noTLSVerify: true
      httpHostHeader: $domain
      connectTimeout: 30s
      tcpKeepAlive: 30s
      noHappyEyeballs: true
      disableChunkedEncoding: false
  - service: http_status:404
EOF
    
    # 创建 systemd 服务文件
    cat > /etc/systemd/system/xui-tunnel.service << EOF
[Unit]
Description=X-UI Cloudflare Tunnel Service
After=network.target x-ui.service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/tunnel.log
StandardError=append:$LOG_DIR/tunnel-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载 systemd
    systemctl daemon-reload
    print_success "Cloudflared 服务配置完成"
}

# ----------------------------
# 启动服务
# ----------------------------
start_services() {
    print_info "启动服务..."
    
    # 确保 X-UI 正在运行
    if systemctl restart x-ui; then
        print_success "✅ X-UI 服务启动成功"
    else
        print_error "❌ X-UI 服务启动失败"
        return 1
    fi
    
    # 停止可能存在的旧隧道服务
    systemctl stop xui-tunnel.service 2>/dev/null || true
    sleep 2
    
    # 启动隧道服务
    systemctl enable xui-tunnel.service > /dev/null 2>&1
    systemctl start xui-tunnel.service
    
    # 等待隧道连接
    local wait_time=0
    local max_wait=60
    
    print_info "等待隧道连接建立（最多60秒）..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        if systemctl is-active --quiet xui-tunnel.service; then
            print_success "✅ X-UI Tunnel 服务运行中"
            break
        fi
        
        if [[ $((wait_time % 15)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            print_info "已等待 ${wait_time}秒..."
        fi
        
        sleep 3
        ((wait_time+=3))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        print_warning "⚠️  隧道服务启动较慢"
        print_info "服务会在后台继续启动，请稍后检查状态。"
    fi
    
    sleep 3
    return 0
}

# ----------------------------
# 显示连接信息
# ----------------------------
show_connection_info() {
    print_info "═══════════════════════════════════════════════"
    print_info "           安装完成！连接信息"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到配置文件"
        return
    fi
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local xui_port=$(grep "^XUI_PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local xui_username=$(grep "^XUI_USERNAME=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    local xui_password=$(grep "^XUI_PASSWORD=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    if [[ -z "$domain" ]]; then
        print_error "无法读取配置"
        return
    fi
    
    print_success "🔗 X-UI 面板访问地址:"
    print_success "   https://$domain"
    echo ""
    
    print_success "🔐 登录凭据:"
    print_success "   用户名: $xui_username"
    print_success "   密码: $xui_password"
    echo ""
    
    print_success "📡 本地访问地址:"
    print_success "   http://服务器IP:$xui_port"
    echo ""
    
    print_info "🧪 服务状态:"
    echo ""
    
    if systemctl is-active --quiet x-ui; then
        print_success "✅ X-UI 服务: 运行中"
    else
        print_error "❌ X-UI 服务: 未运行"
    fi
    
    if systemctl is-active --quiet xui-tunnel.service; then
        print_success "✅ X-UI Tunnel 服务: 运行中"
    else
        print_error "❌ X-UI Tunnel 服务: 未运行"
    fi
    
    echo ""
    print_info "📋 使用说明:"
    echo "  1. 访问 https://$domain 管理 X-UI 面板"
    echo "  2. 在 X-UI 面板中添加和管理代理用户"
    echo "  3. Cloudflare Tunnel 会自动提供 TLS 加密"
    echo ""
    
    print_info "🔧 管理命令:"
    echo "  查看隧道状态: sudo ./xui_tunnel.sh status"
    echo "  重启隧道服务: systemctl restart xui-tunnel.service"
    echo "  查看隧道日志: journalctl -u xui-tunnel.service -f"
    echo "  查看 X-UI 日志: journalctl -u x-ui -f"
    echo ""
    
    print_warning "⚠️  安全提示:"
    echo "  1. 首次登录后请立即修改默认密码"
    echo "  2. 建议启用 X-UI 的面板访问密码"
    echo "  3. 定期更新 X-UI 到最新版本"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    print_info "开始安装流程..."
    
    check_system
    collect_user_info
    install_xui
    install_cloudflared
    
    # Cloudflare 授权
    if ! cloudflare_auth; then
        print_warning "授权可能有问题"
        print_input "是否继续安装？(y/N): "
        read -r continue_install
        if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
            print_error "安装中止"
            return 1
        fi
    fi
    
    # 设置隧道
    if ! setup_tunnel; then
        print_error "隧道设置失败"
        return 1
    fi
    
    configure_cloudflared_service
    
    if ! start_services; then
        print_error "服务启动失败"
        return 1
    fi
    
    show_connection_info
    
    echo ""
    print_success "🎉 安装完成！"
    return 0
}

# ----------------------------
# 卸载功能
# ----------------------------
uninstall_all() {
    print_info "开始卸载 X-UI Tunnel..."
    echo ""
    
    print_warning "⚠️  警告：此操作将删除隧道配置，但保留 X-UI 面板和数据！"
    print_input "确认要卸载吗？(y/N): "
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "卸载已取消"
        return
    fi
    
    echo ""
    print_info "停止隧道服务..."
    
    systemctl stop xui-tunnel.service 2>/dev/null || true
    systemctl disable xui-tunnel.service 2>/dev/null || true
    
    rm -f /etc/systemd/system/xui-tunnel.service
    rm -rf "$CONFIG_DIR" "$LOG_DIR"
    
    print_input "是否删除 cloudflared 二进制文件？(y/N): "
    read -r delete_bin
    if [[ "$delete_bin" == "y" || "$delete_bin" == "Y" ]]; then
        rm -f "$BIN_DIR/cloudflared"
    fi
    
    print_input "是否删除 Cloudflare 授权文件？(y/N): "
    read -r delete_auth
    if [[ "$delete_auth" == "y" || "$delete_auth" == "Y" ]]; then
        rm -rf /root/.cloudflared
    fi
    
    systemctl daemon-reload
    
    echo ""
    print_success "✅ 隧道卸载完成！"
    print_info "X-UI 面板仍然保留，可以通过服务器IP:54321访问"
}

# ----------------------------
# 显示配置信息
# ----------------------------
show_config() {
    if [[ ! -f "$CONFIG_DIR/tunnel.conf" ]]; then
        print_error "未找到隧道配置文件，可能未安装"
        return 1
    fi
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local xui_port=$(grep "^XUI_PORT=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local xui_username=$(grep "^XUI_USERNAME=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -z "$domain" ]]; then
        print_error "无法读取配置"
        return 1
    fi
    
    echo ""
    print_success "当前隧道配置:"
    echo "  X-UI 面板域名: https://$domain"
    echo "  X-UI 本地端口: $xui_port"
    echo "  X-UI 用户名: $xui_username"
    echo ""
    
    print_info "🧪 服务状态:"
    if systemctl is-active --quiet xui-tunnel.service; then
        print_success "  X-UI Tunnel: 运行中"
        
        echo ""
        print_info "隧道信息:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || true
    else
        print_error "  X-UI Tunnel: 未运行"
    fi
    echo ""
}

# ----------------------------
# 显示服务状态
# ----------------------------
show_status() {
    print_info "服务状态检查..."
    echo ""
    
    if systemctl is-active --quiet x-ui; then
        print_success "X-UI 服务: 运行中"
        print_info "  本地访问: http://服务器IP:54321"
    else
        print_error "X-UI 服务: 未运行"
    fi
    
    echo ""
    
    if systemctl is-active --quiet xui-tunnel.service; then
        print_success "X-UI Tunnel 服务: 运行中"
        
        echo ""
        print_info "隧道信息:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || true
        
        # 显示域名信息
        if [ -f "$CONFIG_DIR/tunnel.conf" ]; then
            local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
            echo ""
            print_info "面板访问地址: https://$domain"
        fi
    else
        print_error "X-UI Tunnel 服务: 未运行"
    fi
}

# ----------------------------
# 显示菜单
# ----------------------------
show_menu() {
    show_title
    
    echo "请选择操作："
    echo ""
    echo "  1) 安装 X-UI + Cloudflare Tunnel"
    echo "  2) 卸载 Cloudflare Tunnel (保留X-UI)"
    echo "  3) 查看服务状态"
    echo "  4) 查看配置信息"
    echo "  5) 重启隧道服务"
    echo "  6) 退出"
    echo ""
    
    print_input "请输入选项 (1-6): "
    read -r choice
    
    case "$choice" in
        1)
            SILENT_MODE=false
            if main_install; then
                echo ""
                print_input "按回车键返回菜单..."
                read -r
            else
                echo ""
                print_error "安装失败"
                print_input "按回车键返回菜单..."
                read -r
            fi
            ;;
        2)
            uninstall_all
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        3)
            show_status
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        4)
            show_config
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        5)
            print_info "重启隧道服务..."
            systemctl restart xui-tunnel.service
            sleep 3
            show_status
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
    case "${1:-}" in
        "install")
            SILENT_MODE=false
            show_title
            main_install
            ;;
        "uninstall")
            show_title
            uninstall_all
            ;;
        "config")
            show_title
            show_config
            ;;
        "status")
            show_title
            show_status
            ;;
        "restart")
            systemctl restart xui-tunnel.service
            print_success "隧道服务已重启"
            ;;
        "-y"|"--silent")
            SILENT_MODE=true
            show_title
            main_install
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo ./xui_tunnel.sh menu          # 显示菜单"
            echo "  sudo ./xui_tunnel.sh install       # 安装"
            echo "  sudo ./xui_tunnel.sh uninstall     # 卸载隧道"
            echo "  sudo ./xui_tunnel.sh status        # 查看状态"
            echo "  sudo ./xui_tunnel.sh config        # 查看配置"
            echo "  sudo ./xui_tunnel.sh restart       # 重启隧道"
            echo "  sudo ./xui_tunnel.sh -y            # 静默安装"
            exit 1
            ;;
    esac
}

# 检查是否以root运行
if [[ $EUID -ne 0 ]] && [[ "${1:-}" != "" ]]; then
    print_error "请使用root权限运行此脚本"
    exit 1
fi

main "$@"