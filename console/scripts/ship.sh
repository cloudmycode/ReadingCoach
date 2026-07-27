#!/usr/bin/env bash

# 本机构建 console 静态站点，rsync 到服务器。
#
# 用法：
#   ./scripts/ship.sh
#
# 环境变量：
#   REMOTE_HOST        SSH 目标，默认 root@39.105.229.91
#   REMOTE_STATIC_DIR  服务器静态目录，默认 /home/website/readingcoach.jingjiangke.com/www/console
#   SSH_PORT           SSH 端口，默认 22
#   SYNC_NGINX         设为 1 时同步 server/deploy/nginx.readingcoach.conf 并重载 nginx
#
# 前置条件：
#   - 本机 Node.js 18+、npm
#   - 服务器 Go 服务已在 127.0.0.1:8080 运行
#   - 服务器 REMOTE_STATIC_DIR 目录已创建且可写

set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-root@39.105.229.91}"
REMOTE_STATIC_DIR="${REMOTE_STATIC_DIR:-/home/website/readingcoach.jingjiangke.com/www/console}"
SSH_PORT="${SSH_PORT:-22}"
SYNC_NGINX="${SYNC_NGINX:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSOLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WEB_DIR="${CONSOLE_DIR}/web"
REPO_ROOT="$(cd "${CONSOLE_DIR}/.." && pwd)"
NGINX_CONF="${REPO_ROOT}/server/deploy/nginx.readingcoach.conf"
REMOTE_NGINX_CONF="/etc/nginx/conf.d/readingcoach.conf"

SSH_OPTS=(-p "${SSH_PORT}")
RSYNC_SSH="ssh -p ${SSH_PORT}"

if [[ ! -f "${WEB_DIR}/package.json" ]]; then
  echo "错误：未找到 ${WEB_DIR}/package.json" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "错误：本机未安装 npm" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "错误：本机未安装 rsync" >&2
  exit 1
fi

echo "==> [1/3] 构建前端（${WEB_DIR}）"
cd "${WEB_DIR}"
if [[ -f package-lock.json ]]; then
  npm ci
else
  npm install
fi
npm run build

if [[ ! -d dist ]]; then
  echo "错误：构建后未找到 dist/ 目录" >&2
  exit 1
fi

echo "==> [2/3] 同步静态文件到 ${REMOTE_HOST}:${REMOTE_STATIC_DIR}"
ssh "${SSH_OPTS[@]}" "${REMOTE_HOST}" "
  set -e
  mkdir -p '${REMOTE_STATIC_DIR}'
  if [[ -d '${REMOTE_STATIC_DIR}' && \"\$(ls -A '${REMOTE_STATIC_DIR}' 2>/dev/null)\" ]]; then
    backup='${REMOTE_STATIC_DIR}.backup.'\$(date +%Y%m%d-%H%M%S)
    cp -a '${REMOTE_STATIC_DIR}' \"\${backup}\"
    echo \"    已备份当前版本到 \${backup}\"
  fi
"

rsync -avz --delete -e "${RSYNC_SSH}" "${WEB_DIR}/dist/" "${REMOTE_HOST}:${REMOTE_STATIC_DIR}/"

echo "    已发布 $(du -sh "${WEB_DIR}/dist" | cut -f1) 到 ${REMOTE_STATIC_DIR}"

if [[ "${SYNC_NGINX}" == "1" ]]; then
  if [[ ! -f "${NGINX_CONF}" ]]; then
    echo "错误：未找到 Nginx 配置 ${NGINX_CONF}" >&2
    exit 1
  fi
  echo "==> [3/3] 同步 Nginx 并重载"
  scp -P "${SSH_PORT}" "${NGINX_CONF}" "${REMOTE_HOST}:${REMOTE_NGINX_CONF}"
  ssh "${SSH_OPTS[@]}" "${REMOTE_HOST}" "nginx -t && systemctl reload nginx"
  echo "    Nginx 已重载：${REMOTE_NGINX_CONF}"
else
  echo "==> [3/3] 跳过 Nginx（如需同步请设置 SYNC_NGINX=1）"
fi

echo "==> 完成。请访问 https://readingcoach.jingjiangke.com 验证"
