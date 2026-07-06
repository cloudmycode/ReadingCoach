# ReadingCoach 技术实现方案

## 1. 技术目标

围绕 MVP，建立一条稳定的端到端学习链路：

1. iOS 客户端完成拍照、上传、学习展示、播放和统计展示。
2. 服务端完成 OCR、正文清洗、AI 拆句翻译、音频生成与数据存储。
3. 系统支持历史复习、音频缓存和后续功能扩展。
4. 学习记录与账号绑定，支持多设备同步。

## 2. 总体架构

## 2.1 架构概览

```text
iOS App
  -> API Gateway
  -> Auth Service
  -> Article Service
  -> AI Pipeline Service
       -> OCR Engine
       -> LLM Parse Service
       -> TTS Service
  -> Study Record Service
  -> Analytics Service
  -> Object Storage / CDN
  -> Database
```

## 2.2 架构原则

1. AI 任务与业务接口解耦，避免同步请求过重。
2. 文本解析与音频生成支持分阶段返回。
3. 文章、句子、音频和学习记录使用结构化存储。
4. 便于将来接入不同 OCR、LLM、TTS 提供商。
5. 账号体系与统计体系统一基于 `user_id` 聚合。

## 3. 客户端方案

## 3.1 技术栈建议

1. 平台：iOS 17+
2. 语言：Swift
3. UI 框架：SwiftUI
4. 架构模式：MVVM
5. 网络层：URLSession + async/await
6. 本地存储：SwiftData 或 Core Data
7. 音频播放：AVFoundation
8. 图片处理：VisionKit / Vision + CoreImage

## 3.2 客户端模块划分

1. `AuthModule`
2. `CameraModule`
3. `UploadModule`
4. `ArticleLearningModule`
5. `AudioPlayerModule`
6. `HistoryModule`
7. `StatsModule`
8. `SettingsModule`
9. `SyncModule`

## 3.3 客户端关键能力

### 拍照预处理

1. 自动检测文档边缘
2. 拍照后进入手动裁剪确认页，允许用户调整有效区域
3. 自动拉正和裁剪
4. 仅上传裁剪后的有效区域，减少无关内容干扰
5. 压缩上传图像，控制带宽成本

### 本地缓存

1. 缓存最近学习文章结构化数据
2. 缓存最近音频 URL 与播放位置
3. 缓存当天统计摘要
4. 缓存登录态、最近同步时间和待同步任务

### 登录与同步

1. 用户登录后拉取云端文章、学习记录和统计数据
2. 学习行为优先写入本地，再异步上传服务端
3. 弱网状态下保留待同步队列，网络恢复后继续同步
4. 同步冲突以服务端时间戳和业务规则进行合并

### 播放器

1. 单句播放
2. 全文顺播
3. 倍速控制
4. 后台音频播放
5. 播放中句子同步高亮

## 4. 服务端方案

## 4.1 技术栈建议

推荐服务端技术栈：

1. 语言：Go 1.24+
2. HTTP 框架：Gin 或 Chi
3. 数据库：PostgreSQL
4. 缓存：Redis
5. 对象存储：AWS S3 / 阿里云 OSS / 腾讯云 COS
6. 异步任务：Asynq 或 RabbitMQ
7. 数据访问：GORM 或 sqlc
8. 配置管理：环境变量方案或 Viper
9. 日志：Zap 或 Zerolog

推荐组合：

`Go + Gin + PostgreSQL + Redis + Asynq`

原因：

1. Go 适合高并发 API、文件上传和任务编排场景。
2. 单二进制部署简单，适合 MVP 快速上线。
3. 调用 OCR、LLM、TTS 等外部服务时稳定性和性能都比较合适。
4. 后续从单体服务演进到多服务时迁移成本相对可控。

## 4.2 服务划分

### API Gateway

负责统一接入、鉴权、限流和路由。

Go 落地建议：

