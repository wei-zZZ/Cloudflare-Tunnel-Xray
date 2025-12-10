#!/bin/bash
# Cloudflared优化系统安装脚本

set -e

echo "========================================="
echo " Cloudflared 智能域名优化系统安装程序"
echo "========================================="

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo "请使用root权限运行此脚本: sudo bash setup.sh"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖包..."
    
    # 检测系统类型
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y python3 python3-pip python3-venv curl dnsutils iputils-ping bc
        apt-get install -y systemctl || true
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS
        yum install -y python3 python3-pip curl bind-utils iputils bc
        yum install -y systemd || true
    elif [ -f /etc/arch-release ]; then
        # Arch Linux
        pacman -Syu --noconfirm python python-pip curl dnsutils iputils bc
    else
        log_warn "未知系统类型，尝试安装基本工具..."
        # 尝试通用安装
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y python3 python3-pip curl dnsutils iputils-ping bc
        elif command -v yum &> /dev/null; then
            yum install -y python3 python3-pip curl bind-utils iputils bc
        fi
    fi
    
    # 安装Python包
    log_info "安装Python依赖包..."
    pip3 install --upgrade pip
    pip3 install requests geoip2 pyyaml flask
}

# 安装cloudflared
install_cloudflared() {
    log_info "安装cloudflared..."
    
    # 检查是否已安装
    if command -v cloudflared &> /dev/null; then
        log_info "cloudflared已安装，跳过安装步骤"
        return 0
    fi
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        arm*)
            ARCH="arm"
            ;;
        *)
            ARCH="amd64"
            ;;
    esac
    
    log_info "系统架构: $ARCH"
    
    # 下载cloudflared
    log_info "下载cloudflared..."
    if ! wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" -O /usr/local/bin/cloudflared; then
        log_error "下载cloudflared失败"
        return 1
    fi
    
    chmod +x /usr/local/bin/cloudflared
    
    # 创建cloudflared目录
    mkdir -p /etc/cloudflared
    
    # 创建默认配置文件
    if [ ! -f /etc/cloudflared/config.yml ]; then
        cat > /etc/cloudflared/config.yml << 'EOF'
# Cloudflared 配置文件
# 通过cf-optimizer.py自动更新

proxy-dns: true
proxy-dns-port: 5053
proxy-dns-upstream:
  - https://cloudflare-dns.com/dns-query
  - https://1.1.1.1/dns-query
  - https://1.0.0.1/dns-query

# 可选：设置日志级别
logfile: /var/log/cloudflared.log
loglevel: info
EOF
    fi
    
    # 创建服务文件
    cat > /etc/systemd/system/cloudflared.service << 'EOF'
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared --config /etc/cloudflared/config.yml tunnel run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log_info "cloudflared安装完成"
}

# 下载GeoIP数据库
download_geoip_db() {
    log_info "配置GeoIP数据库..."
    
    GEOIP_DIR="/etc/cloudflared-optimizer"
    GEOIP_DB="$GEOIP_DIR/GeoLite2-City.mmdb"
    
    # 创建目录
    mkdir -p "$GEOIP_DIR"
    
    # 检查是否已有数据库
    if [ -f "$GEOIP_DB" ]; then
        log_info "GeoIP数据库已存在"
        return 0
    fi
    
    log_warn "需要配置GeoIP数据库以支持地理位置优选"
    echo ""
    echo "请选择GeoIP数据库配置方式:"
    echo "1. 使用免费版本（需要手动下载）"
    echo "2. 跳过（将无法使用地理位置优选功能）"
    echo ""
    read -p "请选择 [1/2]: " choice
    
    case $choice in
        1)
            echo ""
            echo "请按以下步骤操作:"
            echo "1. 访问: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data"
            echo "2. 注册免费账户"
            echo "3. 登录后下载 GeoLite2 City 数据库 (MMDB格式)"
            echo "4. 将下载的文件重命名为 GeoLite2-City.mmdb"
            echo "5. 复制到: $GEOIP_DB"
            echo ""
            read -p "按回车键继续..." _
            ;;
        2)
            log_info "跳过GeoIP数据库配置"
            ;;
        *)
            log_info "使用免费版本选项"
            ;;
    esac
    
    # 检查数据库是否存在
    if [ -f "$GEOIP_DB" ]; then
        log_info "GeoIP数据库配置成功"
    else
        log_warn "GeoIP数据库未配置，地理位置优选功能将不可用"
    fi
}

