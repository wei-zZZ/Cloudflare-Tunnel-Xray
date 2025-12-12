#!/bin/bash

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
plain='\033[0m'

# 检查是否以root运行
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}请以root模式运行脚本${plain}"
    exit 1
fi

# 检查x-ui是否安装
check_xui_installed() {
    if [ ! -f /usr/local/x-ui/x-ui ]; then
        echo -e "${red}x-ui未安装，请先安装x-ui${plain}"
        exit 1
    fi
}

# 下载cloudflared
download_cloudflared() {
    if [ ! -e /usr/local/x-ui/cloudflared ]; then
        echo -e "${green}正在下载cloudflared...${plain}"
        case $(uname -m) in
            aarch64) cpu=arm64 ;;
            x86_64) cpu=amd64 ;;
            *) echo -e "${red}不支持的系统架构${plain}" && exit 1 ;;
        esac
        
        curl -L -o /usr/local/x-ui/cloudflared -# --retry 2 \
            https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu
        
        if [ $? -ne 0 ]; then
            echo -e "${red}下载cloudflared失败${plain}"
            exit 1
        fi
        
        chmod +x /usr/local/x-ui/cloudflared
        echo -e "${green}cloudflared下载完成${plain}"
    fi
}

# 获取Cloudflare配置
get_cloudflare_config() {
    echo -e "${blue}=== Cloudflare API配置 ===${plain}"
    echo ""
    
    # 检查是否已有配置
    if [ -f /usr/local/x-ui/cf_config.sh ]; then
        source /usr/local/x-ui/cf_config.sh
        echo -e "${green}已加载现有配置${plain}"
        echo -e "邮箱: ${CF_EMAIL}"
        echo -e "域名: ${CF_DOMAIN}"
        echo ""
        read -p "是否使用现有配置？(Y/n): " use_existing
        if [[ "$use_existing" =~ ^[Nn]$ ]]; then
            rm -f /usr/local/x-ui/cf_config.sh
        else
            return 0
        fi
    fi
    
    echo -e "${yellow}步骤1: 获取Cloudflare账户信息${plain}"
    echo ""
    
    read -p "请输入Cloudflare邮箱: " cf_email
    if [ -z "$cf_email" ]; then
        echo -e "${red}邮箱不能为空${plain}"
        return 1
    fi
    
    read -p "请输入Cloudflare Global API Key: " cf_api_key
    if [ -z "$cf_api_key" ]; then
        echo -e "${red}API Key不能为空${plain}"
        return 1
    fi
    
    echo ""
    echo -e "${yellow}步骤2: 获取域名信息${plain}"
    echo ""
    
    read -p "请输入你的主域名 (例如: example.com): " cf_domain
    if [ -z "$cf_domain" ]; then
        echo -e "${red}域名不能为空${plain}"
        return 1
    fi
    
    # 验证域名是否在Cloudflare
    echo -e "${green}正在验证域名...${plain}"
    
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${cf_domain}" \
        -H "X-Auth-Email: ${cf_email}" \
        -H "X-Auth-Key: ${cf_api_key}" \
        -H "Content-Type: application/json")
    
    if echo "$response" | grep -q '"success":true'; then
        zone_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        if [ -z "$zone_id" ]; then
            echo -e "${red}无法获取Zone ID，请检查域名是否正确${plain}"
            return 1
        fi
        
        echo -e "${green}验证成功！${plain}"
        echo -e "Zone ID: ${zone_id}"
        
        # 保存配置
        cat > /usr/local/x-ui/cf_config.sh << EOF
CF_EMAIL="$cf_email"
CF_API_KEY="$cf_api_key"
CF_DOMAIN="$cf_domain"
CF_ZONE_ID="$zone_id"
EOF
        
        source /usr/local/x-ui/cf_config.sh
        echo -e "${green}配置已保存${plain}"
        return 0
    else
        echo -e "${red}API验证失败，请检查邮箱和API Key${plain}"
        return 1
    fi
}

