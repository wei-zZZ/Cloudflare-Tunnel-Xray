#!/bin/bash
# ============================================
# X-UI 隧道诊断修复脚本
# 紧急修复版本
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# 配置文件路径
CONFIG_DIR="/etc/xui_tunnel"
BIN_DIR="/usr/local/bin"

echo ""
echo "==============================================="
echo "       X-UI 隧道紧急诊断修复工具"
echo "==============================================="
echo ""

# ----------------------------
# 1. 停止所有服务
# ----------------------------
print_info "1. 停止所有相关服务..."
systemctl stop xui-tunnel.service 2>/dev/null || true
pkill -f cloudflared 2>/dev/null || true
sleep 2

# ----------------------------
# 2. 检查关键文件
# ----------------------------
print_info "2. 检查关键文件..."

echo ""
echo "=== 检查证书文件 ==="
if [ -f "/root/.cloudflared/cert.pem" ]; then
    print_success "✅ 找到证书文件: /root/.cloudflared/cert.pem"
    ls -la /root/.cloudflared/cert.pem
else
    print_error "❌ 未找到证书文件"
    exit 1
fi

echo ""
echo "=== 检查凭证文件 ==="
json_files=$(find /root/.cloudflared -name "*.json" -type f 2>/dev/null)
if [ -n "$json_files" ]; then
    for file in $json_files; do
        print_success "✅ 找到凭证文件: $file"
        echo "文件内容前几行:"
        head -3 "$file"
        echo ""
    done
else
    print_error "❌ 未找到任何JSON凭证文件"
    exit 1
fi

echo ""
echo "=== 检查配置文件 ==="
if [ -f "$CONFIG_DIR/tunnel.conf" ]; then
    print_success "✅ 找到隧道配置: $CONFIG_DIR/tunnel.conf"
    cat "$CONFIG_DIR/tunnel.conf"
else
    print_error "❌ 未找到隧道配置"
    exit 1
fi

echo ""
if [ -f "$CONFIG_DIR/tunnel-config.yaml" ]; then
    print_success "✅ 找到YAML配置: $CONFIG_DIR/tunnel-config.yaml"
    cat "$CONFIG_DIR/tunnel-config.yaml"
else
    print_error "❌ 未找到YAML配置"
    exit 1
fi

# ----------------------------
# 3. 手动测试隧道
# ----------------------------
print_info "3. 手动测试隧道启动..."

# 获取配置信息
source "$CONFIG_DIR/tunnel.conf" 2>/dev/null || {
    print_error "无法加载配置文件"
    exit 1
}

# 创建简化的测试配置文件
cat > /tmp/test-config.yaml << EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE
logfile: /tmp/cloudflared-test.log
loglevel: debug
ingress:
  - hostname: $PANEL_DOMAIN
    service: http://localhost:$XUI_PANEL_PORT
  - service: http_status:404
EOF

echo ""
print_info "测试配置文件内容:"
cat /tmp/test-config.yaml

echo ""
print_info "开始手动运行隧道 (10秒测试)..."
echo "按 Ctrl+C 停止测试"

# 后台运行测试
timeout 10 "$BIN_DIR/cloudflared" tunnel --config /tmp/test-config.yaml run 2>&1 | tee /tmp/tunnel-test.log &
TEST_PID=$!

# 等待并检查
sleep 5

if ps -p $TEST_PID > /dev/null 2>&1; then
    print_success "✅ 隧道测试运行正常"
    kill $TEST_PID 2>/dev/null || true
else
    print_error "❌ 隧道测试运行失败"
    echo ""
    print_info "错误日志:"
    tail -20 /tmp/tunnel-test.log
    echo ""
    
    # 检查常见错误
    if grep -q "certificate" /tmp/tunnel-test.log; then
        print_warning "⚠️  证书问题，尝试重新授权..."
        fix_certificate
    fi
    
    if grep -q "credentials" /tmp/tunnel-test.log; then
        print_warning "⚠️  凭证文件问题，尝试修复..."
        fix_credentials
    fi
    
    if grep -q "tunnel.*not found" /tmp/tunnel-test.log; then
        print_warning "⚠️  隧道不存在，尝试重新创建..."
        fix_tunnel
    fi
fi

# ----------------------------
# 4. 修复函数
# ----------------------------
fix_certificate() {
    print_info "修复证书问题..."
    
    echo ""
    print_warning "可能需要重新授权..."
    read -p "是否重新进行Cloudflare授权？(y/N): " -r answer
    
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        rm -rf /root/.cloudflared
        mkdir -p /root/.cloudflared
        
        echo ""
        echo "请复制以下链接到浏览器授权:"
        "$BIN_DIR/cloudflared" tunnel login
        
        read -p "完成授权后按回车继续..." -r
    fi
}

