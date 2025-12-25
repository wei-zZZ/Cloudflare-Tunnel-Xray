#!/bin/bash
# ============================================
# X-UI + Cloudflare Tunnel 完整配置脚本
# 解决TLS冲突和路径匹配问题
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
show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║    X-UI + Cloudflare Tunnel 完整配置         ║"
    echo "║           解决TLS冲突问题                    ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
}

# 检查系统
check_system() {
    print_info "检查系统环境..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行"
        exit 1
    fi
    
    # 安装必要工具
    apt-get update -y
    apt-get install -y curl wget jq 2>/dev/null || true
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
    rm -f /etc/systemd/system/$SERVICE_NAME.service 2>/dev/null || true
    rm -rf "$CONFIG_DIR" 2>/dev/null || true
    rm -rf "$LOG_DIR" 2>/dev/null || true
    
    # 清理Cloudflare配置
    rm -rf /root/.cloudflared 2>/dev/null || true
    mkdir -p /root/.cloudflared
    
    systemctl daemon-reload
    sleep 2
    print_success "清理完成"
}

# 安装X-UI
install_xui() {
    print_info "检查X-UI面板..."
    
    if command -v x-ui &> /dev/null; then
        print_warning "X-UI已安装"
        # 确保服务运行
        systemctl start x-ui 2>/dev/null || true
        return 0
    fi
    
    # 安装X-UI
    print_info "安装X-UI..."
    curl -L -o x-ui-install.sh https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh
    chmod +x x-ui-install.sh
    echo "y" | bash x-ui-install.sh
    rm -f x-ui-install.sh
    
    # 等待启动
    for i in {1..10}; do
        if systemctl is-active --quiet x-ui; then
            print_success "X-UI启动成功"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    
    print_warning "X-UI启动较慢"
    return 0
}

# 安装Cloudflared
install_cloudflared() {
    print_info "安装Cloudflared..."
    
    if command -v cloudflared &> /dev/null; then
        print_warning "cloudflared已安装"
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
    print_success "cloudflared安装成功"
}

# 获取用户配置
get_user_config() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "           配置信息"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    # 域名配置
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
    print_input "X-UI面板端口 [默认: 54321]:"
    read -r PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-"54321"}
    
    # Xray代理端口
    echo ""
    print_input "Xray代理端口 [默认: 10000]:"
    print_input "⚠️ 重要：Xray必须关闭TLS，只监听HTTP"
    read -r PROXY_PORT
    PROXY_PORT=${PROXY_PORT:-"10000"}
    
    # 隧道名称
    TUNNEL_NAME="xui-tunnel-$(date +%s)"
    
    # 保存配置
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config.env" << EOF
# X-UI隧道配置
DOMAIN="$DOMAIN"
PANEL_PORT="$PANEL_PORT"
PROXY_PORT="$PROXY_PORT"
TUNNEL_NAME="$TUNNEL_NAME"
CREATED="$(date '+%Y-%m-%d %H:%M:%S')"
EOF
    
    echo ""
    print_success "配置已保存:"
    echo "  域名: $DOMAIN"
    echo "  面板端口: $PANEL_PORT"
    echo "  代理端口: $PROXY_PORT"
    echo "  隧道名称: $TUNNEL_NAME"
    echo ""
}

# Cloudflare授权
cloudflare_auth() {
    echo ""
    print_info "═══════════════════════════════════════════════"
    print_info "        Cloudflare账户授权"
    print_info "═══════════════════════════════════════════════"
    echo ""
    
    echo "授权步骤："
    echo "1. 复制下面的链接到浏览器"
    echo "2. 登录Cloudflare账户"
    echo "3. 选择要使用的域名"
    echo "4. 完成授权"
    echo "5. 返回终端继续"
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
    
    # 检查授权结果
    if [[ -f "/root/.cloudflared/cert.pem" ]]; then
        print_success "✅ 授权成功"
        return 0
    else
        print_error "❌ 授权失败，未找到证书文件"
        return 1
    fi
}