# 显示x-ui中的WS节点
show_ws_nodes() {
    echo -e "${blue}=== x-ui中的WS节点列表 ===${plain}"
    
    # 获取所有WS节点
    nodes=$(jq '.inbounds[] | select(.streamSettings.wsSettings != null) | "端口: \(.port) | 协议: \(.protocol) | 路径: \(.streamSettings.wsSettings.path)"' /usr/local/x-ui/bin/config.json 2>/dev/null)
    
    if [ -z "$nodes" ]; then
        echo -e "${yellow}未找到WS节点，请先在x-ui面板中创建WS协议节点${plain}"
        echo -e "${yellow}支持的协议：vless-ws, vmess-ws, trojan-ws, shadowsocks-ws${plain}"
        echo -e "${yellow}注意：TLS必须关闭，请求头留空不设${plain}"
        return 1
    fi
    
    echo "$nodes" | nl -w 2 -s ". "
    echo ""
    return 0
}

# 使用API创建隧道
create_tunnel_with_api() {
    echo -e "${green}正在创建Cloudflare隧道...${plain}"
    
    # 获取账户ID
    echo -e "${yellow}获取账户信息...${plain}"
    
    account_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts" \
        -H "X-Auth-Email: ${CF_EMAIL}" \
        -H "X-Auth-Key: ${CF_API_KEY}" \
        -H "Content-Type: application/json")
    
    if echo "$account_response" | grep -q '"success":true'; then
        account_id=$(echo "$account_response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo -e "${green}账户ID获取成功: ${account_id}${plain}"
    else
        echo -e "${red}获取账户ID失败${plain}"
        return 1
    fi
    
    # 创建隧道
    echo -e "${yellow}创建隧道...${plain}"
    
    tunnel_name="xui-tunnel-$(date +%s)"
    
    tunnel_response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/${account_id}/cfd_tunnel" \
        -H "X-Auth-Email: ${CF_EMAIL}" \
        -H "X-Auth-Key: ${CF_API_KEY}" \
        -H "Content-Type: application/json" \
        --data "{\"name\":\"${tunnel_name}\",\"tunnel_secret\":\"$(openssl rand -hex 32)\"}")
    
    if echo "$tunnel_response" | grep -q '"success":true'; then
        tunnel_id=$(echo "$tunnel_response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        tunnel_token=$(echo "$tunnel_response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        
        echo -e "${green}隧道创建成功！${plain}"
        echo -e "隧道ID: ${tunnel_id}"
        
        # 保存token
        echo "$tunnel_token" > /usr/local/x-ui/xuiargotoken.log
        
        return 0
    else
        echo -e "${red}隧道创建失败${plain}"
        return 1
    fi
}

# 手动配置模式（兼容模式）
manual_tunnel_setup() {
    local port=$1
    
    echo -e "${blue}=== 手动配置Argo固定隧道 ===${plain}"
    echo ""
    
    # 停止已有的cloudflared进程
    if [[ -n $(ps -e | grep cloudflared) ]]; then
        kill -15 $(cat /usr/local/x-ui/xuiargoympid.log 2>/dev/null) >/dev/null 2>&1
        sleep 2
    fi
    
    download_cloudflared
    
    echo -e "${yellow}请按照以下步骤操作：${plain}"
    echo ""
    echo "1. 访问 https://dash.cloudflare.com/"
    echo "2. 进入 Zero Trust → Networks → Tunnels"
    echo "3. 点击 'Create a tunnel'"
    echo "4. 输入隧道名称（例如: my-xui-tunnel）"
    echo "5. 选择 'cloudflared' 连接器"
    echo "6. 复制显示的Token"
    echo ""
    
    read -p "请输入复制的Token: " token
    if [ -z "$token" ]; then
        echo -e "${red}Token不能为空${plain}"
        return 1
    fi
    
    read -p "请输入固定域名（例如: xui.yourdomain.com）: " domain
    if [ -z "$domain" ]; then
        echo -e "${red}域名不能为空${plain}"
        return 1
    fi
    
    # 保存配置
    echo "$token" > /usr/local/x-ui/xuiargotoken.log
    echo "$port" > /usr/local/x-ui/xuiargoymport.log
    echo "$domain" > /usr/local/x-ui/xuiargoym.log
    
    # 启动隧道
    echo -e "${green}正在启动隧道...${plain}"
    
    nohup setsid /usr/local/x-ui/cloudflared tunnel \
        --no-autoupdate \
        --edge-ip-version auto \
        --protocol http2 \
        run --token "$token" >/dev/null 2>&1 &
    
    echo "$!" > /usr/local/x-ui/xuiargoympid.log
    
    echo -e "${yellow}等待隧道连接...${plain}"
    sleep 15
    
    # 检查进程
    pid=$(cat /usr/local/x-ui/xuiargoympid.log 2>/dev/null)
    if ! ps -p $pid > /dev/null 2>&1; then
        echo -e "${red}隧道启动失败${plain}"
        return 1
    fi
    
    echo -e "${green}✅ 隧道启动成功！${plain}"
    echo -e "域名: ${domain}"
    echo -e "端口: ${port}"
    
    # 生成订阅链接
    generate_subscription_links "$port" "$domain"
    
    # 添加开机自启
    add_auto_start "$domain"
    
    return 0
}

# 生成订阅链接
generate_subscription_links() {
    local port=$1
    local domain=$2
    
    node_info=$(jq --arg port "$port" '.inbounds[] | select(.port == ($port | tonumber))' /usr/local/x-ui/bin/config.json 2>/dev/null)
    
    if [ -n "$node_info" ]; then
        protocol=$(echo "$node_info" | jq -r '.protocol')
        ws_path=$(echo "$node_info" | jq -r '.streamSettings.wsSettings.path')
        
        echo ""
        echo -e "${green}📋 订阅链接:${plain}"
        
        case $protocol in
            "vless")
                uuid=$(echo "$node_info" | jq -r '.settings.clients[0].id')
                echo -e "${blue}VLESS-WS:${plain}"
                echo "vless://${uuid}@${domain}:8880?type=ws&security=none&path=${ws_path}&host=${domain}#Argo固定隧道"
                echo "vless://${uuid}@${domain}:8443?type=ws&security=tls&path=${ws_path}&host=${domain}#Argo固定隧道(TLS)"
                ;;
            "vmess")
                uuid=$(echo "$node_info" | jq -r '.settings.clients[0].id')
                echo -e "${blue}VMESS-WS:${plain}"
                echo -n '{"add":"'${domain}'","aid":"0","host":"'${domain}'","id":"'${uuid}'","net":"ws","path":"'${ws_path}'","port":"8880","ps":"Argo固定隧道","v":"2"}' | base64 -w 0
                echo ""
                echo -n '{"add":"'${domain}'","aid":"0","host":"'${domain}'","id":"'${uuid}'","net":"ws","path":"'${ws_path}'","port":"8443","ps":"Argo固定隧道(TLS)","tls":"tls","sni":"'${domain}'","type":"none","v":"2"}' | base64 -w 0
                echo ""
                ;;
            "trojan")
                password=$(echo "$node_info" | jq -r '.settings.clients[0].password')
                echo -e "${blue}Trojan-WS:${plain}"
                echo "trojan://${password}@${domain}:8443?security=tls&type=ws&path=${ws_path}&host=${domain}#Argo固定隧道"
                ;;
        esac
    fi
}