# 安装优化系统
install_optimizer() {
    log_info "安装优化系统..."
    
    # 创建目录结构
    mkdir -p /etc/cloudflared-optimizer/{results,logs,templates,static}
    
    # 检查当前目录是否有脚本文件
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 复制主脚本
    if [ -f "$SCRIPT_DIR/cf-optimizer.py" ]; then
        cp "$SCRIPT_DIR/cf-optimizer.py" /etc/cloudflared-optimizer/
        log_info "复制主脚本"
    else
        log_error "未找到主脚本文件 cf-optimizer.py"
        log_info "请确保在脚本同目录下运行安装程序"
        exit 1
    fi
    
    # 复制Web界面脚本
    if [ -f "$SCRIPT_DIR/web-ui.py" ]; then
        cp "$SCRIPT_DIR/web-ui.py" /etc/cloudflared-optimizer/
        log_info "复制Web界面脚本"
    else
        log_warn "未找到Web界面文件 web-ui.py"
    fi
    
    # 设置权限
    chmod +x /etc/cloudflared-optimizer/cf-optimizer.py
    if [ -f /etc/cloudflared-optimizer/web-ui.py ]; then
        chmod +x /etc/cloudflared-optimizer/web-ui.py
    fi
    
    # 创建配置文件
    if [ ! -f /etc/cloudflared-optimizer/config.json ]; then
        cat > /etc/cloudflared-optimizer/config.json << 'EOF'
{
    "test_count": 3,
    "timeout": 3,
    "max_threads": 10,
    "min_success_rate": 80,
    "auto_update_config": true,
    "restart_cloudflared": true,
    "cloudflared_config": "/etc/cloudflared/config.yml",
    "update_interval": 3600,
    "regions": {
        "china": ["Asia/Shanghai", "Asia/Beijing", "Asia/Chongqing"],
        "europe": ["Europe/*"],
        "america": ["America/*"]
    },
    "preferred_regions": [],
    "speed_test": true,
    "speed_test_size": 102400,
    "notification": {
        "enabled": false,
        "type": "webhook",
        "webhook_url": ""
    }
}
EOF
        log_info "创建配置文件"
    fi
    
    # 创建域名列表
    if [ ! -f /etc/cloudflared-optimizer/domains.txt ]; then
        cat > /etc/cloudflared-optimizer/domains.txt << 'EOF'
cf.cdn.cloudflare.net
cdn.cloudflare.net
one.one.one.one
1.1.1.1
1.0.0.1
dns.cloudflare.com
speed.cloudflare.com
cloudflare.com
www.cloudflare.com
time.cloudflare.com
EOF
        log_info "创建域名列表"
    fi
    
    log_info "优化系统文件安装完成"
}

# 配置系统服务
setup_services() {
    log_info "配置系统服务..."
    
    # 创建定时服务
    cat > /etc/systemd/system/cf-optimizer.timer << 'EOF'
[Unit]
Description=定时运行Cloudflared优化
Requires=cf-optimizer.service

[Timer]
OnCalendar=*-*-* 0,6,12,18:00:00
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # 创建优化服务
    cat > /etc/systemd/system/cf-optimizer.service << 'EOF'
[Unit]
Description=Cloudflared域名优化服务
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/bin/python3 /etc/cloudflared-optimizer/cf-optimizer.py
WorkingDirectory=/etc/cloudflared-optimizer
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 创建Web界面服务
    cat > /etc/systemd/system/cf-webui.service << 'EOF'
[Unit]
Description=Cloudflared优化系统Web界面
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/cloudflared-optimizer
ExecStart=/usr/bin/python3 /etc/cloudflared-optimizer/web-ui.py
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 启用服务
    systemctl daemon-reload
    
    # 启用定时任务
    systemctl enable cf-optimizer.timer
    systemctl start cf-optimizer.timer
    
    log_info "定时服务已启用（每天0,6,12,18点运行）"
    
    # 询问是否启用Web界面
    echo ""
    read -p "是否启用Web界面服务？[Y/n]: " choice
    choice=${choice:-Y}
    
    if [[ $choice =~ ^[Yy]$ ]]; then
        systemctl enable cf-webui.service
        systemctl start cf-webui.service
        log_info "Web界面已启用，访问: http://服务器IP:5000"
    fi
    
    # 询问是否启用cloudflared服务
    echo ""
    read -p "是否启用并启动cloudflared服务？[Y/n]: " choice
    choice=${choice:-Y}
    
    if [[ $choice =~ ^[Yy]$ ]]; then
        systemctl enable cloudflared.service
        systemctl start cloudflared.service
        log_info "cloudflared服务已启用"
    fi
}

