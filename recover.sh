#!/usr/bin/env bash
set -e

echo "======================================="
echo " 云服务器逻辑恢复 + 常用工具安装脚本"
echo " 适用：Debian / Ubuntu"
echo "======================================="

if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行"
  exit 1
fi

echo "[1/8] 停止并禁用第三方服务..."
systemctl disable --now \
  docker docker.socket containerd \
  nginx apache2 \
  xray v2ray trojan hysteria sing-box \
  cloudflared warp wg-quick@wg0 2>/dev/null || true

echo "[2/8] 卸载常见第三方组件..."
apt purge -y \
  docker docker.io docker-ce docker-ce-cli containerd \
  nginx apache2 \
  cloudflared \
  xray v2ray trojan hysteria sing-box \
  wireguard wireguard-tools \
  ufw firewalld \
  snapd \
  openresty 2>/dev/null || true

apt autoremove -y
apt autoclean -y

echo "[3/8] 清理残留目录..."
rm -rf \
  /opt/* \
  /usr/local/bin/xray \
  /usr/local/bin/v2ray \
  /usr/local/bin/cloudflared \
  /usr/local/etc/* \
  /etc/xray /etc/v2ray /etc/sing-box \
  /etc/wireguard \
  /etc/cloudflared \
  /var/lib/docker \
  /var/lib/containerd \
  /var/log/xray /var/log/v2ray \
  /root/.acme.sh \
  /root/.warp \
  /root/.config 2>/dev/null || true

echo "[4/8] 重置网络与防火墙..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

ip6tables -F 2>/dev/null || true
ip6tables -X 2>/dev/null || true

systemctl restart networking || systemctl restart NetworkManager || true

echo "[5/8] 恢复 DNS 为官方默认..."
rm -f /etc/resolv.conf
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
chattr +i /etc/resolv.conf 2>/dev/null || true

echo "[6/8] 系统更新..."
apt update
apt upgrade -y

echo "[7/8] 安装常用工具..."
apt install -y \
  curl wget git vim nano \
  htop iftop iotop \
  net-tools iproute2 \
  lsof unzip zip tar \
  ca-certificates \
  sudo bash-completion \
  dnsutils \
  tmux screen \
  rsync cron

echo "[8/8] 基础加固（可选）..."
systemctl enable cron
timedatectl set-timezone UTC

echo "======================================="
echo " ✅ 系统已完成逻辑恢复"
echo " 👉 建议：现在重启一次服务器"
echo "======================================="

read -p "是否立即重启？[y/N]: " r
if [[ "$r" =~ ^[Yy]$ ]]; then
  reboot
fi
