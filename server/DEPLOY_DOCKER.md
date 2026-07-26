# ReadingCoach 服务端 Docker 部署操作手册

本手册指导你用 Docker 部署两个容器：

- `readingcoach-mysql`：MySQL 8.0 数据库（首次启动自动导入结构+数据）
- `readingcoach-server`：Go 后端服务（对外暴露 `8080` 端口）

两个容器在同一自定义网络内，后端用服务名 `mysql` 连接数据库。

---

## 一、前置准备

### 1. 服务器要求

- 一台 Linux 服务器（x86_64 / amd64）
- 已安装 Docker Engine 20.10+ 与 Docker Compose v2

检查是否已安装：

```bash
docker --version
docker compose version
```

#### 方式 A：海外服务器 / 网络通畅（Ubuntu/Debian）

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
```

#### 方式 B：国内服务器（阿里云 / 腾讯云等，CentOS / Alibaba Cloud Linux）

> 国内访问 `get.docker.com`（CloudFront）会在 TLS 阶段被阻断，报
> `curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL`。此时**不要**用官方一键脚本，改用阿里云镜像源：

```bash
# 1. 装工具
yum install -y yum-utils

# 2. 用阿里云的 docker-ce 源
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

# 3. 安装 Docker 与 compose 插件
yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 4. 启动并开机自启
systemctl enable --now docker
```

> 若为 **Alibaba Cloud Linux 3 / CentOS Stream 9**，`$releasever` 可能导致源 404，
> 固定成 8 即可：
> ```bash
> sed -i 's|\$releasever|8|g' /etc/yum.repos.d/docker-ce.repo
> yum clean all && yum makecache
> yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
> ```

#### 配置镜像加速器（国内必做，否则拉不到 mysql/golang 镜像）

Docker Hub 在国内基本无法直连，务必配置加速器：

```bash
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
EOF

systemctl daemon-reload
systemctl restart docker
docker pull hello-world   # 验证能拉镜像
```

> 阿里云每个账号有专属加速地址 `https://<你的ID>.mirror.aliyuncs.com`
> （控制台「容器镜像服务 → 镜像加速器」可查），加到 `registry-mirrors` 首位最稳。
>
> 国内服务器还要在 `server/.env` 里把 `GOPROXY` 改成 `https://goproxy.cn,direct`，
> 否则构建后端镜像时拉 Go 依赖会很慢或失败。

> 之后命令若提示权限不足，可加 `sudo`，或把当前用户加入 docker 组：
> `sudo usermod -aG docker $USER`（需重新登录生效）。

### 2. 获取代码

本项目部署目录约定为 `/home/website/readingcoach.jingjiangke.com/ReadingCoach`。
把仓库克隆到该目录（server 端代码位于仓库的 `server/` 子目录）：

```bash
mkdir -p /home/website/readingcoach.jingjiangke.com
git clone https://github.com/cloudmycode/ReadingCoach.git /home/website/readingcoach.jingjiangke.com/ReadingCoach
cd /home/website/readingcoach.jingjiangke.com/ReadingCoach/server
```

> 后续所有命令都在 `/home/website/readingcoach.jingjiangke.com/ReadingCoach/server` 目录下执行。
> 该目录里有 `Dockerfile`、`docker-compose.yml`、`db/schema.sql` 等部署所需文件。
>
> 若代码已经在服务器上，直接 `cd /home/website/readingcoach.jingjiangke.com/ReadingCoach/server` 即可；
> 更新代码用 `git pull`。

---

## 二、准备配置文件（关键步骤）

需要准备两个文件：`.env`（给 Docker Compose 用）和 `config.json`（给后端服务用）。
**两个文件中的数据库用户名、密码、库名必须完全一致，否则后端连不上数据库。**

### 1. 生成 `.env`

```bash
cp .env.example .env
```

编辑 `.env`，修改以下项（示例）：

```dotenv
MYSQL_ROOT_PASSWORD=一个强口令-root
MYSQL_DATABASE=ReadingCoach
MYSQL_USER=readingcoach
MYSQL_PASSWORD=一个强口令-app
MYSQL_PORT=3306
SERVER_PORT=8080
TZ=Asia/Shanghai
GOPROXY=https://proxy.golang.org,direct
```

字段说明：

