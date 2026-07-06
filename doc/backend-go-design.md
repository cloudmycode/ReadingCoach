# ReadingCoach Go 服务端详细设计

## 1. 目标

本文档用于把 MVP 服务端方案细化到可开工实现的粒度，覆盖工程结构、模块拆分、数据流、异步任务、第三方集成与开发顺序。

## 2. 技术选型

1. 语言：Go 1.24+
2. HTTP 框架：Gin
3. 数据库：PostgreSQL
4. 缓存与任务队列：Redis + Asynq
5. 数据访问：GORM
6. 配置管理：环境变量
7. 日志：Zap
8. 数据迁移：golang-migrate
9. 对象存储：S3 兼容接口

## 3. 工程结构

推荐目录：

```text
readingcoach-server/
├── cmd/
│   ├── api/
│   │   └── main.go
│   └── worker/
│       └── main.go
├── config/
│   └── example.env
├── internal/
│   ├── app/
│   ├── auth/
│   │   ├── handler/
│   │   ├── service/
│   │   ├── repository/
│   │   └── model/
│   ├── article/
│   │   ├── handler/
│   │   ├── service/
│   │   ├── repository/
│   │   └── model/
│   ├── study/
│   ├── stats/
│   ├── sync/
│   ├── settings/
│   ├── provider/
│   │   ├── llm/
│   │   ├── tts/
│   │   ├── ocr/
│   │   └── storage/
│   ├── queue/
│   ├── middleware/
│   ├── pkg/
│   │   ├── jwt/
│   │   ├── response/
│   │   ├── validator/
│   │   └── clock/
│   └── bootstrap/
├── migrations/
├── scripts/
├── Makefile
└── go.mod
```

## 4. 分层约束

### 4.1 handler 层

职责：

1. 解析请求参数
2. 调用 service
3. 返回统一响应结构
4. 不直接操作数据库

### 4.2 service 层

职责：

1. 承载业务规则
2. 组装多个 repository
3. 调用 provider 和 queue
4. 负责事务边界

### 4.3 repository 层

职责：

1. 封装数据库访问
2. 提供领域查询方法
3. 不包含业务分支判断

### 4.4 provider 层

职责：

1. 封装 DeepSeek、微软语音、OCR、对象存储等外部依赖
2. 统一错误格式
3. 隐藏供应商 SDK 细节

## 5. 核心模块设计

## 5.1 auth 模块

职责：

1. Apple 登录
2. 验证码登录
3. access token / refresh token 签发
4. 设备会话管理
5. 登出与 token 刷新

建议接口：

1. `LoginWithApple(ctx, input)`
2. `LoginWithVerifyCode(ctx, input)`
3. `RefreshToken(ctx, refreshToken)`
4. `Logout(ctx, userID, refreshToken)`

## 5.2 article 模块

职责：

1. 上传文章图片
2. 创建解析任务
3. 获取文章详情
4. 更新文章标题、收藏状态
5. 删除文章
6. OCR 文本修正后二次解析

建议接口：

1. `CreateArticle(ctx, input)`
2. `StartParse(ctx, articleID, forceReparse)`
3. `GetArticleDetail(ctx, userID, articleID)`
4. `ReparseWithEditedText(ctx, articleID, text)`

## 5.3 study 模块

职责：

1. 上报学习行为
2. 保存文章学习进度
3. 产出昨日复习推荐基础数据

建议接口：

1. `RecordAction(ctx, input)`
2. `GetProgress(ctx, userID, articleID)`
3. `GetYesterdayReview(ctx, userID)`

## 5.4 stats 模块

职责：

1. 聚合今日学习数据
2. 计算 streak
3. 生成趋势图和打卡日历

建议接口：

1. `GetDashboard(ctx, userID)`
2. `GetCalendar(ctx, userID, month)`
3. `RebuildDailyStats(ctx, userID, date)`

## 5.5 sync 模块

职责：

