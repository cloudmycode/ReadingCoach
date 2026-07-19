#!/bin/bash

# 一键启动脚本
# 步骤：
#   1. 编译 Go 服务（生成 bin/server）
#   2. 建立到远程数据库的 SSH 隧道（本地 13306 -> 远程 127.0.0.1:3306）
#   3. 后台运行服务
#
# 用法：
#   bash scripts/start.sh          # 编译并启动
#   bash scripts/start.sh stop     # 停止服务与隧道

set -e

# 切到 server 目录（脚本位于 server/scripts/ 下）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SERVER_DIR"

# 配置
SSH_HOST="root@45.79.40.29"
LOCAL_DB_PORT=13306
REMOTE_DB="127.0.0.1:3306"
HTTP_PORT=8080
BIN="bin/server"
LOG_DIR="logs"
SERVER_LOG="$LOG_DIR/server.out"

mkdir -p "$LOG_DIR"

# ---------- stop 子命令 ----------
if [ "$1" == "stop" ]; then
  echo "🛑 停止服务与隧道..."
  pkill -f "$BIN" 2>/dev/null && echo "  ✅ 已停止服务" || echo "  ℹ️  服务未运行"
  pkill -f "ssh -N -L ${LOCAL_DB_PORT}:${REMOTE_DB} ${SSH_HOST}" 2>/dev/null \
    && echo "  ✅ 已关闭 SSH 隧道" || echo "  ℹ️  SSH 隧道未运行"
  exit 0
fi

# ---------- 1. 编译 ----------
echo "📦 编译 Go 服务..."
go build -o "$BIN" cmd/server/main.go
chmod +x "$BIN"
echo "  ✅ 编译完成: $BIN"

# ---------- 2. SSH 隧道 ----------
tunnel_up() {
  nc -z 127.0.0.1 "$LOCAL_DB_PORT" >/dev/null 2>&1
}

if tunnel_up; then
  echo "🔌 SSH 隧道已存在（本地 ${LOCAL_DB_PORT} 已可连接），跳过"
else
  echo "🔌 建立 SSH 隧道: ${LOCAL_DB_PORT} -> ${SSH_HOST} (${REMOTE_DB})"
  nohup ssh -N -L "${LOCAL_DB_PORT}:${REMOTE_DB}" "${SSH_HOST}" \
    > "$LOG_DIR/ssh-tunnel.log" 2>&1 &
  disown

  # 等待隧道就绪（最多 15 秒）
  for i in $(seq 1 15); do
    if tunnel_up; then
      echo "  ✅ 隧道就绪"
      break
    fi
    if [ "$i" -eq 15 ]; then
      echo "  ❌ 隧道未能在 15 秒内就绪，请检查 $LOG_DIR/ssh-tunnel.log（可能需要输入密码或密钥）"
      exit 1
    fi
    sleep 1
  done
fi

# ---------- 3. 启动服务 ----------
# 先停掉可能已在运行的旧实例
pkill -f "$BIN" 2>/dev/null && sleep 1 || true

echo "🚀 启动服务（后台）..."
nohup "./$BIN" > "$SERVER_LOG" 2>&1 &
disown

# 健康检查（最多 10 秒）
HEALTH_URL="http://localhost:${HTTP_PORT}/health"
echo "🔍 测试健康检查接口: ${HEALTH_URL}"
for i in $(seq 1 10); do
  BODY="$(curl -s -m 2 "$HEALTH_URL" 2>/dev/null || true)"
  if [ -n "$BODY" ]; then
    echo "  ✅ 服务已启动，${HEALTH_URL} 返回: ${BODY}"
    echo ""
    echo "📋 日志: $SERVER_LOG 与 $LOG_DIR/app.log"
    echo "🛑 停止: bash scripts/start.sh stop"
    exit 0
  fi
  sleep 1
done

echo "  ❌ 服务启动失败，请查看日志: $LOG_DIR/app.log 与 $SERVER_LOG"
exit 1