# 创建隧道
create_tunnel() {
    print_info "创建Cloudflare隧道..."
    
    source "$CONFIG_DIR/config.env"
    
    # 清理可能存在的旧隧道
    "$BIN_DIR/cloudflared" tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
    sleep 2
    
    # 创建新隧道
    print_info "创建隧道: $TUNNEL_NAME"
    if ! "$BIN_DIR/cloudflared" tunnel create "$TUNNEL_NAME"; then
        print_error "隧道创建失败"
        return 1
    fi
    
    sleep 3
    
    # 获取隧道信息
    TUNNEL_INFO=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" || true)
    
    if [[ -z "$TUNNEL_INFO" ]]; then
        print_error "无法获取隧道信息"
        return 1
    fi
    
    TUNNEL_ID=$(echo "$TUNNEL_INFO" | awk '{print $1}')
    
    # 获取凭证文件
    CRED_FILE=$(find /root/.cloudflared -name "*.json" -type f | head -1)
    
    if [[ -z "$CRED_FILE" ]] || [[ ! -f "$CRED_FILE" ]]; then
        print_error "未找到凭证文件"
        return 1
    fi
    
    # 保存隧道信息
    cat >> "$CONFIG_DIR/config.env" << EOF
TUNNEL_ID="$TUNNEL_ID"
CRED_FILE="$CRED_FILE"
EOF
    
    print_success "✅ 隧道创建成功"
    echo "  隧道ID: $TUNNEL_ID"
    echo "  凭证文件: $(basename "$CRED_FILE")"
    
    # 绑定域名到隧道
    print_info "绑定域名到隧道..."
    if "$BIN_DIR/cloudflared" tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>/dev/null; then
        print_success "✅ 域名绑定成功"
    else
        print_warning "⚠️ 域名绑定可能需要手动配置"
        echo "请在Cloudflare DNS中添加CNAME记录:"
        echo "  名称: $DOMAIN"
        echo "  目标: $TUNNEL_ID.cfargotunnel.com"
        echo "  TTL: 自动"
        echo "  代理状态: 开启 (橙色云)"
    fi
    
    return 0
}

