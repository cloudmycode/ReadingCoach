# DeepSeek API 配置说明

## 🔑 获取DeepSeek API密钥

1. 访问 [DeepSeek 官网](https://platform.deepseek.com/)
2. 注册账号并登录
3. 在控制台中创建API密钥
4. 复制API密钥

## ⚙️ 配置方式

当前服务端默认从 `config.json` 读取配置。

1. 复制 `server/config.example.json` 为 `server/config.json`
2. 填入以下字段：

```json
{
  "DeepSeekAPIKey": "your_api_key_here",
  "DeepSeekAPIURL": "https://api.deepseek.com/v1/chat/completions",
  "DeepSeekModel": "deepseek-chat",
  "MicrosoftTTSKey": "your_microsoft_tts_key",
  "MicrosoftTTSRegion": "eastasia",
  "MicrosoftTTSVoice": "en-US-JennyNeural"
}
```

## 🎯 系统提示词配置

### 默认系统提示词
系统默认使用英语学习助手的提示词，专门针对单词学习应用优化。

### 自定义系统提示词
您可以通过环境变量设置自定义系统提示词：

```bash
export DEEPSEEK_SYSTEM_PROMPT="你的自定义系统提示词"
```

### 系统提示词示例

#### 英语学习助手（默认）
```
你是一个专业的英语学习助手，专门帮助用户学习英语单词和提高英语水平。

你的主要职责包括：
1. 解释英语单词的含义、发音、词性和用法
2. 提供单词的记忆技巧和联想方法
3. 给出单词的例句和常见搭配
4. 回答英语学习相关的问题
5. 提供学习建议和方法

请遵循以下原则：
- 用中文回答用户的问题
- 提供准确、详细的英语学习信息
- 使用简单易懂的语言
- 鼓励用户继续学习
- 如果用户询问非英语学习相关的问题，可以回答但建议回到英语学习主题

现在请开始帮助用户学习英语！
```

#### 通用助手
```
你是一个有用的AI助手，请用中文回答用户的问题。
```

#### 技术助手
```
你是一个技术专家，专门帮助用户解决编程和技术问题。
请用中文回答，提供详细的技术解释和解决方案。
```

## 🚀 启动服务

1. 完成 `config.json` 配置后启动服务：
```bash
cd server
go run cmd/server/main.go
```

2. 或者编译后运行：
```bash
cd server
go build -o server cmd/server/main.go
./server
```

## 🧪 测试功能

1. 启动服务端
2. 在客户端拍照并校对文本后提交正文
3. 检查 DeepSeek 是否返回结构化 TSV 内容
4. 检查 Microsoft TTS 是否生成句子音频

## 📝 注意事项

- 如果没有配置 DeepSeek 或 Microsoft TTS，对应能力将不可用
- API密钥请妥善保管，不要提交到代码仓库
- 建议在生产环境中通过密钥管理系统或安全配置中心管理密钥
