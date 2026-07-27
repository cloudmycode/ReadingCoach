# ReadingCoach Web 文章录入 — 线上部署说明

纯静态前端（Vite 构建产物），与现有 Go API **共用域名** `readingcoach.jingjiangke.com`：

- `/` → 网页静态文件
- `/api/*` → 反代到宿主机 `127.0.0.1:8080`（现有 `readingcoach-server` 容器）

**不需要**为 console 单独起 Docker 容器。

---

## 一、架构

```text
浏览器
  └── https://readingcoach.jingjiangke.com
        ├── /              → /var/www/readingcoach-console（静态）
        └── /api/*         → 127.0.0.1:8080（Go 服务，已有）
```

与 `server/DEPLOY_DOCKER.md` 的关系：

| 组件 | 部署方式 | 文档 |
|------|----------|------|
| Go API + MySQL | Docker Compose | `server/DEPLOY_DOCKER.md` |
| Web 文章录入 | 静态文件 + Nginx | 本文档 |
| Nginx | 宿主机 | `server/deploy/nginx.readingcoach.conf` |

---

## 二、前置条件

### 服务器

1. Go 服务已按 `server/DEPLOY_DOCKER.md` 跑通，`curl http://127.0.0.1:8080/health` 返回 `ok`
2. 已安装 **Nginx**，域名 `readingcoach.jingjiangke.com` 已解析到该机器
3. HTTPS 证书已配置（示例路径：`/etc/letsencrypt/live/jingjiangke.com/`）
4. 静态目录可写，默认 `/var/www/readingcoach-console`

### 本机

1. Node.js 18+ 与 npm
2. 能 SSH 到服务器（默认 `root@39.105.229.91`）
3. 仓库已包含 `console/web/package-lock.json`（脚本使用 `npm ci`）

---

## 三、首次部署

### 1. 服务器：创建静态目录

```bash
ssh root@39.105.229.91
mkdir -p /var/www/readingcoach-console
chown -R root:root /var/www/readingcoach-console
```

### 2. 服务器：更新 Nginx（只需一次）

将仓库中的 Nginx 配置拷到服务器并重载：

```bash
# 在本机仓库根目录执行
scp server/deploy/nginx.readingcoach.conf \
  root@39.105.229.91:/etc/nginx/conf.d/readingcoach.conf

ssh root@39.105.229.91 "nginx -t && systemctl reload nginx"
```

或发版时带上 Nginx 同步（见下文 `SYNC_NGINX=1`）。

配置要点：

- `location /api/` → `proxy_pass http://127.0.0.1:8080`（AI/OCR 超时 180s）
- `location /` → `root /var/www/readingcoach-console` + SPA `try_files`
- `client_max_body_size 20m`（与 App 拍照 OCR 一致）

### 3. 本机：构建并发布静态资源

在仓库 `console/` 目录执行：

```bash
./scripts/ship.sh
```

默认行为：本机 `npm ci && npm run build` → `rsync` 同步 `dist/` 到服务器 `/var/www/readingcoach-console/`。

可覆盖环境变量：

```bash
REMOTE_HOST=root@你的IP \
REMOTE_STATIC_DIR=/var/www/readingcoach-console \
SSH_PORT=22 \
./scripts/ship.sh
```

首次建议同时更新 Nginx：

```bash
SYNC_NGINX=1 ./scripts/ship.sh
```

### 4. 验证

```bash
# 首页（应返回 HTML，而非 Go 404）
curl -sI https://readingcoach.jingjiangke.com/ | head -n 5

# API 仍可用
curl -s https://readingcoach.jingjiangke.com/api/health
# 若 /api/health 未暴露，可测：
curl -s http://服务器IP:8080/health
```

浏览器打开 `https://readingcoach.jingjiangke.com`，用孩子学习账号登录，试录入一篇文章。

---

## 四、日常更新

| 变更 | 操作 |
|------|------|
| 仅前端页面/逻辑 | 本机 `console/scripts/ship.sh` |
| 仅 Nginx 配置 | `SYNC_NGINX=1 ./scripts/ship.sh` 或手工 scp + `nginx -t && reload` |
| 仅 Go 后端 | `server/scripts/docker-ship.sh`（与 console 无关） |
| 前后端同时发版 | 先 `docker-ship.sh`，再 `console/scripts/ship.sh` |

发版后建议硬刷新浏览器（`Cmd+Shift+R`），避免旧 JS 缓存。

---

## 五、脚本说明

`console/scripts/ship.sh` 步骤：

1. 在 `console/web` 执行 `npm ci`
2. 执行 `npm run build`，产出 `dist/`
3. `rsync -avz --delete` 同步到 `REMOTE_STATIC_DIR`
4. 若 `SYNC_NGINX=1`：上传 `server/deploy/nginx.readingcoach.conf` 并 `nginx -t && reload`

环境变量：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `REMOTE_HOST` | `root@39.105.229.91` | SSH 目标 |
| `REMOTE_STATIC_DIR` | `/var/www/readingcoach-console` | 服务器静态根目录 |
| `SSH_PORT` | `22` | SSH 端口 |
| `SYNC_NGINX` | `0` | 设为 `1` 时同步并重载 Nginx |

---

## 六、回滚

静态发版保留了 rsync 前的目录快照（脚本在服务器生成 `dist.backup.<时间戳>`）。回滚示例：

```bash
ssh root@39.105.229.91
cd /var/www/readingcoach-console
# 将下面目录名换成 ls /var/www/ 里实际的 backup 目录
rsync -a --delete /var/www/readingcoach-console.backup.YYYYMMDD-HHMMSS/ ./
```

或直接重新 checkout 旧版本代码后再次执行 `./scripts/ship.sh`。

---

## 七、常见问题

### 打开域名仍是 Go 接口或 404

Nginx 未切到静态配置。检查 `/etc/nginx/conf.d/readingcoach.conf` 是否含 `root /var/www/readingcoach-console`，并 `nginx -t && systemctl reload nginx`。

### 页面能开，登录报网络错误

1. 确认 Go 容器在跑：`docker compose ps`（在 server 部署目录）
2. 确认 `curl http://127.0.0.1:8080/health` 为 `ok`
3. 确认 Nginx 中 `location /api/` 反代正确

### 录入文章一直转圈后超时

拆句翻译较慢，Nginx `proxy_read_timeout` 需 ≥ 120s（示例配置为 180s）。若仍超时，检查 DashScope Key 与 server 日志：`docker compose logs -f server`。

### 刷新子路径（如 `/articles`）404

SPA 需 `try_files $uri $uri/ /index.html;`，见 `server/deploy/nginx.readingcoach.conf`。

---

## 相关文件

| 文件 | 说明 |
|------|------|
| `console/web/` | 前端源码 |
| `console/scripts/ship.sh` | 本机构建并发布到服务器 |
| `server/deploy/nginx.readingcoach.conf` | 同域 Nginx 示例（静态 + API） |
| `server/DEPLOY_DOCKER.md` | Go 服务 Docker 部署 |
