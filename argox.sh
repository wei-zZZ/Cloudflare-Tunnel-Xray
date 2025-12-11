#!/usr/bin/env bash

# ============================================================================
# ArgoX 脚本优化版
# 项目地址: https://github.com/fscarmen/argox
# 优化重点: 代码结构、错误处理、性能优化、安全性
# ============================================================================

set -o errexit          # 遇到错误时退出
set -o nounset          # 使用未定义变量时退出
set -o pipefail         # 管道中任意命令失败则整个失败

# ============================================================================
# 版本与配置常量
# ============================================================================
readonly VERSION='1.6.12 (2025.12.09)'
readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# ============================================================================
# 目录配置
# ============================================================================
readonly WORK_DIR='/etc/argox'
readonly TEMP_DIR='/tmp/argox'
readonly LOG_DIR='/var/log/argox'
readonly BACKUP_DIR="$WORK_DIR/backup"

# ============================================================================
# 服务配置常量
# ============================================================================
readonly METRICS_PORT='3333'
readonly TLS_SERVER='addons.mozilla.org'
readonly DEFAULT_XRAY_VERSION='25.12.8'
readonly WS_PATH_DEFAULT='argox'
readonly DEFAULT_NODE_NAME='ArgoX'

# ============================================================================
# 网络与代理配置
# ============================================================================
readonly GH_PROXY='https://hub.glowp.xyz/'
readonly SUBSCRIBE_TEMPLATE="https://raw.githubusercontent.com/fscarmen/client_template/main"

# CDN域名列表
readonly CDN_DOMAINS=(
    "skk.moe"
    "ip.sb" 
    "time.is"
    "cfip.xxxxxxxx.tk"
    "bestcf.top"
    "cdn.2020111.xyz"
    "xn--b6gac.eu.org"
    "cf.090227.xyz"
)

# ============================================================================
# 颜色定义
# ============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# ============================================================================
# 多语言文本定义
# ============================================================================
declare -A LANG_EN LANG_ZH

# 英文文本
LANG_EN=(
    [0]="Language:\n 1. English (default) \n 2. 简体中文"
    [1]="Quick Install Mode: Added a one-click installation feature that auto-fills all parameters, simplifying the deployment process. Chinese users can use -l or -L; English users can use -k or -K. Case-insensitive support makes operations more flexible."
    [2]="Project to create Argo tunnels and Xray specifically for VPS, detailed:[https://github.com/fscarmen/argox]\n Features:\n\t • Allows the creation of Argo tunnels via Token, Json and ad hoc methods. User can easily obtain the json at https://fscarmen.cloudflare.now.cc .\n\t • Extremely fast installation method, saving users time.\n\t • Support system: Ubuntu, Debian, CentOS, Alpine and Arch Linux 3.\n\t • Support architecture: AMD,ARM and s390x\n"
    [3]="Input errors up to 5 times.The script is aborted."
    [4]="UUID should be 36 characters, please re-enter \(\${a} times remaining\)"
    [5]="The script supports Debian, Ubuntu, CentOS, Alpine or Arch systems only. Feedback: [https://github.com/fscarmen/argox/issues]"
    [6]="Curren operating system is \$SYS.\\\n The system lower than \$SYSTEM \${MAJOR[int]} is not supported. Feedback: [https://github.com/fscarmen/argox/issues]"
    [7]="Install dependence-list:"
    [8]="All dependencies already exist and do not need to be installed additionally."
    [9]="To upgrade, press [y]. No upgrade by default:"
    [10]="(3/8) Please enter Argo Domain (Default is temporary domain if left blank):"
    [11]="Please enter Argo Token or Json ( User can easily obtain the json at https://fscarmen.cloudflare.now.cc ):"
    [12]="\(6/8\) Please enter Xray UUID \(Default is \$UUID_DEFAULT\):"
    [13]="\(7/8\) Please enter Xray WS Path \(Default is \$WS_PATH_DEFAULT\):"
    [14]="Xray WS Path only allow uppercase and lowercase letters and numeric characters, please re-enter \(\${a} times remaining\):"
    [15]="ArgoX script has not been installed yet."
    [16]="ArgoX is completely uninstalled."
    [17]="Version"
    [18]="New features"
    [19]="System information"
    [20]="Operating System"
    [21]="Kernel"
    [22]="Architecture"
    [23]="Virtualization"
    [24]="Choose:"
    [25]="Current architecture \$(uname -m) is not supported. Feedback: [https://github.com/fscarmen/argox/issues]"
    [26]="Not install"
    [27]="close"
    [28]="open"
    [29]="View links (argox -n)"
    [30]="Change the Argo tunnel (argox -t)"
    [31]="Sync Argo and Xray to the latest version (argox -v)"
    [32]="Upgrade kernel, turn on BBR, change Linux system (argox -b)"
    [33]="Uninstall (argox -u)"
    [34]="Install ArgoX script (argo + xray)"
    [35]="Exit"
    [36]="Please enter the correct number"
    [37]="successful"
    [38]="failed"
    [39]="ArgoX is not installed."
    [40]="Argo tunnel is: \$ARGO_TYPE\\\n The domain is: \$ARGO_DOMAIN"
    [41]="Argo tunnel type:\n 1. Try\n 2. Token or Json"
    [42]="\(5/8\) Please select or enter the preferred domain, the default is \${CDN_DOMAIN[0]}:"
    [43]="\$APP local version: \$LOCAL.\\\t The newest version: \$ONLINE"
    [44]="No upgrade required."
    [45]="Argo authentication message does not match the rules, neither Token nor Json, script exits. Feedback:[https://github.com/fscarmen/argox/issues]"
    [46]="Connect"
    [47]="The script must be run as root, you can enter sudo -i and then download and run again. Feedback:[https://github.com/fscarmen/argox/issues]"
    [48]="Downloading the latest version \$APP failed, script exits. Feedback:[https://github.com/fscarmen/argox/issues]"
    [49]="\(8/8\) Please enter the node name. \(Default is \${NODE_NAME_DEFAULT}\):"
    [50]="\${APP[@]} services are not enabled, node information cannot be output. Press [y] if you want to open."
    [51]="Install Sing-box multi-protocol scripts [https://github.com/fscarmen/sing-box]"
    [52]="Memory Usage"
    [53]="The xray service is detected to be installed. Script exits."
    [54]="Warp / warp-go was detected to be running. Please enter the correct server IP:"
    [55]="The script runs today: \$TODAY. Total: \$TOTAL"
    [56]="\(4/8\) Please enter the Reality port \(Default is \${REALITY_PORT_DEFAULT}\):"
    [57]="Install sba scripts (argo + sing-box) [https://github.com/fscarmen/sba]"
    [58]="No server ip, script exits. Feedback:[https://github.com/fscarmen/sing-box/issues]"
    [59]="\(2/8\) Please enter VPS IP \(Default is: \${SERVER_IP_DEFAULT}\):"
    [60]="Quicktunnel domain can be obtained from: http://\${SERVER_IP_1}:\${METRICS_PORT}/quicktunnel"
    [61]="Ports are in used: \$REALITY_PORT"
    [62]="Create shortcut [ argox ] successfully."
    [63]="The full template can be found at:\n https://t.me/ztvps/67\n https://github.com/chika0801/sing-box-examples/tree/main/Tun"
    [64]="subscribe"
    [65]="To uninstall Nginx press [y], it is not uninstalled by default:"
    [66]="Adaptive Clash / V2rayN / NekoBox / ShadowRocket / SFI / SFA / SFM Clients"
    [67]="template"
    [68]="(1/8) Output subscription QR code and https service, need to install nginx\n If not, please enter [n]. Default installation:"
    [69]="Set SElinux: enforcing --> disabled"
    [70]="ArgoX is not installed and cannot change the CDN."
    [71]="Current CDN is: \${CDN_NOW}"
    [72]="Please select or enter a new CDN (press Enter to keep the current one):"
    [73]="CDN has been changed from \${CDN_NOW} to \${CDN_NEW}"
    [74]="Unable to access api.github.com. This may be due to IP restrictions (HTTP/1.1 403 Rate Limit Exceeded). Please try again later"
    [75]="Special Note: Due to incomplete links exported by v2rayN and Nekobox, please handle as follows:\n\nNekobox: Set UoT to 2 to enable UDP over TCP\n\nv2rayN:"
    [76]="Transport Protocol: WS , Host: \${ARGO_DOMAIN} , Path: /\${WS_PATH}-sh , TLS: tls , SNI: \${ARGO_DOMAIN}"
    [77]="Quick install mode (argox -k)"
)

# 中文文本
LANG_ZH=(
    [0]="语言选择:\n 1. 英文 (默认) \n 2. 简体中文"
    [1]="极速安装模式：新增一键安装功能，所有参数自动填充，简化部署流程。中文用户使用 -l 或 -L，英文用户使用 -k 或 -K，大小写均支持，操作更灵活"
    [2]="本项目专为 VPS 添加 Argo 隧道及 Xray,详细说明: [https://github.com/fscarmen/argox]\n 脚本特点:\n\t • 允许通过 Token, Json 及 临时方式来创建 Argo 隧道,用户通过以下网站轻松获取 json: https://fscarmen.cloudflare.now.cc\n\t • 极速安装方式,大大节省用户时间\n\t • 智能判断操作系统: Ubuntu 、Debian 、CentOS 、Alpine 和 Arch Linux,请务必选择 LTS 系统\n\t • 支持硬件结构类型: AMD 和 ARM\n"
    [3]="输入错误达5次,脚本退出"
    [4]="UUID 应为36位字符,请重新输入 \(剩余\${a}次\)"
    [5]="本脚本只支持 Debian、Ubuntu、CentOS、Alpine 或 Arch 系统,问题反馈:[https://github.com/fscarmen/argox/issues]"
    [6]="当前操作是 \$SYS\\\n 不支持 \$SYSTEM \${MAJOR[int]} 以下系统,问题反馈:[https://github.com/fscarmen/argox/issues]"
    [7]="安装依赖列表:"
    [8]="所有依赖已存在，不需要额外安装"
    [9]="升级请按 [y]，默认不升级:"
    [10]="(3/8) 请输入 Argo 域名 (如果没有，可以跳过以使用 Argo 临时域名):"
    [11]="请输入 Argo Token 或者 Json ( 用户通过以下网站轻松获取 json: https://fscarmen.cloudflare.now.cc ):"
    [12]="\(6/8\) 请输入 Xray UUID \(默认为 \$UUID_DEFAULT\):"
    [13]="\(7/8\) 请输入 Xray WS 路径 \(默认为 \$WS_PATH_DEFAULT\):"
    [14]="Xray WS 路径只允许英文大小写及数字字符，请重新输入 \(剩余\${a}次\):"
    [15]="ArgoX 脚本还没有安装"
    [16]="ArgoX 已彻底卸载"
    [17]="脚本版本"
    [18]="功能新增"
    [19]="系统信息"
    [20]="当前操作系统"
    [21]="内核"
    [22]="处理器架构"
    [23]="虚拟化"
    [24]="请选择:"
    [25]="当前架构 \$(uname -m) 暂不支持,问题反馈:[https://github.com/fscarmen/argox/issues]"
    [26]="未安装"
    [27]="关闭"
    [28]="开启"
    [29]="查看节点信息 (argox -n)"
    [30]="更换 Argo 隧道 (argox -t)"
    [31]="同步 Argo 和 Xray 至最新版本 (argox -v)"
    [32]="升级内核、安装BBR、DD脚本 (argox -b)"
    [33]="卸载 (argox -u)"
    [34]="安装 ArgoX 脚本 (argo + xray)"
    [35]="退出"
    [36]="请输入正确数字"
    [37]="成功"
    [38]="失败"
    [39]="ArgoX 未安装"
    [40]="Argo 隧道类型为: \$ARGO_TYPE\\\n 域名是: \$ARGO_DOMAIN"
    [41]="Argo 隧道类型:\n 1. Try\n 2. Token 或者 Json"
    [42]="\(5/8\) 请选择或者填入优选域名，默认为 \${CDN_DOMAIN[0]}:"
    [43]="\$APP 本地版本: \$LOCAL.\\\t 最新版本: \$ONLINE"
    [44]="不需要升级"
    [45]="Argo 认证信息不符合规则，既不是 Token，也是不是 Json，脚本退出，问题反馈:[https://github.com/fscarmen/argox/issues]"
    [46]="连接"
    [47]="必须以root方式运行脚本，可以输入 sudo -i 后重新下载运行，问题反馈:[https://github.com/fscarmen/argox/issues]"
    [48]="下载最新版本 \$APP 失败，脚本退出，问题反馈:[https://github.com/fscarmen/argox/issues]"
    [49]="\(8/8\) 请输入节点名称 \(默认为 \${NODE_NAME_DEFAULT}\):"
    [50]="\${APP[@]} 服务未开启，不能输出节点信息。如需打开请按 [y]: "
    [51]="安装 Sing-box 协议全家桶脚本 [https://github.com/fscarmen/sing-box]"
    [52]="内存占用"
    [53]="检测到已安装 xray 服务，脚本退出!"
    [54]="检测到 warp / warp-go 正在运行，请输入确认的服务器 IP:"
    [55]="脚本当天运行次数: \$TODAY，累计运行次数: \$TOTAL"
    [56]="\(4/8\) 请输入 Reality 的端口号 \(默认为 \${REALITY_PORT_DEFAULT}\):"
    [57]="安装 sba 脚本 (argo + sing-box) [https://github.com/fscarmen/sba]"
    [58]="没有 server ip，脚本退出，问题反馈:[https://github.com/fscarmen/sing-box/issues]"
    [59]="\(2/8\) 请输入 VPS IP \(默认为: \${SERVER_IP_DEFAULT}\):"
    [60]="临时隧道域名可以从以下网站获取: http://\${SERVER_IP_1}:\${METRICS_PORT}/quicktunnel"
    [61]="正在使用中的端口: \$REALITY_PORT"
    [62]="创建快捷 [ argox ] 指令成功!"
    [63]="完整模板可参照:\n https://t.me/ztvps/67\n https://github.com/chika0801/sing-box-examples/tree/main/Tun"
    [64]="订阅"
    [65]="如要卸载 Nginx 请按 [y]，默认不卸载:"
    [66]="自适应 Clash / V2rayN / NekoBox / ShadowRocket / SFI / SFA / SFM 客户端"
    [67]="模版"
    [68]="(1/8) 输出订阅二维码和 https 服务，需要安装依赖 nginx\n 如不需要，请输入 [n]，默认安装:"
    [69]="设置 SElinux: enforcing --> disabled"
    [70]="ArgoX 未安装，不能更换 CDN"
    [71]="当前 CDN 为: \${CDN_NOW}"
    [72]="请选择或输入新的 CDN (回车保持当前值):"
    [73]="CDN 已从 \${CDN_NOW} 更改为 \${CDN_NEW}"
    [74]="无法访问 api.github.com，可能是由于 IP 限制导致的（HTTP/1.1 403 Rate Limit Exceeded），请稍后重试"
    [75]="特别说明: 由于 v2rayN 与 Nekobox 导出的链接不全，请自行处理如下:\n\nNekobox: 把 UoT 设置为2，以开启 UDP over TCP\n\nv2rayN:"
    [76]="传输协议: WS , 伪装域名: \${ARGO_DOMAIN} , 路径: /\${WS_PATH}-sh , 传输层安全: tls , SNI: \${ARGO_DOMAIN}"
    [77]="极速安装模式 (argox -l)"
)