1. 新设备启动同步
2. 拉取最近文章和进度
3. 拉取设置与统计摘要

建议接口：

1. `Bootstrap(ctx, userID)`

## 6. Provider 接口设计

## 6.1 LLMProvider

```go
type LLMProvider interface {
    CleanArticleText(ctx context.Context, input CleanArticleTextInput) (*CleanArticleTextOutput, error)
    ParseSentences(ctx context.Context, input ParseSentencesInput) (*ParseSentencesOutput, error)
}
```

### DeepSeek 实现职责

1. 根据 OCR 原文清洗正文
2. 按句输出结构化 JSON
3. 生成翻译和拆句讲解

### 输出要求

1. 必须返回可反序列化 JSON
2. 句子顺序稳定
3. 错误时保留 request id 和原始响应片段用于排查

## 6.2 TTSProvider

```go
type TTSProvider interface {
    GenerateSentenceAudio(ctx context.Context, input GenerateSentenceAudioInput) (*GenerateSentenceAudioOutput, error)
}
```

### 微软语音实现职责

1. 接收单句英文
2. 调用微软免费语音模块生成音频
3. 返回临时音频文件或字节流
4. 由 storage provider 转存到对象存储

音频持久化要求：

1. 每个句子生成独立音频文件。
2. 音频文件上传到对象存储后保留稳定访问路径。
3. 只要句子内容未变化，不重复生成音频。
4. 当句子内容变更并重新解析时，生成新的音频资源地址。

## 6.3 OCRProvider

```go
type OCRProvider interface {
    ExtractText(ctx context.Context, input ExtractTextInput) (*ExtractTextOutput, error)
}
```

## 6.4 StorageProvider

```go
type StorageProvider interface {
    Upload(ctx context.Context, key string, contentType string, body io.Reader) (string, error)
    Delete(ctx context.Context, key string) error
}
```

## 7. 异步任务设计

## 7.1 任务类型

1. `article:ocr`
2. `article:parse`
3. `article:tts`
4. `stats:rebuild_daily`

## 7.2 任务 payload

推荐使用强类型结构：

```go
type OCRTaskPayload struct {
    ArticleID string `json:"articleId"`
    UserID    string `json:"userId"`
}
```

```go
type ParseTaskPayload struct {
    ArticleID string `json:"articleId"`
    UserID    string `json:"userId"`
}
```

```go
type TTSTaskPayload struct {
    ArticleID string `json:"articleId"`
    SentenceID string `json:"sentenceId"`
    UserID string `json:"userId"`
}
```

## 7.3 Worker 流程

### OCR Worker

1. 读取文章记录
2. 下载或读取裁剪后图片
3. 调用 OCRProvider
4. 保存 `raw_ocr_text`
5. 更新状态为 `ocr_completed`
6. 投递 `article:parse`

### Parse Worker

1. 读取 `raw_ocr_text`
2. 调用 DeepSeek 清洗正文
3. 调用 DeepSeek 逐句解析
4. 写入 `articles.cleaned_text`
5. 写入 `article_sentences`
6. 更新状态为 `parse_completed`
7. 为每个句子投递 `article:tts`

### TTS Worker

1. 读取句子英文
2. 调用微软语音 provider
3. 上传音频到对象存储
4. 回写 `audio_url` 和 `duration_ms`
5. 全部句子完成后更新文章 `audio_status`

客户端协作规则：

1. 服务端只负责生成并保存音频，不主动下发二进制内容到客户端缓存目录。
2. 客户端首次播放时通过 `audio_url` 下载对应句子音频。
3. 后续是否重下由客户端依据本地缓存命中情况决定。

## 7.4 重试策略

1. OCR 失败：最多重试 3 次
2. DeepSeek 失败：最多重试 2 次
3. TTS 失败：最多重试 3 次
4. 重试后仍失败，状态置为 `failed` 并记录错误原因

## 8. 数据库实现建议

