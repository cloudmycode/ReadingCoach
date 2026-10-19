#!/usr/bin/env bash

# 本机构建 amd64 镜像，更新已有部署的后端，不覆盖服务器配置或操作数据库。
# 用法：./scripts/docker-ship.sh
# 可覆盖：REMOTE_HOST、REMOTE_DIR、SSH_PORT、IMAGE、GOPROXY。
# 首次部署须先按 DEPLOY_DOCKER.md 配置并启动 MySQL。
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-root@39.105.229.91}"
REMOTE_DIR="${REMOTE_DIR:-/home/website/readingcoach.jingjiangke.com/ReadingCoach/server}"
SSH_PORT="${SSH_PORT:-22}"
IMAGE="${IMAGE:-readingcoach-server:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 镜像名会写入临时 Compose 覆盖文件，只允许镜像引用字符。
if [[ ! "$IMAGE" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/:@-]*$ ]]; then
  echo "无效镜像名称：${IMAGE}" >&2
  exit 1
fi

# SSH 的远端命令经过 shell 解析，逐个引用参数以支持路径中的空格等字符。
remote() {
  local command
  printf -v command '%q ' bash -s -- "$@"
  ssh -p "$SSH_PORT" "$REMOTE_HOST" "$command"
}

echo "==> [1/5] 检查服务器部署环境（保留现有配置）"
remote "$REMOTE_DIR" <<'REMOTE'
set -euo pipefail
cd "$1"
for file in docker-compose.yml .env config.json; do
  if [[ ! -s "$file" || ! -f "$file" ]]; then
    echo "缺少部署文件：$file；请先完成首次部署配置。" >&2
    exit 1
  fi
done
docker info >/dev/null
docker compose config --quiet
REMOTE

LOCAL_TMP="$(mktemp -d /tmp/readingcoach-ship.XXXXXXXX)"
trap 'rm -rf "$LOCAL_TMP"' EXIT
LOCAL_TAR="${LOCAL_TMP}/server.tar.gz"
REMOTE_TAR="/tmp/${LOCAL_TMP##*/}.tar.gz"

echo "==> [2/5] 构建 linux/amd64 镜像：${IMAGE}"
docker buildx build \
  --platform linux/amd64 \
  --build-arg GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" \
  -t "$IMAGE" --load "$SERVER_DIR"

echo "==> [3/5] 打包并传输镜像"
docker save "$IMAGE" | gzip > "$LOCAL_TAR"
scp -P "$SSH_PORT" "$LOCAL_TAR" "${REMOTE_HOST}:${REMOTE_TAR}"

echo "==> [4/5] 仅更新后端容器"
remote "$REMOTE_DIR" "$REMOTE_TAR" "$IMAGE" <<'REMOTE'
set -euo pipefail
cd "$1"
archive="$2"
override="$(mktemp /tmp/readingcoach-compose.XXXXXXXX)"
trap 'rm -f "$archive" "$override"' EXIT
gunzip -c "$archive" | docker load
# 临时覆盖镜像名，支持 IMAGE 自定义；不改服务器 docker-compose.yml 或 .env。
printf 'services:\n  server:\n    image: "%s"\n' "$3" > "$override"
compose() { docker compose -f docker-compose.yml -f "$override" "$@"; }
compose up -d --no-build --no-deps --pull never --force-recreate --timeout 30 server

echo "==> [5/5] 等待服务启动及数据库连通检查（最多 120 秒）"
deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
  if compose exec -T server wget -qO- -T 5 http://localhost:8080/api/health >/dev/null 2>&1; then
    compose ps server
    echo "==> 发布完成，服务及数据库检查通过。"
    exit 0
  fi
  sleep 2
done
echo "服务健康检查未通过，发布失败；请在部署目录执行 docker compose logs --tail=100 server 排查。" >&2
exit 1
REMOTE