# 添加开机自启
add_auto_start() {
    local domain=$1
    
    cat > /root/argo_fixed_tunnel.sh << EOF
#!/bin/bash
export TUNNEL_HOSTNAME="${domain}"
nohup setsid /usr/local/x-ui/cloudflared tunnel \\
    --no-autoupdate \\
    --edge-ip-version auto \\
    --protocol http2 \\
    run --token \$(cat /usr/local/x-ui/xuiargotoken.log 2>/dev/null) >/dev/null 2>&1 &
echo \$! > /usr/local/x-ui/xuiargoympid.log
EOF
    
    chmod +x /root/argo_fixed_tunnel.sh
    
    if ! grep -q "@reboot root bash /root/argo_fixed_tunnel.sh" /etc/crontab 2>/dev/null; then
        echo "@reboot root bash /root/argo_fixed_tunnel.sh >/dev/null 2>&1" >> /etc/crontab
        echo -e "${green}✅ 已添加到开机自启${plain}"
    fi
}

# 停止隧道
stop_argo_tunnel() {
    echo -e "${yellow}正在停止Argo隧道...${plain}"
    
    if [ -f /usr/local/x-ui/xuiargoympid.log ]; then
        pid=$(cat /usr/local/x-ui/xuiargoympid.log)
        kill -15 $pid >/dev/null 2>&1
        sleep 2
        
        echo -e "${green}✅ 隧道已停止${plain}"
    else
        echo -e "${yellow}没有运行中的隧道${plain}"
    fi
}

