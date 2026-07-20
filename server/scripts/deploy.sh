#!/usr/bin/env bash

# 发布脚本：本机交叉编译 Linux 二进制，拷贝到服务器对应目录。
#
# 用法：
#   ./scripts/deploy.sh
#
# 可用环境变量覆盖默认配置：
#   REMOTE_HOST  远程 SSH 目标，默认 root@45.79.40.29
#   REMOTE_DIR   服务器部署目录，默认 /home/www/websites/readingcoach.jingjiangke.com
#   SSH_PORT     SSH 端口，默认 22

set -euo pipefail

APP_NAME="readingcoach-server"
REMOTE_HOST="${REMOTE_HOST:-root@45.79.40.29}"
REMOTE_DIR="${REMOTE_DIR:-/home/www/websites/readingcoach.jingjiangke.com}"
SSH_PORT="${SSH_PORT:-22}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN_PATH="${SERVER_DIR}/release/dist/${APP_NAME}"

echo "==> 交叉编译 ${APP_NAME} (linux/amd64)"
mkdir -p "$(dirname "${BIN_PATH}")"
(
  cd "${SERVER_DIR}"
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -buildvcs=false -trimpath -o "${BIN_PATH}" ./cmd/server
)

echo "==> 停止远程 ${APP_NAME}（便于覆盖二进制）"
ssh -p "${SSH_PORT}" "${REMOTE_HOST}" "
  APP='${REMOTE_DIR}/${APP_NAME}'
  if command -v systemctl >/dev/null 2>&1 && systemctl cat '${APP_NAME}' >/dev/null 2>&1; then
    systemctl stop '${APP_NAME}' || true
    echo '已通过 systemd 停止服务'
  elif pgrep -f \"\${APP}\" >/dev/null 2>&1; then
    pkill -f \"\${APP}\" || true
    sleep 1
    echo '已终止进程'
  else
    echo '未发现运行中的进程'
  fi
"

echo "==> 拷贝到 ${REMOTE_HOST}:${REMOTE_DIR}/${APP_NAME}"
ssh -p "${SSH_PORT}" "${REMOTE_HOST}" "mkdir -p '${REMOTE_DIR}'"
scp -P "${SSH_PORT}" "${BIN_PATH}" "${REMOTE_HOST}:${REMOTE_DIR}/${APP_NAME}"

# 服务器没有 config.json 时才拷贝一份模板，避免覆盖已填好的生产配置。
CONFIG_UPLOADED=false
if ssh -p "${SSH_PORT}" "${REMOTE_HOST}" "test -f '${REMOTE_DIR}/config.json'"; then
  echo "==> 远程已存在 config.json，保持不变"
else
  echo "==> 远程缺少 config.json，上传模板 config.example.json"
  scp -P "${SSH_PORT}" "${SERVER_DIR}/config.example.json" "${REMOTE_HOST}:${REMOTE_DIR}/config.json"
  CONFIG_UPLOADED=true
  echo "    ⚠️  请登录服务器编辑 ${REMOTE_DIR}/config.json 填写生产配置后再启动服务"
fi

if [[ "${CONFIG_UPLOADED}" == "true" ]]; then
  echo "==> 跳过重启：请先编辑远程 config.json"
elif ssh -p "${SSH_PORT}" "${REMOTE_HOST}" "command -v systemctl >/dev/null 2>&1 && systemctl cat '${APP_NAME}' >/dev/null 2>&1"; then
  echo "==> 重启远程 ${APP_NAME}"
  ssh -p "${SSH_PORT}" "${REMOTE_HOST}" "systemctl restart '${APP_NAME}' && systemctl status '${APP_NAME}' --no-pager"
else
  echo "==> 未安装 systemd 服务，请手动启动 ${REMOTE_DIR}/${APP_NAME}"
fi

echo "==> 完成"
