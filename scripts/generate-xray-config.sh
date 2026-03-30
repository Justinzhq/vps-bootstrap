#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_PATH="${BASE_DIR}/templates/xray-config.json.tpl"
OUT_DIR="/usr/local/etc/xray"
OUT_PATH="${OUT_DIR}/config.json"

XRAY_PORT="${XRAY_PORT:-443}"
XRAY_UUID="${XRAY_UUID:-}"
REALITY_DEST="${REALITY_DEST:-www.cloudflare.com:443}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.cloudflare.com}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo XRAY_UUID=... REALITY_PRIVATE_KEY=... bash scripts/generate-xray-config.sh"
  exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
  echo "缺少 envsubst，请先运行 initial.sh 或安装 gettext-base"
  exit 1
fi

if ! command -v xray >/dev/null 2>&1; then
  echo "未检测到 xray，请先运行 scripts/install-xray.sh"
  exit 1
fi

if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "模板不存在：${TEMPLATE_PATH}"
  exit 1
fi

case "$XRAY_PORT" in
  ''|*[!0-9]*)
    echo "XRAY_PORT 必须是数字"
    exit 1
    ;;
esac

if [ -z "$XRAY_UUID" ]; then
  echo "缺少 XRAY_UUID"
  exit 1
fi

if [ -z "$REALITY_PRIVATE_KEY" ]; then
  echo "缺少 REALITY_PRIVATE_KEY"
  exit 1
fi

if [ -z "$REALITY_SHORT_ID" ]; then
  echo "缺少 REALITY_SHORT_ID"
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "[*] 生成 Xray 配置..."
export XRAY_PORT XRAY_UUID REALITY_DEST REALITY_SERVER_NAME REALITY_PRIVATE_KEY REALITY_SHORT_ID
envsubst < "$TEMPLATE_PATH" > "$OUT_PATH"

echo "[*] 校验配置..."
xray run -test -config "$OUT_PATH"

echo "[*] 重启 Xray..."
systemctl restart xray

echo "[*] 当前服务状态："
systemctl --no-pager --full status xray || true

echo "============================"
echo " Xray REALITY 配置已生成、校验并重启"
echo " 配置文件：${OUT_PATH}"
echo "============================"