# 查看隧道状态
check_argo_status() {
    echo -e "${blue}=== Argo隧道状态 ===${plain}"
    echo ""
    
    if [ -f /usr/local/x-ui/xuiargoympid.log ]; then
        pid=$(cat /usr/local/x-ui/xuiargoympid.log)
        if ps -p $pid > /dev/null 2>&1; then
            echo -e "${green}✅ 隧道正在运行${plain}"
            echo -e "${blue}进程ID: ${plain}${pid}"
            
            if [ -f /usr/local/x-ui/xuiargoymport.log ]; then
                port=$(cat /usr/local/x-ui/xuiargoymport.log)
                echo -e "${blue}本地端口: ${plain}${port}"
            fi
            
            if [ -f /usr/local/x-ui/xuiargoym.log ]; then
                domain=$(cat /usr/local/x-ui/xuiargoym.log)
                echo -e "${blue}域名: ${plain}${domain}"
            fi
        else
            echo -e "${red}❌ 隧道进程已停止${plain}"
        fi
    else
        echo -e "${yellow}⚠️  隧道未运行${plain}"
    fi
}

# 安装隧道
install_argo_tunnel() {
    if ! show_ws_nodes; then
        return 1
    fi
    
    read -p "请输入要使用Argo的节点端口号: " port
    
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${red}端口号必须是数字${plain}"
        return 1
    fi
    
    # 验证端口
    node_exists=$(jq --arg port "$port" '.inbounds[] | select(.port == ($port | tonumber))' /usr/local/x-ui/bin/config.json 2>/dev/null)
    if [ -z "$node_exists" ]; then
        echo -e "${red}端口 ${port} 的节点不存在${plain}"
        return 1
    fi
    
    # 验证是否是WS节点
    ws_settings=$(echo "$node_exists" | jq -r '.streamSettings.wsSettings')
    if [ "$ws_settings" = "null" ]; then
        echo -e "${red}端口 ${port} 的节点不是WS协议${plain}"
        return 1
    fi
    
    echo ""
    echo -e "${blue}请选择安装方式:${plain}"
    echo "1. 自动化安装（需要Cloudflare API）"
    echo "2. 手动安装（需要手动复制Token）"
    read -p "请选择 [1-2]: " install_type
    
    case $install_type in
        1)
            if [ ! -f /usr/local/x-ui/cf_config.sh ]; then
                echo -e "${red}请先配置Cloudflare API信息${plain}"
                return 1
            fi
            source /usr/local/x-ui/cf_config.sh
            
            if create_tunnel_with_api; then
                # 配置DNS
                echo ""
                read -p "请输入子域名（例如输入 'xui' 将创建 xui.${CF_DOMAIN}）: " subdomain
                if [ -z "$subdomain" ]; then
                    subdomain="xui$(date +%m%d)"
                fi
                
                domain="${subdomain}.${CF_DOMAIN}"
                echo "$port" > /usr/local/x-ui/xuiargoymport.log
                echo "$domain" > /usr/local/x-ui/xuiargoym.log
                
                # 启动隧道
                echo -e "${green}启动隧道...${plain}"
                nohup setsid /usr/local/x-ui/cloudflared tunnel \
                    --no-autoupdate \
                    --edge-ip-version auto \
                    --protocol http2 \
                    run --token "$(cat /usr/local/x-ui/xuiargotoken.log)" >/dev/null 2>&1 &
                echo "$!" > /usr/local/x-ui/xuiargoympid.log
                
                sleep 15
                echo -e "${green}✅ 安装完成！${plain}"
                generate_subscription_links "$port" "$domain"
                add_auto_start "$domain"
            fi
            ;;
        2)
            manual_tunnel_setup "$port"
            ;;
        *)
            echo -e "${red}无效选择${plain}"
            return 1
            ;;
    esac
}