| 变量 | 说明 |
|---|---|
| `MYSQL_ROOT_PASSWORD` | MySQL root 密码（仅容器内部/运维用） |
| `MYSQL_DATABASE` | 要创建的数据库名 |
| `MYSQL_USER` / `MYSQL_PASSWORD` | 后端服务连库用的普通账号 |
| `MYSQL_PORT` | 宿主机映射端口（供外部工具直连；不需要可关闭，见下文） |
| `SERVER_PORT` | 后端对宿主机暴露的端口 |
| `TZ` | 时区，保持 `Asia/Shanghai` |
| `GOPROXY` | Go 依赖代理，国内服务器可改 `https://goproxy.cn,direct` |

### 2. 生成 `config.json`

```bash
cp config.docker.example.json config.json
```

编辑 `config.json`，重点修改：

```json
{
  "HTTPAddr": ":8080",
  "MySQLHost": "mysql",
  "MySQLPort": "3306",
  "MySQLUser": "readingcoach",
  "MySQLPass": "一个强口令-app",
  "MySQLDB": "ReadingCoach",
  "JWTSecret": "一段足够长的随机字符串",
  "LogsDir": "./logs",
  "AttachmentsDir": "./attachments",
  "QwenAPIKey": "填入你的 DashScope Key",
  "QwenAPIURL": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
  "QwenModel": "qwen-plus",
  "QwenVLAPIKey": "填入你的 DashScope Key（可与文本 Key 相同）",
  "QwenVLAPIURL": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
  "QwenVLModel": "qwen-vl-ocr",
  "TTSVoice": "en-US-JennyNeural"
}
```

一致性检查（务必核对）：

| config.json | 必须等于 .env |
|---|---|
| `MySQLHost` | 固定为 `mysql`（容器服务名，不要改成 IP） |
| `MySQLPort` | 固定为 `3306`（容器内部端口，不是 `MYSQL_PORT`） |
| `MySQLUser` | `MYSQL_USER` |
| `MySQLPass` | `MYSQL_PASSWORD` |
| `MySQLDB` | `MYSQL_DATABASE` |

> 生成一段随机 `JWTSecret` 可用：`openssl rand -hex 32`

---

## 三、准备数据库初始数据

MySQL 容器**首次启动**（数据卷为空）时，会自动导入 `server/db/schema.sql`。

- 直接使用仓库自带的 `db/schema.sql`：会导入其中的结构与示例数据（导出时间见文件头部注释）。
- 想用**生产库的最新数据**：先从现有数据库导出，替换该文件，再首次启动：

```bash
# 在旧服务器上导出（示例）
mysqldump -u root -p --databases db_words --no-create-db > dump.sql
# 将 dump.sql 内容整理为不含 CREATE DATABASE/USE 的结构+数据，覆盖到 server/db/schema.sql
```

> ⚠️ 自动导入只在数据卷为空时发生一次。若容器已经建过卷，之后再改 `schema.sql` 不会重新导入（需清空卷，见第七节）。

---

## 四、构建并启动

有两种方式，任选其一。

### 方式一（推荐，本项目采用）：本机构建镜像 → 传到服务器加载运行

服务器不安装 Go / 不编译，只负责运行。构建在本机（Mac）完成后打包传过去。

> ⚠️ Mac 多为 Apple Silicon(ARM64)，服务器是 amd64，脚本内部用
> `docker buildx --platform linux/amd64` 交叉编译，避免 `exec format error`。

前置条件：
- 服务器已完成第一节的 Docker 安装与**镜像加速器**配置（用于拉取 `mysql:8.0`）
- 服务器 `server` 目录下已准备好 `.env`、`config.json`（第二节），
  以及仓库自带的 `docker-compose.yml`、`db/schema.sql`
- 本机已装 Docker（含 buildx）并能 SSH 到服务器

在**本机**项目的 `server/` 目录执行：

```bash
./scripts/docker-ship.sh
```

脚本会依次：`buildx` 构建 amd64 镜像 → `docker save | gzip` 打包 → `scp` 传到服务器 →
服务器 `docker load` → `docker compose up -d --no-build` 启动。

可用环境变量覆盖默认值（默认目标 `root@39.105.229.91`、目录 `/home/website/readingcoach.jingjiangke.com/ReadingCoach/server`）：

```bash
REMOTE_HOST=root@你的IP \
REMOTE_DIR=/home/website/readingcoach.jingjiangke.com/ReadingCoach/server \
SSH_PORT=22 \
./scripts/docker-ship.sh
```

