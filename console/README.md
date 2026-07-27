# ReadingCoach Web 文章录入

本目录用于存放网页端快速录入文章的需求、设计与前端工程。

## 文档

- [需求说明书](./REQUIREMENTS.md) — 范围、接口复用、页面与分期
- [线上部署说明](./DEPLOY.md) — Nginx、发版流程与验证

## 前端工程

目录：`console/web`（Vite + Vue 3 + TypeScript）

### 本地开发

1. 启动 Go 服务（默认 `http://localhost:8080`）
2. 安装依赖并启动前端：

```bash
cd console/web
npm install
npm run dev
```

浏览器打开 `http://localhost:5173`。开发模式下 Vite 会把 `/api` 代理到本地 Go 服务。

### 构建与线上部署

**推荐**：在 `console/` 目录执行一键发版脚本（详见 [DEPLOY.md](./DEPLOY.md)）：

```bash
cd console
./scripts/ship.sh
```

首次部署或 Nginx 有变更时：

```bash
SYNC_NGINX=1 ./scripts/ship.sh
```

手动构建：

```bash
cd console/web
npm ci && npm run build
```

产物在 `dist/`，由脚本同步到服务器 `/var/www/readingcoach-console`。纯静态页面，无需单独 Docker。

## 现状说明

- iOS App：孩子端（阅读、查词、生词复习）
- Go 服务端：现有 API 按「当前登录用户」隔离数据
- 本 Web 端：**用孩子账号登录，录入文章、查看列表与内容、维护文章（改标题/删文/句子纠错）**；不做 OCR、家长绑定与学习看板

## 建议阅读顺序

1. 阅读 [REQUIREMENTS.md](./REQUIREMENTS.md) 的「功能范围」与「附录：接口速查」
2. 在 `console/web` 开发：登录 + 录入 + 列表 + 详情 + 改标题 + 删文章 + 句子纠错
