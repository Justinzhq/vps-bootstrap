#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   sudo bash scripts/initial.sh user "ssh-ed25519 AAAA... your@key"
#
# 参数：
#   $1 管理用户名，默认 user
#   $2 SSH 公钥整行内容，必填
#
# 环境变量：
#   TZ_VALUE=UTC

NEW_USER="${1:-user}"
PUBKEY="${2:-}"
TZ_VALUE="${TZ_VALUE:-UTC}"
SUDOERS_FILE="/etc/sudoers.d/90-${NEW_USER}-nopasswd"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN_FILE="${SSHD_CONFIG_DIR}/10-vps-bootstrap.conf"
LEGACY_SSHD_DROPIN_FILE="${SSHD_CONFIG_DIR}/99-vps-bootstrap.conf"
CLOUD_INIT_CONFIG_DIR="/etc/cloud/cloud.cfg.d"
CLOUD_INIT_SSH_FILE="${CLOUD_INIT_CONFIG_DIR}/99-vps-bootstrap-ssh.cfg"

strip_managed_sshd_keys_from_main() {
  local tmp_file
  tmp_file="$(mktemp)"

  awk '
    /^[[:space:]]*(Port|PubkeyAuthentication|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|PermitEmptyPasswords|UsePAM|PermitRootLogin)[[:space:]]+/ {
      next
    }
    { print }
  ' "$SSHD_CONFIG" > "$tmp_file"

  cp "$tmp_file" "$SSHD_CONFIG"
  rm -f "$tmp_file"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo bash scripts/initial.sh <user> \"<pubkey>\""
  exit 1
fi

if [ -z "$PUBKEY" ]; then
  echo "必须提供 SSH 公钥，避免开启 SSH-only 登录后把自己锁在门外"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[*] 更新系统..."
apt update
apt -y upgrade

echo "[*] 安装基础工具..."
apt -y install \
  sudo curl git make ufw fail2ban tmux htop \
  ca-certificates gnupg lsb-release jq \
  gettext-base openssh-server openssl

echo "[*] 设置时区为 ${TZ_VALUE} ..."
timedatectl set-timezone "$TZ_VALUE" || true

echo "[*] 创建管理用户 ${NEW_USER} ..."
if ! id "$NEW_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$NEW_USER"
fi

usermod -aG sudo "$NEW_USER"

echo "[*] 配置 sudo 免密码..."
printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "$NEW_USER" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"

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

echo "[*] 切换为 SSH key-only 登录..."
mkdir -p "$SSHD_CONFIG_DIR"
rm -f "$LEGACY_SSHD_DROPIN_FILE"

if ! grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CONFIG"; then
  printf 'Include /etc/ssh/sshd_config.d/*.conf\n' >> "$SSHD_CONFIG"
fi

strip_managed_sshd_keys_from_main

cat > "$SSHD_DROPIN_FILE" <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
UsePAM yes
EOF

if [ -d "$CLOUD_INIT_CONFIG_DIR" ]; then
  echo "[*] 同步 cloud-init SSH 策略..."
  cat > "$CLOUD_INIT_SSH_FILE" <<'EOF'
ssh_pwauth: false
EOF
fi

echo "[*] 校验 SSH 配置..."
sshd -t

echo "[*] 配置 UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
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
systemctl disable --now ssh.socket 2>/dev/null || true
systemctl enable --now ssh || systemctl enable --now sshd || true
systemctl restart ssh || systemctl restart sshd || true

echo "============================"
echo " 初始化完成："
echo " - 管理用户：${NEW_USER}"
echo " - 已加入 sudo 组，并配置为免密码 sudo"
echo " - SSH 已切换为 key-only 登录（已禁用密码认证）"
echo " - SSH 配置文件：${SSHD_DROPIN_FILE}"
echo " - UFW 已启用（OpenSSH + 80 + 443）"
echo " - Fail2Ban 已启用"
echo " - 若系统启用了 cloud-init，已同步 ssh_pwauth=false"
echo " - envsubst 已可用"
echo " 请保留当前会话，先新开终端验证 ${NEW_USER} 登录"
echo "============================"