1. MVP 阶段先采用模块化单体服务，不急于拆成多个独立微服务。
2. 用包结构拆分 `auth`、`article`、`study`、`stats`、`sync` 等领域模块。
3. 统一通过中间件处理鉴权、日志、限流和错误响应。

### User Service

负责用户信息、登录态、订阅状态和设备绑定。

### Auth Service

负责认证相关能力：

1. Apple 登录
2. 手机号或邮箱验证码登录
3. Access Token 与 Refresh Token 管理
4. 设备会话管理
5. 退出登录与 token 刷新

### Article Service

负责文章上传、文章详情、历史列表、文章修订与存储。

### AI Pipeline Service

负责 AI 相关处理编排：

1. OCR 识别
2. 正文清洗
3. 句子切分
4. 逐句翻译与拆句讲解
5. 音频生成

Go 落地建议：

1. API 层只负责创建任务和返回状态，不同步等待完整解析结果。
2. OCR、解析、TTS 由 Asynq worker 分阶段执行。
3. 每阶段结果及时落库，便于失败重试和任务恢复。

### Study Record Service

负责记录用户学习行为、复习行为和打卡状态。

### Sync Strategy

负责跨设备一致性：

1. 文章与学习记录绑定账号
2. 播放位置与最近学习状态可增量同步
3. 统计数据由服务端统一汇总，避免端侧口径不一致

### Analytics Service

负责统计日报、连续学习天数和趋势图数据。

## 5. AI 处理链路

## 5.1 处理流程

1. 客户端拍照或导入原图
2. 客户端进入裁剪确认流程，生成裁剪后的上传图
3. 服务端保存裁剪后的图片到对象存储
4. OCR 提取原始文本
5. 使用规则和大模型清洗正文
6. 按句切分英文内容
7. 对每句生成：
   - 中文翻译
   - 拆句讲解
   - 可选关键词解释
8. 调用 TTS 生成句子级或全文级音频
9. 存储结构化结果并返回客户端

学习同步补充说明：

1. 已登录用户的文章在创建时写入 `user_id`
2. 学习过程中关键行为实时写入 `study_records`
3. `daily_stats` 由服务端异步汇总生成
4. 新设备登录后通过同步接口拉取最近学习摘要

## 5.2 OCR 策略

推荐方案：

1. 优先使用成熟 OCR 服务，如 Google Cloud Vision、Azure OCR、阿里云 OCR。
2. 如果预算敏感，可结合开源 OCR，如 PaddleOCR，但英文长文场景仍建议用商业 OCR。

## 5.3 LLM Prompt 任务拆分

建议不要用一个超大 Prompt 一次完成所有工作，改为拆分两阶段：

### 阶段一：正文清洗

目标：

1. 保留文章正文
2. 去掉题号、页码、选项和明显噪声
3. 输出干净英文全文

### 阶段二：句子结构化

目标：

1. 将全文按自然句拆分
2. 为每句输出标准 JSON
3. 字段包括英文、中文翻译、拆句讲解、顺序编号

这样更容易控制输出稳定性。

## 5.4 TTS 方案

可选：

1. OpenAI 音频模型
2. ElevenLabs
3. Azure Speech
4. 火山引擎或腾讯云 TTS

推荐要求：

1. 发音自然
2. 生成速度稳定
3. 支持英文较长文本
4. 成本可控

## 6. 数据模型

## 6.1 users

| 字段 | 类型 | 说明 |
|---|---|---|
| id | uuid | 用户 ID |
| email | varchar | 登录邮箱 |
| phone | varchar | 手机号 |
| nickname | varchar | 昵称 |
| avatar_url | varchar | 头像 |
| apple_sub | varchar | Apple 登录唯一标识 |
| last_login_at | timestamp | 最近登录时间 |
| created_at | timestamp | 创建时间 |

## 6.2 user_sessions

