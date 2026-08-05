# ---------- 构建阶段：静态编译 Linux 二进制 ----------
# 不使用 # syntax=docker/dockerfile:1，避免构建前必须拉取 docker/dockerfile（国内常超时）
FROM golang:1.24-alpine AS builder

# 国内服务器构建可用 --build-arg GOPROXY=https://goproxy.cn,direct 加速
ARG GOPROXY=https://proxy.golang.org,direct
ENV GOPROXY=${GOPROXY} \
    CGO_ENABLED=0 \
    GOOS=linux

WORKDIR /src

RUN apk add --no-cache git ca-certificates

# 先拷贝依赖清单，利用缓存层
COPY go.mod go.sum ./
RUN go mod download

# 再拷贝源码并编译
COPY . .
RUN go build -trimpath -buildvcs=false -o /out/readingcoach-server ./cmd/server

# ---------- 运行阶段：精简镜像 ----------
FROM alpine:3.20

# ca-certificates 用于访问 DashScope（千问文本/OCR）等 HTTPS 接口；tzdata 保证 loc=Local 时区正确
RUN apk add --no-cache ca-certificates tzdata wget && \
    adduser -D -u 10001 appuser

WORKDIR /app

COPY --from=builder /out/readingcoach-server /app/readingcoach-server

# 预建运行目录并赋权，命名卷首次挂载会继承该目录属主
RUN mkdir -p /app/logs /app/attachments && chown -R appuser:appuser /app

USER appuser

EXPOSE 8080

ENTRYPOINT ["/app/readingcoach-server"]
