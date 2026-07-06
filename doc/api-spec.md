# ReadingCoach API 详细接口文档

## 1. 文档说明

本文档定义 ReadingCoach MVP 阶段的前后端接口契约，供 iOS 客户端、Go 服务端和测试联调使用。

### 1.1 基础信息

1. 接口风格：REST
2. 数据格式：`application/json`
3. 文件上传：`multipart/form-data`
4. 字符编码：`UTF-8`
5. 时间格式：默认使用 ISO 8601 UTC 时间字符串

### 1.2 环境建议

1. 开发环境：`https://api-dev.readingcoach.app`
2. 测试环境：`https://api-staging.readingcoach.app`
3. 生产环境：`https://api.readingcoach.app`

### 1.3 通用请求头

未登录接口：

```http
Content-Type: application/json
X-Client-Version: 1.0.0
X-Platform: ios
X-Device-Id: <uuid>
```

登录后接口：

```http
Content-Type: application/json
Authorization: Bearer <access_token>
X-Client-Version: 1.0.0
X-Platform: ios
X-Device-Id: <uuid>
```

### 1.4 通用响应结构

成功：

```json
{
  "code": 0,
  "message": "ok",
  "data": {}
}
```

失败：

```json
{
  "code": 400100,
  "message": "invalid request",
  "requestId": "req_123456"
}
```

### 1.5 通用错误码

| 错误码 | 含义 |
|---|---|
| 0 | 成功 |
| 400100 | 参数错误 |
| 401100 | 未登录或 token 无效 |
| 401101 | token 已过期 |
| 403100 | 无权限访问该资源 |
| 404100 | 资源不存在 |
| 409100 | 状态冲突 |
| 429100 | 请求过于频繁 |
| 500100 | 服务内部错误 |
| 500200 | 第三方服务调用失败 |
| 500300 | AI 解析失败 |
| 500400 | 音频生成失败 |

## 2. 认证接口

## 2.1 Apple 登录

`POST /api/v1/auth/apple/login`

### 请求体

```json
{
  "identityToken": "apple-identity-token",
  "authorizationCode": "apple-authorization-code",
  "deviceId": "ios-device-uuid",
  "deviceName": "iPhone 16 Pro",
  "appVersion": "1.0.0"
}
```

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "user": {
      "id": "usr_123",
      "nickname": "Amy",
      "avatarUrl": "",
      "loginProvider": "apple"
    },
    "accessToken": "jwt-access-token",
    "refreshToken": "jwt-refresh-token",
    "expiresIn": 7200,
    "isNewUser": true
  }
}
```

### 音频使用规则

1. `audioUrl` 指向服务端保存的句子音频资源。
2. 客户端首次访问该句子时下载音频到本地缓存。
3. 本地已存在缓存时，客户端不应重复下载同一音频。
4. 若服务端后续更换音频资源，可通过变更 URL 或附加版本字段触发客户端重新下载。

## 2.2 验证码发送

`POST /api/v1/auth/verify-code/send`

### 请求体

```json
{
  "channel": "email",
  "target": "demo@example.com"
}
```

### 说明

1. `channel` 取值：`email` 或 `phone`
2. MVP 若只做一种方式，可保留接口但仅开放一种通道

## 2.3 验证码登录

`POST /api/v1/auth/verify-code/login`

### 请求体

```json
{
  "channel": "email",
  "target": "demo@example.com",
  "code": "123456",
  "deviceId": "ios-device-uuid",
  "deviceName": "iPhone 16 Pro",
  "appVersion": "1.0.0"
}
```

### 响应体

同 Apple 登录。

## 2.4 刷新登录态

`POST /api/v1/auth/refresh`

### 请求体

```json
{
  "refreshToken": "jwt-refresh-token"
}
```

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "accessToken": "new-access-token",
    "refreshToken": "new-refresh-token",
    "expiresIn": 7200
  }
}
```

## 2.5 退出登录

`POST /api/v1/auth/logout`

### 请求体

```json
{
  "refreshToken": "jwt-refresh-token"
}
```

## 2.6 获取当前用户信息

