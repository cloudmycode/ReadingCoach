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

	"words/server/pkg/utils"
)

// TextAnalyzer 文本分析器接口
type TextAnalyzer interface {
	AnalyzeTextWithPrompt(ctx context.Context, text string, prompt string) ([][]string, error)
	CompleteTextPrompt(ctx context.Context, prompt string) (string, error)
}

// AIService 只负责调用 DeepSeek 做文本理解。
type AIService struct {
	deepSeekAPIKey string
	deepSeekAPIURL string
	deepSeekModel  string

	client *http.Client
}

// NewAIService 创建 DeepSeek 文本服务实例。
func NewAIService(
	deepSeekAPIKey,
	deepSeekAPIURL,
	deepSeekModel string,
) *AIService {
	if deepSeekAPIURL == "" {
		deepSeekAPIURL = "https://api.deepseek.com/v1/chat/completions"
	}
	if deepSeekModel == "" {
		deepSeekModel = "deepseek-chat"
	}

	return &AIService{
		deepSeekAPIKey: deepSeekAPIKey,
		deepSeekAPIURL: deepSeekAPIURL,
		deepSeekModel:  deepSeekModel,
		client:         &http.Client{Timeout: 90 * time.Second},
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

func (s *AIService) AnalyzeTextWithPrompt(ctx context.Context, text string, prompt string) ([][]string, error) {
	if strings.TrimSpace(s.deepSeekAPIKey) == "" {
		return nil, fmt.Errorf("deepseek api key not configured")
	}

	text = strings.TrimSpace(text)
	if text == "" {
		return nil, fmt.Errorf("no text provided")
	}

	requestBody := aiChatRequest{
		Model:       s.deepSeekModel,
		MaxTokens:   4096,
		Temperature: 0.1,
		Messages: []aiChatMessage{
			{
				Role:    "user",
				Content: prompt + "\n\n正文：\n" + text,
			},
		},
	}

	payload, err := json.Marshal(requestBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.deepSeekAPIURL, bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.deepSeekAPIKey)

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("deepseek error: %s", string(body))
	}

	var result aiChatResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	if len(result.Choices) == 0 {
		return nil, fmt.Errorf("deepseek returned empty choices")
	}

	rawContent, err := extractAIMessageText(result.Choices[0].Message.Content)
	if err != nil {
		return nil, err
	}

	lines, err := utils.ParseTSVLines(rawContent)
	if err != nil {
		return nil, fmt.Errorf("parse TSV format: %w", err)
	}

	return lines, nil
}

func (s *AIService) CompleteTextPrompt(ctx context.Context, prompt string) (string, error) {
	if strings.TrimSpace(s.deepSeekAPIKey) == "" {
		return "", fmt.Errorf("deepseek api key not configured")
	}
	if strings.TrimSpace(prompt) == "" {
		return "", fmt.Errorf("no prompt provided")
	}

	requestBody := aiChatRequest{
		Model:       s.deepSeekModel,
		MaxTokens:   2048,
		Temperature: 0.2,
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

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.deepSeekAPIURL, bytes.NewReader(payload))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.deepSeekAPIKey)

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
		return "", fmt.Errorf("deepseek error: %s", string(body))
	}

	var result aiChatResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}
	if len(result.Choices) == 0 {
		return "", fmt.Errorf("deepseek returned empty choices")
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

	return "", fmt.Errorf("unsupported deepseek content format")
}
