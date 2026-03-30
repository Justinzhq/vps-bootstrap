#!/usr/bin/env bash
set -euo pipefail

if ! command -v xray >/dev/null 2>&1; then
  echo "未检测到 xray，请先运行：sudo bash scripts/install-xray.sh"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "未检测到 openssl，请先安装 openssl"
  exit 1
fi

echo "============================"
echo "[*] UUID:"
xray uuid
echo

echo "[*] X25519 密钥对:"
xray x25519
echo

echo "[*] Short ID:"
openssl rand -hex 8
echo
echo "============================"
echo "请保存好以下信息："
echo "- 服务端需要：UUID / Private key / Short ID"
echo "- 客户端需要：UUID / Public key / Short ID"
echo "============================"