# ============================================================================
# 全局变量
# ============================================================================
L='E'  # 默认语言
SYSTEM=''
IS_CENTOS=''
SYS=''
ARGO_DAEMON_FILE=''
XRAY_DAEMON_FILE=''
DAEMON_RUN_PATTERN=''
STATUS=("$(text 26)" "$(text 26)")  # Argo, Xray 状态
IS_NGINX='no_nginx'
NONINTERACTIVE_INSTALL=''
VARIABLE_FILE=''
CHAT_GPT_OUT_V4='direct'
CHAT_GPT_OUT_V6='direct'

# ============================================================================
# 工具函数
# ============================================================================

# 日志函数
log_init() {
    mkdir -p "$LOG_DIR"
    exec 2>>"$LOG_DIR/error.log"
}

log_info() {
    echo -e "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_DIR/argox.log"
}

log_error() {
    echo -e "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_DIR/argox.log" >&2
    exit 1
}

log_warning() {
    echo -e "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_DIR/argox.log"
}

# 颜色输出函数
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

print_red() { print_color "$RED" "$@"; }
print_green() { print_color "$GREEN" "$@"; }
print_yellow() { print_color "$YELLOW" "$@"; }
print_blue() { print_color "$BLUE" "$@"; }
print_magenta() { print_color "$MAGENTA" "$@"; }
print_cyan() { print_color "$CYAN" "$@"; }

# 文本显示函数
text() {
    local key=$1
    local lang_var="LANG_${L}[$key]"
    
    if [[ -v "LANG_${L}[$key]" ]]; then
        eval echo "\"\${LANG_${L}[$key]}\""
    else
        echo "Text key $key not found for language $L"
    fi
}

# 带颜色的提示函数
info() { print_green "$@"; }
warning() { print_yellow "$@"; }
error() { print_red "$@" && exit 1; }
hint() { print_cyan "$@"; }

# 读取输入函数
reading() {
    local prompt="$1"
    local var_name="$2"
    read -rp "$(info "$prompt") " input
    eval "$var_name=\"$input\""
}

# ============================================================================
# 初始化函数
# ============================================================================

init_environment() {
    log_info "Initializing ArgoX environment..."
    
    # 创建必要目录
    mkdir -p "$WORK_DIR" "$TEMP_DIR" "$LOG_DIR" "$BACKUP_DIR"
    
    # 设置退出清理
    trap cleanup EXIT INT TERM
    
    # 初始化日志
    log_init
}

cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}

# ============================================================================
# 验证函数
# ============================================================================

validate_ip() {
    local ip="$1"
    
    # IPv4 验证
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            [[ $octet -le 255 ]] || return 1
        done
        return 0
    # IPv6 验证
    elif [[ $ip =~ ^[0-9a-fA-F:]+$ ]]; then
        return 0
    fi
    
    return 1
}