| 字段 | 类型 | 说明 |
|---|---|---|
| id | uuid | 会话 ID |
| user_id | uuid | 用户 ID |
| device_id | varchar | 设备 ID |
| platform | varchar | 平台 |
| refresh_token_hash | varchar | 刷新令牌摘要 |
| expires_at | timestamp | 过期时间 |
| created_at | timestamp | 创建时间 |
| revoked_at | timestamp | 注销时间 |

## 6.3 articles

| 字段 | 类型 | 说明 |
|---|---|---|
| id | uuid | 文章 ID |
| user_id | uuid | 所属用户 |
| title | varchar | 文章标题 |
| source_image_url | varchar | 裁剪后的上传图片地址 |
| raw_ocr_text | text | OCR 原始文本 |
| cleaned_text | text | 清洗后的正文 |
| parse_status | varchar | 解析状态 |
| audio_status | varchar | 音频状态 |
| created_at | timestamp | 创建时间 |
| updated_at | timestamp | 更新时间 |

## 6.4 article_sentences

| 字段 | 类型 | 说明 |
|---|---|---|
| id | uuid | 句子 ID |
| article_id | uuid | 文章 ID |
| order_no | int | 顺序 |
| english_text | text | 英文原句 |
| chinese_translation | text | 中文翻译 |
| grammar_note | text | 拆句讲解 |
| audio_url | varchar | 音频地址 |
| duration_ms | int | 音频时长 |

## 6.5 study_records

| 字段 | 类型 | 说明 |
|---|---|---|
| id | uuid | 记录 ID |
| user_id | uuid | 用户 ID |
| article_id | uuid | 文章 ID |
| action_type | varchar | 行为类型 |
| study_date | date | 学习日期 |
| duration_seconds | int | 时长 |
| progress_payload | jsonb | 当前句、播放位置等进度信息 |
| created_at | timestamp | 创建时间 |

## 6.6 daily_stats

| 字段 | 类型 | 说明 |
|---|---|---|
| id | uuid | 主键 |
| user_id | uuid | 用户 ID |
| stat_date | date | 日期 |
| new_articles_count | int | 新学习文章数 |
| review_articles_count | int | 复习文章数 |
| total_study_seconds | int | 总学习时长 |
| streak_days | int | 连续学习天数 |

## 7. 核心接口设计

## 7.1 上传图片

`POST /api/v1/articles/upload`

请求：

- multipart/form-data
- 字段：`image`
- 可选字段：`cropMeta`，用于记录裁剪框坐标、旋转角度和图片尺寸，便于问题排查与后续优化

说明：

1. 客户端默认上传裁剪后的图片，而不是完整原图
2. `cropMeta` 仅作为调试和体验优化辅助信息，不参与 OCR 主输入

响应：

```json
{
  "articleId": "uuid",
  "uploadUrl": "https://...",
  "status": "uploaded"
}
```

## 7.2 登录

`POST /api/v1/auth/login`

请求示例：

```json
{
  "provider": "apple",
  "identityToken": "token-from-apple",
  "deviceId": "ios-device-uuid"
}
```

响应示例：

```json
{
  "user": {
    "id": "uuid",
    "nickname": "Amy"
  },
  "accessToken": "jwt-access-token",
  "refreshToken": "jwt-refresh-token"
}
```

## 7.3 刷新登录态

`POST /api/v1/auth/refresh`

## 7.4 创建解析任务

`POST /api/v1/articles/{articleId}/parse`

响应：

```json
{
  "articleId": "uuid",
  "parseStatus": "processing"
}
```

## 7.5 查询文章详情

`GET /api/v1/articles/{articleId}`

响应示例：

```json
{
  "id": "uuid",
  "title": "A Lesson From Nature",
  "parseStatus": "completed",
  "audioStatus": "completed",
  "sentences": [
    {
      "orderNo": 1,
      "englishText": "When the storm finally ended, the village was silent.",
      "chineseTranslation": "当暴风雨终于结束时，村庄一片寂静。",
      "grammarNote": "主句为 the village was silent，when 引导时间状语从句。",
      "audioUrl": "https://cdn.example.com/audio/1.mp3"
    }
  ]
}
```

