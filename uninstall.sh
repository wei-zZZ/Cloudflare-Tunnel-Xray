cat > uninstall_secure_tunnel.sh << 'EOF'
#!/bin/bash
# ============================================
# Cloudflare Tunnel 完全卸载脚本
# ============================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }

print_warning "═══════════════════════════════════════════════"
print_warning "         Cloudflare Tunnel 完全卸载"
print_warning "═══════════════════════════════════════════════"
echo ""

# 确认操作
read -p "确定要完全卸载 Cloudflare Tunnel 吗？(y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_error "操作已取消"
    exit 0
fi

echo ""
print_info "开始卸载..."

# ============================================
# 1. 停止所有相关服务
# ============================================
print_info "停止所有相关服务..."

# 停止系统服务
systemctl stop secure-tunnel-xray.service 2>/dev/null || true
systemctl stop secure-tunnel-argo.service 2>/dev/null || true

# 禁用服务
systemctl disable secure-tunnel-xray.service 2>/dev/null || true
systemctl disable secure-tunnel-argo.service 2>/dev/null || true

# 停止订阅服务器
pkill -f "server.py" 2>/dev/null || true
pkill -f "simple_server.py" 2>/dev/null || true
pkill -f "python3.*server" 2>/dev/null || true

# 停止其他相关进程
pkill -f "xray" 2>/dev/null || true
pkill -f "cloudflared" 2>/dev/null || true

# 释放端口
for port in {8080..8200}; do
    if ss -tulpn | grep ":$port" >/dev/null; then
        sudo fuser -k ${port}/tcp 2>/dev/null || true
    fi
done

sleep 3
print_success "✅ 所有服务已停止"

# ============================================
# 2. 删除系统服务文件
# ============================================
print_info "删除系统服务文件..."

rm -f /etc/systemd/system/secure-tunnel-xray.service 2>/dev/null
rm -f /etc/systemd/system/secure-tunnel-argo.service 2>/dev/null
rm -f /etc/systemd/system/secure-tunnel-sub.service 2>/dev/null

# 重新加载systemd
systemctl daemon-reload 2>/dev/null || true

print_success "✅ 系统服务文件已删除"

# ============================================
# 3. 删除应用程序文件
# ============================================
print_info "删除应用程序文件..."

# 删除二进制文件
rm -f /usr/local/bin/xray 2>/dev/null
rm -f /usr/local/bin/cloudflared 2>/dev/null

# 删除配置目录
rm -rf /etc/secure_tunnel 2>/dev/null
rm -rf /var/lib/secure_tunnel 2>/dev/null
rm -rf /var/log/secure_tunnel 2>/dev/null

# 删除数据目录
rm -rf /root/.cloudflared 2>/dev/null
rm -rf /root/.cloudflare-warp 2>/dev/null
rm -rf /etc/cloudflared 2>/dev/null

print_success "✅ 应用程序文件已删除"

# ============================================
# 4. 删除用户和组
# ============================================
print_info "删除用户和组..."

userdel secure_tunnel 2>/dev/null || true
groupdel secure_tunnel 2>/dev/null || true

print_success "✅ 用户和组已删除"

# ============================================
# 5. 清理临时文件
# ============================================
print_info "清理临时文件..."

rm -rf /tmp/xray* 2>/dev/null
rm -rf /tmp/cloudflare* 2>/dev/null
rm -rf /tmp/secure_tunnel* 2>/dev/null

# 清理日志文件
journalctl --vacuum-time=1h 2>/dev/null || true

print_success "✅ 临时文件已清理"

# ============================================
# 6. 清理Cloudflare隧道（可选）
# ============================================
read -p "是否要清理Cloudflare上的隧道？(y/N): " clean_cf
if [[ "$clean_cf" == "y" || "$clean_cf" == "Y" ]]; then
    print_info "清理Cloudflare隧道..."
    
    # 尝试使用cloudflared清理
    if command -v /usr/local/bin/cloudflared &> /dev/null; then
        /usr/local/bin/cloudflared tunnel list 2>/dev/null || true
        echo ""
        print_warning "请在Cloudflare面板中手动删除隧道："
        print_warning "1. 登录 Cloudflare 控制台"
        print_warning "2. 进入 Zero Trust → Access → Tunnels"
        print_warning "3. 删除相关的隧道"
    else
        print_warning "cloudflared 未安装，无法列出隧道"
    fi
fi

# ============================================
# 7. 清理DNS记录（可选）
# ============================================
read -p "是否要清理相关的DNS记录？(y/N): " clean_dns
if [[ "$clean_dns" == "y" || "$clean_dns" == "Y" ]]; then
    print_info "请在Cloudflare DNS中手动删除以下记录："
    print_info "1. 登录 Cloudflare 控制台"
    print_info "2. 进入 DNS → Records"
    print_info "3. 删除与隧道相关的CNAME记录"
fi

# ============================================
# 8. 验证清理结果
# ============================================
print_info "验证清理结果..."
echo ""

# 检查服务
echo "检查服务状态："
systemctl status secure-tunnel-xray.service 2>/dev/null | grep -q "loaded" && echo "❌ Xray服务仍存在" || echo "✅ Xray服务已删除"
systemctl status secure-tunnel-argo.service 2>/dev/null | grep -q "loaded" && echo "❌ Argo服务仍存在" || echo "✅ Argo服务已删除"

echo ""

# 检查进程
echo "检查进程："
pgrep -f xray >/dev/null && echo "❌ Xray进程仍在运行" || echo "✅ 无Xray进程"
pgrep -f cloudflared >/dev/null && echo "❌ cloudflared进程仍在运行" || echo "✅ 无cloudflared进程"
pgrep -f "server.py" >/dev/null && echo "❌ 订阅服务器进程仍在运行" || echo "✅ 无订阅服务器进程"

echo ""

# 检查文件
echo "检查文件："
[[ -f /usr/local/bin/xray ]] && echo "❌ xray二进制文件仍存在" || echo "✅ xray文件已删除"
[[ -f /usr/local/bin/cloudflared ]] && echo "❌ cloudflared二进制文件仍存在" || echo "✅ cloudflared文件已删除"
[[ -d /etc/secure_tunnel ]] && echo "❌ 配置目录仍存在" || echo "✅ 配置目录已删除"
[[ -d /root/.cloudflared ]] && echo "❌ Cloudflare证书目录仍存在" || echo "✅ Cloudflare证书目录已删除"

echo ""
print_success "═══════════════════════════════════════════════"
print_success "           卸载完成！"
print_success "═══════════════════════════════════════════════"
echo ""
print_info "现在可以重新安装："
echo "  sudo ./secure_tunnel_final.sh install"
echo ""
print_info "或者测试其他脚本："
echo "  sudo ./secure_tunnel.sh install"
echo "  sudo ./secure_tunnel_fixed.sh install"
echo ""
print_warning "⚠️ 注意："
print_warning "1. Cloudflare隧道可能需要手动清理"
print_warning "2. DNS记录可能需要手动删除"
print_warning "3. 如果重新安装失败，可能需要重启服务器"
EOF

# 给脚本执行权限
chmod +x uninstall_secure_tunnel.sh

echo "✅ 卸载脚本已创建：uninstall_secure_tunnel.sh"
echo "使用方法：sudo ./uninstall_secure_tunnel.sh"
