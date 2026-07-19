# Server Structure

## Current Layout

```text
server/
├── cmd/            # 程序入口
├── internal/       # handlers / services / database / logger
├── pkg/            # 配置与通用工具
├── db/             # 数据库结构与数据库辅助脚本
├── scripts/        # 本地启动与部署脚本
├── deploy/         # nginx 等部署配置
├── docs/           # 接口与部署文档
├── attachments/    # 本地开发时的静态附件目录
└── release/        # 生产发布产物（deploy.sh 生成）
```

## Notes

- `attachments/` 是运行时目录，不建议提交生成的音频文件。
- `config.json` 是本地/服务器私有配置，不提交到仓库。
- `release/`、`bin/`、`logs/` 都属于运行产物，不应作为源码目录使用。
