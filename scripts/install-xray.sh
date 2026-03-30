#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo bash scripts/install-xray.sh"
  exit 1
fi

WORK_DIR="/tmp/xray-install"
SCRIPT_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "[*] 下载 Xray 官方安装脚本..."
curl -fsSL "$SCRIPT_URL" -o install-release.sh
chmod +x install-release.sh

echo "[*] 安装 / 升级 Xray..."
bash install-release.sh install

echo "[*] 设置开机自启..."
systemctl enable xray

echo "============================"
echo " Xray 已安装"
echo " - 二进制：/usr/local/bin/xray"
echo " - 配置目录：/usr/local/etc/xray/"
echo " 下一步请运行 scripts/gen-reality-secrets.sh"
echo " 然后再运行 scripts/generate-xray-config.sh"
echo "============================"