# 创建正确的ingress配置
create_ingress_config() {
    print_info "创建ingress配置..."
    
    source "$CONFIG_DIR/config.env"
    mkdir -p "$LOG_DIR"
    
    # 创建正确的ingress配置
    # 使用通配符路径匹配所有UUID
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
logfile: $LOG_DIR/cloudflared.log
loglevel: info

# Ingress规则
ingress:
  # X-UI管理面板
  - hostname: $DOMAIN
    path: /
    service: http://127.0.0.1:$PANEL_PORT

  # 代理节点 - WebSocket流量
  # 匹配所有UUID路径：/[UUID]
  - hostname: $DOMAIN
    path: /*
    service: http://127.0.0.1:$PROXY_PORT

  # 默认404页面
  - service: http_status:404
EOF
    
    print_success "✅ ingress配置创建完成"
    echo ""
    echo "配置特点:"
    echo "  ✅ 通配符路径 /* 匹配所有UUID"
    echo "  ✅ Xray监听HTTP端口: $PROXY_PORT"
    echo "  ✅ Cloudflare提供TLS加密"
    echo "  ❌ Xray必须关闭TLS"
    echo ""
}

# 创建X-UI配置指南
create_config_guide() {
    print_info "创建X-UI配置指南..."
    
    source "$CONFIG_DIR/config.env"
    
    # 生成一个示例UUID
    EXAMPLE_UUID="$(cat /proc/sys/kernel/random/uuid)"
    
    cat > "$CONFIG_DIR/xui-config-guide.md" << EOF
# X-UI 配置指南
# ⚠️ 重要：解决TLS冲突问题

## 配置摘要
- 域名: $DOMAIN
- 面板端口: $PANEL_PORT
- 代理端口: $PROXY_PORT
- 隧道ID: $TUNNEL_ID

## 1. 核心原则
### ❌ 错误配置（双TLS冲突）
客户端 → HTTPS → Cloudflare → HTTPS → Xray
                    ↑           ↑
                 Cloudflare    Xray
                 提供TLS       也提供TLS
                 
### ✅ 正确配置（单TLS）
客户端 → HTTPS → Cloudflare → HTTP → Xray
                    ↑
                 Cloudflare
                 提供TLS
                 Xray只处理HTTP

## 2. X-UI面板配置

### 步骤1：登录X-UI面板
访问: http://服务器IP:$PANEL_PORT
用户名: admin
密码: admin

### 步骤2：创建入站配置
\`\`\`
入站配置：
├── 备注: VLESS节点
├── 协议: VLESS
├── 端口: $PROXY_PORT           # ⚠️ 必须与此配置一致
├── 用户ID: [点击生成UUID]      # 每个用户不同
├── 传输协议: WebSocket (ws)
├── WebSocket路径: /[UUID]      # 使用用户ID作为路径
├── 主机名: $DOMAIN
├── TLS: ❌ 关闭                # ⚠️ 最重要！
└── 安全: none
\`\`\`

### 示例配置：
\`\`\`
备注: 我的节点
协议: VLESS
端口: $PROXY_PORT
用户ID: $EXAMPLE_UUID
传输协议: ws
WebSocket路径: /$EXAMPLE_UUID
主机名: $DOMAIN
TLS: 关闭
\`\`\`

## 3. 客户端连接配置

### VLESS链接格式
\`\`\`
vless://[UUID]@$DOMAIN:443?type=ws&security=none&host=$DOMAIN&path=%2F[UUID]&sni=$DOMAIN#节点名称
\`\`\`

### 示例链接：
\`\`\`
vless://$EXAMPLE_UUID@$DOMAIN:443
  ?type=ws
  &security=none                # ⚠️ 不是tls！
  &host=$DOMAIN
  &path=%2F$EXAMPLE_UUID        # URL编码：/%2F + UUID
  &sni=$DOMAIN
  #我的节点
\`\`\`

### VMESS链接格式
\`\`\`
vmess://base64编码的配置
\`\`\`

JSON配置：
\`\`\`
{
  "v": "2",
  "ps": "VMESS节点",
  "add": "$DOMAIN",
  "port": "443",
  "id": "[UUID]",
  "aid": "0",
  "scy": "none",
  "net": "ws",
  "type": "none",
  "host": "$DOMAIN",
  "path": "/[UUID]",
  "tls": "",                     # 空字符串，不是tls
  "sni": "$DOMAIN"
}
\`\`\`

## 4. Cloudflare设置检查

### DNS设置
1. 登录Cloudflare面板
2. 进入DNS → 记录
3. 添加CNAME记录：
   - 类型: CNAME
   - 名称: $DOMAIN
   - 目标: $TUNNEL_ID.cfargotunnel.com
   - TTL: 自动
   - 代理状态: ✅ 开启 (橙色云)

### SSL/TLS设置
1. 进入SSL/TLS → 概述
   - 加密模式: Full
2. 进入SSL/TLS → 边缘证书
   - 始终使用HTTPS: ✅ 开启
   - 自动HTTPS重写: ✅ 开启

### 网络设置
1. 进入网络
   - WebSocket: ✅ 开启
   - IPv6兼容性: ✅ 开启

## 5. 故障排除

### 问题1：连接超时
检查：
1. 隧道服务是否运行: systemctl status $SERVICE_NAME
2. X-UI服务是否运行: systemctl status x-ui
3. DNS是否生效: nslookup $DOMAIN

### 问题2：TLS握手失败
原因：Xray开启了TLS
解决：在X-UI面板中关闭TLS

### 问题3：路径不匹配
原因：客户端路径与X-UI配置不一致
检查：
1. X-UI中的WebSocket路径: /[UUID]
2. 客户端链接中的path参数: %2F[UUID]

### 问题4：无法访问面板
检查：
1. X-UI是否在运行: systemctl status x-ui
2. 本地能否访问: curl http://127.0.0.1:$PANEL_PORT
3. Cloudflare DNS是否生效

## 6. 管理命令

### 查看状态
\`\`\`
# 隧道服务状态
systemctl status $SERVICE_NAME

# X-UI服务状态
systemctl status x-ui

# 查看隧道列表
$BIN_DIR/cloudflared tunnel list

# 查看日志
journalctl -u $SERVICE_NAME -f
\`\`\`

### 重启服务
\`\`\`
# 重启隧道
systemctl restart $SERVICE_NAME

# 重启X-UI
systemctl restart x-ui
\`\`\`

### 测试连接
\`\`\`
# 测试本地X-UI
curl http://127.0.0.1:$PANEL_PORT

# 测试HTTPS访问
curl -v https://$DOMAIN

# 手动运行隧道测试
$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
\`\`\`
EOF
    
    print_success "✅ 配置指南已创建: $CONFIG_DIR/xui-config-guide.md"
}

# 创建系统服务
create_system_service() {
    print_info "创建系统服务..."
    
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=X-UI Cloudflare Tunnel Service
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment="TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem"
ExecStart=$BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/config.yaml run
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/tunnel.log
StandardError=append:$LOG_DIR/tunnel-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "✅ 系统服务创建完成"
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
        
        # 显示隧道状态
        echo ""
        print_info "隧道状态:"
        "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || {
            print_warning "无法获取隧道列表"
        }
        
        return 0
    else
        print_error "❌ 隧道服务启动失败"
        echo ""
        print_info "查看错误日志:"
        journalctl -u $SERVICE_NAME -n 20 --no-pager
        return 1
    fi
}

# 显示安装结果
show_installation_result() {
    echo ""
    print_success "═══════════════════════════════════════════════"
    print_success "           安装配置完成！"
    print_success "═══════════════════════════════════════════════"
    echo ""
    
    source "$CONFIG_DIR/config.env" 2>/dev/null || {
        print_error "无法读取配置"
        return
    }
    
    print_success "🎉 X-UI面板访问地址:"
    print_success "   https://$DOMAIN"
    echo ""
    
    print_success "🔧 配置摘要:"
    echo "  域名: $DOMAIN"
    echo "  面板端口: $PANEL_PORT"
    echo "  代理端口: $PROXY_PORT"
    echo "  隧道ID: $TUNNEL_ID"
    echo ""
    
    print_success "⚠️  重要提示:"
    echo "  1. X-UI中必须关闭TLS"
    echo "  2. WebSocket路径使用UUID: /[用户ID]"
    echo "  3. 检查Cloudflare DNS设置"
    echo "  4. SSL/TLS模式设为 Full"
    echo ""
    
    print_success "📋 下一步操作:"
    echo "  1. 访问 https://$DOMAIN 登录X-UI面板"
    echo "  2. 创建入站节点，端口: $PROXY_PORT"
    echo "  3. 协议: VLESS + WebSocket"
    echo "  4. 路径: /[生成的UUID]"
    echo "  5. TLS: ❌ 关闭"
    echo ""
    
    print_success "🛠️  管理命令:"
    echo "  状态检查: systemctl status $SERVICE_NAME"
    echo "  重启服务: systemctl restart $SERVICE_NAME"
    echo "  查看日志: journalctl -u $SERVICE_NAME -f"
    echo "  配置指南: cat $CONFIG_DIR/xui-config-guide.md"
    echo ""
    
    print_warning "⏳ 注意事项:"
    echo "  1. DNS可能需要时间生效（最多24小时）"
    echo "  2. 首次登录后修改默认密码"
    echo "  3. 如果无法连接，检查TLS设置"
    echo ""
}

# 主安装流程
main_install() {
    show_title
    
    print_info "开始X-UI + Cloudflare Tunnel配置..."
    echo ""
    
    # 清理环境
    cleanup_old
    
    # 系统检查
    check_system
    
    # 安装组件
    install_xui
    install_cloudflared
    
    # 获取配置
    get_user_config
    
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
    
    # 创建ingress配置
    create_ingress_config
    
    # 创建配置指南
    create_config_guide
    
    # 创建系统服务
    create_system_service
    
    # 启动服务
    if ! start_services; then
        print_error "服务启动失败"
        return 1
    fi
    
    # 显示结果
    show_installation_result
    
    print_success "🎊 配置完成！请严格按照指南设置X-UI。"
    
    return 0
}

# 快速修复
quick_fix() {
    echo ""
    print_info "快速修复隧道配置..."
    
    # 停止服务
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    pkill -f cloudflared 2>/dev/null || true
    sleep 2
    
    # 检查配置
    if [ ! -f "$CONFIG_DIR/config.env" ]; then
        print_error "未找到配置文件"
        return 1
    fi
    
    source "$CONFIG_DIR/config.env"
    
    # 重新创建ingress配置
    cat > "$CONFIG_DIR/config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
logfile: $LOG_DIR/cloudflared.log
loglevel: info

ingress:
  - hostname: $DOMAIN
    path: /
    service: http://127.0.0.1:$PANEL_PORT

  - hostname: $DOMAIN
    path: /*
    service: http://127.0.0.1:$PROXY_PORT

  - service: http_status:404
EOF
    
    print_success "✅ 配置已修复"
    
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
    echo "  1) 一键安装配置"
    echo "  2) 快速修复配置"
    echo "  3) 查看服务状态"
    echo "  4) 查看配置信息"
    echo "  5) 重启所有服务"
    echo "  6) 卸载清理"
    echo "  7) 退出"
    echo ""
    
    print_input "请输入选项 (1-7): "
    read -r choice
    
    case "$choice" in
        1)
            if main_install; then
                echo ""
                read -p "按回车返回菜单..." -r
            else
                echo ""
                print_error "安装失败"
                read -p "按回车返回菜单..." -r
            fi
            ;;
        2)
            quick_fix
            echo ""
            read -p "按回车返回菜单..." -r
            ;;
        3)
            echo ""
            print_info "服务状态:"
            echo "X-UI面板:"
            systemctl status x-ui --no-pager | head -8
            echo ""
            echo "隧道服务:"
            systemctl status $SERVICE_NAME --no-pager | head -8
            echo ""
            read -p "按回车返回菜单..." -r
            ;;
        4)
            echo ""
            if [ -f "$CONFIG_DIR/config.env" ]; then
                print_info "当前配置:"
                cat "$CONFIG_DIR/config.env"
                echo ""
                if [ -f "$CONFIG_DIR/config.yaml" ]; then
                    print_info "ingress配置:"
                    cat "$CONFIG_DIR/config.yaml"
                fi
            else
                echo "未找到配置文件"
            fi
            echo ""
            read -p "按回车返回菜单..." -r
            ;;
        5)
            print_info "重启所有服务..."
            systemctl restart x-ui
            systemctl restart $SERVICE_NAME
            sleep 2
            print_success "服务已重启"
            echo ""
            read -p "按回车返回菜单..." -r
            ;;
        6)
            print_warning "卸载清理..."
            systemctl stop $SERVICE_NAME 2>/dev/null || true
            systemctl disable $SERVICE_NAME 2>/dev/null || true
            systemctl stop x-ui 2>/dev/null || true
            pkill -f cloudflared 2>/dev/null || true
            rm -f /etc/systemd/system/$SERVICE_NAME.service 2>/dev/null || true
            rm -rf "$CONFIG_DIR" 2>/dev/null || true
            rm -rf "$LOG_DIR" 2>/dev/null || true
            rm -rf /root/.cloudflared 2>/dev/null || true
            systemctl daemon-reload
            print_success "已清理"
            echo ""
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

# 主函数
main() {
    # 检查root权限
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
            systemctl status $SERVICE_NAME --no-pager
            ;;
        "menu"|"")
            show_menu
            ;;
        *)
            show_title
            echo "使用方法:"
            echo "  sudo $0 menu        # 显示菜单"
            echo "  sudo $0 install     # 安装配置"
            echo "  sudo $0 fix         # 快速修复"
            echo "  sudo $0 status      # 查看状态"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"