#!/bin/bash
# ============================================
# Cloudflare Tunnel + X-UI 安装脚本（稳定版）
# 版本: 2.0 - 改进错误处理和隧道配置
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
XUI_PORT=54321
DEFAULT_USERNAME="admin"
DEFAULT_PASSWORD="admin"

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
    echo "║    Cloudflare Tunnel + X-UI 安装脚本        ║"
    echo "║             版本: 2.0 (稳定版)              ║"
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
    
    # 检查系统类型
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        print_info "检测到系统: $OS"
    else
        print_error "无法检测操作系统"
        exit 1
    fi
    
    # 更新系统
    print_info "更新系统包..."
    apt-get update -y
    
    # 安装必要工具
    print_info "安装必要工具..."
    local tools=("curl" "wget" "git" "jq" "net-tools")
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
    
    if [ "$SILENT_MODE" = true ]; then
        USER_DOMAIN="xui.example.com"
        print_info "静默模式：使用默认域名 $USER_DOMAIN"
        print_info "隧道名称: $TUNNEL_NAME"
        return
    fi
    
    # 获取域名
    while true; do
        print_input "请输入您的域名 (用于访问X-UI面板，例如: xui.yourdomain.com):"
        read -r USER_DOMAIN
        
        if [[ -z "$USER_DOMAIN" ]]; then
            print_error "域名不能为空！"
            continue
        fi
        
        if [[ "$USER_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "域名格式不正确，请重新输入！"
        fi
    done
    
    # 隧道名称
    print_input "请输入隧道名称 [默认: xui-tunnel]:"
    read -r TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"xui-tunnel"}
    
    # X-UI凭据
    echo ""
    print_input "设置X-UI登录信息:"
    print_input "用户名 [默认: admin]:"
    read -r xui_user
    XUI_USERNAME=${xui_user:-"admin"}
    
    print_input "密码 [默认: admin]:"
    read -r -s xui_pass
    echo ""
    XUI_PASSWORD=${xui_pass:-"admin"}
    
    # 确认信息
    echo ""
    print_success "配置确认:"
    echo "  域名: $USER_DOMAIN"
    echo "  隧道名称: $TUNNEL_NAME"
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
    print_info "开始安装 X-UI 面板..."
    
    # 检查是否已安装
    if command -v x-ui &> /dev/null || systemctl is-active --quiet x-ui; then
        print_warning "X-UI 似乎已经安装，跳过安装步骤"
        
        print_input "是否重新安装 X-UI？(y/N):"
        read -r reinstall
        if [[ "$reinstall" == "y" || "$reinstall" == "Y" ]]; then
            print_info "卸载旧版 X-UI..."
            x-ui uninstall || true
        else
            return 0
        fi
    fi
    
    # 下载并安装 X-UI
    print_info "下载 X-UI 安装脚本..."
    wget -O x-ui-install.sh https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh
    chmod +x x-ui-install.sh
    
    print_info "正在安装 X-UI..."
    if bash x-ui-install.sh; then
        print_success "X-UI 安装成功"
    else
        print_error "X-UI 安装失败"
        print_info "尝试备用安装方法..."
        
        # 备用安装方法
        wget -O x-ui-linux-amd64.tar.gz https://github.com/vaxilu/x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz
        tar -zxvf x-ui-linux-amd64.tar.gz
        chmod +x x-ui/x-ui
        cp x-ui/x-ui /usr/local/bin/
        
        # 创建服务文件
        cat > /etc/systemd/system/x-ui.service << EOF
[Unit]
Description=x-ui Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/x-ui/
ExecStart=/usr/local/bin/x-ui
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable x-ui
        systemctl start x-ui
    fi
    
    # 清理安装文件
    rm -f x-ui-install.sh x-ui-linux-amd64.tar.gz 2>/dev/null || true
    
    # 等待X-UI启动
    print_info "等待X-UI启动..."
    for i in {1..30}; do
        if systemctl is-active --quiet x-ui; then
            print_success "X-UI 服务运行正常"
            break
        fi
        echo -n "."
        sleep 1
    done
    
    if ! systemctl is-active --quiet x-ui; then
        print_warning "X-UI 启动较慢，继续安装过程..."
    fi
    
    # 设置X-UI登录凭据（如果需要）
    print_info "配置X-UI登录信息..."
    sleep 5  # 给X-UI更多时间启动
    
    print_success "X-UI 安装完成"
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
    
    # 下载 cloudflared
    print_info "下载 cloudflared..."
    if wget -q --show-progress -O /tmp/cloudflared "$cf_url"; then
        mv /tmp/cloudflared "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
        print_success "cloudflared 安装成功"
    else
        print_error "cloudflared 下载失败，尝试备用方法..."
        
        # 备用下载方法
        if curl -L -o /tmp/cloudflared "$cf_url"; then
            mv /tmp/cloudflared "$BIN_DIR/cloudflared"
            chmod +x "$BIN_DIR/cloudflared"
            print_success "cloudflared 安装成功（备用方法）"
        else
            print_error "无法下载 cloudflared"
            exit 1
        fi
    fi
    
    # 验证安装
    if "$BIN_DIR/cloudflared" --version &> /dev/null; then
        print_success "cloudflared 版本: $("$BIN_DIR/cloudflared" --version)"
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
    
    # 清理旧的授权
    print_info "清理旧的授权文件..."
    rm -rf /root/.cloudflared 2>/dev/null || true
    mkdir -p /root/.cloudflared
    
    echo "授权步骤："
    echo "1. 下面会显示一个 Cloudflare 授权链接"
    echo "2. 复制链接到浏览器打开"
    echo "3. 登录您的 Cloudflare 账户"
    echo "4. 选择要使用的域名: uiargo.9420ce.top"
    echo "5. 授权后返回终端继续"
    echo ""
    print_input "按回车键开始授权..."
    read -r
    
    echo ""
    echo "=============================================="
    print_info "请复制以下链接到浏览器："
    echo ""
    
    # 运行授权命令
    if "$BIN_DIR/cloudflared" tunnel login; then
        print_success "授权命令执行成功"
    else
        print_error "授权命令执行失败"
        return 1
    fi
    
    echo ""
    echo "=============================================="
    print_input "完成授权后按回车继续..."
    read -r
    
    # 检查授权结果
    print_info "检查授权结果..."
    
    local check_count=0
    while [[ $check_count -lt 10 ]]; do
        if [[ -f "/root/.cloudflared/cert.pem" ]]; then
            print_success "✅ 找到证书文件"
            
            # 检查凭证文件
            local json_files=(/root/.cloudflared/*.json)
            if [[ ${#json_files[@]} -gt 0 ]] && [[ -f "${json_files[0]}" ]]; then
                print_success "✅ 找到凭证文件: $(basename "${json_files[0]}")"
                return 0
            else
                print_warning "未找到JSON凭证文件，将在创建隧道时生成"
                return 0
            fi
        fi
        sleep 2
        ((check_count++))
    done
    
    print_error "❌ 授权失败：未找到证书文件"
    print_info "可能的原因："
    echo "  1. 未完成授权流程"
    echo "  2. 浏览器未返回正确的证书"
    echo "  3. 网络问题"
    echo ""
    return 1
}

# ----------------------------
# 创建隧道
# ----------------------------
create_tunnel() {
    print_info "创建 Cloudflare 隧道..."
    
    # 检查证书
    if [[ ! -f "/root/.cloudflared/cert.pem" ]]; then
        print_error "未找到证书文件，请先完成授权"
        return 1
    fi
    
    # 清理可能存在的同名隧道
    print_info "清理旧的隧道配置..."
    "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 列出当前隧道
    print_info "当前隧道列表:"
    "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || echo "无隧道"
    
    # 创建新隧道
    print_info "创建新隧道: $TUNNEL_NAME"
    echo "正在创建隧道，请稍候..."
    
    if timeout 120 "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"; then
        print_success "隧道创建命令执行成功"
    else
        print_error "隧道创建失败"
        return 1
    fi
    
    sleep 3
    
    # 获取隧道ID
    local tunnel_info
    tunnel_info=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || true)
    
    if [[ -z "$tunnel_info" ]]; then
        print_error "无法找到隧道 $TUNNEL_NAME"
        return 1
    fi
    
    local tunnel_id=$(echo "$tunnel_info" | awk '{print $1}')
    print_success "✅ 隧道创建成功"
    print_success "隧道ID: $tunnel_id"
    print_success "隧道名称: $TUNNEL_NAME"
    
    # 获取凭证文件
    local json_file=$(ls -t /root/.cloudflared/*.json 2>/dev/null | head -1)
    if [[ -z "$json_file" ]] || [[ ! -f "$json_file" ]]; then
        print_error "未找到隧道凭证文件"
        return 1
    fi
    
    print_success "凭证文件: $(basename "$json_file")"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 保存隧道配置
    cat > "$CONFIG_DIR/tunnel.conf" << EOF
# X-UI隧道配置
TUNNEL_ID=$tunnel_id
TUNNEL_NAME=$TUNNEL_NAME
DOMAIN=$USER_DOMAIN
CREDENTIALS_FILE=$json_file
XUI_PORT=$XUI_PORT
XUI_USERNAME=$XUI_USERNAME
XUI_PASSWORD=$XUI_PASSWORD
CREATED_DATE=$(date +"%Y-%m-%d %H:%M:%S")
EOF
    
    print_success "隧道配置保存到: $CONFIG_DIR/tunnel.conf"
    return 0
}

# ----------------------------
# 配置 DNS 记录
# ----------------------------
setup_dns() {
    print_info "配置DNS记录..."
    
    local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -z "$tunnel_id" ]] || [[ -z "$domain" ]]; then
        print_error "无法读取隧道配置"
        return 1
    fi
    
    print_info "绑定域名 $domain 到隧道 $TUNNEL_NAME..."
    
    if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$domain"; then
        print_success "✅ DNS记录配置成功"
    else
        print_warning "⚠️  DNS配置可能失败，但可以继续"
        print_info "您可能需要手动在Cloudflare面板创建CNAME记录:"
        echo "  类型: CNAME"
        echo "  名称: $domain"
        echo "  目标: $tunnel_id.cfargotunnel.com"
        echo ""
    fi
    
    # 测试DNS解析
    print_info "测试DNS解析..."
    if dig "$domain" +short | grep -q "cfargotunnel"; then
        print_success "DNS解析正常"
    else
        print_warning "DNS解析可能需要时间生效"
    fi
    
    return 0
}

# ----------------------------
# 创建配置文件
# ----------------------------
create_config_files() {
    print_info "创建配置文件..."
    
    local tunnel_id=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local json_file=$(grep "^CREDENTIALS_FILE=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -z "$tunnel_id" ]] || [[ -z "$json_file" ]] || [[ -z "$domain" ]]; then
        print_error "无法读取配置信息"
        return 1
    fi
    
    # 创建 cloudflared 配置文件（简化版）
    cat > "$CONFIG_DIR/config.yaml" << EOF
# Cloudflare Tunnel 配置文件
tunnel: $tunnel_id
credentials-file: $json_file

# 日志设置
logfile: $LOG_DIR/cloudflared.log
loglevel: info

# 入口规则
ingress:
  - hostname: $domain
    service: http://localhost:$XUI_PORT
    originRequest:
      connectTimeout: 30s
      tcpKeepAlive: 30s
      noHappyEyeballs: false
      httpHostHeader: $domain

  # 默认404页面
  - service: http_status:404
EOF
    
    print_success "配置文件创建完成: $CONFIG_DIR/config.yaml"
    
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    
    return 0
}

# ----------------------------
# 创建系统服务
# ----------------------------
create_system_service() {
    print_info "创建系统服务..."
    
    # 创建服务文件
    cat > /etc/systemd/system/xui-tunnel.service << EOF
[Unit]
Description=X-UI Cloudflare Tunnel Service
After=network.target
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
StandardOutput=append:$LOG_DIR/service.log
StandardError=append:$LOG_DIR/error.log

# 安全设置
NoNewPrivileges=yes
LimitNPROC=100
LimitNOFILE=100000

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
    
    # 确保X-UI运行
    if ! systemctl is-active --quiet x-ui; then
        print_info "启动X-UI服务..."
        systemctl start x-ui
        sleep 3
    fi
    
    # 停止可能存在的隧道服务
    systemctl stop xui-tunnel.service 2>/dev/null || true
    sleep 2
    
    # 启动隧道服务
    print_info "启动隧道服务..."
    systemctl enable xui-tunnel.service
    systemctl start xui-tunnel.service
    
    # 等待并检查服务状态
    local wait_time=0
    local max_wait=30
    
    print_info "等待服务启动（最多30秒）..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        if systemctl is-active --quiet xui-tunnel.service; then
            print_success "✅ 隧道服务启动成功"
            break
        fi
        
        echo -n "."
        sleep 3
        ((wait_time+=3))
        
        # 每15秒显示一次进度
        if [[ $((wait_time % 15)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            echo ""
            print_info "已等待 ${wait_time}秒..."
        fi
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        print_warning "⚠️  服务启动较慢，检查日志..."
        journalctl -u xui-tunnel.service -n 20 --no-pager
    fi
    
    sleep 2
    
    # 显示服务状态
    echo ""
    print_info "服务状态:"
    
    if systemctl is-active --quiet x-ui; then
        print_success "  X-UI服务: 运行中"
    else
        print_error "  X-UI服务: 未运行"
    fi
    
    if systemctl is-active --quiet xui-tunnel.service; then
        print_success "  隧道服务: 运行中"
    else
        print_error "  隧道服务: 未运行"
    fi
    
    return 0
}

# ----------------------------
# 显示安装结果
# ----------------------------
show_installation_result() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           安装完成！"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    local domain=$(grep "^DOMAIN=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local xui_user=$(grep "^XUI_USERNAME=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    local xui_pass=$(grep "^XUI_PASSWORD=" "$CONFIG_DIR/tunnel.conf" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -n "$domain" ]]; then
        print_success "🎉 X-UI面板访问地址:"
        print_success "   https://$domain"
        echo ""
    fi
    
    print_success "🔐 X-UI登录凭据:"
    print_success "   用户名: ${xui_user:-admin}"
    print_success "   密码: ${xui_pass:-admin}"
    echo ""
    
    print_success "📡 本地访问地址:"
    print_success "   http://服务器IP:54321"
    echo ""
    
    print_info "🛠️  管理命令:"
    echo "  查看状态: systemctl status xui-tunnel.service"
    echo "  查看日志: journalctl -u xui-tunnel.service -f"
    echo "  重启隧道: systemctl restart xui-tunnel.service"
    echo "  停止隧道: systemctl stop xui-tunnel.service"
    echo ""
    
    print_info "🔧 故障排除:"
    echo "  1. 如果无法访问，等待2-3分钟DNS生效"
    echo "  2. 检查服务状态: systemctl status xui-tunnel"
    echo "  3. 查看详细日志: tail -f /var/log/xui_tunnel/error.log"
    echo "  4. 确认X-UI是否运行: systemctl status x-ui"
    echo ""
    
    print_warning "⚠️  重要提示:"
    echo "  1. 首次登录后立即修改默认密码"
    echo "  2. 建议启用X-UI的访问密码"
    echo "  3. 定期备份配置"
    
    echo ""
    print_success "安装完成！您现在可以通过 https://${domain:-您的域名} 访问X-UI面板"
}

# ----------------------------
# 主安装流程
# ----------------------------
main_install() {
    show_title
    
    print_info "开始安装 X-UI + Cloudflare Tunnel..."
    echo ""
    
    # 执行安装步骤
    check_system
    collect_user_info
    install_xui
    install_cloudflared
    
    # Cloudflare授权
    if ! cloudflare_auth; then
        print_error "授权失败，安装中止"
        return 1
    fi
    
    # 创建隧道
    if ! create_tunnel; then
        print_error "隧道创建失败"
        return 1
    fi
    
    # 配置DNS
    setup_dns
    
    # 创建配置文件
    if ! create_config_files; then
        print_error "配置文件创建失败"
        return 1
    fi
    
    # 创建系统服务
    create_system_service
    
    # 启动服务
    start_services
    
    # 显示结果
    show_installation_result
    
    return 0
}

# ----------------------------
# 快速修复函数
# ----------------------------
quick_fix() {
    echo ""
    print_info "快速修复隧道问题..."
    
    # 1. 停止服务
    systemctl stop xui-tunnel.service 2>/dev/null || true
    pkill -f cloudflared 2>/dev/null || true
    sleep 2
    
    # 2. 检查X-UI
    if ! systemctl is-active --quiet x-ui; then
        print_info "启动X-UI..."
        systemctl start x-ui
        sleep 3
    fi
    
    # 3. 重新生成配置文件
    if [ -f "$CONFIG_DIR/tunnel.conf" ]; then
        create_config_files
    fi
    
    # 4. 启动服务
    systemctl daemon-reload
    systemctl restart xui-tunnel.service
    
    sleep 5
    
    # 5. 检查结果
    if systemctl is-active --quiet xui-tunnel.service; then
        print_success "✅ 修复成功！隧道服务已启动"
    else
        print_error "❌ 修复失败，查看日志:"
        journalctl -u xui-tunnel.service -n 30 --no-pager
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
    echo "  2) 快速修复隧道问题"
    echo "  3) 查看服务状态"
    echo "  4) 查看配置信息"
    echo "  5) 重启隧道服务"
    echo "  6) 卸载隧道服务"
    echo "  7) 退出"
    echo ""
    
    print_input "请输入选项 (1-7): "
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
            quick_fix
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        3)
            echo ""
            print_info "服务状态:"
            systemctl status x-ui --no-pager | head -10
            echo ""
            systemctl status xui-tunnel.service --no-pager | head -10
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        4)
            if [ -f "$CONFIG_DIR/tunnel.conf" ]; then
                echo ""
                print_info "当前配置:"
                cat "$CONFIG_DIR/tunnel.conf"
                echo ""
                if [ -f "$CONFIG_DIR/config.yaml" ]; then
                    print_info "配置文件:"
                    cat "$CONFIG_DIR/config.yaml"
                fi
            else
                print_error "未找到配置文件"
            fi
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        5)
            print_info "重启隧道服务..."
            systemctl restart xui-tunnel.service
            sleep 3
            systemctl status xui-tunnel.service --no-pager | head -10
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        6)
            print_warning "卸载隧道服务（保留X-UI）..."
            systemctl stop xui-tunnel.service 2>/dev/null || true
            systemctl disable xui-tunnel.service 2>/dev/null || true
            rm -f /etc/systemd/system/xui-tunnel.service
            rm -rf "$CONFIG_DIR" "$LOG_DIR"
            systemctl daemon-reload
            print_success "隧道服务已卸载"
            echo ""
            print_input "按回车键返回菜单..."
            read -r
            ;;
        7)
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
            main_install
            ;;
        "fix")
            quick_fix
            ;;
        "status")
            show_title
            systemctl status x-ui --no-pager
            echo ""
            systemctl status xui-tunnel.service --no-pager
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo ./xui_tunnel.sh menu        # 显示菜单"
            echo "  sudo ./xui_tunnel.sh install     # 安装"
            echo "  sudo ./xui_tunnel.sh fix         # 快速修复"
            echo "  sudo ./xui_tunnel.sh status      # 查看状态"
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