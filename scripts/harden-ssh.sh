#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   sudo SSH_PORT=2222 DISABLE_ROOT_LOGIN=true DISABLE_PASSWORD_AUTH=true \
#     bash scripts/harden-ssh.sh
#
# 环境变量：
#   SSH_PORT=22
#   DISABLE_ROOT_LOGIN=true
#   DISABLE_PASSWORD_AUTH=true

SSH_PORT="${SSH_PORT:-22}"
DISABLE_ROOT_LOGIN="${DISABLE_ROOT_LOGIN:-true}"
DISABLE_PASSWORD_AUTH="${DISABLE_PASSWORD_AUTH:-true}"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN_FILE="${SSHD_CONFIG_DIR}/99-vps-bootstrap.conf"
FAIL2BAN_JAIL_LOCAL="/etc/fail2ban/jail.local"

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo SSH_PORT=... bash scripts/harden-ssh.sh"
  exit 1
fi

if ! command -v sshd >/dev/null 2>&1; then
  echo "未检测到 sshd，请先确认 openssh-server 已安装"
  exit 1
fi

case "$SSH_PORT" in
  ''|*[!0-9]*)
    echo "SSH_PORT 必须是数字"
    exit 1
    ;;
esac

if [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
  echo "SSH_PORT 必须在 1-65535 之间"
  exit 1
fi

echo "[*] 调整 SSH 配置..."
mkdir -p "$SSHD_CONFIG_DIR"

if ! grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CONFIG"; then
  printf 'Include /etc/ssh/sshd_config.d/*.conf\n' >> "$SSHD_CONFIG"
fi

cat > "$SSHD_DROPIN_FILE" <<EOF
Port ${SSH_PORT}
PubkeyAuthentication yes
PasswordAuthentication $( [ "$DISABLE_PASSWORD_AUTH" = "true" ] && echo "no" || echo "yes" )
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
PermitRootLogin $( [ "$DISABLE_ROOT_LOGIN" = "true" ] && echo "no" || echo "prohibit-password" )
EOF

echo "[*] 校验 SSH 配置..."
sshd -t

echo "[*] 更新防火墙规则..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${SSH_PORT}/tcp"

  if [ "$SSH_PORT" != "22" ]; then
    ufw delete allow OpenSSH || true
    ufw delete limit OpenSSH || true
    ufw delete allow 22/tcp || true
    ufw delete limit 22/tcp || true
  fi
fi

echo "[*] 同步 Fail2Ban SSH 端口..."
if [ -f "$FAIL2BAN_JAIL_LOCAL" ]; then
  awk -v ssh_port="$SSH_PORT" '
    BEGIN { in_sshd = 0 }
    /^\[sshd\]/ { in_sshd = 1; print; next }
    /^\[/ && $0 != "[sshd]" { in_sshd = 0; print; next }
    in_sshd && /^[[:space:]]*port[[:space:]]*=/ {
      print "port     = " ssh_port
      next
    }
    { print }
  ' "$FAIL2BAN_JAIL_LOCAL" > "${FAIL2BAN_JAIL_LOCAL}.tmp"
  mv "${FAIL2BAN_JAIL_LOCAL}.tmp" "$FAIL2BAN_JAIL_LOCAL"
  systemctl restart fail2ban || true
fi

echo "[*] 重启 SSH 服务..."
systemctl restart ssh || systemctl restart sshd

echo "============================"
echo " SSH 加固完成："
echo " - 端口：${SSH_PORT}"
echo " - Root SSH 登录禁用：${DISABLE_ROOT_LOGIN}"
echo " - 密码认证禁用：${DISABLE_PASSWORD_AUTH}"
echo " - SSH 配置文件：${SSHD_DROPIN_FILE}"
echo " - UFW 已同步为 SSH 端口 ${SSH_PORT}"
echo " - Fail2Ban 已同步监控 SSH 端口 ${SSH_PORT}"
echo " 请先新开一个终端验证 SSH，再关闭当前会话"
echo "============================"
