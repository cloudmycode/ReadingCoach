# ReadingCoach 服务端 Docker 发布说明

三个容器：`readingcoach-mysql`（MySQL 8）、`readingcoach-server`（Go，宿主机 `8080`）、`readingcoach-adminer`（数据库 Web 管理，默认 `8081`）。  
推荐流程：**本机构建镜像 → 传到服务器加载运行**（`./scripts/docker-ship.sh`）。

部署目录：`/home/website/readingcoach.jingjiangke.com/ReadingCoach/server`

站点根目录建议结构：

```text
/home/website/readingcoach.jingjiangke.com/
├── ReadingCoach/          # git clone，含 server/ 与 console/web 源码
│   ├── server/            # Docker 后端部署
│   └── console/web/       # 前端源码（构建在本机）
└── www/console/           # 前端线上静态文件（Nginx root）
```

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

首次部署先启动数据库（空数据卷会导入基础表），等待状态变为 healthy：

```bash
docker compose up -d mysql
docker compose ps mysql
# 如需数据库管理页面，再启动：docker compose up -d adminer
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

脚本先检查服务器现有 `docker-compose.yml`、`.env`、`config.json`，然后构建 `linux/amd64` 镜像、打包传输、加载镜像，只重建 `server` 容器。不会启动或重建 MySQL / Adminer，不上传配置、不导入 SQL、不清理数据卷。数据库需要已在运行。

发布后最多等待 120 秒，通过容器内 `/api/health` 检查服务和数据库连通性；失败返回非零状态，不报告发布成功。该检查不调用千问，不能代替真实出题和批改验收。可用 `IMAGE=readingcoach-server:版本号` 指定镜像标签，脚本以临时 Compose 文件应用，不修改服务器原文件。

### 4. 本次小测与奖励功能的配置和建表

- **千问无需新增配置**：文章与小测共用服务器现有 `config.json` 中的 `QwenAPIKey`、`QwenAPIURL`、`QwenModel`。没有 `QuizAI` 或单独的 DeepSeek Key；部署脚本不读取、生成或覆盖这些密钥。
- **新增表由应用启动创建**：`20260920_add_reading_challenges.sql` 嵌入 Go 程序，连接现有数据库后执行 `CREATE TABLE IF NOT EXISTS`，失败则停止启动。数据库账号须有建表权限，不需单独上传或执行这份 SQL。
- **不是通用迁移器**：不会扫描并执行 `db/migrations/` 下的所有文件，也不创建数据库或重建已有业务表；首次空库仍需 `db/schema.sql`。其他迁移和后续已有表字段变更须按各自说明执行。

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
| 本次阅读小测与奖励新增表 | 应用启动自动执行嵌入的幂等建表迁移，无需脚本执行 SQL |
| 其他表结构迁移（已有库） | 按对应迁移说明处理；不会自动扫描 migrations，改 `schema.sql` 也不会升级已有库 |

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
| `deploy/nginx.readingcoach.conf` | Nginx 示例（`/` → `www/console`，`/api/` 反代） |

前端发版见仓库 `console/README.md`（本机 `console/scripts/ship.sh`）。
