package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"
	"unicode"

	"words/server/internal/logger"
)

var (
	// 含汉字的半角/全角括号整段删除，例如 "(你好)"、"（注释）"。
	ocrParenGroupWithHan = regexp.MustCompile(`\([^()]*\p{Han}[^()]*\)|（[^（）]*\p{Han}[^（）]*）`)
	// 去掉中文后残留的空括号。
	ocrEmptyParens = regexp.MustCompile(`\(\s*\)|（\s*）`)
)

// truncateForLog 截断日志中过长的内容，避免刷屏。
func truncateForLog(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + fmt.Sprintf("...(共%d字节，已截断)", len(s))
}

// ImageTextExtractor 定义从图片中提取正文文字的能力。
type ImageTextExtractor interface {
	ExtractArticleText(ctx context.Context, imageBase64, mimeType string) (string, error)
}

// ArticleImageOCRPrompt 指导视觉模型只提取书本正文英文，去除噪音并保留段落。
const ArticleImageOCRPrompt = `你是专业的英文书籍文字识别助手。请识别并提取图片中的英文正文内容，严格遵守：
1. 只输出英文正文本身，保留自然段落，不同段落之间用一个空行分隔；
2. 必须忽略并删除图片中的全部中文（含中文译文、注释、批注、题干等），一个汉字都不要输出；
3. 去除页眉、页脚、页码、书名、章节名、练习题、选项、批注和手写笔记等非正文内容；
4. 修正明显的识别错误以及被行末换行拆断的单词，但不得改写、翻译、增删英文正文；
5. 直接输出纯文本英文正文，不要输出任何解释、标题、序号或 Markdown 标记。`

// OCRService 通过支持视觉的多模态模型（OpenAI 兼容接口，如阿里 Qwen-VL）识别图片正文。
type OCRService struct {
	apiKey string
	apiURL string
	model  string

	client *http.Client
}

// NewOCRService 创建视觉 OCR 服务实例。
func NewOCRService(apiKey, apiURL, model string) *OCRService {
	if apiURL == "" {
		apiURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
	}
	if model == "" {
		model = "qwen-vl-ocr"
	}
	return &OCRService{
		apiKey: apiKey,
		apiURL: apiURL,
		model:  model,
		client: &http.Client{Timeout: 90 * time.Second},
	}
}

type visionImageURL struct {
	URL string `json:"url"`
}

type visionContentPart struct {
	Type     string          `json:"type"`
	Text     string          `json:"text,omitempty"`
	ImageURL *visionImageURL `json:"image_url,omitempty"`
}

type visionChatMessage struct {
	Role    string              `json:"role"`
	Content []visionContentPart `json:"content"`
}

type visionChatRequest struct {
	Model     string              `json:"model"`
	Messages  []visionChatMessage `json:"messages"`
	MaxTokens int                 `json:"max_tokens,omitempty"`
}

