#!/usr/bin/env bash

# 当前脚本版本号
VERSION='1.0.0 (2025.12.09)'

# 各变量默认值
GH_PROXY='https://hub.glowp.xyz/'
WORK_DIR='/etc/argowg'
TEMP_DIR='/tmp/argowg'
TLS_SERVER='addons.mozilla.org'
METRICS_PORT='3333'
CDN_DOMAIN=("skk.moe" "ip.sb" "time.is" "cfip.xxxxxxxx.tk" "bestcf.top" "cdn.2020111.xyz" "xn--b6gac.eu.org" "cf.090227.xyz")
SUBSCRIBE_TEMPLATE="https://raw.githubusercontent.com/fscarmen/client_template/main"

export DEBIAN_FRONTEND=noninteractive

trap "rm -rf $TEMP_DIR; echo -e '\n' ;exit 1" INT QUIT TERM EXIT

mkdir -p $TEMP_DIR

E[0]="Language:\n 1. English (default) \n 2. 简体中文"
C[0]="${E[0]}"
E[1]="Quick Install Mode: Added a one-click installation feature that auto-fills all parameters, simplifying the deployment process. Chinese users can use -l or -L; English users can use -k or -K. Case-insensitive support makes operations more flexible."
C[1]="极速安装模式：新增一键安装功能，所有参数自动填充，简化部署流程。中文用户使用 -l 或 -L，英文用户使用 -k 或 -K，大小写均支持，操作更灵活"
E[2]="Project to create Argo tunnels and WireGuard specifically for VPS, detailed:[https://github.com/fscarmen/argowg]\n Features:\n\t • Allows the creation of Argo tunnels via Token, Json and ad hoc methods. User can easily obtain the json at https://fscarmen.cloudflare.now.cc .\n\t • Extremely fast installation method, saving users time.\n\t • Support system: Ubuntu, Debian, CentOS, Alpine and Arch Linux 3.\n\t • Support architecture: AMD,ARM and s390x\n"
C[2]="本项目专为 VPS 添加 Argo 隧道及 WireGuard,详细说明: [https://github.com/fscarmen/argowg]\n 脚本特点:\n\t • 允许通过 Token, Json 及 临时方式来创建 Argo 隧道,用户通过以下网站轻松获取 json: https://fscarmen.cloudflare.now.cc\n\t • 极速安装方式,大大节省用户时间\n\t • 智能判断操作系统: Ubuntu 、Debian 、CentOS 、Alpine 和 Arch Linux,请务必选择 LTS 系统\n\t • 支持硬件结构类型: AMD 和 ARM\n"
E[3]="Input errors up to 5 times.The script is aborted."
C[3]="输入错误达5次,脚本退出"
E[4]="WG Private Key should be 44 characters, please re-enter \(\${a} times remaining\)"
C[4]="WG 私钥应为44位字符,请重新输入 \(剩余\${a}次\)"
E[5]="The script supports Debian, Ubuntu, CentOS, Alpine or Arch systems only. Feedback: [https://github.com/fscarmen/argowg/issues]"
C[5]="本脚本只支持 Debian、Ubuntu、CentOS、Alpine 或 Arch 系统,问题反馈:[https://github.com/fscarmen/argowg/issues]"
E[6]="Curren operating system is \$SYS.\\\n The system lower than \$SYSTEM \${MAJOR[int]} is not supported. Feedback: [https://github.com/fscarmen/argowg/issues]"
C[6]="当前操作是 \$SYS\\\n 不支持 \$SYSTEM \${MAJOR[int]} 以下系统,问题反馈:[https://github.com/fscarmen/argowg/issues]"
E[7]="Install dependence-list:"
C[7]="安装依赖列表:"
E[8]="All dependencies already exist and do not need to be installed additionally."
C[8]="所有依赖已存在，不需要额外安装"
E[9]="To upgrade, press [y]. No upgrade by default:"
C[9]="升级请按 [y]，默认不升级:"
E[10]="(3/8) Please enter Argo Domain (Default is temporary domain if left blank):"
C[10]="(3/8) 请输入 Argo 域名 (如果没有，可以跳过以使用 Argo 临时域名):"
E[11]="Please enter Argo Token or Json ( User can easily obtain the json at https://fscarmen.cloudflare.now.cc ):"
C[11]="请输入 Argo Token 或者 Json ( 用户通过以下网站轻松获取 json: https://fscarmen.cloudflare.now.cc ):"
E[12]="\(6/8\) Please enter WireGuard Private Key \(Generate new one if left blank\):"
C[12]="\(6/8\) 请输入 WireGuard 私钥 \(留空则生成新的\):"
E[13]="\(7/8\) Please enter WireGuard Address \(Default is 10.0.0.2/32\):"
C[13]="\(7/8\) 请输入 WireGuard 地址 \(默认为 10.0.0.2/32\):"
E[14]="\(8/8\) Please enter WireGuard DNS \(Default is 1.1.1.1\):"
C[14]="\(8/8\) 请输入 WireGuard DNS \(默认为 1.1.1.1\):"
E[15]="ArgoWG script has not been installed yet."
C[15]="ArgoWG 脚本还没有安装"
E[16]="ArgoWG is completely uninstalled."
C[16]="ArgoWG 已彻底卸载"
E[17]="Version"
C[17]="脚本版本"
E[18]="New features"
C[18]="功能新增"
E[19]="System infomation"
C[19]="系统信息"
E[20]="Operating System"
C[20]="当前操作系统"
E[21]="Kernel"
C[21]="内核"
E[22]="Architecture"
C[22]="处理器架构"
E[23]="Virtualization"
C[23]="虚拟化"
E[24]="Choose:"
C[24]="请选择:"
E[25]="Curren architecture \$(uname -m) is not supported. Feedback: [https://github.com/fscarmen/argowg/issues]"
C[25]="当前架构 \$(uname -m) 暂不支持,问题反馈:[https://github.com/fscarmen/argowg/issues]"
E[26]="Not install"
C[26]="未安装"
E[27]="close"
C[27]="关闭"
E[28]="open"
C[28]="开启"
E[29]="View WireGuard config (argowg -n)"
C[29]="查看 WireGuard 配置 (argowg -n)"
E[30]="Change the Argo tunnel (argowg -t)"
C[30]="更换 Argo 隧道 (argowg -t)"
E[31]="Sync Argo and WireGuard to the latest version (argowg -v)"
C[31]="同步 Argo 和 WireGuard 至最新版本 (argowg -v)"
E[32]="Upgrade kernel, turn on BBR, change Linux system (argowg -b)"
C[32]="升级内核、安装BBR、DD脚本 (argowg -b)"
E[33]="Uninstall (argowg -u)"
C[33]="卸载 (argowg -u)"
E[34]="Install ArgoWG script (argo + wireguard)"
C[34]="安装 ArgoWG 脚本 (argo + wireguard)"
E[35]="Exit"
C[35]="退出"
E[36]="Please enter the correct number"
C[36]="请输入正确数字"
E[37]="successful"
C[37]="成功"
E[38]="failed"
C[38]="失败"
E[39]="ArgoWG is not installed."
C[39]="ArgoWG 未安装"
E[40]="Argo tunnel is: \$ARGO_TYPE\\\n The domain is: \$ARGO_DOMAIN"
C[40]="Argo 隧道类型为: \$ARGO_TYPE\\\n 域名是: \$ARGO_DOMAIN"
E[41]="Argo tunnel type:\n 1. Try\n 2. Token or Json"
C[41]="Argo 隧道类型:\n 1. Try\n 2. Token 或者 Json"
E[42]="(4/8) Please enter WireGuard Listen Port (Default is 51820):"
C[42]="(4/8) 请输入 WireGuard 监听端口 (默认为 51820):"
E[43]="\$APP local verion: \$LOCAL.\\\t The newest verion: \$ONLINE"
C[43]="\$APP 本地版本: \$LOCAL.\\\t 最新版本: \$ONLINE"
E[44]="No upgrade required."
C[44]="不需要升级"
E[45]="Argo authentication message does not match the rules, neither Token nor Json, script exits. Feedback:[https://github.com/fscarmen/argowg/issues]"
C[45]="Argo 认证信息不符合规则，既不是 Token，也是不是 Json，脚本退出，问题反馈:[https://github.com/fscarmen/argowg/issues]"
E[46]="Connect"
C[46]="连接"
E[47]="The script must be run as root, you can enter sudo -i and then download and run again. Feedback:[https://github.com/fscarmen/argowg/issues]"
C[47]="必须以root方式运行脚本，可以输入 sudo -i 后重新下载运行，问题反馈:[https://github.com/fscarmen/argowg/issues]"
E[48]="Downloading the latest version \$APP failed, script exits. Feedback:[https://github.com/fscarmen/argowg/issues]"
C[48]="下载最新版本 \$APP 失败，脚本退出，问题反馈:[https://github.com/fscarmen/argowg/issues]"
E[49]="(5/8) Please enter the node name. (Default is \${NODE_NAME_DEFAULT}):"
C[49]="(5/8) 请输入节点名称 (默认为 \${NODE_NAME_DEFAULT}):"
E[50]="WireGuard service is not enabled, config cannot be output. Press [y] if you want to open."
C[50]="WireGuard 服务未开启，不能输出配置。如需打开请按 [y]: "
E[51]="WireGuard Public Key:"
C[51]="WireGuard 公钥:"
E[52]="WireGuard Private Key:"
C[52]="WireGuard 私钥:"
E[53]="WireGuard Address:"
C[53]="WireGuard 地址:"
E[54]="WireGuard DNS:"
C[54]="WireGuard DNS:"
E[55]="WireGuard Listen Port:"
C[55]="WireGuard 监听端口:"
E[56]="Argo Domain:"
C[56]="Argo 域名:"
E[57]="Endpoint (for client):"
C[57]="端点 (客户端使用):"
E[58]="Generated WireGuard config:"
C[58]="生成的 WireGuard 配置:"
E[59]="Install WireGuard first"
C[59]="请先安装 WireGuard"
E[60]="WireGuard config QR code:"
C[60]="WireGuard 配置二维码:"
E[61]="Ports are in used: \$WG_PORT"
C[61]="正在使用中的端口: \$WG_PORT"
E[62]="Create shortcut [ argowg ] successfully."
C[62]="创建快捷 [ argowg ] 指令成功!"
E[63]="(2/8) Please enter VPS IP (Default is: \${SERVER_IP_DEFAULT}):"
C[63]="(2/8) 请输入 VPS IP (默认为: \${SERVER_IP_DEFAULT}):"
E[64]="WireGuard is detected to be running. Please enter the correct server IP:"
C[64]="检测到 WireGuard 正在运行，请输入确认的服务器 IP:"
E[65]="No server ip, script exits. Feedback:[https://github.com/fscarmen/argowg/issues]"
C[65]="没有 server ip，脚本退出，问题反馈:[https://github.com/fscarmen/argowg/issues]"
E[66]="WireGuard peer config:"
C[66]="WireGuard 对等配置:"
E[67]="Allocated IPs:"
C[67]="分配的 IP:"
E[68]="Additional IPs (comma separated):"
C[68]="额外分配的 IP (逗号分隔):"
E[69]="(9/8) Please enter additional IPs for WireGuard (comma separated, leave empty if not needed):"
C[69]="(9/8) 请输入 WireGuard 额外分配的 IP (逗号分隔，不需要请留空):"
E[70]="Quick install mode (argowg -k)"
C[70]="极速安装模式 (argowg -l)"
E[71]="Generate new WireGuard key pair"
C[71]="生成新的 WireGuard 密钥对"
E[72]="Use existing WireGuard key pair"
C[72]="使用现有的 WireGuard 密钥对"