validate_uuid() {
    local uuid="$1"
    [[ "$uuid" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]
}

# 检查必需命令是否存在
check_required_commands() {
    local commands=("wget" "curl" "unzip" "jq")
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_warning "Command $cmd not found, will attempt to install"
        fi
    done
}

# ============================================================================
# 配置管理
# ============================================================================

CONFIG_FILE="$WORK_DIR/config.env"

save_config() {
    cat > "$CONFIG_FILE" << EOF
# ArgoX Configuration
# Generated on $(date)
LANGUAGE=$L
ARGO_TYPE=$ARGO_TYPE
ARGO_DOMAIN=$ARGO_DOMAIN
SERVER_IP=$SERVER_IP
REALITY_PORT=$REALITY_PORT
UUID=$UUID
WS_PATH=$WS_PATH
NODE_NAME=$NODE_NAME
CDN_DOMAIN=$CDN_DOMAIN
INSTALL_NGINX=$INSTALL_NGINX
EOF
    
    log_info "Configuration saved to $CONFIG_FILE"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
}

backup_config() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/config_$timestamp"
    
    mkdir -p "$backup_path"
    cp -r "$WORK_DIR"/*.json "$WORK_DIR"/*.yml "$WORK_DIR"/*.conf "$backup_path"/ 2>/dev/null || true
    
    log_info "Configuration backed up to $backup_path"
}

# ============================================================================
# 服务管理函数
# ============================================================================

service_manager() {
    local action="$1"
    local service="$2"
    
    case "$SYSTEM" in
        Alpine)
            case "$action" in
                enable) rc-update add "$service" default ;;
                disable) rc-update del "$service" default ;;
                start|stop|restart|status) rc-service "$service" "$action" ;;
            esac
            ;;
        *)
            systemctl "$action" "$service" 2>/dev/null
            ;;
    esac
}

enable_service() {
    log_info "Enabling service: $1"
    service_manager enable "$1"
}

disable_service() {
    log_info "Disabling service: $1"
    service_manager disable "$1"
}

start_service() {
    log_info "Starting service: $1"
    if service_manager start "$1"; then
        log_info "Service $1 started successfully"
        return 0
    else
        log_error "Failed to start service $1"
    fi
}

stop_service() {
    log_info "Stopping service: $1"
    service_manager stop "$1"
}

restart_service() {
    log_info "Restarting service: $1"
    service_manager restart "$1"
}

service_status() {
    service_manager status "$1"
}

# ============================================================================
# 下载函数
# ============================================================================

# 并行下载函数
download_parallel() {
    local urls=("$@")
    local pids=()
    local failed=0
    
    log_info "Starting parallel download of ${#urls[@]} files"
    
    for url in "${urls[@]}"; do
        local filename=$(basename "$url")
        wget --no-check-certificate -q "$url" -O "$TEMP_DIR/$filename" &
        pids+=($!)
    done
    
    # 等待所有下载完成
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=$((failed + 1))
        fi
    done
    
    if [ $failed -gt 0 ]; then
        log_warning "Failed to download $failed files"
        return 1
    fi
    
    return 0
}

# 安全的下载函数
safe_download() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if wget --no-check-certificate -q "$url" -O "$output"; then
            log_info "Downloaded: $(basename "$output")"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_warning "Download failed, retrying ($retry_count/$max_retries)..."
        sleep 2
    done
    
    log_error "Failed to download: $url"
}

# ============================================================================
# 语言选择函数
# ============================================================================
select_language() {
    if [ -z "$L" ]; then
        case $(cat "$WORK_DIR/language" 2>/dev/null) in
            E) L='E' ;;
            C) L='C' ;;
            *) 
                [ -z "$L" ] && L='E'
                if ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL"; then
                    echo ""
                    hint "\n $(text 0) \n"
                    reading " $(text 24) " LANGUAGE
                    [ "$LANGUAGE" = 2 ] && L='C'
                fi
                ;;
        esac
    fi
    
    log_info "Selected language: $L"
}

# ============================================================================
# 系统检查函数
# ============================================================================

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error " $(text 47) "
    fi
    log_info "Running as root: OK"
}

# 检查系统架构
check_arch() {
    case $(uname -m) in
        aarch64|arm64 )
            ARGO_ARCH='arm64'
            XRAY_ARCH='arm64-v8a'
            JQ_ARCH='arm64'
            QRENCODE_ARCH='arm64'
            ;;
        x86_64|amd64 )
            ARGO_ARCH='amd64'
            XRAY_ARCH='64'
            JQ_ARCH='amd64'
            QRENCODE_ARCH='amd64'
            ;;
        armv7l )
            ARGO_ARCH='arm'
            XRAY_ARCH='arm32-v7a'
            JQ_ARCH='armhf'
            QRENCODE_ARCH='arm'
            ;;
        * )
            log_error " $(text 25) "
            ;;
    esac
    
    log_info "Architecture detected: $(uname -m) -> ARGO:$ARGO_ARCH, XRAY:$XRAY_ARCH"
}

# 检测系统信息
check_system_info() {
    log_info "Detecting system information..."
    
    # 检测虚拟化
    if command -v systemd-detect-virt &>/dev/null; then
        VIRT=$(systemd-detect-virt)
    elif command -v hostnamectl &>/dev/null; then
        VIRT=$(hostnamectl | awk '/Virtualization/{print $NF}')
    elif command -v virt-what &>/dev/null; then
        VIRT=$(virt-what)
    else
        VIRT='Unknown'
    fi
    
    # 检测操作系统
    local os_release_files=("/etc/os-release" "/etc/lsb-release" "/etc/redhat-release" "/etc/issue")
    local os_cmds=("hostnamectl" "lsb_release")
    
    for file in "${os_release_files[@]}"; do
        if [[ -f "$file" ]]; then
            case "$file" in
                "/etc/os-release")
                    SYS=$(awk -F '"' 'tolower($0) ~ /pretty_name/{print $2}' "$file")
                    ;;
                "/etc/lsb-release")
                    SYS=$(awk -F '"' 'tolower($0) ~ /distrib_description/{print $2}' "$file")
                    ;;
                "/etc/redhat-release")
                    SYS=$(cat "$file")
                    ;;
                "/etc/issue")
                    SYS=$(sed -E '/^$|^\\/d' "$file" | awk -F '\\' '{print $1}' | sed 's/[ ]*$//g')
                    ;;
            esac
            [[ -n "$SYS" ]] && break
        fi
    done
    
    # 如果文件检测失败，尝试命令检测
    if [[ -z "$SYS" ]]; then
        for cmd in "${os_cmds[@]}"; do
            if command -v "$cmd" &>/dev/null; then
                case "$cmd" in
                    "hostnamectl")
                        SYS=$(hostnamectl | awk -F ': ' 'tolower($0) ~ /operating system/{print $2}')
                        ;;
                    "lsb_release")
                        SYS=$(lsb_release -sd)
                        ;;
                esac
                [[ -n "$SYS" ]] && break
            fi
        done
    fi
    
    # 系统识别
    local regex_list=("debian" "ubuntu" "centos|red hat|kernel|alma|rocky" "arch linux" "alpine" "fedora")
    local release_list=("Debian" "Ubuntu" "CentOS" "Arch" "Alpine" "Fedora")
    local exclude_list=("---")
    local major_list=("9" "16" "7" "" "" "37")
    
    for i in "${!regex_list[@]}"; do
        if [[ "${SYS,,}" =~ ${regex_list[i]} ]]; then
            SYSTEM="${release_list[i]}"
            break
        fi
    done
    
    # 特定系统处理
    if [[ -z "$SYSTEM" ]]; then
        command -v yum &>/dev/null && SYSTEM='CentOS' || log_error " $(text 5) "
    fi
    
    # 版本检查
    for ex in "${exclude_list[@]}"; do
        [[ ! "${SYS,,}" =~ $ex ]]
    done
    
    local sys_version=$(echo "$SYS" | sed "s/[^0-9.]//g" | cut -d. -f1)
    if [[ "$sys_version" -lt "${major_list[i]}" ]]; then
        log_error " $(eval echo "\$(text 6)") "
    fi
    
    # 系统特定配置
    ARGO_DAEMON_FILE='/etc/systemd/system/argo.service'
    XRAY_DAEMON_FILE='/etc/systemd/system/xray.service'
    DAEMON_RUN_PATTERN="ExecStart="
    
    case "$SYSTEM" in
        CentOS)
            IS_CENTOS="CentOS$(echo "$SYS" | sed "s/[^0-9.]//g" | cut -d. -f1)"
            ;;
        Alpine)
            ARGO_DAEMON_FILE='/etc/init.d/argo'
            XRAY_DAEMON_FILE='/etc/init.d/xray'
            DAEMON_RUN_PATTERN="command_args="
            ;;
    esac
    
    log_info "System detected: $SYSTEM ($SYS), Virtualization: $VIRT"
}

# 检测IP信息
check_system_ip() {
    log_info "Detecting network information..."
    
    local ipv4_test_urls=(
        "http://api-ipv4.ip.sb"
        "http://ipv4.icanhazip.com"
        "http://api.ipify.org"
    )
    
    local ipv6_test_urls=(
        "http://api-ipv6.ip.sb"
        "http://ipv6.icanhazip.com"
        "http://api6.ipify.org"
    )
    
    # 获取默认网络接口
    local default_iface4=$(ip -4 route show default 2>/dev/null | awk '/default/ {for (i=0; i<NF; i++) if ($i=="dev") {print $(i+1); exit}}')
    local default_iface6=$(ip -6 route show default 2>/dev/null | awk '/default/ {for (i=0; i<NF; i++) if ($i=="dev") {print $(i+1); exit}}')
    
    # 获取绑定地址
    local bind_address4=''
    local bind_address6=''
    
    if [[ -n "$default_iface4" ]]; then
        local local_ip4=$(ip -4 addr show "$default_iface4" 2>/dev/null | sed -n 's#.*inet \([^/]\+\)/[0-9]\+.*global.*#\1#p')
        [[ -n "$local_ip4" ]] && bind_address4="--bind-address=$local_ip4"
    fi
    
    if [[ -n "$default_iface6" ]]; then
        local local_ip6=$(ip -6 addr show "$default_iface6" 2>/dev/null | sed -n 's#.*inet6 \([^/]\+\)/[0-9]\+.*global.*#\1#p')
        [[ -n "$local_ip6" ]] && bind_address6="--bind-address=$local_ip6"
    fi
    
    # 获取公网IPv4
    for url in "${ipv4_test_urls[@]}"; do
        WAN4=$(wget $bind_address4 -qO- --no-check-certificate --tries=1 --timeout=3 "$url" 2>/dev/null | tr -d '\n')
        [[ -n "$WAN4" ]] && break
    done
    
    # 获取IPv4地理位置信息
    if [[ -n "$WAN4" ]]; then
        local geo_url="https://ipinfo.io/$WAN4/json"
        if [[ "$L" == "C" ]]; then
            geo_url="https://ip.forvps.gq/${WAN4}?lang=zh-CN"
        fi
        
        local geo_info=$(wget -qO- --no-check-certificate --tries=2 --timeout=5 "$geo_url" 2>/dev/null)
        if [[ -n "$geo_info" ]]; then
            COUNTRY4=$(echo "$geo_info" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
            ASNORG4=$(echo "$geo_info" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
        fi
    fi
    
    # 获取公网IPv6
    for url in "${ipv6_test_urls[@]}"; do
        WAN6=$(wget $bind_address6 -qO- --no-check-certificate --tries=1 --timeout=3 "$url" 2>/dev/null | tr -d '\n')
        [[ -n "$WAN6" ]] && break
    done
    
    # 获取IPv6地理位置信息
    if [[ -n "$WAN6" ]]; then
        local geo_url="https://ipinfo.io/$WAN6/json"
        if [[ "$L" == "C" ]]; then
            geo_url="https://ip.forvps.gq/${WAN6}?lang=zh-CN"
        fi
        
        local geo_info=$(wget -qO- --no-check-certificate --tries=2 --timeout=5 "$geo_url" 2>/dev/null)
        if [[ -n "$geo_info" ]]; then
            COUNTRY6=$(echo "$geo_info" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
            ASNORG6=$(echo "$geo_info" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
        fi
    fi
    
    log_info "IPv4: $WAN4 ($COUNTRY4), IPv6: $WAN6 ($COUNTRY6)"
}

# ============================================================================
# 依赖管理
# ============================================================================

# 系统包管理器配置
setup_package_manager() {
    case "$SYSTEM" in
        Debian|Ubuntu)
            PACKAGE_UPDATE=("apt-get" "update" "-y")
            PACKAGE_INSTALL=("apt-get" "install" "-y" "--no-install-recommends")
            PACKAGE_UNINSTALL=("apt-get" "remove" "--purge" "-y")
            ;;
        CentOS|Fedora)
            if [[ "$SYSTEM" == "CentOS" && "$IS_CENTOS" == "CentOS7" ]]; then
                PACKAGE_UPDATE=("yum" "update" "-y")
                PACKAGE_INSTALL=("yum" "install" "-y")
                PACKAGE_UNINSTALL=("yum" "remove" "-y")
            else
                PACKAGE_UPDATE=("dnf" "update" "-y")
                PACKAGE_INSTALL=("dnf" "install" "-y")
                PACKAGE_UNINSTALL=("dnf" "remove" "-y")
            fi
            ;;
        Arch)
            PACKAGE_UPDATE=("pacman" "-Sy")
            PACKAGE_INSTALL=("pacman" "-S" "--noconfirm")
            PACKAGE_UNINSTALL=("pacman" "-R" "--noconfirm")
            ;;
        Alpine)
            PACKAGE_UPDATE=("apk" "update")
            PACKAGE_INSTALL=("apk" "add" "--no-cache")
            PACKAGE_UNINSTALL=("apk" "del")
            ;;
        *)
            log_error "Unsupported system: $SYSTEM"
            ;;
    esac
    
    log_info "Package manager configured for $SYSTEM"
}

# 检查并安装依赖
check_dependencies() {
    log_info "Checking dependencies..."
    
    local deps_to_install=()
    
    # 基础依赖
    local basic_deps=("wget" "curl" "unzip" "tar" "grep" "sed" "awk")
    
    # 系统特定依赖
    case "$SYSTEM" in
        Alpine)
            # Alpine 需要额外依赖
            deps_to_install+=("bash" "openrc" "virt-what")
            ;;
        *)
            # 其他系统需要 systemctl
            basic_deps+=("systemctl")
            ;;
    esac
    
    # 检查基础依赖
    for dep in "${basic_deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            deps_to_install+=("$dep")
        fi
    done
    
    # 检查并安装缺失的依赖
    if [[ ${#deps_to_install[@]} -gt 0 ]]; then
        info "\n $(text 7) ${deps_to_install[*]} \n"
        
        # 更新包列表
        if "${PACKAGE_UPDATE[@]}" &>/dev/null; then
            log_info "Package list updated"
        else
            log_warning "Failed to update package list"
        fi
        
        # 安装依赖
        if "${PACKAGE_INSTALL[@]}" "${deps_to_install[@]}" &>/dev/null; then
            log_info "Dependencies installed successfully"
        else
            log_error "Failed to install dependencies: ${deps_to_install[*]}"
        fi
    else
        info "\n $(text 8) \n"
    fi
    
    # 如果是 Alpine，升级 wget（如果使用的是 busybox 版本）
    if [[ "$SYSTEM" == "Alpine" ]]; then
        local wget_check=$(wget --help 2>&1 | head -n 1)
        if [[ "$wget_check" == *"BusyBox"* ]]; then
            log_info "Upgrading BusyBox wget to full version..."
            "${PACKAGE_INSTALL[@]}" wget &>/dev/null
        fi
    fi
}

# 检查并安装Nginx
check_nginx() {
    log_info "Checking Nginx installation..."
    
    if ! command -v nginx &>/dev/null; then
        info "\n $(text 7) nginx \n"
        
        if "${PACKAGE_INSTALL[@]}" nginx &>/dev/null; then
            log_info "Nginx installed successfully"
            
            # 停止默认的nginx服务
            if [[ "$SYSTEM" != "Alpine" ]]; then
                systemctl stop nginx 2>/dev/null || true
                systemctl disable nginx 2>/dev/null || true
            fi
        else
            log_error "Failed to install Nginx"
        fi
    else
        log_info "Nginx already installed"
    fi
}

# ============================================================================
# Argo 相关变量和函数
# ============================================================================

argo_variable() {
    log_info "Setting Argo variables..."
    
    # 询问是否安装 Nginx
    if ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && \
       [[ -z "$INSTALL_NGINX" && ! -d "$WORK_DIR" ]]; then
        reading "\n $(text 68) " INSTALL_NGINX
    fi
    
    INSTALL_NGINX=${INSTALL_NGINX:-"y"}
    
    if [[ "${INSTALL_NGINX,,}" != 'n' ]]; then
        check_nginx &
    fi
    
    # 确定服务器IP
    if grep -qi 'cloudflare' <<< "$ASNORG4$ASNORG6"; then
        if grep -qi 'cloudflare' <<< "$ASNORG6" && [[ -n "$WAN4" ]] && ! grep -qi 'cloudflare' <<< "$ASNORG4"; then
            SERVER_IP_DEFAULT=$WAN4
        elif grep -qi 'cloudflare' <<< "$ASNORG4" && [[ -n "$WAN6" ]] && ! grep -qi 'cloudflare' <<< "$ASNORG6"; then
            SERVER_IP_DEFAULT=$WAN6
        else
            local retry_count=5
            while [[ -z "$SERVER_IP" && $retry_count -gt 0 ]]; do
                reading "\n $(text 54) " SERVER_IP
                retry_count=$((retry_count - 1))
            done
            
            [[ -z "$SERVER_IP" ]] && log_error " $(text 3) "
        fi
    elif [[ -n "$WAN4" ]]; then
        SERVER_IP_DEFAULT=$WAN4
    elif [[ -n "$WAN6" ]]; then
        SERVER_IP_DEFAULT=$WAN6
    fi
    
    # 输入服务器IP
    if [[ ! -d "$WORK_DIR" ]]; then
        if ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && [[ -z "$SERVER_IP" ]]; then
            reading "\n $(text 59) " SERVER_IP
        fi
        
        SERVER_IP=${SERVER_IP:-"$SERVER_IP_DEFAULT"}
        [[ -z "$SERVER_IP" ]] && log_error " $(text 58) "
        
        # 检测ChatGPT解锁状态
        if [[ "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            CHATGPT_STACK='-4'
        else
            CHATGPT_STACK='-6'
        fi
        
        if [[ "$(check_chatgpt ${CHATGPT_STACK})" == 'unlock' ]]; then
            CHAT_GPT_OUT_V4='direct'
            CHAT_GPT_OUT_V6='direct'
        else
            CHAT_GPT_OUT_V4='warp-IPv4'
            CHAT_GPT_OUT_V6='warp-IPv6'
        fi
        
        log_info "ChatGPT status: $(check_chatgpt ${CHATGPT_STACK})"
    fi
    
    # 输入Argo域名
    if [[ "$NONINTERACTIVE_INSTALL" != 'noninteractive_install' && -z "$ARGO_DOMAIN" ]]; then
        reading "\n $(text 10) " ARGO_DOMAIN
    fi
    
    ARGO_DOMAIN=$(echo "$ARGO_DOMAIN" | sed 's/[[:space:]]//g; s/:$//')
    
    # 输入Argo认证信息
    if ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && \
       [[ -n "$ARGO_DOMAIN" && -z "$ARGO_AUTH" ]]; then
        local retry_count=5
        while [[ $retry_count -gt 0 ]]; do
            if [[ $retry_count -lt 5 ]]; then
                warning "\n $(text 45) \n"
            fi
            
            reading "\n $(text 11) " ARGO_AUTH
            
            if [[ "$ARGO_AUTH" =~ TunnelSecret || "$ARGO_AUTH" =~ [A-Z0-9a-z=]{120,250}$ ]]; then
                break
            fi
            
            retry_count=$((retry_count - 1))
        done
        
        [[ $retry_count -eq 0 ]] && log_error " $(text 3) "
    fi
    
    # 判断认证类型
    if [[ "$ARGO_AUTH" =~ TunnelSecret ]]; then
        ARGO_JSON=$(echo "$ARGO_AUTH" | tr -d ' ')
        log_info "Argo authentication type: JSON"
    elif [[ "$ARGO_AUTH" =~ [A-Z0-9a-z=]{120,250}$ ]]; then
        ARGO_TOKEN=$(awk '{print $NF}' <<< "$ARGO_AUTH")
        log_info "Argo authentication type: Token"
    fi
}

# ============================================================================
# Xray 相关变量和函数
# ============================================================================

xray_variable() {
    log_info "Setting Xray variables..."
    
    # 输入Reality端口
    local port_retry=5
    while [[ -z "$REALITY_PORT" && $port_retry -gt 0 ]]; do
        REALITY_PORT_DEFAULT=$(shuf -i 1000-65535 -n 1)
        
        if ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL"; then
            reading "\n $(text 56) " REALITY_PORT
        fi
        
        REALITY_PORT=${REALITY_PORT:-"$REALITY_PORT_DEFAULT"}
        
        # 检查端口是否被占用
        if ss -nltup | grep -q ":$REALITY_PORT"; then
            warning "\n $(text 61) \n"
            unset REALITY_PORT
        else
            break
        fi
        
        port_retry=$((port_retry - 1))
    done
    
    [[ -z "$REALITY_PORT" ]] && log_error " $(text 3) "
    
    # 选择CDN域名
    if [[ -z "$SERVER" ]]; then
        if ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL"; then
            echo ""
            for i in "${!CDN_DOMAINS[@]}"; do
                hint " $((i+1)). ${CDN_DOMAINS[i]} "
            done
            
            reading "\n $(text 42) " CUSTOM_CDN
        fi
        
        case "$CUSTOM_CDN" in
            [1-9]|[1-9][0-9])
                local index=$((CUSTOM_CDN-1))
                if [[ $index -lt ${#CDN_DOMAINS[@]} ]]; then
                    SERVER="${CDN_DOMAINS[$index]}"
                else
                    SERVER="${CDN_DOMAINS[0]}"
                fi
                ;;
            *)
                if [[ -n "$CUSTOM_CDN" ]]; then
                    SERVER="$CUSTOM_CDN"
                else
                    SERVER="${CDN_DOMAINS[0]}"
                fi
                ;;
        esac
    fi
    
    # 输入UUID
    local uuid_retry=5
    while [[ $uuid_retry -gt 0 ]]; do
        UUID_DEFAULT=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "")
        
        if ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL"; then
            reading "\n $(text 12) " UUID
        fi
        
        UUID=${UUID:-"$UUID_DEFAULT"}
        
        if validate_uuid "$UUID"; then
            break
        else
            warning "\n $(text 4) "
        fi
        
        uuid_retry=$((uuid_retry - 1))
    done
    
    [[ $uuid_retry -eq 0 ]] && log_error " $(text 3) "
    
    # 输入WS路径
    if ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && [[ -z "$WS_PATH" ]]; then
        reading "\n $(text 13) " WS_PATH
    fi
    
    local path_retry=5
    while [[ -n "$WS_PATH" && ! "$WS_PATH" =~ ^[a-z0-9]+$ && $path_retry -gt 0 ]]; do
        reading " $(text 14) " WS_PATH
        path_retry=$((path_retry - 1))
    done
    
    [[ $path_retry -eq 0 ]] && log_error " $(text 3) "
    
    WS_PATH=${WS_PATH:-"$WS_PATH_DEFAULT"}
    
    # 输入节点名称
    if [[ -z "$NODE_NAME" ]]; then
        if command -v hostname &>/dev/null; then
            NODE_NAME_DEFAULT=$(hostname)
        elif [[ -s /etc/hostname ]]; then
            NODE_NAME_DEFAULT=$(cat /etc/hostname)
        else
            NODE_NAME_DEFAULT="$DEFAULT_NODE_NAME"
        fi
        
        if ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL"; then
            reading "\n $(text 49) " NODE_NAME
        fi
        
        NODE_NAME=${NODE_NAME:-"$NODE_NAME_DEFAULT"}
    fi
    
    log_info "Xray configured: Port=$REALITY_PORT, CDN=$SERVER, UUID=$UUID, Path=$WS_PATH, Name=$NODE_NAME"
}

# ============================================================================
# 快速安装模式变量设置
# ============================================================================

fast_install_variables() {
    log_info "Setting up fast install variables..."
    
    NONINTERACTIVE_INSTALL='noninteractive_install'
    
    # 生成随机端口
    REALITY_PORT=${REALITY_PORT:-$(shuf -i 1000-65535 -n 1)}
    
    local port_check_retry=0
    while ss -nltup | grep -q ":$REALITY_PORT" && [[ $port_check_retry -lt 5 ]]; do
        REALITY_PORT=$(shuf -i 1000-65535 -n 1)
        port_check_retry=$((port_check_retry + 1))
    done
    
    [[ $port_check_retry -ge 5 ]] && log_error " $(text 3) "
    
    # 设置默认值
    SERVER=${SERVER:-"${CDN_DOMAINS[0]}"}
    UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "")}
    WS_PATH=${WS_PATH:-"$WS_PATH_DEFAULT"}
    
    # 节点名称
    if command -v hostname &>/dev/null; then
        NODE_NAME_DEFAULT=$(hostname)
    elif [[ -s /etc/hostname ]]; then
        NODE_NAME_DEFAULT=$(cat /etc/hostname)
    else
        NODE_NAME_DEFAULT="$DEFAULT_NODE_NAME"
    fi
    
    NODE_NAME=${NODE_NAME:-"$NODE_NAME_DEFAULT"}
    
    log_info "Fast install variables set: Port=$REALITY_PORT, Server=$SERVER, UUID=$UUID"
}

# ============================================================================
# 安装状态检查
# ============================================================================

check_install() {
    log_info "Checking installation status..."
    
    # 检查Nginx
    if [[ -s "$WORK_DIR/nginx.conf" ]]; then
        IS_NGINX='is_nginx'
    else
        IS_NGINX='no_nginx'
    fi
    
    # 初始化状态
    STATUS[0]="$(text 26)"  # Argo状态
    STATUS[1]="$(text 26)"  # Xray状态
    
    # 检查Argo服务
    if [[ -s "${ARGO_DAEMON_FILE}" ]]; then
        STATUS[0]="$(text 27)"
        if service_status argo &>/dev/null; then
            STATUS[0]="$(text 28)"
        fi
    fi
    
    # 检查Xray服务
    if [[ -s "${XRAY_DAEMON_FILE}" ]]; then
        if ! grep -q "$WORK_DIR" "${XRAY_DAEMON_FILE}"; then
            local existing_service=$(grep "${DAEMON_RUN_PATTERN}" "${XRAY_DAEMON_FILE}")
            log_error " $(text 53)\n $existing_service "
        fi
        
        STATUS[1]="$(text 27)"
        if service_status xray &>/dev/null; then
            STATUS[1]="$(text 28)"
        fi
    fi
    
    # 并行下载所需文件
    download_required_files
    
    log_info "Installation status: Argo=${STATUS[0]}, Xray=${STATUS[1]}, Nginx=$IS_NGINX"
}

# 并行下载所需文件
download_required_files() {
    local download_urls=()
    local download_jobs=()
    
    # Argo文件
    if [[ "${STATUS[0]}" == "$(text 26)" ]] && [[ ! -s "$WORK_DIR/cloudflared" ]]; then
        local argo_url="${GH_PROXY}https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARGO_ARCH"
        download_urls+=("$argo_url")
    fi
    
    # Xray文件
    if [[ "${STATUS[1]}" == "$(text 26)" ]] && [[ ! -s "$WORK_DIR/xray" ]]; then
        local xray_url="${GH_PROXY}https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$XRAY_ARCH.zip"
        download_urls+=("$xray_url")
    fi
    
    # jq工具
    if [[ ! -s "$WORK_DIR/jq" ]]; then
        local jq_url="${GH_PROXY}https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-$JQ_ARCH"
        download_urls+=("$jq_url")
    fi
    
    # qrencode工具
    if [[ "${INSTALL_NGINX:-y}" != 'n' ]] && [[ ! -s "$WORK_DIR/qrencode" ]]; then
        local qrencode_url="${GH_PROXY}https://github.com/fscarmen/client_template/raw/main/qrencode-go/qrencode-go-linux-$QRENCODE_ARCH"
        download_urls+=("$qrencode_url")
    fi
    
    # 并行下载
    for url in "${download_urls[@]}"; do
        local filename=$(basename "$url")
        (
            if safe_download "$url" "$TEMP_DIR/$filename"; then
                log_info "Downloaded: $filename"
            fi
        ) &
        download_jobs+=($!)
    done
    
    # 等待所有下载完成
    for job in "${download_jobs[@]}"; do
        wait "$job"
    done
    
    # 处理下载的文件
    process_downloaded_files
}

# 处理下载的文件
process_downloaded_files() {
    # 处理cloudflared
    if [[ -x "$TEMP_DIR/cloudflared" ]]; then
        chmod +x "$TEMP_DIR/cloudflared"
    fi
    
    # 处理Xray
    if [[ -f "$TEMP_DIR/Xray-linux-$XRAY_ARCH.zip" ]]; then
        unzip -qo "$TEMP_DIR/Xray-linux-$XRAY_ARCH.zip" xray *.dat -d "$TEMP_DIR" 2>/dev/null || true
        rm -f "$TEMP_DIR/Xray-linux-$XRAY_ARCH.zip"
    fi
    
    # 处理jq
    if [[ -f "$TEMP_DIR/jq-linux-$JQ_ARCH" ]]; then
        mv "$TEMP_DIR/jq-linux-$JQ_ARCH" "$TEMP_DIR/jq"
        chmod +x "$TEMP_DIR/jq"
    fi
    
    # 处理qrencode
    if [[ -f "$TEMP_DIR/qrencode-go-linux-$QRENCODE_ARCH" ]]; then
        mv "$TEMP_DIR/qrencode-go-linux-$QRENCODE_ARCH" "$TEMP_DIR/qrencode"
        chmod +x "$TEMP_DIR/qrencode"
    fi
}

# ============================================================================
# 防火墙配置
# ============================================================================

firewall_configuration() {
    local action="$1"
    local port
    
    # 从配置文件中获取端口
    if [[ -f "$WORK_DIR/inbound.json" ]]; then
        port=$(grep -o '"port":[[:space:]]*[0-9]*' "$WORK_DIR/inbound.json" | head -1 | grep -o '[0-9]*')
    fi
    
    port=${port:-$REALITY_PORT}
    
    log_info "Firewall $action port: $port"
    
    # 检查防火墙命令
    if command -v firewall-cmd &>/dev/null; then
        case "$action" in
            open)
                firewall-cmd --zone=public --add-port="${port}/tcp" --permanent &>/dev/null
                firewall-cmd --reload &>/dev/null
                ;;
            close)
                firewall-cmd --zone=public --remove-port="${port}/tcp" --permanent &>/dev/null
                firewall-cmd --reload &>/dev/null
                ;;
        esac
    fi
    
    # SELinux配置
    if [[ -s /etc/selinux/config ]] && command -v getenforce &>/dev/null && [[ $(getenforce) == 'Enforcing' ]]; then
        hint "\n $(text 69) "
        setenforce 0
        if ! grep -q '^SELINUX=disabled$' /etc/selinux/config; then
            sed -i 's/^SELINUX=[epd].*/# &/; /SELINUX=[epd]/a\SELINUX=disabled' /etc/selinux/config
        fi
    fi
}

