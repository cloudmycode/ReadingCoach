#!/usr/bin/env bash

# 在服务器上把 readingcoach-server 安装为 systemd 服务。
# 需在目标服务器上以 root（或 sudo）执行。
#
# 可用环境变量覆盖默认配置：
#   DEPLOY_DIR    部署目录，默认 /home/www/websites/readingcoach.jingjiangke.com
#   SERVICE_USER  服务运行用户，默认 root

set -euo pipefail

APP_NAME="readingcoach-server"
DEPLOY_DIR="${DEPLOY_DIR:-/home/www/websites/readingcoach.jingjiangke.com}"
SERVICE_USER="${SERVICE_USER:-root}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

BIN_PATH="${DEPLOY_DIR}/${APP_NAME}"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "未找到可执行文件 ${BIN_PATH}，请先用本机的 deploy.sh 发布二进制" >&2
  exit 1
fi

mkdir -p "${DEPLOY_DIR}/logs" "${DEPLOY_DIR}/attachments"

cat > /tmp/${APP_NAME}.service <<EOF
[Unit]
Description=ReadingCoach Go Server
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${DEPLOY_DIR}
ExecStart=${BIN_PATH}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/${APP_NAME}.service "${SERVICE_FILE}"
sudo systemctl daemon-reload
sudo systemctl enable "${APP_NAME}"
sudo systemctl restart "${APP_NAME}"
sudo systemctl status "${APP_NAME}" --no-pager