# 清理配置
cleanup_config() {
    echo -e "${yellow}正在清理所有配置...${plain}"
    
    stop_argo_tunnel
    sleep 2
    
    rm -f /usr/local/x-ui/cf_config.sh 2>/dev/null
    rm -f /usr/local/x-ui/xuiargoympid.log 2>/dev/null
    rm -f /usr/local/x-ui/xuiargoymport.log 2>/dev/null
    rm -f /usr/local/x-ui/xuiargoym.log 2>/dev/null
    rm -f /usr/local/x-ui/xuiargotoken.log 2>/dev/null
    rm -f /root/argo_fixed_tunnel.sh 2>/dev/null
    
    sed -i '/argo_fixed_tunnel.sh/d' /etc/crontab 2>/dev/null
    
    echo -e "${green}✅ 所有配置已清理${plain}"
}

# 主菜单
show_menu() {
    echo ""
    echo -e "${blue}========== Argo固定隧道安装器 ==========${plain}"
    echo -e "${green}为x-ui节点创建Cloudflare固定隧道${plain}"
    echo ""
    
    check_xui_installed
    
    echo -e "${green}1. 查看x-ui中的WS节点${plain}"
    echo -e "${green}2. 配置Cloudflare API信息${plain}"
    echo -e "${green}3. 安装Argo固定隧道${plain}"
    echo -e "${green}4. 停止隧道${plain}"
    echo -e "${green}5. 查看隧道状态${plain}"
    echo -e "${green}6. 生成订阅链接${plain}"
    echo -e "${green}7. 清理所有配置${plain}"
    echo -e "${green}0. 退出${plain}"
    echo ""
    
    read -p "请选择 [0-7]: " choice
    
    case $choice in
        1)
            show_ws_nodes
            read -p "按回车键返回主菜单..." key
            show_menu
            ;;
        2)
            get_cloudflare_config
            read -p "按回车键返回主菜单..." key
            show_menu
            ;;
        3)
            install_argo_tunnel
            read -p "按回车键返回主菜单..." key
            show_menu
            ;;
        4)
            stop_argo_tunnel
            read -p "按回车键返回主菜单..." key
            show_menu
            ;;
        5)
            check_argo_status
            read -p "按回车键返回主菜单..." key
            show_menu
            ;;
        6)
            if [ -f /usr/local/x-ui/xuiargoymport.log ] && [ -f /usr/local/x-ui/xuiargoym.log ]; then
                port=$(cat /usr/local/x-ui/xuiargoymport.log)
                domain=$(cat /usr/local/x-ui/xuiargoym.log)
                generate_subscription_links "$port" "$domain"
            else
                echo -e "${red}请先安装Argo固定隧道${plain}"
            fi
            read -p "按回车键返回主菜单..." key
            show_menu
            ;;
        7)
            cleanup_config
            read -p "按回车键返回主菜单..." key
            show_menu
            ;;
        0)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo -e "${red}无效选择${plain}"
            sleep 1
            show_menu
            ;;
    esac
}

# 脚本入口
echo -e "${blue}Argo固定隧道安装脚本 v1.0${plain}"
echo ""

# 检查依赖
if ! command -v jq &> /dev/null; then
    echo -e "${yellow}正在安装jq...${plain}"
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y jq
    elif command -v yum &> /dev/null; then
        yum install -y epel-release && yum install -y jq
    elif command -v dnf &> /dev/null; then
        dnf install -y jq
    else
        echo -e "${red}无法安装jq，请手动安装${plain}"
        exit 1
    fi
fi

show_menu