# ============================================================================
# 配置文件生成函数
# ============================================================================

# 生成Nginx配置文件
json_nginx() {
    log_info "Generating Nginx configuration..."
    
    # 从现有配置中提取信息
    if [[ -s "$WORK_DIR"/*inbound*.json ]]; then
        local json_content=$(cat "$WORK_DIR"/*inbound*.json)
        WS_PATH=$(echo "$json_content" | grep -o '"path":"/[^"]*"' | head -1 | cut -d'/' -f2 | sed 's/-vl.*//')
        SERVER_IP=${SERVER_IP:-$(echo "$json_content" | grep -o '"SERVER_IP":"[^"]*"' | head -1 | cut -d'"' -f4)}
        UUID=$(echo "$json_content" | grep -o '"password":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    # 处理IPv6地址
    if [[ "$SERVER_IP" =~ : ]]; then
        REVERSE_IP="[$SERVER_IP]"
    else
        REVERSE_IP="$SERVER_IP"
    fi
    
    # 生成Nginx配置
    cat > "$WORK_DIR/nginx.conf" << EOF
user  root;
worker_processes  auto;

error_log  /dev/null;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
  map \$http_user_agent \$path {
    default                    /;                # 默认路径
    ~*v2rayN|Neko|Throne       /base64;          # 匹配 V2rayN / NekoBox / Throne 客户端
    ~*clash                    /clash;           # 匹配 Clash 客户端
    ~*ShadowRocket             /shadowrocket;    # 匹配 ShadowRocket  客户端
    ~*SFM                      /sing-box-pc;     # 匹配 Sing-box pc 客户端
    ~*SFI|SFA                  /sing-box-phone;  # 匹配 Sing-box phone 客户端
  }

    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /dev/null;

    sendfile        on;
    keepalive_timeout  65;

  server {
    listen 127.0.0.1:3006 proxy_protocol; # xray fallbacks

    # 来自 /auto 的分流
    location ~ ^/${UUID}/auto {
      default_type 'text/plain; charset=utf-8';
      alias ${WORK_DIR}/subscribe/\$path;
    }

    location ~ ^/${UUID}/(.*) {
      autoindex on;
      proxy_set_header X-Real-IP \$proxy_protocol_addr;
      default_type 'text/plain; charset=utf-8';
      alias ${WORK_DIR}/subscribe/\$1;
    }
  }
}
EOF
    
    log_info "Nginx configuration generated at $WORK_DIR/nginx.conf"
}

# 生成Argo配置文件
json_argo() {
    log_info "Generating Argo configuration..."
    
    if [[ ! -s "$WORK_DIR/tunnel.json" ]] && [[ -n "$ARGO_JSON" ]]; then
        echo "$ARGO_JSON" > "$WORK_DIR/tunnel.json"
    fi
    
    if [[ ! -s "$WORK_DIR/tunnel.yml" ]] && [[ -n "$ARGO_DOMAIN" ]]; then
        cat > "$WORK_DIR/tunnel.yml" << EOF
tunnel: $(echo "$ARGO_JSON" | grep -o '"TunnelID":"[^"]*"' | cut -d'"' -f4)
credentials-file: $WORK_DIR/tunnel.json

ingress:
  - hostname: ${ARGO_DOMAIN}
    service: http://localhost:8080
  - service: http_status:404
EOF
    fi
    
    log_info "Argo configuration files generated"
}

# ============================================================================
# 主安装函数
# ============================================================================

install_argox() {
    log_info "Starting ArgoX installation..."
    
    # 设置变量
    argo_variable
    xray_variable
    
    # 等待并行任务完成
    wait
    
    # 生成Reality密钥对
    if [[ -z "$REALITY_PRIVATE" ]] || [[ -z "$REALITY_PUBLIC" ]]; then
        if [[ -x "$TEMP_DIR/xray" ]]; then
            REALITY_KEYPAIR=$("$TEMP_DIR/xray" x25519 2>/dev/null)
            REALITY_PRIVATE=$(echo "$REALITY_KEYPAIR" | awk '/Private/{print $NF}')
            REALITY_PUBLIC=$(echo "$REALITY_KEYPAIR" | awk '/Public|Password/{print $NF}')
        fi
    fi
    
    # 创建必要的目录和文件
    mkdir -p /etc/systemd/system
    mkdir -p "$WORK_DIR/subscribe"
    echo "$L" > "$WORK_DIR/language"
    
    if [[ -s "$VARIABLE_FILE" ]]; then
        cp "$VARIABLE_FILE" "$WORK_DIR/"
    fi
    
    # 移动下载的文件到工作目录
    move_downloaded_files
    
    # 生成Argo运行命令
    generate_argo_command
    
    # 生成服务文件
    generate_service_files
    
    # 生成配置文件
    generate_config_files
    
    # 启动服务
    start_services
    
    # 创建快捷方式
    create_shortcut
    
    # 保存配置
    save_config
    
    log_info "ArgoX installation completed successfully"
}

# 移动下载的文件
move_downloaded_files() {
    wait
    
    [[ ! -s "$WORK_DIR/cloudflared" ]] && [[ -x "$TEMP_DIR/cloudflared" ]] && \
        mv "$TEMP_DIR/cloudflared" "$WORK_DIR/"
    
    [[ ! -s "$WORK_DIR/jq" ]] && [[ -x "$TEMP_DIR/jq" ]] && \
        mv "$TEMP_DIR/jq" "$WORK_DIR/"
    
    if [[ "${INSTALL_NGINX:-y}" != 'n' ]] && [[ ! -s "$WORK_DIR/qrencode" ]] && [[ -x "$TEMP_DIR/qrencode" ]]; then
        mv "$TEMP_DIR/qrencode" "$WORK_DIR/"
    fi
    
    if [[ ! -s "$WORK_DIR/xray" ]] && [[ -x "$TEMP_DIR/xray" ]]; then
        mv "$TEMP_DIR/xray" "$TEMP_DIR/geoip.dat" "$TEMP_DIR/geosite.dat" "$WORK_DIR/" 2>/dev/null || true
    fi
}

# 生成Argo运行命令
generate_argo_command() {
    if [[ -n "$ARGO_JSON" ]] && [[ -n "$ARGO_DOMAIN" ]]; then
        ARGO_RUNS="$WORK_DIR/cloudflared tunnel --edge-ip-version auto --config $WORK_DIR/tunnel.yml run"
        json_argo
    elif [[ -n "$ARGO_TOKEN" ]] && [[ -n "$ARGO_DOMAIN" ]]; then
        ARGO_RUNS="$WORK_DIR/cloudflared tunnel --edge-ip-version auto run --token ${ARGO_TOKEN}"
    else
        ARGO_RUNS="$WORK_DIR/cloudflared tunnel --edge-ip-version auto --no-autoupdate --metrics 0.0.0.0:${METRICS_PORT} --url http://localhost:8080"
    fi
}

# 生成服务文件
generate_service_files() {
    log_info "Generating service files..."
    
    # 生成Argo服务文件
    if [[ "$SYSTEM" == 'Alpine' ]]; then
        generate_alpine_service_files
    else
        generate_systemd_service_files
    fi
}

# 生成Alpine服务文件
generate_alpine_service_files() {
    # 分离命令和参数
    local command_part="${ARGO_RUNS%% --*}"
    local args_part="${ARGO_RUNS#$command_part }"
    
    # Argo服务文件
    cat > "${ARGO_DAEMON_FILE}" << EOF
#!/sbin/openrc-run

name="argo"
description="Cloudflare Tunnel"
command="${command_part}"
command_args="${args_part}"
pidfile="/var/run/\${RC_SVCNAME}.pid"
command_background="yes"
output_log="$WORK_DIR/argo.log"
error_log="$WORK_DIR/argo.log"

depend() {
    need net
    after net
}

start_pre() {
    # 确保日志目录存在
    mkdir -p $WORK_DIR

    # 如果需要启动 nginx
    if [ -s $WORK_DIR/nginx.conf ]; then
        $(command -v nginx) -c $WORK_DIR/nginx.conf
    fi
}

stop_post() {
    # 停止服务时检查并关闭相关的 nginx 进程
    if [ -s $WORK_DIR/nginx.conf ]; then
        # 查找使用我们配置文件的 nginx 进程并停止它
        local nginx_pids=\$(ps -ef | awk -v work_dir="$WORK_DIR" '{if (\$0 ~ "nginx.*" work_dir "/nginx.conf") print \$1}')
        [ -n "\$nginx_pids" ] && kill -15 \$nginx_pids 2>/dev/null
    fi
}
EOF
    
    chmod +x "${ARGO_DAEMON_FILE}"
    
    # Xray服务文件
    cat > "${XRAY_DAEMON_FILE}" << EOF
#!/sbin/openrc-run

name="xray"
description="Xray Service"
command="$WORK_DIR/xray"
command_args="run -c $WORK_DIR/inbound.json -c $WORK_DIR/outbound.json"
pidfile="/var/run/\${RC_SVCNAME}.pid"
command_background="yes"
output_log="$WORK_DIR/xray.log"
error_log="$WORK_DIR/xray.log"

depend() {
    need net
    after net
}
EOF
    
    chmod +x "${XRAY_DAEMON_FILE}"
}

# 生成Systemd服务文件
generate_systemd_service_files() {
    # Argo服务文件
    local argo_service="[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0"
    
    if [[ "${INSTALL_NGINX:-y}" != 'n' ]] && [[ "$IS_CENTOS" != 'CentOS7' ]]; then
        argo_service+="
ExecStartPre=$(command -v nginx) -c $WORK_DIR/nginx.conf"
    fi
    
    argo_service+="
ExecStart=$ARGO_RUNS
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target"
    
    echo "$argo_service" > "${ARGO_DAEMON_FILE}"
    
    # Xray服务文件
    cat > "${XRAY_DAEMON_FILE}" << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target

[Service]
User=root
ExecStart=$WORK_DIR/xray run -c $WORK_DIR/inbound.json -c $WORK_DIR/outbound.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF
}

# 生成配置文件
generate_config_files() {
    log_info "Generating configuration files..."
    
    # 等待Xray文件下载完成
    local wait_count=0
    while [[ $wait_count -lt 20 ]] && [[ ! -s "$WORK_DIR/xray" ]]; do
        if [[ -s "$TEMP_DIR/xray" ]]; then
            mv "$TEMP_DIR/xray" "$TEMP_DIR/geoip.dat" "$TEMP_DIR/geosite.dat" "$WORK_DIR/" 2>/dev/null || true
            break
        fi
        sleep 2
        wait_count=$((wait_count + 1))
    done
    
    if [[ $wait_count -ge 20 ]]; then
        local APP='Xray'
        log_error " $(text 48) "
    fi
    
    # 生成inbound.json
    generate_inbound_config
    
    # 生成outbound.json
    generate_outbound_config
    
    # 生成Nginx配置
    if [[ "${INSTALL_NGINX:-y}" != 'n' ]]; then
        json_nginx
    fi
}

# 生成inbound配置
generate_inbound_config() {
    cat > "$WORK_DIR/inbound.json" << EOF
{
    "log": {
        "access": "/dev/null",
        "error": "/dev/null",
        "loglevel": "none"
    },
    "inbounds": [
        {
            "tag": "${NODE_NAME} reality-vision",
            "protocol": "vless",
            "port": ${REALITY_PORT},
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": "3001",
                        "xver": 1
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": true,
                    "dest": "${TLS_SERVER}:443",
                    "xver": 0,
                    "serverNames": ["${TLS_SERVER}"],
                    "privateKey": "${REALITY_PRIVATE}",
                    "publicKey": "${REALITY_PUBLIC}",
                    "maxTimeDiff": 70000,
                    "shortIds": [""]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        },
        {
            "port": 3001,
            "listen": "127.0.0.1",
            "protocol": "vless",
            "tag": "${NODE_NAME} reality-grpc",
            "settings": {
                "clients": [{"id": "${UUID}", "flow": ""}],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "grpc",
                "grpcSettings": {
                    "serviceName": "grpc",
                    "multiMode": true
                },
                "sockopt": {
                    "acceptProxyProtocol": true
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        },
        {
            "listen": "127.0.0.1",
            "port": 8080,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}],
                "decryption": "none",
                "fallbacks": [
                    {"path": "/${WS_PATH}-vl", "dest": 3002},
                    {"path": "/${WS_PATH}-vm", "dest": 3003},
                    {"path": "/${WS_PATH}-tr", "dest": 3004},
                    {"path": "/${WS_PATH}-sh", "dest": 3005},
                    {"dest": 3006, "alpn": "", "xver": 1}
                ]
            },
            "streamSettings": {"network": "tcp"}
        },
        {
            "port": 3002,
            "listen": "127.0.0.1",
            "protocol": "vless",
            "settings": {
                "clients": [{"id": "${UUID}", "level": 0}],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {"path": "/${WS_PATH}-vl"}
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false
            }
        },
        {
            "port": 3003,
            "listen": "127.0.0.1",
            "protocol": "vmess",
            "settings": {
                "clients": [{"id": "${UUID}", "alterId": 0}]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {"path": "/${WS_PATH}-vm"}
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false
            }
        },
        {
            "port": 3004,
            "listen": "127.0.0.1",
            "protocol": "trojan",
            "settings": {
                "clients": [{"password": "${UUID}"}]
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {"path": "/${WS_PATH}-tr"}
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false
            }
        },
        {
            "port": 3005,
            "listen": "127.0.0.1",
            "protocol": "shadowsocks",
            "settings": {
                "clients": [{
                    "method": "chacha20-ietf-poly1305",
                    "password": "${UUID}"
                }],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {"path": "/${WS_PATH}-sh"}
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false
            }
        }
    ],
    "dns": {
        "servers": ["https+local://8.8.8.8/dns-query"]
    }
}
EOF
}

# 生成outbound配置
generate_outbound_config() {
    cat > "$WORK_DIR/outbound.json" << EOF
{
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "settings": {},
            "tag": "block"
        },
        {
            "protocol": "wireguard",
            "settings": {
                "secretKey": "YFYOAdbw1bKTHlNNi+aEjBM3BO7unuFC5rOkMRAz9XY=",
                "address": [
                    "172.16.0.2/32",
                    "2606:4700:110:8a36:df92:102a:9602:fa18/128"
                ],
                "peers": [
                    {
                        "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
                        "allowedIPs": ["0.0.0.0/0", "::/0"],
                        "endpoint": "engage.cloudflareclient.com:2408"
                    }
                ],
                "reserved": [78, 135, 76],
                "mtu": 1280
            },
            "tag": "wireguard"
        },
        {
            "protocol": "freedom",
            "settings": {"domainStrategy": "UseIPv4"},
            "proxySettings": {"tag": "wireguard"},
            "tag": "warp-IPv4"
        },
        {
            "protocol": "freedom",
            "settings": {"domainStrategy": "UseIPv6"},
            "proxySettings": {"tag": "wireguard"},
            "tag": "warp-IPv6"
        }
    ],
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "domain": ["api.openai.com"],
                "outboundTag": "${CHAT_GPT_OUT_V4}"
            },
            {
                "type": "field",
                "domain": ["geosite:openai"],
                "outboundTag": "${CHAT_GPT_OUT_V6}"
            }
        ]
    }
}
EOF
}