`GET /api/v1/me`

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "id": "usr_123",
    "nickname": "Amy",
    "avatarUrl": "",
    "loginProvider": "apple",
    "createdAt": "2026-07-06T08:00:00Z"
  }
}
```

## 3. 图片与文章接口

## 3.1 上传裁剪后的文章图片

`POST /api/v1/articles/upload`

### 请求类型

`multipart/form-data`

### 表单字段

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| image | file | 是 | 裁剪后的文章图片 |
| cropMeta | string | 否 | 裁剪元信息 JSON 字符串 |
| source | string | 否 | `camera` 或 `album` |

### `cropMeta` 示例

```json
{
  "originalWidth": 3024,
  "originalHeight": 4032,
  "cropX": 120,
  "cropY": 260,
  "cropWidth": 2500,
  "cropHeight": 1800,
  "rotation": 0
}
```

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "articleId": "art_123",
    "sourceImageUrl": "https://cdn.example.com/articles/art_123/source.jpg",
    "parseStatus": "uploaded"
  }
}
```

## 3.2 提交解析任务

`POST /api/v1/articles/{articleId}/parse`

### 请求体

```json
{
  "forceReparse": false
}
```

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "articleId": "art_123",
    "parseStatus": "processing",
    "audioStatus": "pending"
  }
}
```

## 3.3 获取文章详情

`GET /api/v1/articles/{articleId}`

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "id": "art_123",
    "title": "A Lesson From Nature",
    "sourceImageUrl": "https://cdn.example.com/articles/art_123/source.jpg",
    "cleanedText": "When the storm finally ended, the village was silent.",
    "parseStatus": "completed",
    "audioStatus": "completed",
    "sentenceCount": 12,
    "createdAt": "2026-07-06T08:00:00Z",
    "sentences": [
      {
        "id": "sen_1",
        "orderNo": 1,
        "englishText": "When the storm finally ended, the village was silent.",
        "chineseTranslation": "当暴风雨终于结束时，村庄一片寂静。",
        "grammarNote": "主句为 the village was silent，when 引导时间状语从句。",
        "audioUrl": "https://cdn.example.com/audio/sen_1.mp3",
        "durationMs": 4200
      }
    ]
  }
}
```

## 3.4 查询文章列表

`GET /api/v1/articles`

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| page | int | 否 | 默认 `1` |
| pageSize | int | 否 | 默认 `20`，最大 `50` |
| keyword | string | 否 | 按标题或正文搜索 |
| dateFrom | string | 否 | `YYYY-MM-DD` |
| dateTo | string | 否 | `YYYY-MM-DD` |
| onlyFavorite | bool | 否 | 是否仅看收藏 |

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "list": [
      {
        "id": "art_123",
        "title": "A Lesson From Nature",
        "sentenceCount": 12,
        "parseStatus": "completed",
        "audioStatus": "completed",
        "isFavorite": false,
        "lastStudiedAt": "2026-07-06T08:10:00Z",
        "createdAt": "2026-07-06T08:00:00Z"
      }
    ],
    "pagination": {
      "page": 1,
      "pageSize": 20,
      "total": 1,
      "hasMore": false
    }
  }
}
```

## 3.5 更新文章标题或收藏状态

`PATCH /api/v1/articles/{articleId}`

### 请求体

```json
{
  "title": "A Lesson From Nature",
  "isFavorite": true
}
```

## 3.6 删除文章

`DELETE /api/v1/articles/{articleId}`

### 说明

1. 删除为软删除
2. 删除后不再出现在历史列表

## 3.7 更新 OCR 文本并重新解析

`POST /api/v1/articles/{articleId}/reparse`

### 请求体

```json
{
  "editedText": "When the storm finally ended, the village was silent."
}
```

## 4. 学习记录接口

## 4.1 上报学习行为

`POST /api/v1/study/records`

### 请求体

```json
{
  "articleId": "art_123",
  "actionType": "sentence_played",
  "studyDate": "2026-07-06",
  "durationSeconds": 18,
  "progressPayload": {
    "sentenceId": "sen_1",
    "orderNo": 1,
    "positionMs": 1800,
    "mode": "intensive"
  }
}
```

### `actionType` 枚举

1. `article_started`
2. `sentence_played`
3. `article_completed`
4. `review_started`
5. `review_completed`
6. `translation_toggled`
7. `audio_speed_changed`

## 4.2 获取文章学习进度

`GET /api/v1/articles/{articleId}/progress`

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "articleId": "art_123",
    "lastMode": "review",
    "lastSentenceId": "sen_3",
    "lastOrderNo": 3,
    "positionMs": 1200,
    "updatedAt": "2026-07-06T08:20:00Z"
  }
}
```

