# 千问（DashScope）API 配置说明

文本能力（拆句、翻译、单词解释、句子问答）与拍照 OCR 均使用阿里云 DashScope 千问模型。

## 获取 API Key

1. 访问 [阿里云百炼 / DashScope](https://bailian.console.aliyun.com/)
2. 创建或复制 API Key
3. 填入 `config.json` 的 `QwenAPIKey` / `QwenVLAPIKey`（可填同一个 Key）

## 配置方式

复制 `server/config.docker.example.json` 为 `server/config.json`，填入：

```json
{
  "QwenAPIKey": "your_dashscope_api_key",
  "QwenAPIURL": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
  "QwenModel": "qwen-plus",
  "QwenVLAPIKey": "your_dashscope_api_key",
  "QwenVLAPIURL": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
  "QwenVLModel": "qwen-vl-ocr"
}
```

| 字段 | 用途 | 推荐值 |
|---|---|---|
| `QwenModel` | 文本：拆句 / 翻译 / 单词解释 / 问答 | `qwen-plus`（也可用 `qwen-turbo` / `qwen-flash`） |
| `QwenVLModel` | 拍照 OCR | `qwen-vl-ocr` |

> 若只填其中一个 Key，启动时会自动互为缺省（同一 DashScope 账号）。

## 启动服务

```bash
cd server
go run ./cmd/server
```

Docker 部署见 `DEPLOY_DOCKER.md`：改服务器上的 `config.json` 后执行 `docker compose restart server`，或本机重新 `./scripts/docker-ship.sh`。

## 注意事项

- API Key 不要提交到 Git（`config.json` 已在 `.gitignore`）
- 旧配置里的 `DeepSeekAPIKey` 仍会被读取并映射为 `QwenAPIKey`，但请求地址会走 DashScope；建议直接改成新字段