# 启动服务
start_services() {
    log_info "Starting services..."
    
    # 检查安装状态
    check_install
    
    # 启动Argo服务
    case "${STATUS[0]}" in
        "$(text 26)")
            warning "\n Argo $(text 28) $(text 38) \n"
            ;;
        "$(text 27)")
            enable_service argo
            if service_status argo &>/dev/null; then
                info "\n Argo $(text 28) $(text 37) \n"
            else
                warning "\n Argo $(text 28) $(text 38) \n"
            fi
            ;;
        "$(text 28)")
            info "\n Argo $(text 28) $(text 37) \n"
            ;;
    esac
    
    # 启动Xray服务
    case "${STATUS[1]}" in
        "$(text 26)")
            warning "\n Xray $(text 28) $(text 38) \n"
            ;;
        "$(text 27)")
            enable_service xray
            if service_status xray &>/dev/null; then
                info "\n Xray $(text 28) $(text 37) \n"
            else
                warning "\n Xray $(text 28) $(text 38) \n"
            fi
            ;;
        "$(text 28)")
            info "\n Xray $(text 28) $(text 37) \n"
            ;;
    esac
}

# ============================================================================
# 快捷方式创建
# ============================================================================

create_shortcut() {
    log_info "Creating shortcut..."
    
    cat > "$WORK_DIR/ax.sh" << EOF
#!/usr/bin/env bash

bash <(wget --no-check-certificate -qO- ${GH_PROXY}https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh) "\$@"
EOF
    
    chmod +x "$WORK_DIR/ax.sh"
    ln -sf "$WORK_DIR/ax.sh" /usr/bin/argox 2>/dev/null || true
    
    # 检查PATH
    if ! echo "$PATH" | grep -q "/usr/bin"; then
        echo 'export PATH=$PATH:/usr/bin' >> ~/.bashrc
        source ~/.bashrc
    fi
    
    if [[ -s /usr/bin/argox ]]; then
        hint "\n $(text 62) "
    fi
}

# ============================================================================
# 订阅导出功能
# ============================================================================

