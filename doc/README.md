# ReadingCoach 文档目录

本目录用于沉淀 `ReadingCoach` 项目的产品、设计与技术方案。

当前代码主目录：

- iOS 客户端：`/Users/wang/Project/WordsApp/ReadingCoach/iosclient/ReadingApp`
- Go 服务端：`/Users/wang/Project/WordsApp/ReadingCoach/server`

## 文档列表

- [产品需求说明书](./product-requirements.md)
- [技术实现方案](./technical-design.md)
- [UI 设计方案](./ui-design.md)
- [Go 服务端详细设计](./backend-go-design.md)
- [开发计划与排期建议](./development-plan.md)

接口契约以服务端实现为准：[`server/docs/API_REFERENCE.md`](../server/docs/API_REFERENCE.md)，路由表见 [`server/internal/handlers/routes.go`](../server/internal/handlers/routes.go)。

## 建议阅读顺序

1. 先阅读产品需求说明书，统一目标用户、核心场景和 MVP 范围。
2. 再阅读技术实现方案，明确 iOS 客户端、服务端、AI 处理链路和数据模型。
3. 阅读服务端 API 参考与路由表，确定前后端联调契约。
4. 阅读 Go 服务端详细设计，推进后端工程搭建与任务拆分。
5. 阅读开发计划与排期建议，安排前后端并行开发与联调节奏。
6. 最后阅读 UI 设计方案，推进原型设计、视觉设计和交互细化。
