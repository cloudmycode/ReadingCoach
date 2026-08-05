package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"words/server/internal/logger"
)

// TextAnalyzer 文本分析器接口。
type TextAnalyzer interface {
	AnalyzeArticleText(ctx context.Context, text string) (ArticleAnalysisResult, error)
	// CompleteJSONPrompt 以结构化 JSON 方式调用模型。
	// schemaJSON 非空时优先尝试 json_schema；为空或模型不支持时回退 json_object。
	CompleteJSONPrompt(ctx context.Context, prompt, schemaName, schemaJSON string) (string, error)
}

// AIService 通过阿里 DashScope（千问）OpenAI 兼容接口做文本理解。
type AIService struct {
	apiKey string
	apiURL string
	model  string

	client *http.Client

	// 一旦发现当前模型不接受 json_schema，后续直接走 json_object，避免重复 400。
	jsonSchemaUnsupported atomic.Bool
}

// NewAIService 创建千问文本服务实例。
func NewAIService(apiKey, apiURL, model string) *AIService {
	if apiURL == "" {
		apiURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
	}
	if model == "" {
		model = "qwen-plus"
	}

	return &AIService{
		apiKey: apiKey,
		apiURL: apiURL,
		model:  model,
		client: &http.Client{Timeout: 90 * time.Second},
	}
}

type aiChatRequest struct {
	Model          string             `json:"model"`
	Messages       []aiChatMessage    `json:"messages"`
	MaxTokens      int                `json:"max_tokens,omitempty"`
	Temperature    float64            `json:"temperature,omitempty"`
	ResponseFormat *aiResponseFormat  `json:"response_format,omitempty"`
}

type aiChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type aiResponseFormat struct {
	Type       string              `json:"type"`
	JSONSchema *aiJSONSchemaFormat `json:"json_schema,omitempty"`
}

type aiJSONSchemaFormat struct {
	Name   string          `json:"name"`
	Strict bool            `json:"strict,omitempty"`
	Schema json.RawMessage `json:"schema"`
}

