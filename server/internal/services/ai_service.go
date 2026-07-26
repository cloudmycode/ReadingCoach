package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

)

// TextAnalyzer 文本分析器接口
type TextAnalyzer interface {
	AnalyzeArticleText(ctx context.Context, text string) (ArticleAnalysisResult, error)
	CompleteTextPrompt(ctx context.Context, prompt string) (string, error)
}

// AIService 通过阿里 DashScope（千问）OpenAI 兼容接口做文本理解。
type AIService struct {
	apiKey string
	apiURL string
	model  string

	client *http.Client
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
	Model       string          `json:"model"`
	Messages    []aiChatMessage `json:"messages"`
	MaxTokens   int             `json:"max_tokens,omitempty"`
	Temperature float64         `json:"temperature,omitempty"`
}

type aiChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
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

	rawContent, err := s.chatCompletion(ctx, ArticleTextAnalysisPrompt+"\n\n正文：\n"+text, 4096, 0.1)
	if err != nil {
		return ArticleAnalysisResult{}, err
	}

	result, err := ParseArticleAnalysisJSON(rawContent)
	if err != nil {
		return ArticleAnalysisResult{}, fmt.Errorf("parse article analysis json: %w", err)
	}
	return result, nil
}

func (s *AIService) CompleteTextPrompt(ctx context.Context, prompt string) (string, error) {
	if strings.TrimSpace(s.apiKey) == "" {
		return "", fmt.Errorf("qwen api key not configured")
	}
	if strings.TrimSpace(prompt) == "" {
		return "", fmt.Errorf("no prompt provided")
	}

	return s.chatCompletion(ctx, prompt, 2048, 0.2)
}

func (s *AIService) chatCompletion(ctx context.Context, prompt string, maxTokens int, temperature float64) (string, error) {
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
	}

	payload, err := json.Marshal(requestBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.apiURL, bytes.NewReader(payload))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.apiKey)

	resp, err := s.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("qwen error(status=%d): %s", resp.StatusCode, truncateForLog(string(body), 500))
	}

	var result aiChatResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}
	if len(result.Choices) == 0 {
		return "", fmt.Errorf("qwen returned empty choices")
	}

	return extractAIMessageText(result.Choices[0].Message.Content)
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
