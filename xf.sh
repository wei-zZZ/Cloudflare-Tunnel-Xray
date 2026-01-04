#!/bin/bash
# Debian 系统时间同步与APT镜像源一键综合修复脚本
set -e

echo "🛠️  Debian 系统综合修复脚本启动..."
echo "================================================"
echo "本脚本将修复："
echo "  1. 系统时间不同步问题"
echo "  2. APT软件源镜像同步/验证问题"
echo "================================================"

# ========== 第一部分：修复时间同步 ==========
echo ""
echo "🕐 [阶段 1/3] 检查并修复系统时间同步..."
echo "----------------------------------------"

# 1.1 检查当前时间状态
echo "[1.1] 检查系统时间状态..."
if command -v timedatectl &> /dev/null; then
    TIMEDATE_OUTPUT=$(timedatectl)
    echo "$TIMEDATE_OUTPUT"
    
    # 检查时间同步状态
    if echo "$TIMEDATE_OUTPUT" | grep -q "System clock synchronized: yes"; then
        TIME_SYNCED=true
        echo "✅ 系统时钟已同步"
    else
        TIME_SYNCED=false
        echo "⚠️  系统时钟未同步"
    fi
    
    # 检查NTP服务状态
    NTP_STATUS=$(echo "$TIMEDATE_OUTPUT" | grep "NTP service:" | awk '{print $3}')
    echo "NTP服务状态: $NTP_STATUS"
else
    echo "⚠️  timedatectl 命令不可用"
    TIME_SYNCED=false
fi

# 1.2 解决时间同步冲突问题
if [ "$TIME_SYNCED" = false ] || [ "$NTP_STATUS" = "n/a" ]; then
    echo "[1.2] 配置时间同步服务..."
    
    # 停止可能冲突的服务
    echo "停止可能冲突的时间服务..."
    sudo systemctl stop systemd-timesyncd 2>/dev/null || true
    sudo systemctl disable systemd-timesyncd 2>/dev/null || true
    
    # 安装 chrony
    if ! dpkg -l | grep -q chrony; then
        echo "正在安装 chrony..."
        sudo apt-get update --fix-missing 2>/dev/null || true
        sudo apt-get install -y chrony
    else
        echo "chrony 已安装"
    fi
    
    # 确定正确的服务名
    if systemctl list-unit-files | grep -q "^chrony.service"; then
        SERVICE_NAME="chrony"
    elif systemctl list-unit-files | grep -q "^chronyd.service"; then
        SERVICE_NAME="chronyd"
    else
        SERVICE_NAME="chrony"
    fi
    
    # 启用并启动服务
    echo "启用时间服务 ($SERVICE_NAME)..."
    sudo systemctl enable "$SERVICE_NAME" 2>/dev/null || true
    sudo systemctl start "$SERVICE_NAME"
    
    # 尝试设置NTP，如果失败则使用替代方法
    echo "配置NTP同步..."
    if ! sudo timedatectl set-ntp true 2>/dev/null; then
        echo "⚠️  timedatectl set-ntp 失败，使用替代方法"
        
        # 方法1: 直接配置chrony服务
        sudo systemctl restart "$SERVICE_NAME"
        
        # 方法2: 手动同步一次
        echo "执行手动时间同步..."
        sudo "$SERVICE_NAME" -a makestep 2>/dev/null || true
        
        # 方法3: 检查chrony配置
        echo "检查chrony配置..."
        if [ -f /etc/chrony/chrony.conf ] || [ -f /etc/chrony.conf ]; then
            echo "chrony配置文件存在"
        else
            echo "创建基本chrony配置..."
            echo "pool pool.ntp.org iburst" | sudo tee /etc/chrony/chrony.conf
            echo "makestep 1.0 3" | sudo tee -a /etc/chrony/chrony.conf
        fi
        
        # 重启服务应用配置
        sudo systemctl restart "$SERVICE_NAME"
    fi
    
    # 等待时间同步
    echo "等待时间同步 (15秒)..."
    sleep 15
    
    # 显示同步状态
    echo "[1.3] 时间同步结果："
    if command -v chronyc &> /dev/null; then
        chronyc tracking 2>/dev/null || echo "  chronyc tracking 不可用"
    fi
    echo "timedatectl 状态："
    timedatectl | grep -E "(System clock synchronized|NTP service|Local time)"
else
    echo "✅ 时间同步检查通过，跳过修复"
fi

# ========== 第二部分：修复APT镜像源 ==========
echo ""
echo "📦 [阶段 2/3] 修复 APT 软件源问题..."
echo "----------------------------------------"

# 2.1 备份当前源列表
echo "[2.1] 备份软件源配置..."
BACKUP_FILE="/etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)"
if [ -f /etc/apt/sources.list ]; then
    sudo cp /etc/apt/sources.list "$BACKUP_FILE"
    echo "备份已创建: $BACKUP_FILE"