# 自定义字体彩色，read 函数
warning() { echo -e "\033[31m\033[01m$*\033[0m"; }  # 红色
error() { echo -e "\033[31m\033[01m$*\033[0m" && exit 1; } # 红色
info() { echo -e "\033[32m\033[01m$*\033[0m"; }   # 绿色
hint() { echo -e "\033[33m\033[01m$*\033[0m"; }   # 黄色
reading() { read -rp "$(info "$1")" "$2"; }
text() { grep -q '\$' <<< "${E[$*]}" && eval echo "\$(eval echo "\${${L}[$*]}")" || eval echo "\${${L}[$*]}"; }

# 检测是否需要启用 Github CDN，如能直接连通，则不使用
check_cdn() {
  [ -n "$GH_PROXY" ] && wget --server-response --quiet --output-document=/dev/null --no-check-certificate --tries=2 --timeout=3 ${GH_PROXY}https://raw.githubusercontent.com/fscarmen/ArgoWG/main/README.md >/dev/null 2>&1 || unset GH_PROXY
}

# 判断处理器架构
check_arch() {
  case $(uname -m) in
    aarch64|arm64 )
      ARGO_ARCH=arm64; WG_ARCH=arm64
      ;;
    x86_64|amd64 )
      ARGO_ARCH=amd64; WG_ARCH=amd64
      ;;
    armv7l )
      ARGO_ARCH=arm; WG_ARCH=arm
      ;;
    * )
      error " $(text 25) "
  esac
}