> 日常改代码后如何发版，见**第六节**。

### 方式二（备选）：直接在服务器上构建

在**服务器** `server/` 目录执行：

```bash
docker compose up -d --build
```

首次会编译 Go 镜像 + 拉取 MySQL 镜像 + 导入数据，耗时数分钟属正常。
此方式要求服务器能通过 `goproxy.cn` 拉取 Go 依赖（`.env` 里已设 `GOPROXY`）。

---

## 五、验证部署

### 1. 查看容器状态

```bash
docker compose ps
```

期望两个容器都是 `running`，其中 mysql 显示 `healthy`。

### 2. 查看日志

```bash
docker compose logs -f server     # 后端日志（Ctrl+C 退出跟随）
docker compose logs -f mysql      # 数据库日志
```

### 3. 健康检查接口

```bash
curl http://localhost:8080/health
# 期望返回：ok
```

### 4. 数据库连通性（带 DB Ping 的检查）

```bash
curl http://localhost:8080/api/health
```

---

## 六、更新后端代码到服务器

改完 Go 代码（或 `Dockerfile` / 依赖）后，需要**重新构建镜像并替换服务器上的后端容器**。MySQL 数据卷、附件卷、日志卷都会保留，一般不用动数据库。

本项目推荐用**方式 A**（本机构建再推上去）；服务器网络差、不便拉 Go 依赖时不要用方式 B。

### 方式 A（推荐）：本机一键推送

适用：日常改 `server/` 下的 Go 代码、依赖、`Dockerfile`。

#### 1. 确认本机环境

- 本机 Docker Desktop 已启动（含 buildx）
- 能 SSH 到服务器（默认 `root@39.105.229.91`）
- 本地改动已保存；建议先提交/推送到 Git，方便回溯（脚本本身不依赖 Git）

#### 2. 在本机执行发版脚本

```bash
cd /path/to/ReadingCoach/server
./scripts/docker-ship.sh
```

脚本会自动完成：

1. `docker buildx` 按 `linux/amd64` 构建 `readingcoach-server:latest`
2. `docker save | gzip` 打包镜像
3. `scp` 传到服务器 `/tmp/readingcoach-server.tar.gz`
4. 服务器 `docker load` + `docker compose up -d --no-build` 滚动替换后端容器

自定义目标主机/目录时：

```bash
REMOTE_HOST=root@你的IP \
REMOTE_DIR=/home/website/readingcoach.jingjiangke.com/ReadingCoach/server \
SSH_PORT=22 \
./scripts/docker-ship.sh
```

#### 3. 验证更新是否成功

```bash
# 本机或服务器上均可
ssh root@39.105.229.91 'cd /home/website/readingcoach.jingjiangke.com/ReadingCoach/server && docker compose ps'
ssh root@39.105.229.91 'cd /home/website/readingcoach.jingjiangke.com/ReadingCoach/server && docker compose logs --tail=50 server'
curl -s https://readingcoach.jingjiangke.com/api/health
```

期望：`readingcoach-server` 为 `running`（最好 `healthy`），健康接口返回正常。

> 耗时主要在本机构建与传镜像（通常几分钟）。中间短暂不可用属正常；MySQL 容器不会被重建。

---

### 方式 B（备选）：在服务器上拉代码并重建

适用：本机不便构建，且服务器能顺利拉 Go 依赖（`GOPROXY` 已配好）。

```bash
ssh root@39.105.229.91
cd /home/website/readingcoach.jingjiangke.com/ReadingCoach
git pull
cd server
docker compose up -d --build
docker compose ps
curl -s http://localhost:8080/api/health
```

> `git pull` 不会覆盖服务器上的 `.env`、`config.json`（它们通常不在仓库里）。若改过 `docker-compose.yml`，重建后会一并生效。

---

### 按变更类型选择操作

| 你改了什么 | 怎么更新 |
|---|---|
| Go 代码 / `go.mod` / `Dockerfile` | 方式 A 或 B（必须重建镜像） |
| 仅 `config.json`（Key、模型名等） | **不用重建镜像**，在服务器改文件后执行 `docker compose restart server` |
| 仅 `.env`（端口、密码等） | 改完后 `docker compose up -d`（必要时再 `restart`） |
| 仅 Nginx 配置 `deploy/nginx.readingcoach.conf` | 拷到 `/etc/nginx/conf.d/` 后 `nginx -t && systemctl reload nginx` |
| `db/schema.sql`（表结构） | **不会**自动应用到已有库；需手工在库里执行 `ALTER`/`CREATE`，或走第八节「清库重来」（会丢数据） |