## 8.1 主表

1. `users`
2. `user_sessions`
3. `articles`
4. `article_sentences`
5. `study_records`
6. `daily_stats`
7. `user_settings`

## 8.2 关键索引

1. `articles(user_id, created_at desc)`
2. `article_sentences(article_id, order_no)`
3. `study_records(user_id, study_date)`
4. `study_records(article_id, created_at)`
5. `daily_stats(user_id, stat_date)`
6. `user_sessions(user_id, revoked_at)`
7. `article_sentences(article_id, audio_url)`

## 8.3 状态字段建议

`articles.parse_status`

1. `uploaded`
2. `ocr_processing`
3. `ocr_completed`
4. `parse_processing`
5. `parse_completed`
6. `tts_processing`
7. `completed`
8. `failed`

`articles.audio_status`

1. `pending`
2. `processing`
3. `completed`
4. `failed`

## 9. 鉴权设计

## 9.1 token 策略

1. `accessToken` 使用 JWT
2. `refreshToken` 使用随机字符串或 JWT 都可
3. `refreshToken` 入库前只保存 hash

## 9.2 中间件

建议包含：

1. `RequestIDMiddleware`
2. `RecoveryMiddleware`
3. `LoggerMiddleware`
4. `AuthMiddleware`
5. `RateLimitMiddleware`

## 9.3 权限规则

1. 用户只能访问自己的文章和学习记录
2. 所有带 `articleId` 的接口都需要校验 `user_id`
3. 同步接口仅返回当前登录用户的数据

## 10. 配置项建议

```env
APP_ENV=dev
HTTP_PORT=8080
POSTGRES_DSN=
REDIS_ADDR=
JWT_SECRET=
JWT_EXPIRE_SECONDS=7200
REFRESH_TOKEN_EXPIRE_HOURS=720
S3_ENDPOINT=
S3_BUCKET=
S3_ACCESS_KEY=
S3_SECRET_KEY=
DEEPSEEK_API_KEY=
DEEPSEEK_BASE_URL=
MICROSOFT_TTS_KEY=
MICROSOFT_TTS_REGION=
OCR_PROVIDER=
OCR_API_KEY=
```

## 11. 日志与监控

## 11.1 日志字段建议

1. `request_id`
2. `user_id`
3. `article_id`
4. `task_type`
5. `provider`
6. `latency_ms`
7. `error_code`

## 11.2 监控指标建议

1. API QPS
2. API 错误率
3. OCR 成功率
4. DeepSeek 成功率
5. TTS 成功率
6. 平均解析耗时
7. 队列堆积数
8. 单日第三方调用成本

## 12. 开发顺序建议

## 12.1 第一阶段

1. 初始化 Gin 项目骨架
2. 接入 PostgreSQL、Redis、Zap、JWT
3. 完成登录、用户信息、文章上传接口

## 12.2 第二阶段

1. 接入 Asynq
2. 跑通 OCR -> DeepSeek -> TTS 主链路
3. 完成文章详情与历史列表接口

## 12.3 第三阶段

1. 完成学习记录与进度接口
2. 完成统计接口
3. 完成同步启动接口

## 12.4 第四阶段

1. 增加限流、审计日志、告警
2. 压测上传与任务队列
3. 补齐单元测试和集成测试

## 13. 测试建议

1. provider 层使用 mock 做单元测试
2. repository 层做数据库集成测试
3. handler 层做 HTTP 接口测试
4. worker 层重点测试失败重试和幂等
5. AI 输出解析重点测试 JSON 结构容错

## 14. 可以直接开工的最小任务拆分

1. 建仓并初始化 `cmd/api` 与 `cmd/worker`
2. 建立数据库迁移文件
3. 实现 `auth` 模块
4. 实现 `article upload + parse` 模块
5. 实现 `study + stats + sync` 模块
6. 实现 DeepSeek、微软语音、OCR provider
7. 接入对象存储与音频上传
