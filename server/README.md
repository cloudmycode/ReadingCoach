# Server Structure

## Current Layout

```text
server/
├── cmd/            # 程序入口
├── internal/       # handlers / services / database / logger
├── pkg/            # 配置与通用工具
├── db/             # 数据库结构与数据库辅助脚本
├── scripts/        # Docker 构建/部署脚本（docker-ship.sh）与测试脚本
├── deploy/         # nginx 等部署配置
├── docs/           # 接口与配置文档
├── attachments/    # 本地开发时的静态附件目录
└── release/        # 运行产物目录（可忽略）
```

## Notes

- `attachments/` 是运行时目录，不建议提交生成的音频文件。
- `config.json` 是本地/服务器私有配置，不提交到仓库。
- `release/`、`bin/`、`logs/` 都属于运行产物，不应作为源码目录使用。

## 阅读小测与家庭奖励

服务端已加入异步出题、批改、30 天挑战和兑换券。配置、接口及测试步骤见 [阅读闯关服务端说明](docs/READING_CHALLENGES.md)。需要 MySQL 8.0+；新增迁移由服务启动幂等执行，Docker 构建保留该迁移供 Go 嵌入。