#### 只改配置示例

```bash
ssh root@39.105.229.91
cd /home/website/readingcoach.jingjiangke.com/ReadingCoach/server
# 编辑 config.json 后：
docker compose restart server
curl -s http://localhost:8080/api/health
```

#### 库表有变更时（已有生产数据）

不要指望改 `schema.sql` 再重启就会升级。正确做法：

1. 先备份：`docker compose exec mysql sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" ReadingCoach' > backup_$(date +%F).sql`
2. 在 MySQL 里执行迁移 SQL（`docker compose exec mysql mysql -u root -p ReadingCoach < migrate.sql`）
3. 再按方式 A/B 发版后端（若代码依赖新表结构）

---

## 七、日常运维命令

```bash
# 停止（保留数据）
docker compose stop

# 启动
docker compose start

# 重启后端（不影响数据库）
docker compose restart server

# 更新后端：见第六节（推荐本机 ./scripts/docker-ship.sh）

# 停止并删除容器（数据卷保留）
docker compose down

# 进入 MySQL 命令行
docker compose exec mysql mysql -u root -p

# 备份数据库到宿主机文件
docker compose exec mysql sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" ReadingCoach' > backup_$(date +%F).sql
```

数据存放位置（Docker 命名卷，不会随容器删除而丢失）：

- `mysql-data`：数据库文件
- `server-attachments`：上传/生成的附件
- `server-logs`：后端日志

查看卷：`docker volume ls | grep readingcoach` 或 `docker compose config --volumes`

---

## 八、常见问题排查

### 1. 后端报连接数据库失败

- 核对 `config.json` 与 `.env` 的用户名/密码/库名是否一致
- 确认 `config.json` 的 `MySQLHost` 是 `mysql`、`MySQLPort` 是 `3306`
- 首次启动数据库导入较久，后端有 `depends_on: healthy` 会自动等待；若仍失败可 `docker compose restart server`

### 2. 想重新导入初始数据（清库重来）

> 会删除数据库所有数据，谨慎操作！

```bash
docker compose down
docker volume rm server_mysql-data   # 卷名以 docker volume ls 实际输出为准
docker compose up -d --build
```

### 3. 不想把 MySQL 端口暴露到公网

编辑 `docker-compose.yml`，删除或注释 mysql 服务下的 `ports` 段：

```yaml
  mysql:
    # ports:
    #   - "${MYSQL_PORT:-3306}:3306"
```

这样只有后端容器能通过内网访问数据库，更安全。

### 4. 修改了 `config.json` 后不生效

`config.json` 以只读方式挂载进容器，改完后需重启后端：

```bash
docker compose restart server
```

---

## 九、（可选）配合 Nginx 反向代理 + HTTPS

若用域名 `readingcoach.jingjiangke.com` 对外，可直接使用仓库里的配置：

```bash
cp /home/website/readingcoach.jingjiangke.com/ReadingCoach/server/deploy/nginx.readingcoach.conf \
   /etc/nginx/conf.d/readingcoach.conf
nginx -t && systemctl reload nginx
```

证书路径对应通配符证书（DNS-01 申请）：

```text
/etc/letsencrypt/live/jingjiangke.com/fullchain.pem
/etc/letsencrypt/live/jingjiangke.com/privkey.pem
```

配置要点：HTTP→HTTPS 跳转；反代到 `127.0.0.1:8080`；`client_max_body_size 20m`；OCR 超时 `proxy_read_timeout 180s`。

验证：

```bash
curl -s https://readingcoach.jingjiangke.com/api/health
```

---

## 附：目录内相关文件

| 文件 | 说明 |
|---|---|
| `Dockerfile` | 后端镜像构建定义（多阶段编译） |
| `docker-compose.yml` | 两容器编排 |
| `.dockerignore` | 构建上下文排除项 |
| `.env.example` → `.env` | Compose 环境变量（含 MySQL 密码） |
| `config.docker.example.json` → `config.json` | 后端配置（含 AI Key） |
| `db/schema.sql` | 首次启动自动导入的数据库结构+数据 |