## 4.3 获取昨日复习推荐

`GET /api/v1/review/yesterday`

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "date": "2026-07-05",
    "articles": [
      {
        "articleId": "art_123",
        "title": "A Lesson From Nature",
        "sentenceCount": 12
      }
    ]
  }
}
```

## 5. 统计与同步接口

## 5.1 获取统计首页数据

`GET /api/v1/stats/dashboard`

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "todayArticles": 2,
    "totalArticles": 18,
    "streakDays": 6,
    "totalStudyDays": 12,
    "totalSentences": 224,
    "reviewCount": 9,
    "weekTrend": [
      { "date": "2026-06-30", "articles": 1 },
      { "date": "2026-07-01", "articles": 2 }
    ]
  }
}
```

## 5.2 获取打卡日历

`GET /api/v1/stats/calendar?month=2026-07`

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "month": "2026-07",
    "days": [
      { "date": "2026-07-01", "studied": true },
      { "date": "2026-07-02", "studied": false }
    ]
  }
}
```

## 5.3 启动同步接口

`GET /api/v1/sync/bootstrap`

### 使用场景

1. 新设备首次登录
2. 用户主动下拉刷新
3. 客户端发现本地缓存过旧

### 响应体

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "serverTime": "2026-07-06T08:30:00Z",
    "user": {
      "id": "usr_123",
      "nickname": "Amy"
    },
    "recentArticles": [
      {
        "id": "art_123",
        "title": "A Lesson From Nature",
        "lastStudiedAt": "2026-07-06T08:10:00Z"
      }
    ],
    "recentProgress": [
      {
        "articleId": "art_123",
        "lastSentenceId": "sen_3",
        "lastOrderNo": 3,
        "positionMs": 1200,
        "updatedAt": "2026-07-06T08:20:00Z"
      }
    ],
    "statsSummary": {
      "todayArticles": 2,
      "totalArticles": 18,
      "streakDays": 6
    },
    "settings": {
      "playbackSpeed": 1.0,
      "showTranslationByDefault": true
    }
  }
}
```

## 5.4 设置同步

`PUT /api/v1/settings`

### 请求体

```json
{
  "playbackSpeed": 1.0,
  "showTranslationByDefault": true,
  "voiceStyle": "female_us",
  "reviewReminderEnabled": true,
  "reviewReminderTime": "20:30"
}
```

## 6. 状态枚举

## 6.1 文章解析状态

1. `uploaded`
2. `ocr_processing`
3. `ocr_completed`
4. `parse_processing`
5. `parse_completed`
6. `tts_processing`
7. `completed`
8. `failed`

## 6.2 音频状态

1. `pending`
2. `processing`
3. `completed`
4. `failed`

## 6.3 学习模式

1. `intensive`
2. `review`

## 7. 鉴权与安全规则

1. `accessToken` 建议有效期 2 小时。
2. `refreshToken` 建议有效期 30 天。
3. 涉及用户数据的接口默认都需要登录。
4. 游客模式仅本地可用，不调用云端同步接口。
5. 上传接口限制单张图片大小，例如不超过 10 MB。
6. 高频接口需做限流，尤其是登录、上传、重解析和同步接口。

## 8.1 客户端音频缓存规则

1. 客户端根据句子 `audioUrl` 下载音频文件并缓存到本地。
2. 同一 `audioUrl` 已缓存时，优先播放本地文件。
3. 客户端清理缓存后，可按需重新下载。
4. 建议客户端以 `sentenceId + audioUrl hash` 作为本地缓存键。

## 9. 联调建议

1. 先联调登录、上传、文章详情这 3 条主链路。
2. 学习记录和统计接口可在主链路跑通后补齐。
3. 解析接口建议先返回模拟数据，等 AI pipeline 稳定后切换真实调用。
4. iOS 客户端对 `parseStatus` 和 `audioStatus` 做轮询或下拉刷新处理。