# 查安装及运行状态，下标0: argo，下标1: wg；状态码: 26 未安装， 27 已安装未运行， 28 运行中
check_install() {
  STATUS[0]=$(text 26)
  # 检查 argo 服务
  [ -s ${ARGO_DAEMON_FILE} ] && STATUS[0]=$(text 27) && cmd_systemctl status argo &>/dev/null && STATUS[0]=$(text 28)
  
  STATUS[1]=$(text 26)
  # 检查 wireguard 服务
  if [ -s ${WG_DAEMON_FILE} ]; then
    ! grep -q "$WORK_DIR" ${WG_DAEMON_FILE} && error " WireGuard is not installed by this script! "
    STATUS[1]=$(text 27) && cmd_systemctl status wg-quick@wg0 &>/dev/null && STATUS[1]=$(text 28)
  fi

  # 下载所需文件
  [[ ${STATUS[0]} = "$(text 26)" ]] && [ ! -s $WORK_DIR/cloudflared ] && { wget --no-check-certificate -qO $TEMP_DIR/cloudflared ${GH_PROXY}https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARGO_ARCH >/dev/null 2>&1 && chmod +x $TEMP_DIR/cloudflared >/dev/null 2>&1; }&
  [[ ${STATUS[1]} = "$(text 26)" ]] && { wget --no-check-certificate --continue -qO $TEMP_DIR/wg ${GH_PROXY}https://github.com/fscarmen/argowg/raw/main/wireguard-go-linux-$WG_ARCH >/dev/null 2>&1 && chmod +x $TEMP_DIR/wg >/dev/null 2>&1; }&
}

# 为了适配 alpine，定义 cmd_systemctl 的函数
cmd_systemctl() {
  [ -x "$(type -p systemctl)" ] && SYSTEMCTL=1 || SYSTEMCTL=0
  
  local ENABLE_DISABLE=$1
  local APP=$2
  if [ "$ENABLE_DISABLE" = 'enable' ]; then
    if [ "$SYSTEM" = 'Alpine' ]; then
      rc-service $APP start
      rc-update add $APP default
    elif [ "$IS_CENTOS" = 'CentOS7' ]; then
      systemctl daemon-reload
      systemctl enable --now $APP
    else
      systemctl daemon-reload
      systemctl enable --now $APP
    fi

  elif [ "$ENABLE_DISABLE" = 'disable' ]; then
    if [ "$SYSTEM" = 'Alpine' ]; then
      rc-service $APP stop
      rc-update del $APP default
    elif [ "$IS_CENTOS" = 'CentOS7' ]; then
      systemctl disable --now $APP
    else
      systemctl disable --now $APP
    fi
  elif [ "$ENABLE_DISABLE" = 'status' ]; then
    if [ "$SYSTEM" = 'Alpine' ]; then
      rc-service $APP status
    else
      systemctl is-active $APP
    fi
  fi
}

# 检查系统信息
check_system_info() {
  # 判断虚拟化
  if [ -x "$(type -p systemd-detect-virt)" ]; then
    VIRT=$(systemd-detect-virt)
  elif [ -x "$(type -p hostnamectl)" ]; then
    VIRT=$(hostnamectl | awk '/Virtualization/{print $NF}')
  elif [ -x "$(type -p virt-what)" ]; then
    VIRT=$(virt-what)
  fi

  [ -s /etc/os-release ] && SYS="$(awk -F '"' 'tolower($0) ~ /pretty_name/{print $2}' /etc/os-release)"
  [[ -z "$SYS" && -x "$(type -p hostnamectl)" ]] && SYS="$(hostnamectl | awk -F ': ' 'tolower($0) ~ /operating system/{print $2}')"
  [[ -z "$SYS" && -x "$(type -p lsb_release)" ]] && SYS="$(lsb_release -sd)"
  [[ -z "$SYS" && -s /etc/lsb-release ]] && SYS="$(awk -F '"' 'tolower($0) ~ /distrib_description/{print $2}' /etc/lsb-release)"
  [[ -z "$SYS" && -s /etc/redhat-release ]] && SYS="$(cat /etc/redhat-release)"
  [[ -z "$SYS" && -s /etc/issue ]] && SYS="$(sed -E '/^$|^\\/d' /etc/issue | awk -F '\\' '{print $1}' | sed 's/[ ]*$//g')"

  REGEX=("debian" "ubuntu" "centos|red hat|kernel|alma|rocky" "arch linux" "alpine" "fedora")
  RELEASE=("Debian" "Ubuntu" "CentOS" "Arch" "Alpine" "Fedora")
  EXCLUDE=("---")
  MAJOR=("9" "16" "7" "" "" "37")
  PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "pacman -Sy" "apk update -f" "dnf -y update")
  PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "pacman -S --noconfirm" "apk add --no-cache" "dnf -y install")
  PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "pacman -Rcnsu --noconfirm" "apk del -f" "dnf -y autoremove")

  for int in "${!REGEX[@]}"; do
    [[ "${SYS,,}" =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && break
  done
  [ -z "$SYSTEM" ] && error " $(text 5) "

  if [ -z "$SYSTEM" ]; then
    [ -x "$(type -p yum)" ] && int=2 && SYSTEM='CentOS' || error " $(text 5) "
  fi

  for ex in "${EXCLUDE[@]}"; do [[ ! "{$SYS,,}" =~ $ex ]]; done &&
  [[ "$(echo "$SYS" | sed "s/[^0-9.]//g" | cut -d. -f1)" -lt "${MAJOR[int]}" ]] && error " $(text 6) "

  ARGO_DAEMON_FILE='/etc/systemd/system/argo.service'
  WG_DAEMON_FILE='/etc/systemd/system/wg-quick@wg0.service'
  DAEMON_RUN_PATTERN="ExecStart="
  if [ "$SYSTEM" = 'CentOS' ]; then
    IS_CENTOS="CentOS$(echo "$SYS" | sed "s/[^0-9.]//g" | cut -d. -f1)"
  elif [ "$SYSTEM" = 'Alpine' ]; then
    ARGO_DAEMON_FILE='/etc/init.d/argo'
    DAEMON_RUN_PATTERN="command_args="
  fi
}

# 检测 IPv4 IPv6 信息
check_system_ip() {
  [ "$L" = 'C' ] && local IS_CHINESE='?lang=zh-CN'
  local DEFAULT_LOCAL_INTERFACE4=$(ip -4 route show default | awk '/default/ {for (i=0; i<NF; i++) if ($i=="dev") {print $(i+1); exit}}')
  local DEFAULT_LOCAL_INTERFACE6=$(ip -6 route show default | awk '/default/ {for (i=0; i<NF; i++) if ($i=="dev") {print $(i+1); exit}}')
  if [ -n "${DEFAULT_LOCAL_INTERFACE4}${DEFAULT_LOCAL_INTERFACE6}" ]; then
    local DEFAULT_LOCAL_IP4=$(ip -4 addr show $DEFAULT_LOCAL_INTERFACE4 | sed -n 's#.*inet \([^/]\+\)/[0-9]\+.*global.*#\1#gp')
    local DEFAULT_LOCAL_IP6=$(ip -6 addr show $DEFAULT_LOCAL_INTERFACE6 | sed -n 's#.*inet6 \([^/]\+\)/[0-9]\+.*global.*#\1#gp')
    [ -n "$DEFAULT_LOCAL_IP4" ] && local BIND_ADDRESS4="--bind-address=$DEFAULT_LOCAL_IP4"
    [ -n "$DEFAULT_LOCAL_IP6" ] && local BIND_ADDRESS6="--bind-address=$DEFAULT_LOCAL_IP6"
  fi

  WAN4=$(wget $BIND_ADDRESS4 -qO- --no-check-certificate --tries=2 --timeout=2 http://api-ipv4.ip.sb)
  [ -n "$WAN4" ] && local IP4_JSON=$(wget -qO- --no-check-certificate --tries=2 --timeout=10 https://ip.forvps.gq/${WAN4}${IS_CHINESE}) &&
  COUNTRY4=$(sed -En 's/.*"country":[ ]*"([^"]+)".*/\1/p' <<< "$IP4_JSON") &&
  ASNORG4=$(sed -En 's/.*"(isp|asn_org)":[ ]*"([^"]+)".*/\2/p' <<< "$IP4_JSON")

  WAN6=$(wget $BIND_ADDRESS6 -qO- --no-check-certificate --tries=2 --timeout=2 http://api-ipv6.ip.sb)
  [ -n "$WAN6" ] && local IP6_JSON=$(wget -qO- --no-check-certificate --tries=2 --timeout=10 https://ip.forvps.gq/${WAN6}${IS_CHINESE}) &&
  COUNTRY6=$(sed -En 's/.*"country":[ ]*"([^"]+)".*/\1/p' <<< "$IP6_JSON") &&
  ASNORG6=$(sed -En 's/.*"(isp|asn_org)":[ ]*"([^"]+)".*/\2/p' <<< "$IP6_JSON")
}

# 定义 Argo 变量
argo_variable() {
  if grep -qi 'cloudflare' <<< "$ASNORG4$ASNORG6"; then
    if grep -qi 'cloudflare' <<< "$ASNORG6" && [ -n "$WAN4" ] && ! grep -qi 'cloudflare' <<< "$ASNORG4"; then
      SERVER_IP_DEFAULT=$WAN4
    elif grep -qi 'cloudflare' <<< "$ASNORG4" && [ -n "$WAN6" ] && ! grep -qi 'cloudflare' <<< "$ASNORG6"; then
      SERVER_IP_DEFAULT=$WAN6
    else
      local a=6
      until [ -n "$SERVER_IP" ]; do
        ((a--)) || true
        [ "$a" = 0 ] && error "\n $(text 3) \n"
        reading "\n $(text 64) " SERVER_IP
      done
    fi
  elif [ -n "$WAN4" ]; then
    SERVER_IP_DEFAULT=$WAN4
  elif [ -n "$WAN6" ]; then
    SERVER_IP_DEFAULT=$WAN6
  fi

  if [ ! -d $WORK_DIR ]; then
    ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && [ -z "$SERVER_IP" ] && reading "\n $(text 63) " SERVER_IP
    SERVER_IP=${SERVER_IP:-"$SERVER_IP_DEFAULT"}
    [ -z "$SERVER_IP" ] && error " $(text 65) "
  fi

  [[ "$NONINTERACTIVE_INSTALL" != 'noninteractive_install' && -z "$ARGO_DOMAIN" ]] && reading "\n $(text 10) " ARGO_DOMAIN
  ARGO_DOMAIN=$(sed 's/[ ]*//g; s/:[ ]*//' <<< "$ARGO_DOMAIN")

  if ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && [[ -n "$ARGO_DOMAIN" && -z "$ARGO_AUTH" ]]; then
    local a=5
    until [[ "$ARGO_AUTH" =~ TunnelSecret || "$ARGO_AUTH" =~ [A-Z0-9a-z=]{120,250}$ ]]; do
      if [ "$a" = 0 ]; then
        error "\n $(text 3) \n"
      else
        [ "$a" != 5 ] && warning "\n $(text 45) \n"
        reading "\n $(text 11) " ARGO_AUTH
      fi
      ((a--)) || true
    done
  fi

  if [[ "$ARGO_AUTH" =~ TunnelSecret ]]; then
    ARGO_JSON=${ARGO_AUTH//[ ]/}
  elif [[ "$ARGO_AUTH" =~ [A-Z0-9a-z=]{120,250}$ ]]; then
    ARGO_TOKEN=$(awk '{print $NF}' <<< "$ARGO_AUTH")
  fi
}

# 定义 WireGuard 变量
wg_variable() {
  local a=6
  until [ -n "$WG_PORT" ]; do
    ((a--)) || true
    [ "$a" = 0 ] && error "\n $(text 3) \n"
    WG_PORT_DEFAULT=51820
    ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && reading "\n $(text 42) " WG_PORT
    WG_PORT=${WG_PORT:-"$WG_PORT_DEFAULT"}
    ss -nltup | grep -q ":$WG_PORT" && warning "\n $(text 61) \n" && unset WG_PORT
  done

  ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && reading "\n 1. $(text 71)\n 2. $(text 72)\n $(text 24) " KEY_CHOICE
  KEY_CHOICE=${KEY_CHOICE:-1}
  
  if [ "$KEY_CHOICE" = 1 ]; then
    WG_PRIVATE_KEY=$(wg genkey)
    WG_PUBLIC_KEY=$(echo "$WG_PRIVATE_KEY" | wg pubkey)
  else
    local a=5
    until [[ "${WG_PRIVATE_KEY}" =~ ^[A-Za-z0-9+/]{42}[A|Q|g|w]=$ ]]; do
      ((a--)) || true
      [ "$a" = 0 ] && error "\n $(text 3) \n"
      reading "\n $(text 12) " WG_PRIVATE_KEY
      if [[ "${WG_PRIVATE_KEY}" =~ ^[A-Za-z0-9+/]{42}[A|Q|g|w]=$ ]]; then
        WG_PUBLIC_KEY=$(echo "$WG_PRIVATE_KEY" | wg pubkey 2>/dev/null)
        [ -z "$WG_PUBLIC_KEY" ] && unset WG_PRIVATE_KEY && warning "\n $(text 4) "
      else
        warning "\n $(text 4) "
      fi
    done
  fi

  ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && reading "\n $(text 13) " WG_ADDRESS
  WG_ADDRESS=${WG_ADDRESS:-"10.0.0.2/32"}

  ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && reading "\n $(text 14) " WG_DNS
  WG_DNS=${WG_DNS:-"1.1.1.1"}

  ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && reading "\n $(text 69) " WG_EXTRA_IPS
  WG_EXTRA_IPS=${WG_EXTRA_IPS:-""}

  # 输入节点名
  if [ -z "$NODE_NAME" ]; then
    if [ -x "$(type -p hostname)" ]; then
      NODE_NAME_DEFAULT="$(hostname)"
    elif [ -s /etc/hostname ]; then
      NODE_NAME_DEFAULT="$(cat /etc/hostname)"
    else
      NODE_NAME_DEFAULT="ArgoWG"
    fi
    ! grep -q 'noninteractive_install' <<< "$NONINTERACTIVE_INSTALL" && reading "\n $(text 49) " NODE_NAME
    NODE_NAME="${NODE_NAME:-"$NODE_NAME_DEFAULT"}"
  fi
}

# 快速安装的所有预设值
fast_install_variables() {
  NONINTERACTIVE_INSTALL='noninteractive_install'
  
  WG_PORT=${WG_PORT:-51820}
  local PORT_USED_COUNT=0
  while ss -nltup | grep ":$WG_PORT" >/dev/null 2>&1; do
    WG_PORT=$(shuf -i 1000-65535 -n 1)
    ((PORT_USED_COUNT++))
    [ $PORT_USED_COUNT -gt 5 ] && error "\n $(text 3) \n"
  done

  # 生成新的密钥对
  WG_PRIVATE_KEY=$(wg genkey)
  WG_PUBLIC_KEY=$(echo "$WG_PRIVATE_KEY" | wg pubkey)
  WG_ADDRESS=${WG_ADDRESS:-"10.0.0.2/32"}
  WG_DNS=${WG_DNS:-"1.1.1.1"}
  WG_EXTRA_IPS=${WG_EXTRA_IPS:-""}

  # 输入节点名
  if [ -x "$(type -p hostname)" ]; then
    NODE_NAME_DEFAULT="$(hostname)"
  elif [ -s /etc/hostname ]; then
    NODE_NAME_DEFAULT="$(cat /etc/hostname)"
  else
    NODE_NAME_DEFAULT="ArgoWG"
  fi
  NODE_NAME=${NODE_NAME:-"$NODE_NAME_DEFAULT"}
}

check_dependencies() {
  # 如果是 Alpine，先升级 wget
  if [ "$SYSTEM" = 'Alpine' ]; then
    local CHECK_WGET=$(wget 2>&1 | head -n 1)
    grep -qi 'busybox' <<< "$CHECK_WGET" && ${PACKAGE_INSTALL[int]} wget >/dev/null 2>&1

    local DEPS_CHECK=("bash" "rc-update" "virt-what")
    local DEPS_INSTALL=("bash" "openrc" "virt-what")
    for g in "${!DEPS_CHECK[@]}"; do
      [ ! -x "$(type -p ${DEPS_CHECK[g]})" ] && DEPS_ALPINE+=(${DEPS_INSTALL[g]})
    done
    if [ "${#DEPS_ALPINE[@]}" -ge 1 ]; then
      info "\n $(text 7) $(sed "s/ /,&/g" <<< ${DEPS_ALPINE[@]}) \n"
      ${PACKAGE_UPDATE[int]} >/dev/null 2>&1
      ${PACKAGE_INSTALL[int]} ${DEPS_ALPINE[@]} >/dev/null 2>&1
      [[ -z "$VIRT" && "${DEPS_ALPINE[@]}" =~ 'virt-what' ]] && VIRT=$(virt-what | tr '\n' ' ')
    fi
  fi

  # 检测 Linux 系统的依赖
  local DEPS_CHECK=("wget" "ss" "bash" "wg")
  local DEPS_INSTALL=("wget" "iproute2" "bash" "wireguard-tools")

  [ "$SYSTEM" != 'Alpine' ] && DEPS_CHECK+=("systemctl") && DEPS_INSTALL+=("systemctl")

  for g in "${!DEPS_CHECK[@]}"; do
    [ ! -x "$(type -p ${DEPS_CHECK[g]})" ] && DEPS+=(${DEPS_INSTALL[g]})
  done
  if [ "${#DEPS[@]}" -ge 1 ]; then
    info "\n $(text 7) $(sed "s/ /,&/g" <<< ${DEPS[@]}) \n"
    [ "$SYSTEM" != 'CentOS' ] && ${PACKAGE_UPDATE[int]} >/dev/null 2>&1
    ${PACKAGE_INSTALL[int]} ${DEPS[@]} >/dev/null 2>&1
  else
    info "\n $(text 8) \n"
  fi
}

install_argowg() {
  argo_variable
  wg_variable

  wait
  [ ! -d /etc/systemd/system ] && mkdir -p /etc/systemd/system
  mkdir -p $WORK_DIR && echo "$L" > $WORK_DIR/language
  
  # 创建 wireguard 配置目录
  mkdir -p /etc/wireguard

  wait
  [[ ! -s $WORK_DIR/cloudflared && -x $TEMP_DIR/cloudflared ]] && mv $TEMP_DIR/cloudflared $WORK_DIR
  [[ ! -s $WORK_DIR/wg && -x $TEMP_DIR/wg ]] && mv $TEMP_DIR/wg $WORK_DIR

  if [[ -n "${ARGO_JSON}" && -n "${ARGO_DOMAIN}" ]]; then
    ARGO_RUNS="$WORK_DIR/cloudflared tunnel --edge-ip-version auto --config $WORK_DIR/tunnel.yml run"
    json_argo
  elif [[ -n "${ARGO_TOKEN}" && -n "${ARGO_DOMAIN}" ]]; then
    ARGO_RUNS="$WORK_DIR/cloudflared tunnel --edge-ip-version auto run --token ${ARGO_TOKEN}"
  else
    ARGO_RUNS="$WORK_DIR/cloudflared tunnel --edge-ip-version auto --no-autoupdate --metrics 0.0.0.0:${METRICS_PORT} --url udp://localhost:${WG_PORT}"
  fi

  # 生成 WireGuard 配置文件
  cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = ${WG_PRIVATE_KEY}
Address = ${WG_ADDRESS}
ListenPort = ${WG_PORT}
DNS = ${WG_DNS}
MTU = 1280
PostUp = sysctl -w net.ipv4.ip_forward=1; sysctl -w net.ipv6.conf.all.forwarding=1
PostDown = sysctl -w net.ipv4.ip_forward=0; sysctl -w net.ipv6.conf.all.forwarding=0

[Peer]
PublicKey = ${WG_PUBLIC_KEY}
AllowedIPs = 0.0.0.0/0, ::/0
EOF

  # 添加额外 IP
  if [ -n "$WG_EXTRA_IPS" ]; then
    IFS=',' read -ra EXTRA_IPS <<< "$WG_EXTRA_IPS"
    for ip in "${EXTRA_IPS[@]}"; do
      echo "Address = $ip" >> /etc/wireguard/wg0.conf
    done
  fi

  # Argo 生成守护进程文件
  if [ "$SYSTEM" = 'Alpine' ]; then
    cat > ${ARGO_DAEMON_FILE} << EOF
#!/sbin/openrc-run

name="argo"
description="Cloudflare Tunnel"
command="$WORK_DIR/cloudflared"
command_args="${ARGO_RUNS#*cloudflared }"
pidfile="/var/run/\${RC_SVCNAME}.pid"
command_background="yes"
output_log="$WORK_DIR/argo.log"
error_log="$WORK_DIR/argo.log"

depend() {
    need net
    after net
}
EOF
    chmod +x ${ARGO_DAEMON_FILE}
  else
    local ARGO_SERVER="[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=$ARGO_RUNS
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target"

    echo "$ARGO_SERVER" > ${ARGO_DAEMON_FILE}
  fi

  # 再次检测状态，运行 Argo 和 WireGuard
  check_install
  case "${STATUS[0]}" in
    "$(text 26)" )
      warning "\n Argo $(text 28) $(text 38) \n"
      ;;
    "$(text 27)" )
      cmd_systemctl enable argo
      cmd_systemctl status argo &>/dev/null && info "\n Argo $(text 28) $(text 37) \n" || warning "\n Argo $(text 28) $(text 38) \n"
      ;;
    "$(text 28)" )
      info "\n Argo $(text 28) $(text 37) \n"
  esac

  # 启动 WireGuard
  if [ -f /etc/wireguard/wg0.conf ]; then
    if [ "$SYSTEM" = 'Alpine' ]; then
      wg-quick up wg0
      rc-update add wg-quick@wg0 default
    else
      systemctl enable --now wg-quick@wg0
      systemctl status wg-quick@wg0 &>/dev/null && info "\n WireGuard $(text 28) $(text 37) \n" || warning "\n WireGuard $(text 28) $(text 38) \n"
    fi
  fi
}

# 创建快捷方式
create_shortcut() {
  cat > $WORK_DIR/awg.sh << EOF
#!/usr/bin/env bash

bash <(wget --no-check-certificate -qO- ${GH_PROXY}https://raw.githubusercontent.com/fscarmen/argowg/main/argowg.sh) \$1
EOF
  chmod +x $WORK_DIR/awg.sh
  ln -sf $WORK_DIR/awg.sh /usr/bin/argowg

  if [[ ! ":$PATH:" == *":/usr/bin:"* ]]; then
    echo 'export PATH=$PATH:/usr/bin' >> ~/.bashrc
    source ~/.bashrc
  fi

  [ -s /usr/bin/argowg ] && hint "\n $(text 62) "
}

export_list() {
  check_install

  # 没有开启 Argo 和 WireGuard 服务
  local APP
  [ "${STATUS[0]}" != "$(text 28)" ] && APP+=(Argo)
  [ "${STATUS[1]}" != "$(text 28)" ] && APP+=(WireGuard)
  if [ "${#APP[@]}" -gt 0 ]; then
    reading "\n $(text 50) " OPEN_APP
    if [ "${OPEN_APP,,}" = 'y' ]; then
      [ "${STATUS[0]}" != "$(text 28)" ] && cmd_systemctl enable argo
      [ "${STATUS[1]}" != "$(text 28)" ] && systemctl enable --now wg-quick@wg0
    else
      exit
    fi
  fi

  if grep -qs "^${DAEMON_RUN_PATTERN}.*udp://localhost" ${ARGO_DAEMON_FILE}; then
    local a=5
    until [[ -n "$ARGO_DOMAIN" || "$a" = 0 ]]; do
      sleep 2
      ARGO_DOMAIN=$(wget -qO- http://localhost:${METRICS_PORT}/quicktunnel | awk -F '"' '{print $4}')
      ((a--)) || true
    done
  else
    ARGO_DOMAIN=${ARGO_DOMAIN:-"$ARGO_DOMAIN"}
  fi

  [[ "$SERVER_IP" =~ : ]] && SERVER_IP_1="[$SERVER_IP]" || SERVER_IP_1="$SERVER_IP"
  
  grep -q 'metrics.*url' ${ARGO_DAEMON_FILE} && QUICK_TUNNEL_URL="Quicktunnel domain can be obtained from: http://${SERVER_IP_1}:${METRICS_PORT}/quicktunnel"

  # 生成 WireGuard 客户端配置
  local WG_CLIENT_CONFIG="[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.0.2/32
DNS = ${WG_DNS}
MTU = 1280

[Peer]
PublicKey = ${WG_PUBLIC_KEY}
Endpoint = ${ARGO_DOMAIN}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25"

  # 生成完整的配置信息
  EXPORT_LIST_FILE="*******************************************
┌────────────────┐
│                │
│   $(warning "WireGuard")   │
│                │
└────────────────┘
----------------------------

$(info "$(text 51): ${WG_PUBLIC_KEY}
$(text 52): ${WG_PRIVATE_KEY}
$(text 53): ${WG_ADDRESS}
$(text 54): ${WG_DNS}
$(text 55): ${WG_PORT}
$(text 56): ${ARGO_DOMAIN}
$(text 57): ${ARGO_DOMAIN}:${WG_PORT}")

$(text 66):
$(hint "$WG_CLIENT_CONFIG")

$(text 67):
${WG_ADDRESS}
$(echo "$WG_EXTRA_IPS" | tr ',' '\n')

$(info "\n${QUICK_TUNNEL_URL}")
"

  # 生成并显示配置信息
  echo "$EXPORT_LIST_FILE" > $WORK_DIR/list
  cat $WORK_DIR/list
}

# 更换 Argo 隧道类型
change_argo() {
  check_install
  [[ ${STATUS[0]} = "$(text 26)" ]] && error " $(text 39) "

  case $(grep "${DAEMON_RUN_PATTERN}" ${ARGO_DAEMON_FILE}) in
    *--config* )
      ARGO_TYPE='Json'; ARGO_DOMAIN="$(grep -o 'hostname: [^ ]*' $WORK_DIR/tunnel.yml | cut -d' ' -f2)" ;;
    *--token* )
      ARGO_TYPE='Token' ;;
    * )
      ARGO_TYPE='Try'
      ARGO_DOMAIN=$(wget -qO- http://localhost:${METRICS_PORT}/quicktunnel | awk -F '"' '{print $4}')
  esac

  hint "\n $(text 40) \n"
  unset ARGO_DOMAIN
  hint " $(text 41) \n" && reading " $(text 24) " CHANGE_TO
    case "$CHANGE_TO" in
      1 )
        cmd_systemctl disable argo
        [ -s $WORK_DIR/tunnel.json ] && rm -f $WORK_DIR/tunnel.{json,yml}
        if [ "$SYSTEM" = 'Alpine' ]; then
          local ARGS="--edge-ip-version auto --no-autoupdate --metrics 0.0.0.0:${METRICS_PORT} --url udp://localhost:${WG_PORT}"
          sed -i "s@^command_args=.*@command_args=\"$ARGS\"@g" ${ARGO_DAEMON_FILE}
        else
          sed -i "s@ExecStart=.*@ExecStart=$WORK_DIR/cloudflared tunnel --edge-ip-version auto --no-autoupdate --metrics 0.0.0.0:${METRICS_PORT} --url udp://localhost:${WG_PORT}@g" ${ARGO_DAEMON_FILE}
        fi
        ;;
      2 )
        argo_variable
        cmd_systemctl disable argo
        if [ -n "$ARGO_TOKEN" ]; then
          [ -s $WORK_DIR/tunnel.json ] && rm -f $WORK_DIR/tunnel.{json,yml}
          if [ "$SYSTEM" = 'Alpine' ]; then
            local ARGS="--edge-ip-version auto run --token ${ARGO_TOKEN}"
            sed -i "s@^command_args=.*@command_args=\"$ARGS\"@g" ${ARGO_DAEMON_FILE}
          else
            sed -i "s@ExecStart=.*@ExecStart=$WORK_DIR/cloudflared tunnel --edge-ip-version auto run --token ${ARGO_TOKEN}@g" ${ARGO_DAEMON_FILE}
          fi
        elif [ -n "$ARGO_JSON" ]; then
          [ -s $WORK_DIR/tunnel.json ] && rm -f $WORK_DIR/tunnel.{json,yml}
          json_argo
          if [ "$SYSTEM" = 'Alpine' ]; then
            local ARGS="--edge-ip-version auto --config $WORK_DIR/tunnel.yml run"
            sed -i "s@^command_args=.*@command_args=\"$ARGS\"@g" ${ARGO_DAEMON_FILE}
          else
            sed -i "s@ExecStart=.*@ExecStart=$WORK_DIR/cloudflared tunnel --edge-ip-version auto --config $WORK_DIR/tunnel.yml run@g" ${ARGO_DAEMON_FILE}
          fi
        fi
        ;;
      * )
        exit 0
    esac

    cmd_systemctl enable argo
    export_list
}

# 卸载 ArgoWG
uninstall() {
  if [ -d $WORK_DIR ]; then
    cmd_systemctl disable argo
    systemctl disable --now wg-quick@wg0 2>/dev/null || true
    
    # 根据系统类型删除不同的服务文件
    [ "$SYSTEM" = 'Alpine' ] && rm -rf $WORK_DIR $TEMP_DIR /etc/init.d/argo /usr/bin/argowg /etc/wireguard/wg0.conf || rm -rf $WORK_DIR $TEMP_DIR /etc/systemd/system/argo.service /usr/bin/argowg /etc/wireguard/wg0.conf

    info "\n $(text 16) \n"
  else
    error "\n $(text 15) \n"
  fi
}

# Argo 的最新版本
version() {
  local ONLINE=$(wget --no-check-certificate -qO- "${GH_PROXY}https://api.github.com/repos/cloudflare/cloudflared/releases/latest" | grep "tag_name" | cut -d \" -f4)
  [ -z "$ONLINE" ] && error " $(text 74) "
  local LOCAL=$($WORK_DIR/cloudflared -v | awk '{for (i=0; i<NF; i++) if ($i=="version") {print $(i+1)}}')
  local APP=ARGO && info "\n $(text 43) "
  [[ -n "$ONLINE" && "$ONLINE" != "$LOCAL" ]] && reading "\n $(text 9) " UPDATE || info " $(text 44) "

  if [ "${UPDATE,,}" = 'y' ]; then
    wget --no-check-certificate -O $TEMP_DIR/cloudflared ${GH_PROXY}https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARGO_ARCH
    if [ -s $TEMP_DIR/cloudflared ]; then
      cmd_systemctl disable argo
      chmod +x $TEMP_DIR/cloudflared && mv $TEMP_DIR/cloudflared $WORK_DIR/cloudflared
      cmd_systemctl enable argo
      cmd_systemctl status argo &>/dev/null && info " Argo $(text 28) $(text 37)" || error " Argo $(text 28) $(text 38) "
    else
      local APP=ARGO && error "\n $(text 48) "
    fi
  fi
}

# 判断当前 Argo-WG 的运行状态，并对应的给菜单和动作赋值
menu_setting() {
  if [[ "${STATUS[*]}" =~ $(text 27)|$(text 28) ]]; then
    if [ -s $WORK_DIR/cloudflared ]; then
      ARGO_VERSION=$($WORK_DIR/cloudflared -v | awk '{print $3}' | sed "s@^@Version: &@g")
      grep -q '^Alpine$' <<< "$SYSTEM" && local PID_COLUMN='1' || local PID_COLUMN='2'
      local PID=$(ps -ef | awk -v work_dir="${WORK_DIR}" -v col="$PID_COLUMN" '$0 ~ work_dir".*cloudflared" && !/grep/ {print $col; exit}')
      local REALTIME_METRICS_PORT=$(ss -nltp | awk -v pid=$PID '$0 ~ "pid="pid"," {split($4, a, ":"); print a[length(a)]}')
      ss -nltp | grep -q "cloudflared.*pid=${PID}," && ARGO_CHECKHEALTH="$(text 46): $(wget -qO- http://localhost:${REALTIME_METRICS_PORT}/healthcheck | sed "s/OK/$(text 37)/")"
    fi

    OPTION[1]="1.  $(text 29)"
    if [ ${STATUS[0]} = "$(text 28)" ]; then
      AEGO_MEMORY="$(text 52): $(awk '/VmRSS/{printf "%.1f\n", $2/1024}' /proc/$(awk '/\/etc\/argowg\/cloudflared/{print $1}' <<< "$PS_LIST")/status) MB"
      OPTION[2]="2.  $(text 27) Argo (argowg -a)"
    else
      OPTION[2]="2.  $(text 28) Argo (argowg -a)"
    fi
    
    [ -f /etc/wireguard/wg0.conf ] && {
      WG_STATUS=$(systemctl is-active wg-quick@wg0 2>/dev/null || echo "inactive")
      if [ "$WG_STATUS" = "active" ]; then
        WG_MEMORY="$(text 52): $(awk '/VmRSS/{printf "%.1f\n", $2/1024}' /proc/$(awk '/wg-quick/{print $1}' <<< "$PS_LIST")/status) MB"
        OPTION[3]="3.  $(text 27) WireGuard (argowg -w)"
      else
        OPTION[3]="3.  $(text 28) WireGuard (argowg -w)"
      fi
    } || OPTION[3]="3.  $(text 59)"

    OPTION[4]="4.  $(text 30)"
    OPTION[5]="5.  $(text 31)"
    OPTION[6]="6.  $(text 32)"
    OPTION[7]="7.  $(text 33)"

    ACTION[1]() { export_list; exit 0; }
    [[ ${STATUS[0]} = "$(text 28)" ]] &&
    ACTION[2]() {
      cmd_systemctl disable argo
      cmd_systemctl status argo &>/dev/null && error " Argo $(text 27) $(text 38) " || info "\n Argo $(text 27) $(text 37)"
    } ||
    ACTION[2]() {
      cmd_systemctl enable argo
      sleep 2
      cmd_systemctl status argo &>/dev/null && info "\n Argo $(text 28) $(text 37)" || error " Argo $(text 28) $(text 38) "
    }

    [[ "$WG_STATUS" = "active" ]] &&
    ACTION[3]() {
      systemctl disable --now wg-quick@wg0
      systemctl status wg-quick@wg0 &>/dev/null && error " WireGuard $(text 27) $(text 38) " || info "\n WireGuard $(text 27) $(text 37)"
    } ||
    ACTION[3]() {
      systemctl enable --now wg-quick@wg0
      sleep 2
      systemctl status wg-quick@wg0 &>/dev/null && info "\n WireGuard $(text 28) $(text 37)" || error " WireGuard $(text 28) $(text 38) "
    }
    
    ACTION[4]() { change_argo; exit; }
    ACTION[5]() { version; exit; }
    ACTION[6]() { bash <(wget --no-check-certificate -qO- ${GH_PROXY}https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh); exit; }
    ACTION[7]() { uninstall; exit; }

  else
    OPTION[1]="1.  $(text 70)"
    OPTION[2]="2.  $(text 34)"
    OPTION[3]="3.  $(text 32)"

    ACTION[1]() { fast_install_variables; install_argowg; export_list; create_shortcut; exit;}
    ACTION[2]() { install_argowg; export_list; create_shortcut; exit; }
    ACTION[3]() { bash <(wget --no-check-certificate -qO- ${GH_PROXY}https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh); exit; }
  fi

  [ "${#OPTION[@]}" -ge '8' ] && OPTION[0]="0 .  $(text 35)" || OPTION[0]="0.  $(text 35)"
  ACTION[0]() { exit; }
}

menu() {
  clear
  echo -e "======================================================================================================================\n"
  info " $(text 17):$VERSION\n $(text 18):$(text 1)\n $(text 19):\n\t $(text 20):$SYS\n\t $(text 21):$(uname -r)\n\t $(text 22):$ARGO_ARCH\n\t $(text 23):$VIRT "
  info "\t IPv4: $WAN4 $COUNTRY4  $ASNORG4 "
  info "\t IPv6: $WAN6 $COUNTRY6  $ASNORG6 "
  info "\t Argo: ${STATUS[0]}\t $ARGO_VERSION\t $AEGO_MEMORY\t $ARGO_CHECKHEALTH"
  [ -f /etc/wireguard/wg0.conf ] && info "\t WireGuard: ${WG_STATUS:-Not installed}\t $WG_MEMORY"
  echo -e "\n======================================================================================================================\n"
  for ((b=1;b<${#OPTION[*]};b++)); do hint " ${OPTION[b]} "; done
  hint " ${OPTION[0]} "
  reading "\n $(text 24) " CHOOSE

  if grep -qE "^[0-9]$" <<< "$CHOOSE" && [ "$CHOOSE" -lt "${#OPTION[*]}" ]; then
    ACTION[$CHOOSE]
  else
    warning " $(text 36) [0-$((${#OPTION[*]}-1))] " && sleep 1 && menu
  fi
}

check_cdn
check_root
check_arch
check_system_info
check_dependencies
check_system_ip
check_install
menu_setting
[ "$NONINTERACTIVE_INSTALL" = 'noninteractive_install' ] && ACTION[2] || menu