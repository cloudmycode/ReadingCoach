# ReadingCoach Web 文章录入

孩子账号的网页端工具：登录 → 录入文章 → 查看列表/详情 → 改标题、删文、句子纠错。  
纯静态前端（`console/web`），API 复用现有 Go 服务，**无需单独 Docker**。

```text
https://readingcoach.jingjiangke.com
├── /       → /home/website/readingcoach.jingjiangke.com/www/console（静态）
└── /api/*  → 127.0.0.1:8080（Go，见 server/DEPLOY_DOCKER.md）
```

---

## 本地开发

1. 启动 Go 服务（`http://localhost:8080`）
2. 启动前端：

```bash
cd console/web
npm install
npm run dev
```

打开 `http://localhost:5173`（Vite 会将 `/api` 代理到本地 Go）。

---

## 线上部署

**前置**：Go 服务已跑通；服务器有 Nginx 与 HTTPS；本机 Node.js 18+、可 SSH。

### 首次

```bash
# 服务器创建目录
ssh root@39.105.229.91 "mkdir -p /home/website/readingcoach.jingjiangke.com/www/console"

# 本机构建、发布，并同步 Nginx
cd console
SYNC_NGINX=1 ./scripts/ship.sh
```

Nginx 示例：`server/deploy/nginx.readingcoach.conf`（`/` 静态 + `/api/` 反代）。

### 日常发版

```bash
cd console
./scripts/ship.sh
```

仅改 Nginx：`SYNC_NGINX=1 ./scripts/ship.sh`

| 变量 | 默认 | 说明 |
|------|------|------|
| `REMOTE_HOST` | `root@39.105.229.91` | SSH 目标 |
| `REMOTE_STATIC_DIR` | `/home/website/readingcoach.jingjiangke.com/www/console` | 静态目录 |
| `SYNC_NGINX` | `0` | `1` 时同步并重载 Nginx |

发版前会在服务器备份当前静态目录（`*.backup.时间戳`），可用来回滚。

---

## 常见问题

- **域名仍打到 Go / 404**：Nginx 未更新，执行 `SYNC_NGINX=1 ./scripts/ship.sh`
- **登录失败**：确认 `curl http://127.0.0.1:8080/health` 为 `ok`，且 `/api/` 反代正确
- **录入超时**：拆句较慢，Nginx `proxy_read_timeout` 建议 ≥ 180s
- **刷新 `/articles` 404**：需 SPA 配置 `try_files ... /index.html`

---

## 目录

| 路径 | 说明 |
|------|------|
| `web/` | 前端源码（Vite + Vue 3） |
| `scripts/ship.sh` | 构建并 rsync 到服务器 |
| 服务器静态目录 | `/home/website/readingcoach.jingjiangke.com/www/console` |
| 服务器源码（可选） | `/home/website/readingcoach.jingjiangke.com/ReadingCoach/console/web` |
