#!/bin/bash

# 构建脚本
# 用于构建服务器

set -e

echo "🚀 开始构建Words App Server..."

# 创建构建目录
mkdir -p bin

# 构建Web服务器
echo "📦 构建Web服务器..."
go build -o bin/server cmd/server/main.go
echo "✅ Web服务器构建完成: bin/server"

# 设置执行权限
chmod +x bin/*

echo "🎉 所有构建完成!"
echo "📁 可执行文件位置:"
echo "  - Web服务器: bin/server"
echo ""
echo "🚀 运行示例:"
echo "  ./bin/server                    # 启动Web服务器"
