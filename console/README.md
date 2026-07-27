# ReadingCoach Web 文章录入

孩子账号的网页端工具：登录 → 录入文章 → 查看列表/详情 → 改标题、删文、句子纠错。  
纯静态前端（`console/web`），API 复用现有 Go 服务，**无需单独 Docker**。

```text
https://readingcoach.jingjiangke.com
├── /       → /home/website/readingcoach.jingjiangke.com/www/console（静态）
└── /api/*  → 127.0.0.1:8080（Go，见 server/DEPLOY_DOCKER.md）
```

- [需求说明书](./REQUIREMENTS.md) — 范围、接口复用、页面与分期

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

### 1. 配置 Nginx（首次或改配置时）

仓库示例：`server/deploy/nginx.readingcoach.conf`（`/` 静态 + `/api/` 反代）。

在**服务器**执行：

```bash
# 创建静态目录
mkdir -p /home/website/readingcoach.jingjiangke.com/www/console

# 拷贝配置（路径按你服务器上的仓库位置调整）
cp /home/website/readingcoach.jingjiangke.com/ReadingCoach/server/deploy/nginx.readingcoach.conf \
   /etc/nginx/conf.d/readingcoach.conf

# 检查并重载
nginx -t && systemctl reload nginx
```

也可从本机拷过去：

```bash
scp server/deploy/nginx.readingcoach.conf \
  root@39.105.229.91:/etc/nginx/conf.d/readingcoach.conf
ssh root@39.105.229.91 "nginx -t && systemctl reload nginx"
```

配置要点：

| 项 | 值 |
|---|---|
| 静态 root | `/home/website/readingcoach.jingjiangke.com/www/console` |
| API 反代 | `location /api/` → `http://127.0.0.1:8080` |
| SPA | `try_files $uri $uri/ /index.html;` |
| 超时 | OCR/拆句建议 `proxy_read_timeout 180s` |
| 上传 | `client_max_body_size 20m` |

证书示例：`/etc/letsencrypt/live/jingjiangke.com/{fullchain,privkey}.pem`

### 2. 发布前端静态文件

```bash
# 服务器先确保目录存在（首次）
ssh root@39.105.229.91 "mkdir -p /home/website/readingcoach.jingjiangke.com/www/console"

# 本机构建并 rsync
cd console
./scripts/ship.sh
```

| 变量 | 默认 | 说明 |
|------|------|------|
| `REMOTE_HOST` | `root@39.105.229.91` | SSH 目标 |
| `REMOTE_STATIC_DIR` | `/home/website/readingcoach.jingjiangke.com/www/console` | 静态目录 |

发版前会在服务器备份当前静态目录（`*.backup.时间戳`），可用来回滚。  
**发版脚本只同步静态文件，不改 Nginx。**

---

## 常见问题

- **域名仍打到 Go / 404**：检查 `/etc/nginx/conf.d/readingcoach.conf` 的 `root` 是否指向 `www/console`，然后 `nginx -t && systemctl reload nginx`
- **登录失败**：确认 `curl http://127.0.0.1:8080/health` 为 `ok`，且 `/api/` 反代正确
- **录入超时**：拆句较慢，Nginx `proxy_read_timeout` 建议 ≥ 180s
- **刷新 `/articles` 404**：需 SPA 配置 `try_files ... /index.html`

---

## 目录

| 路径 | 说明 |
|------|------|
| `web/` | 前端源码（Vite + Vue 3） |
| `scripts/ship.sh` | 构建并 rsync 到服务器（不含 Nginx） |
| `REQUIREMENTS.md` | 需求与接口说明 |
| `../server/deploy/nginx.readingcoach.conf` | Nginx 配置示例 |
| 服务器静态目录 | `/home/website/readingcoach.jingjiangke.com/www/console` |
| 服务器源码（可选） | `/home/website/readingcoach.jingjiangke.com/ReadingCoach/console/web` |