## 7.6 历史文章列表

`GET /api/v1/articles/history?page=1&pageSize=20`

## 7.7 记录学习行为

`POST /api/v1/study/records`

行为类型建议：

1. `article_started`
2. `sentence_played`
3. `article_completed`
4. `review_started`
5. `review_completed`

## 7.8 获取统计数据

`GET /api/v1/stats/dashboard`

## 7.9 获取同步摘要

`GET /api/v1/sync/bootstrap`

用于新设备登录后拉取：

1. 最近学习文章
2. 学习记录摘要
3. 今日和累计统计数据
4. 用户个性化设置

## 8. 异步任务设计

## 8.1 队列拆分

建议建立三个队列：

1. `ocr_queue`
2. `parse_queue`
3. `tts_queue`

Go 实现建议：

1. 使用 Asynq 作为基于 Redis 的任务队列。
2. 为每类任务定义明确的 payload 结构体，避免弱类型传参。
3. 针对 OCR、解析、TTS 配置不同超时、重试次数和优先级。

## 8.2 原因

1. OCR、解析、音频生成耗时差异大
2. 有利于失败重试和监控
3. 便于后续独立扩容

## 8.3 状态机

文章状态建议：

1. `uploaded`
2. `ocr_processing`
3. `ocr_completed`
4. `parse_processing`
5. `parse_completed`
6. `tts_processing`
7. `completed`
8. `failed`

## 9. 统计逻辑设计

## 9.1 新学习文章

某用户某天首次完成一篇文章的解析并进入学习页，记为一篇新学习文章。

## 9.2 连续学习天数

若当天存在有效学习行为，则当天记为已学习。与前一天连续则 streak +1，否则重置为 1。

## 9.3 有效学习行为

推荐满足任一条件即可：

1. 新上传并成功学习一篇文章
2. 某篇文章累计学习时长超过 3 分钟
3. 完成一次复习播放

## 10. 安全与合规

1. 全部 API 使用 HTTPS
2. 用户数据按 `user_id` 严格隔离
3. 图片存储地址使用签名 URL
4. 服务端记录 Prompt 与返回时需注意脱敏
5. 明确用户协议和隐私政策
6. Refresh Token 仅保存摘要，不明文入库
7. 支持多设备会话撤销与异常下线

Go 工程建议：

1. 使用中间件统一处理 request id、panic recovery、鉴权和访问日志。
2. 对外部 AI 服务调用增加 timeout、retry 和熔断保护。
3. 对登录、上传、同步等高风险接口增加限流和审计日志。

## 11. 成本控制建议

1. OCR 与 LLM 分步执行，避免不必要的音频生成
2. 音频按句缓存，重复打开不重复生成
3. 免费用户限制每日解析篇数
4. 过长文章可按段落拆分处理

## 12. 监控与运维

建议监控指标：

1. 图片上传成功率
2. OCR 成功率
3. LLM 解析成功率
4. 平均解析耗时
5. TTS 生成耗时
6. 每日活跃用户数
7. 每日 AI 成本

建议日志链路：

1. 请求日志
2. 异步任务日志
3. Prompt 调用日志
4. 错误重试日志

## 13. 推荐开发里程碑

### 第 1 阶段：MVP 闭环

1. iOS 拍照与上传
2. 登录与同步基础能力
3. OCR + LLM 解析
4. 学习页展示
5. 音频播放
6. 历史与统计

后端优先级建议：

1. 先完成 Go API 骨架、鉴权和文章上传。
2. 再接入 Asynq 队列与 AI 处理链路。
3. 最后补齐统计汇总、历史列表和同步接口。

### 第 2 阶段：体验优化

1. OCR 编辑纠错
2. 播放性能优化
3. 复习提醒
4. 统计图表完善

### 第 3 阶段：商业化与增长

1. 订阅体系
2. 学习计划
3. 生词本和练习题
