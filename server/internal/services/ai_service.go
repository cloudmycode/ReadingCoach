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

	"words/server/internal/logger"
	"words/server/pkg/utils"
)

// TextAnalyzer 文本分析器接口
type TextAnalyzer interface {
	AnalyzeTextWithPrompt(ctx context.Context, text string, prompt string) ([][]string, error)
}

// TTSService 语音合成服务接口
type TTSService interface {
	GenerateAudio(ctx context.Context, text string, userID string) ([]byte, error)
}

// AIService 统一封装 DeepSeek 文本分析和免费的 Edge TTS 语音合成。
type AIService struct {
	deepSeekAPIKey string
	deepSeekAPIURL string
	deepSeekModel  string

	ttsVoice string

	client *http.Client
}

// NewAIService 创建统一 AI 服务实例。
// TTS 使用免费的 Edge TTS，无需密钥，因此该服务始终可用；
// DeepSeek 文本分析在未配置 API Key 时不可用。
func NewAIService(
	deepSeekAPIKey,
	deepSeekAPIURL,
	deepSeekModel,
	ttsVoice string,
) *AIService {
	if deepSeekAPIURL == "" {
		deepSeekAPIURL = "https://api.deepseek.com/v1/chat/completions"
	}
	if deepSeekModel == "" {
		deepSeekModel = "deepseek-chat"
	}
	if strings.TrimSpace(ttsVoice) == "" {
		ttsVoice = "en-US-JennyNeural"
	}

	return &AIService{
		deepSeekAPIKey: deepSeekAPIKey,
		deepSeekAPIURL: deepSeekAPIURL,
		deepSeekModel:  deepSeekModel,
		ttsVoice:       ttsVoice,
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
	Role    string              `json:"role"`
	Content []aiChatContentPart `json:"content"`
}

type aiChatContentPart struct {
	Type     string          `json:"type"`
	Text     string          `json:"text,omitempty"`
	ImageURL *aiImageURLPart `json:"image_url,omitempty"`
}

type aiImageURLPart struct {
	URL string `json:"url"`
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
				Role: "user",
				Content: []aiChatContentPart{
					{
						Type: "text",
						Text: prompt + "\n\n以下是用户已经校对过的英文正文，请按要求输出：\n" + text,
					},
				},
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

// GenerateAudio 使用免费的 Edge TTS 生成 MP3 音频（无需密钥）。
func (s *AIService) GenerateAudio(ctx context.Context, text string, userID string) ([]byte, error) {
	_ = userID

	text = strings.TrimSpace(text)
	if text == "" {
		return nil, fmt.Errorf("no text provided")
	}

	voiceName := s.voiceForText(text)
	audioData, err := synthesizeEdgeTTS(ctx, text, voiceName, "+0%", "+0Hz", "+0%")
	if err != nil {
		return nil, err
	}

	logger.Debug("🎵 Edge TTS 音频生成完成: voice=%s, text=%d字符, 总大小=%d字节", voiceName, len(text), len(audioData))
	return audioData, nil
}

func (s *AIService) voiceForText(text string) string {
	if containsChinese(text) {
		return "zh-CN-XiaoxiaoNeural"
	}
	return s.ttsVoice
}

func containsChinese(text string) bool {
	for _, r := range text {
		if r >= 0x4E00 && r <= 0x9FFF {
			return true
		}
	}
	return false
}

func xmlEscapeText(text string) string {
	replacer := strings.NewReplacer(
		"&", "&amp;",
		"<", "&lt;",
		">", "&gt;",
		"\"", "&quot;",
		"'", "&apos;",
	)
	return replacer.Replace(text)
}
