#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   sudo bash scripts/initial.sh justin "ssh-ed25519 AAAA... your@key"
#
# 参数：
#   $1 管理用户名，默认 justin
#   $2 SSH 公钥整行内容，可选
#
# 环境变量：
#   TZ_VALUE=UTC

NEW_USER="${1:-justin}"
PUBKEY="${2:-}"
TZ_VALUE="${TZ_VALUE:-UTC}"

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo bash scripts/initial.sh <user> \"<pubkey>\""
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[*] 更新系统..."
apt update
apt -y upgrade

echo "[*] 安装基础工具..."
apt -y install \
  sudo curl git ufw fail2ban tmux htop \
  ca-certificates gnupg lsb-release jq \
  gettext-base openssh-server openssl

echo "[*] 设置时区为 ${TZ_VALUE} ..."
timedatectl set-timezone "$TZ_VALUE" || true

echo "[*] 创建管理用户 ${NEW_USER} ..."
if ! id "$NEW_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$NEW_USER"
fi

usermod -aG sudo "$NEW_USER"

echo "[*] 配置 SSH 公钥..."
mkdir -p "/home/${NEW_USER}/.ssh"
chmod 700 "/home/${NEW_USER}/.ssh"
touch "/home/${NEW_USER}/.ssh/authorized_keys"

if [ -n "$PUBKEY" ]; then
  grep -qxF "$PUBKEY" "/home/${NEW_USER}/.ssh/authorized_keys" || \
    echo "$PUBKEY" >> "/home/${NEW_USER}/.ssh/authorized_keys"
fi

chmod 600 "/home/${NEW_USER}/.ssh/authorized_keys"
chown -R "${NEW_USER}:${NEW_USER}" "/home/${NEW_USER}/.ssh"

echo "[*] 配置 UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw limit OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "[*] 配置 Fail2Ban..."
cat >/etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled  = true
port     = ssh
backend  = systemd
EOF

systemctl enable --now fail2ban
systemctl enable --now ssh || systemctl enable --now sshd || true

echo "============================"
echo " 初始化完成："
echo " - 管理用户：${NEW_USER}"
echo " - 已加入 sudo 组"
echo " - UFW 已启用（OpenSSH + 80 + 443）"
echo " - Fail2Ban 已启用"
echo " - envsubst 已可用"
echo " 请退出后使用 ${NEW_USER} 重新登录"
echo "============================"