else
    echo "⚠️  /etc/apt/sources.list 不存在"
fi

# 2.2 清理APT缓存
echo "[2.2] 清理 APT 缓存..."
sudo rm -rf /var/lib/apt/lists/partial/*
sudo rm -f /var/lib/apt/lists/lock
sudo rm -f /var/cache/apt/archives/lock
echo "缓存清理完成"

# 2.3 选择最佳镜像
echo "[2.3] 选择最佳镜像源..."
MIRRORS=(
    "deb.debian.org"
    "mirrors.ustc.edu.cn"
    "mirrors.tuna.tsinghua.edu.cn"
    "mirrors.aliyun.com"
)

SELECTED_MIRROR=""
for mirror in "${MIRRORS[@]}"; do
    echo "测试连接: $mirror ..."
    if timeout 3 curl -s "https://$mirror" > /dev/null 2>&1; then
        SELECTED_MIRROR="$mirror"
        echo "✅ 选择镜像: $SELECTED_MIRROR"
        break
    fi
done

if [ -z "$SELECTED_MIRROR" ]; then
    echo "⚠️  无法连接任何镜像，使用官方源"
    SELECTED_MIRROR="deb.debian.org"
fi

# 2.4 更新软件源配置
echo "[2.4] 更新软件源配置..."
if [ -f /etc/apt/sources.list ]; then
    # 替换安全源
    if [[ "$SELECTED_MIRROR" == "deb.debian.org" ]]; then
        sudo sed -i 's|http://deb.debian.org/debian-security|https://deb.debian.org/debian-security|g' /etc/apt/sources.list
        sudo sed -i 's|http://deb.debian.org/debian|https://deb.debian.org/debian|g' /etc/apt/sources.list
    else
        sudo sed -i "s|http://deb.debian.org/debian-security|https://$SELECTED_MIRROR/debian-security|g" /etc/apt/sources.list
        sudo sed -i "s|http://deb.debian.org/debian|https://$SELECTED_MIRROR/debian|g" /etc/apt/sources.list
    fi
    echo "已更新为镜像: $SELECTED_MIRROR"
fi

# ========== 第三部分：验证修复 ==========
echo ""
echo "✅ [阶段 3/3] 验证修复结果..."
echo "----------------------------------------"

# 3.1 执行APT更新
echo "[3.1] 执行 apt update..."
echo "----------------------------------------"
APT_OUTPUT=$(sudo apt update 2>&1)
APT_EXIT_CODE=$?
echo "$APT_OUTPUT" | tail -20
echo "----------------------------------------"

# 3.2 显示最终状态
echo "[3.2] 最终系统状态检查："
echo ""

# 时间状态
echo "🕐 时间同步状态："
timedatectl 2>/dev/null | grep -E "(Local time|System clock synchronized|NTP service|Universal time)" | while read -r line; do
    echo "  $line"
done

# APT状态
echo ""
echo "📦 APT 更新状态："
if [ $APT_EXIT_CODE -eq 0 ]; then
    echo "  ✅ APT 更新成功"
    echo "  📍 使用镜像: $SELECTED_MIRROR"
    
    # 检查可升级包
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c upgradable 2>/dev/null || echo "0")
    if [ "$UPGRADABLE" -gt 0 ] && [ "$UPGRADABLE" != "0" ]; then
        echo "  📊 可升级包: $UPGRADABLE 个"
        echo "  运行 'sudo apt upgrade' 升级系统"
    else
        echo "  📊 系统已是最新"
    fi
else
    echo "  ⚠️  APT 更新仍有问题"
    echo "  错误代码: $APT_EXIT_CODE"
    echo "最后5行输出："
    echo "$APT_OUTPUT" | tail -5
fi

# 备份信息
echo ""
echo "💾 备份信息："
if [ -f "$BACKUP_FILE" ]; then
    echo "  配置文件备份: $BACKUP_FILE"
    echo "  恢复命令: sudo cp \"$BACKUP_FILE\" /etc/apt/sources.list"
else
    echo "  ⚠️  未创建备份文件"
fi

# 服务状态
echo ""
echo "🔧 服务状态："
if systemctl is-active chrony --quiet 2>/dev/null; then
    echo "  ✅ chrony 服务运行中"
elif systemctl is-active chronyd --quiet 2>/dev/null; then
    echo "  ✅ chronyd 服务运行中"
else
    echo "  ⚠️  时间服务未运行"
fi

echo ""
echo "================================================"
if [ $APT_EXIT_CODE -eq 0 ] && (systemctl is-active chrony --quiet 2>/dev/null || systemctl is-active chronyd --quiet 2>/dev/null); then
    echo "🎉 修复完成！系统时间和APT均已恢复正常"
else
    echo "⚠️  部分问题可能需要手动处理"
    echo "   检查上述输出以获取详细信息"
fi
echo "================================================"