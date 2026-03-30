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
TMP_CONFIG="$(mktemp)"

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

cp "$SSHD_CONFIG" "$TMP_CONFIG"

set_kv() {
  local key="$1"
  local value="$2"

  if grep -qiE "^[#[:space:]]*${key}[[:space:]]+" "$TMP_CONFIG"; then
    sed -i.bak -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|I" "$TMP_CONFIG"
  else
    printf '%s %s\n' "$key" "$value" >> "$TMP_CONFIG"
  fi
}

echo "[*] 调整 SSH 配置..."
set_kv "Port" "$SSH_PORT"
set_kv "PubkeyAuthentication" "yes"
set_kv "PasswordAuthentication" "$( [ "$DISABLE_PASSWORD_AUTH" = "true" ] && echo "no" || echo "yes" )"
set_kv "KbdInteractiveAuthentication" "no"
set_kv "ChallengeResponseAuthentication" "no"
set_kv "UsePAM" "yes"
set_kv "PermitRootLogin" "$( [ "$DISABLE_ROOT_LOGIN" = "true" ] && echo "no" || echo "prohibit-password" )"

echo "[*] 校验 SSH 配置..."
sshd -t -f "$TMP_CONFIG"

echo "[*] 应用 SSH 配置..."
cp "$TMP_CONFIG" "$SSHD_CONFIG"

echo "[*] 更新防火墙规则..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${SSH_PORT}/tcp"
  ufw limit "${SSH_PORT}/tcp"
fi

echo "[*] 重启 SSH 服务..."
systemctl restart ssh || systemctl restart sshd

rm -f "$TMP_CONFIG" "$TMP_CONFIG.bak"

echo "============================"
echo " SSH 加固完成："
echo " - 端口：${SSH_PORT}"
echo " - Root SSH 登录禁用：${DISABLE_ROOT_LOGIN}"
echo " - 密码认证禁用：${DISABLE_PASSWORD_AUTH}"
echo " 请先新开一个终端验证 SSH，再关闭当前会话"
echo "============================"