type aiChatResponse struct {
	Choices []struct {
		Message struct {
			Content json.RawMessage `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
		TotalTokens      int `json:"total_tokens"`
	} `json:"usage"`
}

func (s *AIService) AnalyzeArticleText(ctx context.Context, text string) (ArticleAnalysisResult, error) {
	if strings.TrimSpace(s.apiKey) == "" {
		return ArticleAnalysisResult{}, fmt.Errorf("qwen api key not configured")
	}

	text = strings.TrimSpace(text)
	if text == "" {
		return ArticleAnalysisResult{}, fmt.Errorf("no text provided")
	}

	prompt := ArticleTextAnalysisPrompt + "\n\n正文：\n" + text
	rawContent, err := s.CompleteJSONPrompt(ctx, prompt, "article_analysis", ArticleAnalysisJSONSchema)
	if err != nil {
		return ArticleAnalysisResult{}, err
	}

	result, err := ParseArticleAnalysisJSON(rawContent)
	if err != nil {
		return ArticleAnalysisResult{}, fmt.Errorf("parse article analysis json: %w", err)
	}
	return result, nil
}

func (s *AIService) CompleteJSONPrompt(ctx context.Context, prompt, schemaName, schemaJSON string) (string, error) {
	if strings.TrimSpace(s.apiKey) == "" {
		return "", fmt.Errorf("qwen api key not configured")
	}
	prompt = strings.TrimSpace(prompt)
	if prompt == "" {
		return "", fmt.Errorf("no prompt provided")
	}
	if !strings.Contains(strings.ToLower(prompt), "json") {
		prompt = prompt + "\n\n只返回合法 JSON。"
	}

	maxTokens := 2048
	if schemaName == "article_analysis" {
		maxTokens = 8192
	}

	raw, err := s.chatCompletionJSON(ctx, prompt, maxTokens, 0.1, schemaName, schemaJSON)
	if err != nil {
		return "", err
	}

	cleaned := extractJSONObject(raw)
	if cleaned == "" {
		return "", fmt.Errorf("empty json response")
	}
	firstValidateErr := validateRawJSON(cleaned, schemaName, schemaJSON)
	if firstValidateErr == nil {
		return cleaned, nil
	}
	logger.Warn("⚠️ 结构化 JSON 校验失败，准备重试修复: schema=%s err=%v raw=%s",
		schemaName, firstValidateErr, truncateForLog(raw, 1500))

	repairPrompt := buildJSONRepairPrompt(schemaName, schemaJSON, raw, firstValidateErr.Error())
	repairedRaw, repairErr := s.chatCompletionJSON(ctx, repairPrompt, maxTokens, 0.0, schemaName, schemaJSON)
	if repairErr != nil {
		return "", fmt.Errorf("json repair failed: %w (first error: %v)", repairErr, firstValidateErr)
	}
	repaired := extractJSONObject(repairedRaw)
	if repaired == "" {
		return "", fmt.Errorf("empty repaired json response (first error: %v)", firstValidateErr)
	}
	if validateErr := validateRawJSON(repaired, schemaName, schemaJSON); validateErr != nil {
		logger.Error("❌ JSON 修复后仍不合法: schema=%s err=%v raw=%s",
			schemaName, validateErr, truncateForLog(repairedRaw, 1500))
		return "", fmt.Errorf("json still invalid after repair: %w", validateErr)
	}
	logger.Info("✅ 结构化 JSON 已通过修复重试 schema=%s", schemaName)
	return repaired, nil
}

func (s *AIService) chatCompletionJSON(
	ctx context.Context,
	prompt string,
	maxTokens int,
	temperature float64,
	schemaName string,
	schemaJSON string,
) (string, error) {
	preferSchema := strings.TrimSpace(schemaJSON) != "" && !s.jsonSchemaUnsupported.Load()
	raw, status, err := s.doChatCompletion(ctx, prompt, maxTokens, temperature, preferSchema, schemaName, schemaJSON)
	if err == nil {
		return raw, nil
	}

	if preferSchema && status == http.StatusBadRequest && isStructuredFormatUnsupported(err.Error()) {
		s.jsonSchemaUnsupported.Store(true)
		logger.Warn("⚠️ 当前模型不支持 json_schema，回退 json_object: %v", err)
		raw, _, fallbackErr := s.doChatCompletion(ctx, prompt, maxTokens, temperature, false, schemaName, schemaJSON)
		if fallbackErr != nil {
			return "", fallbackErr
		}
		return raw, nil
	}
	return "", err
}

func (s *AIService) doChatCompletion(
	ctx context.Context,
	prompt string,
	maxTokens int,
	temperature float64,
	useJSONSchema bool,
	schemaName string,
	schemaJSON string,
) (string, int, error) {
	requestBody := aiChatRequest{
		Model:       s.model,
		MaxTokens:   maxTokens,
		Temperature: temperature,
		Messages: []aiChatMessage{
			{
				Role:    "user",
				Content: prompt,
			},
		},
		ResponseFormat: buildResponseFormat(useJSONSchema, schemaName, schemaJSON),
	}

	payload, err := json.Marshal(requestBody)
	if err != nil {
		return "", 0, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.apiURL, bytes.NewReader(payload))
	if err != nil {
		return "", 0, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.apiKey)

	resp, err := s.client.Do(req)
	if err != nil {
		return "", 0, fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", resp.StatusCode, fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return "", resp.StatusCode, fmt.Errorf("qwen error(status=%d): %s", resp.StatusCode, truncateForLog(string(body), 500))
	}

	var result aiChatResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return "", resp.StatusCode, fmt.Errorf("decode response: %w", err)
	}
	if len(result.Choices) == 0 {
		return "", resp.StatusCode, fmt.Errorf("qwen returned empty choices")
	}

	text, err := extractAIMessageText(result.Choices[0].Message.Content)
	if err != nil {
		return "", resp.StatusCode, err
	}
	return text, resp.StatusCode, nil
}

func buildResponseFormat(useJSONSchema bool, schemaName, schemaJSON string) *aiResponseFormat {
	schemaJSON = strings.TrimSpace(schemaJSON)
	if useJSONSchema && schemaJSON != "" {
		name := strings.TrimSpace(schemaName)
		if name == "" {
			name = "response"
		}
		return &aiResponseFormat{
			Type: "json_schema",
			JSONSchema: &aiJSONSchemaFormat{
				Name:   name,
				Strict: true,
				Schema: json.RawMessage(schemaJSON),
			},
		}
	}
	return &aiResponseFormat{Type: "json_object"}
}

func buildJSONRepairPrompt(schemaName, schemaJSON, broken, validateErr string) string {
	var b strings.Builder
	b.WriteString("你之前返回的内容不是合法或不符合约定的 JSON。请只输出修复后的 JSON 对象，不要 Markdown，不要解释。\n")
	if strings.TrimSpace(schemaName) != "" {
		b.WriteString("目标结构名称：")
		b.WriteString(schemaName)
		b.WriteByte('\n')
	}
	if strings.TrimSpace(schemaJSON) != "" {
		b.WriteString("JSON Schema：\n")
		b.WriteString(schemaJSON)
		b.WriteByte('\n')
	}
	b.WriteString("校验错误：\n")
	b.WriteString(validateErr)
	b.WriteString("\n\n需要修复的内容：\n")
	b.WriteString(broken)
	return b.String()
}

func validateRawJSON(raw, schemaName, schemaJSON string) error {
	if !json.Valid([]byte(raw)) {
		return fmt.Errorf("invalid json syntax")
	}

	switch schemaName {
	case "article_analysis":
		_, err := ParseArticleAnalysisJSON(raw)
		return err
	case "word_explain":
		var payload struct {
			Word         string `json:"word"`
			PartOfSpeech string `json:"part_of_speech"`
			Meaning      string `json:"meaning"`
			Tip          string `json:"tip"`
		}
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			return err
		}
		if strings.TrimSpace(payload.Meaning) == "" && strings.TrimSpace(payload.Word) == "" {
			return fmt.Errorf("word explanation missing word/meaning")
		}
		return nil
	case "sentence_coach":
		var payload struct {
			Answer     string   `json:"answer"`
			Highlights []string `json:"highlights"`
		}
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			return err
		}
		if strings.TrimSpace(payload.Answer) == "" {
			return fmt.Errorf("sentence coach answer is empty")
		}
		return nil
	case "sentence_translation":
		var payload struct {
			Translation string `json:"translation"`
		}
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			return err
		}
		if strings.TrimSpace(payload.Translation) == "" {
			return fmt.Errorf("translation is empty")
		}
		return nil
	}

	// 无业务 schema 时，至少保证是 JSON object。
	if strings.TrimSpace(schemaJSON) == "" {
		trimmed := strings.TrimSpace(raw)
		if !strings.HasPrefix(trimmed, "{") {
			return fmt.Errorf("expected json object")
		}
		return nil
	}

	var generic map[string]json.RawMessage
	if err := json.Unmarshal([]byte(raw), &generic); err != nil {
		return err
	}
	return nil
}

func isStructuredFormatUnsupported(message string) bool {
	lower := strings.ToLower(message)
	keywords := []string{
		"response_format",
		"json_schema",
		"json schema",
		"unknown field",
		"not support",
		"unsupported",
		"invalid parameter",
		"invalid_parameter",
	}
	for _, keyword := range keywords {
		if strings.Contains(lower, keyword) {
			return true
		}
	}
	return false
}

func extractAIMessageText(raw json.RawMessage) (string, error) {
	var asString string
	if err := json.Unmarshal(raw, &asString); err == nil {
		return asString, nil
	}

	var asParts []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	if err := json.Unmarshal(raw, &asParts); err == nil {
		var builder strings.Builder
		for _, part := range asParts {
			if part.Text == "" {
				continue
			}
			if builder.Len() > 0 {
				builder.WriteByte('\n')
			}
			builder.WriteString(part.Text)
		}
		return builder.String(), nil
	}

	return "", fmt.Errorf("unsupported qwen content format")
}
