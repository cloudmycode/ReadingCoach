# WordsApp API 接口说明

面向全新的客户端实现所整理的 API 文档。所有接口均由 Go 服务器 (`cmd/server/main.go`) 暴露，经 `client/utils/api.js` 统一封装调用。

---

## 1. 服务概览

- **服务基础地址**
  - 本地默认：`http://localhost:8080`
  - 现有客户端默认：参考 `client/utils/api.js` 中 `BASE_URL`（示例：`http://192.168.124.86:8080`）
- **健康检查**：`GET /health`（无需鉴权，返回 `ok` 用于探活）
- **静态资源**：`GET /attachments/**`（图片和音频等附件，直接以静态文件形式访问）
- **所有业务接口**均挂载在 `/api` 之下

---

## 2. 鉴权方式

1. 客户端通过短信验证码登录，后端返回 **JWT**。
2. JWT 会同时写入响应体 `data.token`，并通过 `Set-Cookie token=...; HttpOnly` 返回。
3. 客户端需在后续请求的 Header 中携带 `Authorization: Bearer <token>`（或保持 Cookie）。
4. Token 默认 7 天有效；`handlers.AuthHandler.VerifyToken` 会验证并在 `gin.Context` 中放置 `user_id`。

---

## 3. 接口总览

| 模块 | 方法 | 路径 | 认证 | 说明 |
| --- | --- | --- | --- | --- |
| 公共 | GET | `/health` | 否 | 健康检查 |
| 公共 | GET | `/attachments/**` | 否 | 访问上传图片/音频 |
| 认证 | POST | `/api/auth/code` | 否 | 发送短信验证码 |
| 认证 | POST | `/api/auth/login` | 否 | 短信验证码登录，返回 JWT |
| 认证 | GET | `/api/auth/user` | 是 | 获取当前用户信息 |
| 认证 | POST | `/api/auth/logout` | 是 | 登出（清除 Cookie） |
| 文章 | POST | `/api/articles/process-text` | 是 | 提交客户端校对后的英文正文，生成文章与句子音频 |
| 文章 | GET | `/api/articles/:id` | 是 | 文章详情（:id 为加密 ID） |
| 文章 | GET | `/api/articles` | 是 | 当前用户的文章列表 |

---

## 4. 详细说明

### 4.1 `POST /api/auth/code`

- **用途**：生成 6 位验证码并保存数据库，限制 1 分钟一次。
- **请求体**

```json
{ "phone": "13800138000" }
```

- **响应示例**

```json
{
  "success": true,
  "message": "验证码已发送",
  "data": {
    "expiresIn": 180,
    "debugCode": "123456"   // 生产可去除
  }
}
```

- **错误**
  - 400：手机号为空或 JSON 解析失败
  - 429：触发频率限制

### 4.2 `POST /api/auth/login`

- **用途**：校验验证码、查找/创建用户、签发 JWT。
- **请求体**

```json
{
  "phone": "13800138000",
  "code": "123456",
  "agreePolicy": true
}
```

- **响应示例**

```json
{
  "success": true,
  "message": "登录成功",
  "data": {
    "token": "<jwt>",
    "userInfo": {
      "id": 12,
      "nickname": "用户8000",
      "avatar": ""
    }
  }
}
```

- **注意**
  - `agreePolicy=false` 时直接 400。
  - 验证码校验失败返回 401。

### 4.3 `GET /api/auth/user`

- **用途**：获取当前登录用户的昵称与头像。
- **认证**：`Authorization: Bearer <jwt>`
- **响应**

```json
{
  "success": true,
  "message": "获取成功",
  "data": {
    "id": 12,
    "nickname": "用户8000",
    "avatar": ""
  }
}
```

### 4.4 `POST /api/auth/logout`

- **用途**：清除 `token` Cookie。
- **请求体**：无
- **响应**：`{"success": true, "message": "登出成功"}`。

---

### 4.5 `POST /api/articles/process-text`

- **用途**：接收客户端已经校对过的英文正文文本，由 DeepSeek 负责清洗、断句和翻译，然后入库并异步生成音频。
- **认证**：必需。
- **Content-Type**：`application/json`
- **请求体**

```json
{
  "text": "Here is the full English passage.\nIt can contain multiple lines."
}
```

- **返回值**

```json
{
  "success": true,
  "message": "处理成功",
  "data": {
    "resource_id": "A1B2C3D4"
  }
}
```

- **错误**
  - 400：正文为空 / 参数错误
  - 401：未登录
  - 500：AI 服务不可用或入库失败

### 4.6 `GET /api/articles/:id`

- **用途**：根据加密 ID 获取文章详情，包含所有句子。
- **路径参数**：`:id` 为 `/api/articles/process-text` 返回的密文。服务端使用 `utils.DecryptID` 解析。
- **认证**：必需；只能查看自己的文章。
- **响应**（`ArticleService.GetArticleDetail`）

```json
{
  "success": true,
  "message": "获取成功",
  "data": {
    "article_id": 42,
    "title": "Once upon a time ...",
    "sentence_count": 10,
    "sentences": [
      {
        "id": 0,
        "sentence_id": 1001,
        "original": "Hello world.",
        "translation": "你好，世界。",
        "is_favorite": false
      }
      // ...
    ]
  }
}
```

- **额外行为**
  - 自动调用 `UpdateArticleReadStats`，更新阅读次数与 `last_read_at`。

### 4.7 `GET /api/articles`

- **用途**：分页获取当前用户的文章列表。
- **查询参数**
  - `limit`：默认 50，最大 100
  - `offset`：默认 0
- **响应**

```json
{
  "success": true,
  "message": "获取成功",
  "data": {
    "items": [
      {
        "id": "A1B2C3",             // 加密 ID（供跳转详情）
        "article_id": 42,
        "title": "Hello world",
        "sentence_count": 10,
        "read_count": 2,
        "sentence_duration": 12345, // ms，来自 TTS 统计
        "created_at": "2025-11-19T08:00:00Z",
        "last_read_at": "2025-11-20T08:00:00Z"
      }
    ],
    "limit": 50,
    "offset": 0
  }
}
```

---

## 5. 客户端调用约定

- 统一封装在 `client/utils/api.js`
  - `authAPI.sendCode` / `authAPI.login`
  - `aiAPI.analyzeArticleImages` 支持多端上传（App/H5）
  - `articleAPI.listArticles`、`articleAPI.getArticleDetail`
- 默认请求头携带 `Content-Type: application/json`，上传接口改用 `uni.uploadFile`。
- Token 管理由 `client/utils/auth.js` 负责（多用户支持）。

---

## 6. 其他辅助接口/行为

- **附件访问**：当前阅读主流程只依赖 `${ATTACHMENTS_DIR}/articleaudio` 中的句子音频静态资源。
- **TTS 生成**：当文章成功入库后会异步调用统一 AI provider（DeepSeek + Microsoft TTS）生成句子音频并保存在上述目录，时长最终写回 `articles.sentence_duration`。
- **错误返回格式**：统一为 `{"success": false, "message": "错误描述"}`，HTTP 状态码依业务不同（400/401/404/500/502 等）。

---

该文档覆盖现有 server/client 所有可见 API。如需扩展，请在新增路由时同步更新此文档并告知客户端团队。