export_list() {
    log_info "Exporting subscription list..."
    
    check_install
    
    # 检查服务状态
    local services_not_running=()
    [[ "${STATUS[0]}" != "$(text 28)" ]] && services_not_running+=("Argo")
    [[ "${STATUS[1]}" != "$(text 28)" ]] && services_not_running+=("Xray")
    
    if [[ ${#services_not_running[@]} -gt 0 ]]; then
        reading "\n $(eval echo "\$(text 50)") " OPEN_APP
        
        if [[ "${OPEN_APP,,}" == 'y' ]]; then
            [[ "${STATUS[0]}" != "$(text 28)" ]] && enable_service argo
            [[ "${STATUS[1]}" != "$(text 28)" ]] && enable_service xray
        else
            exit 0
        fi
    fi
    
    # 获取Argo域名
    if grep -qs "^${DAEMON_RUN_PATTERN}.*:8080" "${ARGO_DAEMON_FILE}"; then
        local retry_count=5
        while [[ -z "$ARGO_DOMAIN" ]] && [[ $retry_count -gt 0 ]]; do
            ARGO_DOMAIN=$(wget -qO- "http://localhost:${METRICS_PORT}/quicktunnel" 2>/dev/null | awk -F '"' '{print $4}')
            sleep 2
            retry_count=$((retry_count - 1))
        done
    else
        ARGO_DOMAIN=${ARGO_DOMAIN:-"$(grep -m1 '^vless.*host=.*' "$WORK_DIR/list" 2>/dev/null | sed "s@.*host=\(.*\)&.*@\1@g")"}
    fi
    
    # 从配置文件提取信息
    extract_config_info
    
    # 生成订阅文件
    generate_subscription_files
    
    # 显示节点信息
    display_node_info
}

# 从配置文件提取信息
extract_config_info() {
    local json_file
    for file in "$WORK_DIR"/*inbound*.json; do
        [[ -s "$file" ]] && json_file="$file" && break
    done
    
    if [[ -n "$json_file" ]]; then
        local json_content=$(cat "$json_file")
        SERVER_IP=${SERVER_IP:-$(echo "$json_content" | grep -o '"SERVER_IP":"[^"]*"' | head -1 | cut -d'"' -f4)}
        REALITY_PORT=${REALITY_PORT:-$(echo "$json_content" | grep -o '"port":[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*')}
        REALITY_PUBLIC=${REALITY_PUBLIC:-$(echo "$json_content" | grep -o '"publicKey":"[^"]*"' | head -1 | cut -d'"' -f4)}
        REALITY_PRIVATE=${REALITY_PRIVATE:-$(echo "$json_content" | grep -o '"privateKey":"[^"]*"' | head -1 | cut -d'"' -f4)}
        TLS_SERVER=${TLS_SERVER:-$(echo "$json_content" | grep -o '"server_name":"[^"]*"' | head -1 | cut -d'"' -f4)}
        SERVER=${SERVER:-$(echo "$json_content" | grep -o '"SERVER":"[^"]*"' | head -1 | cut -d'"' -f4)}
        UUID=${UUID:-$(echo "$json_content" | grep -o '"password":"[^"]*"' | head -1 | cut -d'"' -f4)}
        WS_PATH=${WS_PATH:-$(echo "$json_content" | grep -o '"path":"/[^"]*"' | head -1 | cut -d'/' -f2 | sed 's/-vl.*//')}
        NODE_NAME=${NODE_NAME:-$(echo "$json_content" | grep -o '"tag":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/ reality-vision.*//')}
        SS_METHOD=${SS_METHOD:-$(echo "$json_content" | grep -o '"method":"[^"]*"' | head -1 | cut -d'"' -f4)}
    fi
}

# 生成订阅文件
generate_subscription_files() {
    log_info "Generating subscription files..."
    
    # 创建订阅目录
    mkdir -p "$WORK_DIR/subscribe"
    
    # 处理IP地址格式
    if [[ "$SERVER_IP" =~ : ]]; then
        SERVER_IP_1="[$SERVER_IP]"
        SERVER_IP_2="[[$SERVER_IP]]"
    else
        SERVER_IP_1="$SERVER_IP"
        SERVER_IP_2="$SERVER_IP"
    fi
    
    # 生成Clash配置
    generate_clash_config
    
    # 生成Shadowrocket配置
    generate_shadowrocket_config
    
    # 生成V2rayN/NekoBox配置
    generate_v2rayn_config
    
    # 生成Sing-box配置
    generate_singbox_config
    
    # 生成二维码
    generate_qrcode_files
}

# 生成Clash配置
generate_clash_config() {
    local clash_config="proxies:
  - {name: \"${NODE_NAME} reality-vision\", type: vless, server: ${SERVER_IP}, port: ${REALITY_PORT}, uuid: ${UUID}, network: tcp, udp: true, tls: true, servername: ${TLS_SERVER}, flow: xtls-rprx-vision, client-fingerprint: chrome, reality-opts: {public-key: ${REALITY_PUBLIC}, short-id: \"\"} }
  - {name: \"${NODE_NAME} reality-grpc\", type: vless, server: ${SERVER_IP}, port: ${REALITY_PORT}, uuid: ${UUID}, network: grpc, udp: true, tls: true, servername: ${TLS_SERVER}, flow: , client-fingerprint: chrome, reality-opts: {public-key: ${REALITY_PUBLIC}, short-id: \"\"}, grpc-opts: {grpc-service-name: \"grpc\"} }
  - {name: \"${NODE_NAME}-Vl\", type: vless, server: ${SERVER}, port: 443, uuid: ${UUID}, udp: true, tls: true, servername: ${ARGO_DOMAIN}, skip-cert-verify: false, network: ws, ws-opts: {path: \"/${WS_PATH}-vl\", headers: {Host: ${ARGO_DOMAIN}}, \"max_early_data\":2560, \"early_data_header_name\":\"Sec-WebSocket-Protocol\"} }
  - {name: \"${NODE_NAME}-Vm\", type: vmess, server: ${SERVER}, port: 443, uuid: ${UUID}, udp: true, alterId: 0, cipher: none, tls: true, servername: ${ARGO_DOMAIN}, skip-cert-verify: false, network: ws, ws-opts: {path: \"/${WS_PATH}-vm\", headers: {Host: ${ARGO_DOMAIN}}, \"max_early_data\":2560, \"early_data_header_name\":\"Sec-WebSocket-Protocol\"}}
  - {name: \"${NODE_NAME}-Tr\", type: trojan, server: ${SERVER}, port: 443, password: ${UUID}, udp: true, tls: true, servername: ${ARGO_DOMAIN}, sni: ${ARGO_DOMAIN}, skip-cert-verify: false, network: ws, ws-opts: {path: \"/${WS_PATH}-tr\", headers: {Host: ${ARGO_DOMAIN}}, \"max_early_data\":2560, \"early_data_header_name\":\"Sec-WebSocket-Protocol\" } }
  - {name: \"${NODE_NAME}-Sh\", type: ss, server: ${SERVER}, port: 443, cipher: ${SS_METHOD}, password: ${UUID}, udp: true, plugin: v2ray-plugin, plugin-opts: { mode: websocket, host: ${ARGO_DOMAIN}, path: \"/${WS_PATH}-sh\", tls: true, servername: ${ARGO_DOMAIN}, skip-cert-verify: false, mux: false } }"
    
    echo "$clash_config" > "$WORK_DIR/subscribe/proxies"
    
    # 下载Clash模板
    wget --no-check-certificate -qO- --tries=3 --timeout=2 "${SUBSCRIBE_TEMPLATE}/clash" 2>/dev/null | \
        sed "s#NODE_NAME#${NODE_NAME}#g; s#PROXY_PROVIDERS_URL#http://${ARGO_DOMAIN}/${UUID}/proxies#" > "$WORK_DIR/subscribe/clash"
}

# 生成Shadowrocket配置
generate_shadowrocket_config() {
    local shadowrocket_config="vless://$(echo -n "auto:${UUID}@${SERVER_IP_2}:${REALITY_PORT}" | base64 -w0)?remarks=${NODE_NAME// /%20}%20reality-vision&obfs=none&tls=1&peer=${TLS_SERVER}&xtls=2&pbk=${REALITY_PUBLIC}
vless://$(echo -n "auto:${UUID}@${SERVER_IP_2}:${REALITY_PORT}" | base64 -w0)?remarks=${NODE_NAME// /%20}%20reality-grpc&path=grpc&obfs=grpc&tls=1&peer=${TLS_SERVER}&pbk=${REALITY_PUBLIC}
vless://${UUID}@${SERVER}:443?encryption=none&security=tls&type=ws&host=${ARGO_DOMAIN}&path=/${WS_PATH}-vl?ed=2560&sni=${ARGO_DOMAIN}#${NODE_NAME// /%20}-Vl
vmess://$(echo -n "none:${UUID}@${SERVER}:443" | base64 -w0)?remarks=${NODE_NAME// /%20}-Vm&obfsParam=${ARGO_DOMAIN}&path=/${WS_PATH}-vm?ed=2560&obfs=websocket&tls=1&peer=${ARGO_DOMAIN}&alterId=0
trojan://${UUID}@${SERVER}:443?peer=${ARGO_DOMAIN}&plugin=obfs-local;obfs=websocket;obfs-host=${ARGO_DOMAIN};obfs-uri=/${WS_PATH}-tr?ed=2560#${NODE_NAME// /%20}-Tr
ss://$(echo -n "chacha20-ietf-poly1305:${UUID}@${SERVER}:443" | base64 -w0)?uot=2&v2ray-plugin=$(echo -n "{\"peer\":\"${ARGO_DOMAIN}\",\"mux\":false,\"path\":\"\\/${WS_PATH}-sh\",\"host\":\"${ARGO_DOMAIN}\",\"mode\":\"websocket\",\"tls\":true}" | base64 -w0)#${NODE_NAME}-Sh"
    
    echo -n "$shadowrocket_config" | base64 -w0 > "$WORK_DIR/subscribe/shadowrocket"
}

# 生成V2rayN/NekoBox配置
generate_v2rayn_config() {
    local vmess_config="{ \"v\": \"2\", \"ps\": \"${NODE_NAME}-Vm\", \"add\": \"${SERVER}\", \"port\": \"443\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/${WS_PATH}-vm?ed=2560\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\" }"
    
    local v2rayn_config="vless://${UUID}@${SERVER_IP_1}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${TLS_SERVER}&fp=chrome&pbk=${REALITY_PUBLIC}&type=tcp&headerType=none#${NODE_NAME} reality-vision
vless://${UUID}@${SERVER_IP_1}:${REALITY_PORT}?security=reality&sni=${TLS_SERVER}&fp=chrome&pbk=${REALITY_PUBLIC}&type=grpc&serviceName=grpc&encryption=none#${NODE_NAME} reality-grpc
vless://${UUID}@${SERVER}:443?encryption=none&security=tls&sni=${ARGO_DOMAIN}&type=ws&host=${ARGO_DOMAIN}&path=%2F${WS_PATH}-vl%3Fed%3D2560#${NODE_NAME}-Vl
vmess://$(echo -n "$vmess_config" | base64 -w0)
trojan://${UUID}@${SERVER}:443?security=tls&sni=${ARGO_DOMAIN}&type=ws&host=${ARGO_DOMAIN}&path=/${WS_PATH}-tr?ed%3D2560#${NODE_NAME}-Tr
ss://$(echo -n "chacha20-ietf-poly1305:${UUID}" | base64 -w0)@${SERVER}:443?plugin=v2ray-plugin;mode%3Dwebsocket;host%3D${ARGO_DOMAIN};path%3D/${WS_PATH}-sh;tls%3Dtrue;servername%3D${ARGO_DOMAIN};skip-cert-verify%3Dfalse;mux%3D0#${NODE_NAME}-Sh"
    
    echo -n "$v2rayn_config" | base64 -w0 > "$WORK_DIR/subscribe/base64"
}

# 生成Sing-box配置
generate_singbox_config() {
    local inbound_replace="{ \"type\":\"vless\", \"tag\":\"${NODE_NAME} reality-vision\", \"server\":\"${SERVER_IP}\", \"server_port\": ${REALITY_PORT}, \"uuid\":\"${UUID}\", \"flow\":\"xtls-rprx-vision\", \"packet_encoding\":\"xudp\", \"tls\":{ \"enabled\":true, \"server_name\":\"${TLS_SERVER}\", \"utls\":{ \"enabled\":true, \"fingerprint\":\"chrome\" }, \"reality\":{ \"enabled\":true, \"public_key\":\"${REALITY_PUBLIC}\", \"short_id\":\"\" } } }, { \"type\": \"vless\", \"tag\":\"${NODE_NAME} reality-grpc\", \"server\": \"${SERVER_IP}\", \"server_port\": ${REALITY_PORT}, \"uuid\": \"${UUID}\", \"packet_encoding\":\"xudp\", \"tls\": { \"enabled\": true, \"server_name\": \"${TLS_SERVER}\", \"utls\": { \"enabled\": true, \"fingerprint\": \"chrome\" }, \"reality\": { \"enabled\": true, \"public_key\": \"${REALITY_PUBLIC}\", \"short_id\": \"\" } }, \"transport\": { \"type\": \"grpc\", \"service_name\": \"grpc\" } }, { \"type\":\"vless\", \"tag\":\"${NODE_NAME}-Vl\", \"server\":\"${SERVER}\", \"server_port\":443, \"uuid\":\"${UUID}\", \"tls\": { \"enabled\":true, \"server_name\":\"${ARGO_DOMAIN}\", \"utls\": { \"enabled\":true, \"fingerprint\":\"chrome\" } }, \"transport\": { \"type\":\"ws\", \"path\":\"/${WS_PATH}-vl\", \"headers\": { \"Host\": \"${ARGO_DOMAIN}\" }, \"max_early_data\":2560, \"early_data_header_name\":\"Sec-WebSocket-Protocol\" } }, { \"type\":\"vmess\", \"tag\":\"${NODE_NAME}-Vm\", \"server\":\"${SERVER}\", \"server_port\":443, \"uuid\":\"${UUID}\", \"tls\": { \"enabled\":true, \"server_name\":\"${ARGO_DOMAIN}\", \"utls\": { \"enabled\":true, \"fingerprint\":\"chrome\" } }, \"transport\": { \"type\":\"ws\", \"path\":\"/${WS_PATH}-vm\", \"headers\": { \"Host\": \"${ARGO_DOMAIN}\" }, \"max_early_data\":2560, \"early_data_header_name\":\"Sec-WebSocket-Protocol\" } }, { \"type\":\"trojan\", \"tag\":\"${NODE_NAME}-Tr\", \"server\": \"${SERVER}\", \"server_port\": 443, \"password\": \"${UUID}\", \"tls\": { \"enabled\":true, \"server_name\":\"${ARGO_DOMAIN}\", \"utls\": { \"enabled\":true, \"fingerprint\":\"chrome\" } }, \"transport\": { \"type\":\"ws\", \"path\":\"/${WS_PATH}-tr\", \"headers\": { \"Host\": \"${ARGO_DOMAIN}\" }, \"max_early_data\":2560, \"early_data_header_name\":\"Sec-WebSocket-Protocol\" } }, { \"type\": \"shadowsocks\", \"tag\": \"${NODE_NAME}-Sh\", \"server\": \"${SERVER}\", \"server_port\": 443, \"method\": \"chacha20-ietf-poly1305\", \"password\": \"${UUID}\", \"udp_over_tcp\": {\"enabled\": true,\"version\": 2}, \"plugin\": \"v2ray-plugin\", \"plugin_opts\": \"mode=websocket;host=${ARGO_DOMAIN};path=/${WS_PATH}-sh;tls=true;servername=${ARGO_DOMAIN};skip-cert-verify=false;mux=0\"}"
    local node_replace="\"${NODE_NAME} reality-vision\", \"${NODE_NAME} reality-grpc\", \"${NODE_NAME}-Vl\", \"${NODE_NAME}-Vm\", \"${NODE_NAME}-Tr\", \"${NODE_NAME}-Sh\""
    
    # 下载Sing-box模板
    local singbox_template1=$(wget --no-check-certificate -qO- --tries=3 --timeout=2 "${SUBSCRIBE_TEMPLATE}/sing-box1" 2>/dev/null)
    
    if [[ -n "$singbox_template1" ]]; then
        echo "$singbox_template1" | sed 's#, {[^}]\+"tun-in"[^}]\+}##' | \
            sed "s#\"<INBOUND_REPLACE>\"#$inbound_replace#; s#\"<NODE_REPLACE>\"#$node_replace#g" | \
            "$WORK_DIR/jq" > "$WORK_DIR/subscribe/sing-box-pc"
        
        echo "$singbox_template1" | sed 's# {[^}]\+"mixed"[^}]\+},##; s#, "auto_detect_interface": true##' | \
            sed "s#\"<INBOUND_REPLACE>\"#$inbound_replace#; s#\"<NODE_REPLACE>\"#$node_replace#g" | \
            "$WORK_DIR/jq" > "$WORK_DIR/subscribe/sing-box-phone"
    fi
}

# 生成二维码文件
generate_qrcode_files() {
    if [[ "$IS_NGINX" == 'is_nginx' ]] && [[ -x "$WORK_DIR/qrencode" ]]; then
        cat > "$WORK_DIR/subscribe/qr" << EOF
$(text 66):
$(text 67):
https://${ARGO_DOMAIN}/${UUID}/auto

$(text 67):
$(text 64) QRcode:
https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=https://${ARGO_DOMAIN}/${UUID}/auto

$(text 67):
$("$WORK_DIR/qrencode" "https://${ARGO_DOMAIN}/${UUID}/auto")
EOF
    fi
}

# 显示节点信息
display_node_info() {
    local quick_tunnel_url=""
    
    # 检查是否为临时隧道
    if grep -q 'metrics.*url' "${ARGO_DAEMON_FILE}"; then
        quick_tunnel_url=$(eval echo "\$(text 60)")
    fi
    
    # 生成客户端配置文件内容
    generate_client_configs
    
    # 生成并显示节点信息
    echo "$EXPORT_LIST_FILE" > "$WORK_DIR/list"
    cat "$WORK_DIR/list"
}

# 生成客户端配置内容
generate_client_configs() {
    # V2rayN/NekoBox部分
    local v2rayn_part="*******************************************
┌────────────────┐  ┌────────────────┐
│                │  │                │
│     $(warning "V2rayN")     │  │    $(warning "NekoBox")     │
│                │  │                │
└────────────────┘  └────────────────┘
----------------------------
$(info "$(sed "G" <<< "${V2RAYN_SUBSCRIBE}")

$(eval echo "\$(text 75)")
ss://$(echo -n "${SS_METHOD}:${UUID}" | base64 -w0)@${SERVER}:443#${NODE_NAME}-Sh
$(eval echo "\$(text 76)")")"

    # Shadowrocket部分
    local shadowrocket_part="*******************************************
┌────────────────┐
│                │
│  $(warning "Shadowrocket")  │
│                │
└────────────────┘
----------------------------

$(hint "$(sed "G" <<< "${SHADOWROCKET_SUBSCRIBE}")")"

    # Clash部分
    local clash_part="*******************************************
┌────────────────┐
│                │
│  $(warning "Clash Verge")   │
│                │
└────────────────┘
----------------------------

$(info "$(sed '1d;G' <<< "$CLASH_SUBSCRIBE")")"

    # Sing-box部分
    local singbox_part="*******************************************
┌────────────────┐
│                │
│    $(warning "Sing-box")    │
│                │
└────────────────┘
----------------------------

$(hint "$(echo "{ \"outbounds\":[ ${INBOUND_REPLACE%,} ] }" | $WORK_DIR/jq)

 $(text 63)")"

    # 组合所有部分
    EXPORT_LIST_FILE="$v2rayn_part

$shadowrocket_part

$clash_part

$singbox_part"
    
    # 添加Nginx相关部分
    if [[ "$IS_NGINX" == 'is_nginx' ]]; then
        local nginx_part="

*******************************************

$(info "Index:
https://${ARGO_DOMAIN}/${UUID}/

QR code:
https://${ARGO_DOMAIN}/${UUID}/qr

V2rayN / Nekoray $(text 66):
https://${ARGO_DOMAIN}/${UUID}/base64")

$(info "Clash $(text 66):
https://${ARGO_DOMAIN}/${UUID}/clash

sing-box for pc $(text 66):
https://${ARGO_DOMAIN}/${UUID}/sing-box-pc

sing-box for cellphone $(text 66):
https://${ARGO_DOMAIN}/${UUID}/sing-box-phone

Shadowrocket $(text 66):
https://${ARGO_DOMAIN}/${UUID}/shadowrocket")

*******************************************

$(hint " $(text 66):
$(text 67):
https://${ARGO_DOMAIN}/${UUID}/auto

 $(text 64) QRcode:
$(text 67):
https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=https://${ARGO_DOMAIN}/${UUID}/auto")

$("$WORK_DIR/qrencode" https://${ARGO_DOMAIN}/${UUID}/auto)"
        
        EXPORT_LIST_FILE+="$nginx_part"
    fi
    
    # 添加快速隧道信息
    if [[ -n "$quick_tunnel_url" ]]; then
        EXPORT_LIST_FILE+="

$(info "\n*******************************************

 ${quick_tunnel_url} ")"
    fi
}

# ============================================================================
# Argo隧道更换功能
# ============================================================================

change_argo() {
    log_info "Changing Argo tunnel..."
    
    check_install
    
    # 检查是否已安装
    if [[ "${STATUS[0]}" == "$(text 26)" ]]; then
        error " $(text 39) "
    fi
    
    # 检测当前Argo隧道类型
    detect_current_argo_type
    
    # 显示当前隧道信息
    hint "\n $(text 40) \n"
    
    # 清空域名变量，准备输入新配置
    unset ARGO_DOMAIN
    
    # 选择隧道类型
    hint " $(text 41) \n"
    reading " $(text 24) " CHANGE_TO
    
    case "$CHANGE_TO" in
        1)
            # 切换到Try模式
            switch_to_try_mode
            ;;
        2)
            # 切换到Token/Json模式
            switch_to_token_json_mode
            ;;
        *)
            exit 0
            ;;
    esac
    
    # 更新Nginx配置（如果使用）
    if [[ "$IS_NGINX" == 'is_nginx' ]]; then
        json_nginx
    fi
    
    # 重启服务
    restart_service argo
    
    # 导出新的订阅列表
    export_list
}

# 检测当前Argo隧道类型
detect_current_argo_type() {
    local daemon_content
    if [[ -s "${ARGO_DAEMON_FILE}" ]]; then
        daemon_content=$(grep "${DAEMON_RUN_PATTERN}" "${ARGO_DAEMON_FILE}")
    fi
    
    case "$daemon_content" in
        *--config*)
            ARGO_TYPE='Json'
            ARGO_DOMAIN=$(grep -m1 '^vless.*&host=' "$WORK_DIR/list" 2>/dev/null | sed "s@.*host=\(.*\)&.*@\1@g")
            ;;
        *--token*)
            ARGO_TYPE='Token'
            ARGO_DOMAIN=$(grep -m1 '^vless.*&host=' "$WORK_DIR/list" 2>/dev/null | sed "s@.*host=\(.*\)&.*@\1@g")
            ;;
        *)
            ARGO_TYPE='Try'
            ARGO_DOMAIN=$(wget -qO- "http://localhost:${METRICS_PORT}/quicktunnel" 2>/dev/null | awk -F '"' '{print $4}')
            ;;
    esac
    
    log_info "Current Argo type: $ARGO_TYPE, Domain: $ARGO_DOMAIN"
}

# 切换到Try模式
switch_to_try_mode() {
    log_info "Switching to Try mode..."
    
    disable_service argo
    
    # 清理旧的配置文件
    if [[ -s "$WORK_DIR/tunnel.json" ]]; then
        rm -f "$WORK_DIR/tunnel.json" "$WORK_DIR/tunnel.yml"
    fi
    
    # 更新服务文件
    if [[ "$SYSTEM" == 'Alpine' ]]; then
        local args="--edge-ip-version auto --no-autoupdate --metrics 0.0.0.0:${METRICS_PORT} --url http://localhost:8080"
        sed -i "s@^command_args=.*@command_args=\"$args\"@g" "${ARGO_DAEMON_FILE}"
    else
        sed -i "s@ExecStart=.*@ExecStart=$WORK_DIR/cloudflared tunnel --edge-ip-version auto --no-autoupdate --metrics 0.0.0.0:${METRICS_PORT} --url http://localhost:8080@g" "${ARGO_DAEMON_FILE}"
    fi
}

# 切换到Token/Json模式
switch_to_token_json_mode() {
    log_info "Switching to Token/Json mode..."
    
    # 重新获取服务器IP
    SERVER_IP=$(grep -o '"SERVER_IP":"[^"]*' "$WORK_DIR"/*inbound*.json 2>/dev/null | head -1 | cut -d'"' -f4)
    
    # 获取新的Argo配置
    argo_variable
    
    disable_service argo
    
    # 清理旧的配置文件
    if [[ -s "$WORK_DIR/tunnel.json" ]]; then
        rm -f "$WORK_DIR/tunnel.json" "$WORK_DIR/tunnel.yml"
    fi
    
    # 根据认证类型更新配置
    if [[ -n "$ARGO_TOKEN" ]]; then
        if [[ "$SYSTEM" == 'Alpine' ]]; then
            local args="--edge-ip-version auto run --token ${ARGO_TOKEN}"
            sed -i "s@^command_args=.*@command_args=\"$args\"@g" "${ARGO_DAEMON_FILE}"
        else
            sed -i "s@ExecStart=.*@ExecStart=$WORK_DIR/cloudflared tunnel --edge-ip-version auto run --token ${ARGO_TOKEN}@g" "${ARGO_DAEMON_FILE}"
        fi
    elif [[ -n "$ARGO_JSON" ]]; then
        json_argo
        if [[ "$SYSTEM" == 'Alpine' ]]; then
            local args="--edge-ip-version auto --config $WORK_DIR/tunnel.yml run"
            sed -i "s@^command_args=.*@command_args=\"$args\"@g" "${ARGO_DAEMON_FILE}"
        else
            sed -i "s@ExecStart=.*@ExecStart=$WORK_DIR/cloudflared tunnel --edge-ip-version auto --config $WORK_DIR/tunnel.yml run@g" "${ARGO_DAEMON_FILE}"
        fi
    fi
}

# ============================================================================
# CDN更换功能
# ============================================================================

change_cdn() {
    log_info "Changing CDN..."
    
    if [[ ! -d "${WORK_DIR}" ]]; then
        error " $(text 70) "
    fi
    
    # 获取当前CDN
    local current_cdn=$(grep -o '"SERVER":"[^"]*' "${WORK_DIR}/inbound.json" 2>/dev/null | head -1 | cut -d'"' -f4)
    
    # 显示当前CDN
    hint "\n $(eval echo "\$(text 71)") \n"
    
    # 显示CDN选项
    for ((i=0; i<${#CDN_DOMAINS[@]}; i++)); do
        hint " $((i+1)). ${CDN_DOMAINS[i]} "
    done
    
    # 选择新CDN
    reading "\n $(text 72) " CDN_CHOOSE
    
    # 如果直接回车，保持当前CDN
    if [[ -z "$CDN_CHOOSE" ]]; then
        log_info "Keeping current CDN: $current_cdn"
        exit 0
    fi
    
    # 确定新CDN
    local new_cdn
    if [[ "$CDN_CHOOSE" =~ ^[1-9][0-9]*$ ]] && [[ "$CDN_CHOOSE" -le "${#CDN_DOMAINS[@]}" ]]; then
        new_cdn="${CDN_DOMAINS[$((CDN_CHOOSE-1))]}"
    else
        new_cdn="$CDN_CHOOSE"
    fi
    
    # 更新所有配置文件
    update_cdn_in_files "$current_cdn" "$new_cdn"
    
    # 导出订阅列表
    export_list
    
    info "\n $(eval echo "\$(text 73)") \n"
}

# 更新文件中的CDN
update_cdn_in_files() {
    local old_cdn="$1"
    local new_cdn="$2"
    
    log_info "Updating CDN from '$old_cdn' to '$new_cdn'"
    
    # 查找并更新所有相关文件
    find "${WORK_DIR}" -type f \( -name "*.json" -o -name "*.yml" -o -name "*.conf" \) -exec grep -l "$old_cdn" {} \; | \
        while read -r file; do
            sed -i "s/${old_cdn}/${new_cdn}/g" "$file"
            log_info "Updated: $file"
        done
    
    # 更新订阅文件
    if [[ -d "${WORK_DIR}/subscribe" ]]; then
        find "${WORK_DIR}/subscribe" -type f -exec sed -i "s/${old_cdn}/${new_cdn}/g" {} \;
    fi
}

# ============================================================================
# 卸载功能
# ============================================================================

uninstall() {
    log_info "Starting uninstallation..."
    
    if [[ -d "$WORK_DIR" ]]; then
        # 停止服务
        disable_service argo
        disable_service xray
        
        # 询问是否卸载Nginx
        if [[ -s "$WORK_DIR/nginx.conf" ]] && [[ $(ps -ef | grep -c "nginx.*$WORK_DIR/nginx.conf") -le 1 ]]; then
            reading "\n $(text 65) " REMOVE_NGINX
            if [[ "${REMOVE_NGINX,,}" == 'y' ]]; then
                "${PACKAGE_UNINSTALL[@]}" nginx &>/dev/null 2>&1
                log_info "Nginx uninstalled"
            fi
        fi
        
        # 根据系统类型删除服务文件
        if [[ "$SYSTEM" == 'Alpine' ]]; then
            rm -rf "$WORK_DIR" "$TEMP_DIR" /etc/init.d/{xray,argo} /usr/bin/argox 2>/dev/null || true
        else
            rm -rf "$WORK_DIR" "$TEMP_DIR" /etc/systemd/system/{xray,argo}.service /usr/bin/argox 2>/dev/null || true
            systemctl daemon-reload 2>/dev/null || true
        fi
        
        # 清理防火墙规则
        local port=$(grep -o '"port":[[:space:]]*[0-9]*' "$WORK_DIR/inbound.json" 2>/dev/null | head -1 | grep -o '[0-9]*')
        if [[ -n "$port" ]] && command -v firewall-cmd &>/dev/null; then
            firewall-cmd --zone=public --remove-port="${port}/tcp" --permanent &>/dev/null
            firewall-cmd --reload &>/dev/null
        fi
        
        info "\n $(text 16) \n"
        log_info "Uninstallation completed"
    else
        error "\n $(text 15) \n"
    fi
}

# ============================================================================
# 版本检查和升级功能
# ============================================================================

version() {
    log_info "Checking for updates..."
    
    # 检查Argo版本
    check_argo_version
    
    # 检查Xray版本
    check_xray_version
    
    # 执行升级
    perform_updates
}

# 检查Argo版本
check_argo_version() {
    local online_version=$(get_latest_github_release "cloudflare/cloudflared")
    
    if [[ -z "$online_version" ]]; then
        error " $(text 74) "
    fi
    
    local local_version=""
    if [[ -s "$WORK_DIR/cloudflared" ]]; then
        local_version=$("$WORK_DIR/cloudflared" -v 2>/dev/null | awk '{for (i=0; i<NF; i++) if ($i=="version") {print $(i+1)}}')
    fi
    
    APP='ARGO'
    info "\n $(eval echo "\$(text 43)") "
    
    if [[ -n "$online_version" ]] && [[ "$online_version" != "$local_version" ]]; then
        reading "\n $(text 9) " UPDATE_ARGO
    else
        info " $(text 44) "
    fi
}

# 检查Xray版本
check_xray_version() {
    local online_version=$(get_latest_github_release "XTLS/Xray-core")
    
    if [[ -z "$online_version" ]]; then
        error " $(text 74) "
    fi
    
    local local_version=""
    if [[ -s "$WORK_DIR/xray" ]]; then
        local_version=$("$WORK_DIR/xray" version 2>/dev/null | awk '{for (i=0; i<NF; i++) if ($i=="Xray") {print $(i+1)}}')
    fi
    
    APP='Xray'
    info "\n $(eval echo "\$(text 43)") "
    
    if [[ -n "$online_version" ]] && [[ "$online_version" != "$local_version" ]]; then
        reading "\n $(text 9) " UPDATE_XRAY
    else
        info " $(text 44) "
    fi
}

# 获取GitHub最新版本
get_latest_github_release() {
    local repo="$1"
    local api_url="${GH_PROXY}https://api.github.com/repos/$repo/releases/latest"
    
    local version=$(curl -s "$api_url" 2>/dev/null | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/')
    
    # 如果获取失败，尝试其他方法
    if [[ -z "$version" ]]; then
        version=$(curl -s "$api_url" 2>/dev/null | grep '"tag_name"' | sed 's/.*"\(.*\)".*/\1/' | sed 's/^v//')
    fi
    
    echo "$version"
}

# 执行升级
perform_updates() {
    if [[ "${UPDATE_ARGO,,}" == 'y' ]] || [[ "${UPDATE_XRAY,,}" == 'y' ]]; then
        check_system_info
    fi
    
    # 升级Argo
    if [[ "${UPDATE_ARGO,,}" == 'y' ]]; then
        upgrade_argo
    fi
    
    # 升级Xray
    if [[ "${UPDATE_XRAY,,}" == 'y' ]]; then
        upgrade_xray
    fi
}

# 升级Argo
upgrade_argo() {
    log_info "Upgrading Argo..."
    
    local download_url="${GH_PROXY}https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARGO_ARCH"
    
    if safe_download "$download_url" "$TEMP_DIR/cloudflared"; then
        disable_service argo
        chmod +x "$TEMP_DIR/cloudflared"
        mv "$TEMP_DIR/cloudflared" "$WORK_DIR/cloudflared"
        enable_service argo
        
        if service_status argo &>/dev/null; then
            info " Argo $(text 28) $(text 37)"
        else
            error " Argo $(text 28) $(text 38) "
        fi
    else
        APP='ARGO'
        error "\n $(text 48) "
    fi
}

# 升级Xray
upgrade_xray() {
    log_info "Upgrading Xray..."
    
    local download_url="${GH_PROXY}https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$XRAY_ARCH.zip"
    
    if safe_download "$download_url" "$TEMP_DIR/Xray-linux-$XRAY_ARCH.zip"; then
        disable_service xray
        
        if unzip -qo "$TEMP_DIR/Xray-linux-$XRAY_ARCH.zip" xray geoip.dat geosite.dat -d "$WORK_DIR" 2>/dev/null; then
            rm -f "$TEMP_DIR/Xray-linux-$XRAY_ARCH.zip"
            enable_service xray
            
            if service_status xray &>/dev/null; then
                info " Xray $(text 28) $(text 37)"
            else
                error " Xray $(text 28) $(text 38) "
            fi
        else
            error "Failed to extract Xray files"
        fi
    else
        APP='Xray'
        error "\n $(text 48) "
    fi
}

# ============================================================================
# 菜单系统
# ============================================================================

menu_setting() {
    log_info "Setting up menu..."
    
    # 获取服务状态信息
    get_service_status_info
    
    # 根据安装状态设置菜单选项
    if [[ "${STATUS[*]}" =~ $(text 27)|$(text 28) ]]; then
        setup_installed_menu
    else
        setup_uninstalled_menu
    fi
    
    log_info "Menu setup completed"
}

# 获取服务状态信息
get_service_status_info() {
    # 获取Argo信息
    if [[ -s "$WORK_DIR/cloudflared" ]]; then
        ARGO_VERSION=$("$WORK_DIR/cloudflared" -v 2>/dev/null | awk '{print $3}' | sed "s@^@Version: &@g")
        
        # 获取进程信息和健康状态
        if [[ "${STATUS[0]}" == "$(text 28)" ]]; then
            local argo_pid=$(get_service_pid "argo")
            if [[ -n "$argo_pid" ]]; then
                AEGO_MEMORY="$(text 52): $(get_process_memory "$argo_pid") MB"
                
                local metrics_port=$(ss -nltp 2>/dev/null | awk -v pid="$argo_pid" '$0 ~ "pid="pid"," {split($4, a, ":"); print a[length(a)]}')
                if [[ -n "$metrics_port" ]]; then
                    local health_check=$(wget -qO- "http://localhost:${metrics_port}/healthcheck" 2>/dev/null)
                    if [[ -n "$health_check" ]]; then
                        ARGO_CHECKHEALTH="$(text 46): ${health_check/OK/$(text 37)}"
                    fi
                fi
            fi
        fi
    fi
    
    # 获取Xray信息
    if [[ -s "$WORK_DIR/xray" ]]; then
        XRAY_VERSION=$("$WORK_DIR/xray" version 2>/dev/null | awk 'NR==1 {print $2}' | sed "s@^@Version: &@g")
        
        if [[ "${STATUS[1]}" == "$(text 28)" ]]; then
            local xray_pid=$(get_service_pid "xray")
            if [[ -n "$xray_pid" ]]; then
                XRAY_MEMORY="$(text 52): $(get_process_memory "$xray_pid") MB"
            fi
        fi
    fi
    
    # 获取Nginx信息
    if [[ "$IS_NGINX" == 'is_nginx' ]]; then
        NGINX_VERSION=$(nginx -v 2>&1 | sed "s#.*/#Version: #")
        
        local nginx_pid=$(get_nginx_pid)
        if [[ -n "$nginx_pid" ]]; then
            NGINX_MEMORY="$(text 52): $(get_process_memory "$nginx_pid") MB"
        fi
    fi
}

# 获取服务PID
get_service_pid() {
    local service="$1"
    case "$SYSTEM" in
        Alpine)
            rc-service "$service" status 2>/dev/null | grep -o "pid [0-9]*" | awk '{print $2}'
            ;;
        *)
            systemctl show -p MainPID "$service" 2>/dev/null | cut -d= -f2
            ;;
    esac
}

# 获取Nginx PID
get_nginx_pid() {
    ps -ef | awk -v work_dir="$WORK_DIR" '$0 ~ "nginx.*" work_dir "/nginx.conf" && !/grep/ {print $2; exit}'
}

# 获取进程内存使用
get_process_memory() {
    local pid="$1"
    if [[ -f "/proc/$pid/status" ]]; then
        awk '/VmRSS/{printf "%.1f\n", $2/1024}' "/proc/$pid/status" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# 设置已安装状态菜单
setup_installed_menu() {
    OPTION[1]="1.  $(text 29)"
    
    # Argo开关选项
    if [[ "${STATUS[0]}" == "$(text 28)" ]]; then
        OPTION[2]="2.  $(text 27) Argo (argox -a)"
    else
        OPTION[2]="2.  $(text 28) Argo (argox -a)"
    fi
    
    # Xray开关选项
    if [[ "${STATUS[1]}" == "$(text 28)" ]]; then
        OPTION[3]="3.  $(text 27) Xray (argox -x)"
    else
        OPTION[3]="3.  $(text 28) Xray (argox -x)"
    fi
    
    OPTION[4]="4.  $(text 30)"
    OPTION[5]="5.  $(text 31)"
    OPTION[6]="6.  $(text 32)"
    OPTION[7]="7.  $(text 33)"
    OPTION[8]="8.  $(text 51)"
    OPTION[9]="9.  $(text 57)"
    
    # 设置动作函数
    setup_installed_actions
}

# 设置已安装状态动作
setup_installed_actions() {
    ACTION[1]=export_list_action
    ACTION[2]=toggle_argo_action
    ACTION[3]=toggle_xray_action
    ACTION[4]=change_argo_action
    ACTION[5]=version_action
    ACTION[6]=kernel_upgrade_action
    ACTION[7]=uninstall_action
    ACTION[8]=install_singbox_action
    ACTION[9]=install_sba_action
}

# 设置未安装状态菜单
setup_uninstalled_menu() {
    OPTION[1]="1.  $(text 77)"
    OPTION[2]="2.  $(text 34)"
    OPTION[3]="3.  $(text 32)"
    OPTION[4]="4.  $(text 51)"
    OPTION[5]="5.  $(text 57)"
    
    setup_uninstalled_actions
}

# 设置未安装状态动作
setup_uninstalled_actions() {
    ACTION[1]=fast_install_action
    ACTION[2]=normal_install_action
    ACTION[3]=kernel_upgrade_action
    ACTION[4]=install_singbox_action
    ACTION[5]=install_sba_action
}

# ============================================================================
# 菜单动作函数
# ============================================================================

export_list_action() {
    export_list
    exit 0
}

toggle_argo_action() {
    if [[ "${STATUS[0]}" == "$(text 28)" ]]; then
        disable_service argo
        if ! service_status argo &>/dev/null; then
            info "\n Argo $(text 27) $(text 37)"
        else
            error " Argo $(text 27) $(text 38) "
        fi
    else
        enable_service argo
        sleep 2
        if service_status argo &>/dev/null; then
            info "\n Argo $(text 28) $(text 37)"
            
            # 如果是临时隧道模式，导出列表
            if grep -qs "^${DAEMON_RUN_PATTERN}.*8080$" "${ARGO_DAEMON_FILE}"; then
                export_list
            fi
        else
            error " Argo $(text 28) $(text 38) "
        fi
    fi
}

toggle_xray_action() {
    if [[ "${STATUS[1]}" == "$(text 28)" ]]; then
        disable_service xray
        if ! service_status xray &>/dev/null; then
            info "\n Xray $(text 27) $(text 37)"
        else
            error " Xray $(text 27) $(text 38) "
        fi
    else
        enable_service xray
        sleep 2
        if service_status xray &>/dev/null; then
            info "\n Xray $(text 28) $(text 37)"
        else
            error " Xray $(text 28) $(text 38) "
        fi
    fi
}

change_argo_action() {
    change_argo
    exit
}

version_action() {
    version
    exit
}

kernel_upgrade_action() {
    bash <(wget --no-check-certificate -qO- "${GH_PROXY}https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh")
    exit
}

uninstall_action() {
    uninstall
    exit
}

install_singbox_action() {
    bash <(wget --no-check-certificate -qO- "${GH_PROXY}https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh") "-$L"
    exit
}

install_sba_action() {
    bash <(wget --no-check-certificate -qO- "${GH_PROXY}https://raw.githubusercontent.com/fscarmen/sba/main/sba.sh") "-$L"
    exit
}

fast_install_action() {
    fast_install_variables
    install_argox
    export_list
    create_shortcut
    exit
}

normal_install_action() {
    install_argox
    export_list
    create_shortcut
    exit
}

# ============================================================================
# 主菜单函数
# ============================================================================

menu() {
    clear
    
    # 显示标题和分隔线
    print_banner
    
    # 显示系统信息
    print_system_info
    
    # 显示服务状态
    print_service_status
    
    # 显示菜单选项
    print_menu_options
    
    # 获取用户选择
    get_user_choice
}

# 打印横幅
print_banner() {
    echo -e "${BLUE}======================================================================================================================${NC}\n"
    info " $(text 17): $VERSION\n $(text 18): $(text 1)\n $(text 19):"
}

# 打印系统信息
print_system_info() {
    echo -e "\t $(text 20): $SYS"
    echo -e "\t $(text 21): $(uname -r)"
    echo -e "\t $(text 22): $ARGO_ARCH"
    echo -e "\t $(text 23): $VIRT"
    
    # 网络信息
    echo -e "\t IPv4: $WAN4 $COUNTRY4 $ASNORG4"
    echo -e "\t IPv6: $WAN6 $COUNTRY6 $ASNORG6"
}

# 打印服务状态
print_service_status() {
    echo -e "\t Argo: ${STATUS[0]}\t $ARGO_VERSION\t $AEGO_MEMORY\t $ARGO_CHECKHEALTH"
    echo -e "\t Xray: ${STATUS[1]}\t $XRAY_VERSION\t\t $XRAY_MEMORY"
    
    if [[ "$IS_NGINX" == 'is_nginx' ]]; then
        echo -e "\t Nginx: ${STATUS[0]}\t $NGINX_VERSION\t $NGINX_MEMORY"
    fi
    
    echo -e "\n${BLUE}======================================================================================================================${NC}\n"
}

# 打印菜单选项
print_menu_options() {
    for ((i=1; i<${#OPTION[*]}; i++)); do
        hint " ${OPTION[i]} "
    done
    
    # 退出选项
    if [[ "${#OPTION[@]}" -ge '10' ]]; then
        hint " 0 .  $(text 35) "
    else
        hint " 0.  $(text 35) "
    fi
}

# 获取用户选择
get_user_choice() {
    reading "\n $(text 24) " CHOOSE
    
    # 验证输入
    if [[ "$CHOOSE" =~ ^[0-9]+$ ]] && [[ "$CHOOSE" -lt "${#OPTION[*]}" ]]; then
        if [[ "$CHOOSE" -eq 0 ]]; then
            exit 0
        else
            execute_action "$CHOOSE"
        fi
    else
        warning " $(text 36) [0-$((${#OPTION[*]}-1))] "
        sleep 1
        menu
    fi
}

# 执行动作
execute_action() {
    local choice="$1"
    
    if [[ -n "${ACTION[$choice]}" ]] && type "${ACTION[$choice]}" &>/dev/null; then
        "${ACTION[$choice]}"
    else
        warning "Action for option $choice not found"
        sleep 1
        menu
    fi
}

# ============================================================================
# 参数解析和主流程
# ============================================================================

# 解析命令行参数
parse_args() {
    local args=("$@")
    
    for arg in "${args[@]}"; do
        case "${arg,,}" in
            -e|-k)
                L='E'
                ;;
            -c|-b|-l)
                L='C'
                ;;
        esac
    done
    
    # 使用getopt处理复杂参数
    while getopts ":aAxXtTdDuUnNvVbBf:F:kKlL" opt; do
        case "${opt,,}" in
            a)
                select_language
                check_system_info
                check_install
                toggle_argo_action
                ;;
            x)
                select_language
                check_system_info
                check_install
                toggle_xray_action
                ;;
            t)
                select_language
                check_system_info
                change_argo
                ;;
            d)
                select_language
                check_system_info
                change_cdn
                ;;
            u)
                select_language
                check_system_info
                uninstall
                ;;
            n)
                select_language
                check_system_info
                export_list
                ;;
            v)
                select_language
                check_arch
                version
                ;;
            b)
                select_language
                kernel_upgrade_action
                ;;
            f)
                NONINTERACTIVE_INSTALL='noninteractive_install'
                VARIABLE_FILE="$OPTARG"
                if [[ -f "$VARIABLE_FILE" ]]; then
                    source "$VARIABLE_FILE"
                fi
                ;;
            k|l)
                fast_install_variables
                ;;
            \?)
                warning "Invalid option: -$OPTARG"
                ;;
        esac
    done
    
    # 处理非选项参数
    shift $((OPTIND-1))
    
    # 如果有剩余参数，可能是快速安装模式
    if [[ $# -gt 0 ]]; then
        handle_remaining_args "$@"
    fi
}

# 处理剩余参数
handle_remaining_args() {
    for arg in "$@"; do
        case "${arg,,}" in
            install)
                normal_install_action
                ;;
            fast|quick)
                fast_install_action
                ;;
            *)
                warning "Unknown argument: $arg"
                ;;
        esac
    done
}

# 主函数
main() {
    # 初始化环境
    init_environment
    
    # 解析参数
    parse_args "$@"
    
    # 基本检查
    select_language
    check_root
    check_arch
    check_system_info
    setup_package_manager
    check_dependencies
    check_system_ip
    
    # 检查CDN连接
    check_cdn
    
    # 检查安装状态
    check_install
    
    # 设置菜单
    menu_setting
    
    # 如果是非交互式安装，直接执行
    if [[ "$NONINTERACTIVE_INSTALL" == 'noninteractive_install' ]]; then
        if type "${ACTION[2]}" &>/dev/null; then
            "${ACTION[2]}"
        else
            warning "Non-interactive installation action not available"
            menu
        fi
    else
        # 显示菜单
        menu
    fi
}

# ============================================================================
# 脚本开始执行
# ============================================================================

# 调用主函数
main "$@"

# 清理退出
cleanup
exit 0