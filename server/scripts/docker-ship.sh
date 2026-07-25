#!/usr/bin/env bash

# 本机（Mac/ARM）构建 amd64 后端镜像，打包传到服务器并加载启动。
# 对应部署文档「方案 C：本机构建 → save → scp → load」。
#
# 用法：
#   ./scripts/docker-ship.sh
#
# 可用环境变量覆盖默认值：
#   REMOTE_HOST   远程 SSH 目标，默认 root@39.105.229.91
#   REMOTE_DIR    服务器部署目录（含 docker-compose.yml），
#                 默认 /home/website/readingcoach.jingjiangke.com/server
#   SSH_PORT      SSH 端口，默认 22
#   IMAGE         镜像名:标签，默认 readingcoach-server:latest
#
# 前置条件：
#   - 本机已装 Docker 且支持 buildx
#   - 服务器已装 Docker、配好镜像加速器（用于拉取 mysql:8.0）
#   - 服务器 REMOTE_DIR 下已准备好 .env 与 config.json，且已有 docker-compose.yml、db/schema.sql

set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-root@39.105.229.91}"
REMOTE_DIR="${REMOTE_DIR:-/home/website/readingcoach.jingjiangke.com/server}"
SSH_PORT="${SSH_PORT:-22}"
IMAGE="${IMAGE:-readingcoach-server:latest}"
PLATFORM="linux/amd64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_TAR="/tmp/readingcoach-server.tar.gz"
REMOTE_TAR="/tmp/readingcoach-server.tar.gz"

echo "==> [1/4] buildx 构建 ${PLATFORM} 镜像：${IMAGE}"
docker buildx build \
  --platform "${PLATFORM}" \
  --build-arg GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" \
  -t "${IMAGE}" \
  --load \
  "${SERVER_DIR}"

echo "==> [2/4] 导出并压缩镜像到 ${LOCAL_TAR}"
docker save "${IMAGE}" | gzip > "${LOCAL_TAR}"
echo "    镜像包大小：$(du -h "${LOCAL_TAR}" | cut -f1)"

echo "==> [3/4] 传输到 ${REMOTE_HOST}:${REMOTE_TAR}"
scp -P "${SSH_PORT}" "${LOCAL_TAR}" "${REMOTE_HOST}:${REMOTE_TAR}"

echo "==> [4/4] 服务器加载镜像并启动容器"
ssh -p "${SSH_PORT}" "${REMOTE_HOST}" "
  set -e
  echo '    -> docker load'
  gunzip -c '${REMOTE_TAR}' | docker load
  cd '${REMOTE_DIR}'
  echo '    -> docker compose up -d --no-build'
  docker compose up -d --no-build
  rm -f '${REMOTE_TAR}'
  docker compose ps
"

rm -f "${LOCAL_TAR}"
echo "==> 完成。可用 'ssh ${REMOTE_HOST} \"cd ${REMOTE_DIR} && docker compose logs -f server\"' 查看日志"
