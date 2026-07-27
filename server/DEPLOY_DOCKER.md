# ReadingCoach 服务端 Docker 发布说明

三个容器：`readingcoach-mysql`（MySQL 8）、`readingcoach-server`（Go，宿主机 `8080`）、`readingcoach-adminer`（数据库 Web 管理，默认 `8081`）。  
推荐流程：**本机构建镜像 → 传到服务器加载运行**（`./scripts/docker-ship.sh`）。

部署目录：`/home/website/readingcoach.jingjiangke.com/ReadingCoach/server`

---

## 一、首次部署

### 1. 服务器准备

- Linux（amd64），已装 Docker Engine + Compose v2
- 国内服务器请配置镜像加速器，并在 `.env` 里设 `GOPROXY=https://goproxy.cn,direct`

```bash
mkdir -p /home/website/readingcoach.jingjiangke.com
git clone https://github.com/cloudmycode/ReadingCoach.git \
  /home/website/readingcoach.jingjiangke.com/ReadingCoach
cd /home/website/readingcoach.jingjiangke.com/ReadingCoach/server
```

### 2. 配置

```bash
cp .env.example .env
cp config.docker.example.json config.json
```

编辑两份文件，**数据库账号/密码/库名必须一致**：

| config.json | 对应 .env | 注意 |
|---|---|---|
| `MySQLHost` | — | 固定 `mysql` |
| `MySQLPort` | — | 固定 `3306`（容器内端口） |
| `MySQLUser` / `MySQLPass` / `MySQLDB` | `MYSQL_USER` / `MYSQL_PASSWORD` / `MYSQL_DATABASE` | 三者一致 |
| `JWTSecret` | — | `openssl rand -hex 32` |
| `QwenAPIKey` / `QwenVLAPIKey` | — | DashScope Key |
| — | `ADMINER_PORT` | Adminer 宿主机端口，默认 `8081` |

首次启动且数据卷为空时，会自动导入 `db/schema.sql`。已有数据后改该文件**不会**重新导入。

首次或更新 `docker-compose.yml` 后，若需启动 Adminer：

```bash
docker compose up -d
```

### 3. 本机发版上线

本机需：Docker Desktop（含 buildx）、能 SSH 到服务器。在本机 `server/` 目录执行：

```bash
./scripts/docker-ship.sh
```

默认目标：`root@39.105.229.91`，目录见文首。可覆盖：

```bash
REMOTE_HOST=root@你的IP \
REMOTE_DIR=/home/website/readingcoach.jingjiangke.com/ReadingCoach/server \
./scripts/docker-ship.sh
```

脚本：`buildx` 构建 `linux/amd64` → 打包 → `scp` → 服务器 `docker load` → `compose up -d --no-build`。

备选（不推荐网络差的机器）：服务器上 `docker compose up -d --build`。

---

## 二、日常更新

| 变更 | 操作 |
|---|---|
| Go / `go.mod` / `Dockerfile` | 本机 `./scripts/docker-ship.sh` |
| 仅 `config.json` | 服务器改文件后 `docker compose restart server` |
| 仅 `.env` | 改完后 `docker compose up -d` |
| `docker-compose.yml`（如新增 Adminer） | 服务器 `docker compose up -d`（拉镜像并启动新服务） |
| Nginx | 拷到 `/etc/nginx/conf.d/` 后 `nginx -t && systemctl reload nginx` |
| 表结构（已有库） | 先备份，再手工执行迁移 SQL；**不要**指望改 `schema.sql` 自动升级 |

验证：

```bash
docker compose ps
curl -s http://localhost:8080/health          # 期望 ok
curl -s https://readingcoach.jingjiangke.com/api/health
```

### Adminer（数据库 Web 管理）

浏览器打开 `http://服务器IP:8081`（或 `.env` 里 `ADMINER_PORT` 指定的端口）。登录页填写：

| 项 | 值 |
|---|---|
| 系统 | MySQL |
| 服务器 | `mysql` |
| 用户名 | `.env` 的 `MYSQL_USER`（或 `root`） |
| 密码 | 对应账号密码 |
| 数据库 | `MYSQL_DATABASE`（可留空进库后选） |

> Adminer 仅作运维便利，**不要**对公网开放。生产环境建议只在本机/内网访问，或注释 `docker-compose.yml` 里 adminer 的 `ports` 段。

---

## 三、常用命令

```bash
docker compose ps
docker compose logs -f server
docker compose restart server
docker compose stop / start
docker compose down                          # 删容器，卷保留
docker compose exec mysql mysql -u root -p

# 备份
docker compose exec mysql sh -c \
  'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" ReadingCoach' \
  > backup_$(date +%F).sql
```

清库重来（会丢数据）：

```bash
docker compose down
docker volume rm server_mysql-data   # 以 docker volume ls 实际名为准
docker compose up -d
```

不想暴露 MySQL 公网：注释 `docker-compose.yml` 里 mysql 的 `ports`。  
不想暴露 Adminer：注释 adminer 的 `ports`，或仅在需要时 `docker compose up -d adminer`。

---

## 四、Nginx（可选）

```bash
cp deploy/nginx.readingcoach.conf /etc/nginx/conf.d/readingcoach.conf
nginx -t && systemctl reload nginx
```

证书：`/etc/letsencrypt/live/jingjiangke.com/{fullchain,privkey}.pem`  
反代 `127.0.0.1:8080`，`client_max_body_size 20m`，OCR 超时约 `180s`。

---

## 相关文件

| 文件 | 说明 |
|---|---|
| `Dockerfile` / `docker-compose.yml` | 镜像与编排 |
| `.env.example` → `.env` | Compose 环境变量 |
| `config.docker.example.json` → `config.json` | 后端配置（含 AI Key） |
| `db/schema.sql` | 首次空卷自动导入 |
| `scripts/docker-ship.sh` | 本机构建并推送到服务器 |
| `deploy/nginx.readingcoach.conf` | Nginx 示例（Web 静态 + `/api` 反代） |