fix_credentials() {
    print_info "修复凭证文件..."
    
    # 查找最新的凭证文件
    local latest_json=$(find /root/.cloudflared -name "*.json" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")
    
    if [ -n "$latest_json" ] && [ -f "$latest_json" ]; then
        print_success "找到凭证文件: $latest_json"
        
        # 更新配置文件
        sed -i "s|CREDENTIALS_FILE=.*|CREDENTIALS_FILE=$latest_json|" "$CONFIG_DIR/tunnel.conf"
        
        # 更新YAML配置
        TUNNEL_ID=$(grep "^TUNNEL_ID=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
        PANEL_DOMAIN=$(grep "^PANEL_DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
        XUI_PANEL_PORT=$(grep "^XUI_PANEL_PORT=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
        
        cat > "$CONFIG_DIR/tunnel-config.yaml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $latest_json
logfile: /var/log/xui_tunnel/tunnel.log
loglevel: info
ingress:
  - hostname: $PANEL_DOMAIN
    service: http://localhost:$XUI_PANEL_PORT
  - service: http_status:404
EOF
        
        print_success "凭证文件已修复"
    else
        print_error "未找到可用的凭证文件"
    fi
}

fix_tunnel() {
    print_info "修复隧道..."
    
    # 获取隧道名称
    local tunnel_name=$(grep "^TUNNEL_NAME=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
    
    if [ -z "$tunnel_name" ]; then
        tunnel_name="xui-tunnel"
    fi
    
    echo ""
    print_info "删除旧隧道: $tunnel_name"
    "$BIN_DIR/cloudflared" tunnel delete -f "$tunnel_name" 2>/dev/null || true
    sleep 2
    
    print_info "创建新隧道..."
    if "$BIN_DIR/cloudflared" tunnel create "$tunnel_name"; then
        sleep 3
        
        # 获取新隧道ID
        local new_tunnel_info=$("$BIN_DIR/cloudflared" tunnel list 2>/dev/null | grep "$tunnel_name" || true)
        
        if [ -n "$new_tunnel_info" ]; then
            local new_tunnel_id=$(echo "$new_tunnel_info" | awk '{print $1}')
            print_success "新隧道ID: $new_tunnel_id"
            
            # 更新配置文件
            sed -i "s|TUNNEL_ID=.*|TUNNEL_ID=$new_tunnel_id|" "$CONFIG_DIR/tunnel.conf"
            
            # 获取凭证文件
            local json_file=$(find /root/.cloudflared -name "*.json" -type f | head -1)
            if [ -n "$json_file" ]; then
                sed -i "s|CREDENTIALS_FILE=.*|CREDENTIALS_FILE=$json_file|" "$CONFIG_DIR/tunnel.conf"
            fi
            
            print_success "隧道已修复"
        else
            print_error "无法获取新隧道ID"
        fi
    else
        print_error "隧道创建失败"
    fi
}

# ----------------------------
# 5. 创建极简服务文件
# ----------------------------
print_info "4. 创建极简服务文件..."

cat > /etc/systemd/system/xui-tunnel.service << 'EOF'
[Unit]
Description=X-UI Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/xui_tunnel/tunnel-config.yaml run
Restart=always
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
print_success "服务文件已更新"

# ----------------------------
# 6. 重启服务
# ----------------------------
print_info "5. 重启服务..."

systemctl restart xui-tunnel.service
sleep 3

if systemctl is-active --quiet xui-tunnel.service; then
    print_success "✅ 隧道服务启动成功！"
    
    echo ""
    print_info "服务状态:"
    systemctl status xui-tunnel.service --no-pager | head -10
    
    echo ""
    print_info "隧道列表:"
    "$BIN_DIR/cloudflared" tunnel list 2>/dev/null || echo "无法获取隧道列表"
    
    echo ""
    print_success "🎉 修复完成！"
    
    # 显示访问信息
    if [ -f "$CONFIG_DIR/tunnel.conf" ]; then
        PANEL_DOMAIN=$(grep "^PANEL_DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
        NODE_DOMAIN=$(grep "^NODE_DOMAIN=" "$CONFIG_DIR/tunnel.conf" | cut -d'=' -f2)
        
        echo ""
        print_success "访问信息:"
        echo "  面板: https://$PANEL_DOMAIN"
        echo "  节点: $NODE_DOMAIN:443"
    fi
else
    print_error "❌ 隧道服务仍然失败"
    
    echo ""
    print_info "查看详细错误:"
    journalctl -u xui-tunnel.service -n 30 --no-pager
    
    echo ""
    print_warning "尝试手动运行排查:"
    echo "  $BIN_DIR/cloudflared tunnel --config $CONFIG_DIR/tunnel-config.yaml run"
fi

# ----------------------------
# 7. 清理
# ----------------------------
rm -f /tmp/test-config.yaml /tmp/tunnel-test.log /tmp/cloudflared-test.log 2>/dev/null || true

echo ""
print_info "诊断完成！"