# 第一次运行测试
run_first_test() {
    log_info "运行第一次测试..."
    
    echo ""
    read -p "是否现在运行第一次域名测试？[Y/n]: " choice
    choice=${choice:-Y}
    
    if [[ $choice =~ ^[Yy]$ ]]; then
        cd /etc/cloudflared-optimizer
        python3 cf-optimizer.py --test-only
        
        if [ $? -eq 0 ]; then
            log_info "测试完成！"
            
            # 显示最佳域名
            if [ -f "/etc/cloudflared-optimizer/results/best-domain.txt" ]; then
                echo ""
                echo "最佳域名: $(cat /etc/cloudflared-optimizer/results/best-domain.txt)"
            fi
        else
            log_warn "测试过程中出现警告"
        fi
    fi
}

# 显示使用说明
show_usage() {
    echo ""
    echo "========================================="
    echo "安装完成！"
    echo "========================================="
    echo ""
    echo "主要文件位置:"
    echo "  /etc/cloudflared-optimizer/cf-optimizer.py    # 主脚本"
    echo "  /etc/cloudflared-optimizer/web-ui.py         # Web界面"
    echo "  /etc/cloudflared-optimizer/config.json       # 配置文件"
    echo "  /etc/cloudflared-optimizer/domains.txt       # 域名列表"
    echo ""
    echo "使用方法:"
    echo "1. 手动运行测试:"
    echo "   sudo python3 /etc/cloudflared-optimizer/cf-optimizer.py"
    echo ""
    echo "2. 运行Web界面:"
    echo "   sudo systemctl start cf-webui.service"
    echo "   访问 http://服务器IP:5000"
    echo ""
    echo "3. 查看服务状态:"
    echo "   sudo systemctl status cf-optimizer.timer"
    echo "   sudo systemctl status cf-webui.service"
    echo "   sudo systemctl status cloudflared"
    echo ""
    echo "4. 查看日志:"
    echo "   sudo journalctl -u cf-optimizer.service"
    echo "   sudo journalctl -u cf-webui.service"
    echo "   sudo tail -f /etc/cloudflared-optimizer/logs/*.log"
    echo ""
    echo "5. 测试结果:"
    echo "   sudo cat /etc/cloudflared-optimizer/results/best-domain.txt"
    echo "   sudo cat /etc/cloudflared-optimizer/results/latest.json | python3 -m json.tool"
    echo ""
    echo "6. 修改配置:"
    echo "   sudo nano /etc/cloudflared-optimizer/config.json"
    echo "   sudo nano /etc/cloudflared-optimizer/domains.txt"
    echo ""
    echo "7. 添加自定义域名:"
    echo "   编辑 /etc/cloudflared-optimizer/domains.txt 文件"
    echo ""
    echo "8. 配置GeoIP数据库:"
    echo "   将 GeoLite2-City.mmdb 文件复制到:"
    echo "   /etc/cloudflared-optimizer/GeoLite2-City.mmdb"
    echo ""
    echo "========================================="
}

# 主安装流程
main() {
    echo "开始安装Cloudflared优化系统..."
    echo ""
    
    # 安装依赖
    install_dependencies
    
    # 安装cloudflared
    install_cloudflared
    
    # 配置GeoIP数据库
    download_geoip_db
    
    # 安装优化系统
    install_optimizer
    
    # 配置服务
    setup_services
    
    # 第一次运行测试
    run_first_test
    
    # 显示使用说明
    show_usage
    
    log_info "安装完成！"
}

# 运行主函数
main "$@"