// ExtractArticleText 将图片（base64 编码）发送给视觉模型，返回整理后的正文文本。
func (s *OCRService) ExtractArticleText(ctx context.Context, imageBase64, mimeType string) (string, error) {
	if strings.TrimSpace(s.apiKey) == "" {
		return "", fmt.Errorf("qwen-vl api key not configured")
	}
	if strings.TrimSpace(imageBase64) == "" {
		return "", fmt.Errorf("no image provided")
	}
	if strings.TrimSpace(mimeType) == "" {
		mimeType = "image/jpeg"
	}

	dataURI := fmt.Sprintf("data:%s;base64,%s", mimeType, imageBase64)
	requestBody := visionChatRequest{
		Model:     s.model,
		MaxTokens: 4096,
		Messages: []visionChatMessage{
			{
				Role: "user",
				Content: []visionContentPart{
					{Type: "image_url", ImageURL: &visionImageURL{URL: dataURI}},
					{Type: "text", Text: ArticleImageOCRPrompt},
				},
			},
		},
	}

	payload, err := json.Marshal(requestBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	logger.Info("🖼️ [OCR] 开始请求视觉模型 model=%s url=%s 图片=%d字节(base64) 请求体=%d字节",
		s.model, s.apiURL, len(imageBase64), len(payload))

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.apiURL, bytes.NewReader(payload))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.apiKey)

	started := time.Now()
	resp, err := s.client.Do(req)
	if err != nil {
		// 超时 / 连接失败 / 出网被阻断都会走到这里
		logger.Error("❌ [OCR] 请求视觉模型失败（耗时 %s）: %v", time.Since(started), err)
		return "", fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		logger.Error("❌ [OCR] 读取响应失败（耗时 %s）: %v", time.Since(started), err)
		return "", fmt.Errorf("read response: %w", err)
	}
	elapsed := time.Since(started)
	logger.Info("📥 [OCR] 收到响应 status=%d 耗时=%s 响应体=%d字节", resp.StatusCode, elapsed, len(body))

	if resp.StatusCode != http.StatusOK {
		logger.Error("❌ [OCR] 视觉模型返回非 200：status=%d body=%s",
			resp.StatusCode, truncateForLog(string(body), 2000))
		return "", fmt.Errorf("qwen-vl error(status=%d): %s", resp.StatusCode, truncateForLog(string(body), 500))
	}

	// 复用 ai_service.go 中的响应结构与内容解析逻辑（同一 package）。
	var result aiChatResponse
	if err := json.Unmarshal(body, &result); err != nil {
		logger.Error("❌ [OCR] 响应 JSON 解析失败: %v body=%s", err, truncateForLog(string(body), 2000))
		return "", fmt.Errorf("decode response: %w", err)
	}
	logger.Info("🔎 [OCR] 用量 prompt=%d completion=%d total=%d, choices=%d",
		result.Usage.PromptTokens, result.Usage.CompletionTokens, result.Usage.TotalTokens, len(result.Choices))
	if len(result.Choices) == 0 {
		logger.Error("❌ [OCR] 视觉模型返回空 choices，原始响应=%s", truncateForLog(string(body), 2000))
		return "", fmt.Errorf("qwen-vl returned empty choices")
	}

	content, err := extractAIMessageText(result.Choices[0].Message.Content)
	if err != nil {
		logger.Error("❌ [OCR] 解析消息内容失败: %v 原始 content=%s",
			err, truncateForLog(string(result.Choices[0].Message.Content), 2000))
		return "", err
	}

	content = filterChineseFromOCRText(content)
	logger.Info("✅ [OCR] 识别完成，正文 %d 字符，预览：%s", len(content), truncateForLog(content, 300))
	return content, nil
}

// filterChineseFromOCRText 去掉 OCR 结果中的汉字与中文标点，只保留英文可读内容。
// 含中文的括号整段删除；去中文后残留的空括号一并清除。
func filterChineseFromOCRText(raw string) string {
	text := ocrParenGroupWithHan.ReplaceAllString(raw, "")

	var builder strings.Builder
	builder.Grow(len(text))
	for _, r := range text {
		if unicode.Is(unicode.Han, r) || isCJKPunctuation(r) {
			continue
		}
		builder.WriteRune(r)
	}
	text = ocrEmptyParens.ReplaceAllString(builder.String(), "")

	lines := strings.Split(text, "\n")
	cleaned := make([]string, 0, len(lines))
	blankPending := false
	for _, line := range lines {
		line = strings.TrimSpace(ocrEmptyParens.ReplaceAllString(line, ""))
		line = collapseASCIISpaces(line)
		if line == "" {
			if len(cleaned) > 0 {
				blankPending = true
			}
			continue
		}
		if blankPending {
			cleaned = append(cleaned, "")
			blankPending = false
		}
		cleaned = append(cleaned, line)
	}
	return strings.TrimSpace(strings.Join(cleaned, "\n"))
}

func isCJKPunctuation(r rune) bool {
	switch {
	case r >= 0x3000 && r <= 0x303F: // CJK 符号标点（含 ideographic space）
		return true
	case r >= 0xFF01 && r <= 0xFF60: // 全角 ASCII/标点（中文排版常见）
		return true
	case r == '，' || r == '。' || r == '！' || r == '？' || r == '；' || r == '：' ||
		r == '、' || r == '（' || r == '）' || r == '【' || r == '】' ||
		r == '《' || r == '》' || r == '「' || r == '」' || r == '『' || r == '』':
		return true
	default:
		return false
	}
}

func collapseASCIISpaces(s string) string {
	fields := strings.Fields(s)
	return strings.Join(fields, " ")
}
