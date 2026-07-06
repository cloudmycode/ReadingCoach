package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"words/server/internal/logger"
	"words/server/pkg/utils"
)

// ImageAnalyzer 图片分析器接口
type ImageAnalyzer interface {
	AnalyzeImagesWithPrompt(ctx context.Context, images [][]byte, prompt string) ([][]string, error)
}

// TTSService 语音合成服务接口
type TTSService interface {
	GenerateAudio(ctx context.Context, text string, userID string) ([]byte, error)
}

// AIService 统一封装 DeepSeek 图片解析和 Microsoft TTS。
type AIService struct {
	deepSeekAPIKey string
	deepSeekAPIURL string
	deepSeekModel  string

	microsoftTTSKey    string
	microsoftTTSRegion string
	microsoftTTSVoice  string
	microsoftTTSAPIURL string

	client *http.Client
}

// 兼容旧命名，避免其他代码大面积改动。
type DoubaoService = AIService

// NewAIService 创建统一 AI 服务实例。
func NewAIService(
	deepSeekAPIKey,
	deepSeekAPIURL,
	deepSeekModel,
	microsoftTTSKey,
	microsoftTTSRegion,
	microsoftTTSVoice,
	microsoftTTSAPIURL string,
) *AIService {
	hasVision := strings.TrimSpace(deepSeekAPIKey) != ""
	hasTTS := strings.TrimSpace(microsoftTTSKey) != "" && (strings.TrimSpace(microsoftTTSRegion) != "" || strings.TrimSpace(microsoftTTSAPIURL) != "")
	if !hasVision && !hasTTS {
		return nil
	}

	if deepSeekAPIURL == "" {
		deepSeekAPIURL = "https://api.deepseek.com/v1/chat/completions"
	}
	if deepSeekModel == "" {
		deepSeekModel = "replace-with-deepseek-vision-model"
	}
	if microsoftTTSVoice == "" {
		microsoftTTSVoice = "en-US-JennyNeural"
	}
	if microsoftTTSAPIURL == "" && microsoftTTSRegion != "" {
		microsoftTTSAPIURL = fmt.Sprintf("https://%s.tts.speech.microsoft.com/cognitiveservices/v1", microsoftTTSRegion)
	}

	return &AIService{
		deepSeekAPIKey:     deepSeekAPIKey,
		deepSeekAPIURL:     deepSeekAPIURL,
		deepSeekModel:      deepSeekModel,
		microsoftTTSKey:    microsoftTTSKey,
		microsoftTTSRegion: microsoftTTSRegion,
		microsoftTTSVoice:  microsoftTTSVoice,
		microsoftTTSAPIURL: microsoftTTSAPIURL,
		client:             &http.Client{Timeout: 90 * time.Second},
	}
}

// NewDoubaoService 保留旧构造函数签名作为兼容层。
func NewDoubaoService(
	apiKey,
	apiURL,
	model,
	ttsKey,
	ttsRegion,
	ttsVoice,
	ttsAPIURL string,
) *AIService {
	return NewAIService(apiKey, apiURL, model, ttsKey, ttsRegion, ttsVoice, ttsAPIURL)
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

func (s *AIService) AnalyzeImagesWithPrompt(ctx context.Context, images [][]byte, prompt string) ([][]string, error) {
	lines, _, err := s.AnalyzeImagesWithPromptAndUsage(ctx, images, prompt)
	return lines, err
}

// AnalyzeImagesWithPromptAndUsage 使用 DeepSeek 进行图文解析，并返回 token 使用量。
func (s *AIService) AnalyzeImagesWithPromptAndUsage(ctx context.Context, images [][]byte, prompt string) ([][]string, int, error) {
	if strings.TrimSpace(s.deepSeekAPIKey) == "" {
		return nil, 0, fmt.Errorf("deepseek api key not configured")
	}
	if len(images) == 0 {
		return nil, 0, fmt.Errorf("no image data provided")
	}

	content := make([]aiChatContentPart, 0, len(images)+1)
	validImages := 0
	totalBytes := 0
	for idx, imageData := range images {
		if len(imageData) == 0 {
			continue
		}
		validImages++
		totalBytes += len(imageData)
		content = append(content, aiChatContentPart{
			Type: "image_url",
			ImageURL: &aiImageURLPart{
				URL: "data:image/jpeg;base64," + base64.StdEncoding.EncodeToString(imageData),
			},
		})
		content = append(content, aiChatContentPart{
			Type: "text",
			Text: fmt.Sprintf("以上是第 %d 张图片。", validImages),
		})
		logger.Debug("🖼️ DeepSeek 图片[%d] 已编码: 源字节=%d", idx, len(imageData))
	}
	if validImages == 0 {
		return nil, 0, fmt.Errorf("no valid image data")
	}

	content = append(content, aiChatContentPart{
		Type: "text",
		Text: prompt,
	})

	requestBody := aiChatRequest{
		Model:       s.deepSeekModel,
		MaxTokens:   4096,
		Temperature: 0.1,
		Messages: []aiChatMessage{
			{
				Role:    "user",
				Content: content,
			},
		},
	}

	payload, err := json.Marshal(requestBody)
	if err != nil {
		return nil, 0, fmt.Errorf("marshal request: %w", err)
	}

	logger.Debug("📤 DeepSeek 请求构造完成: prompt=%d字符, 图片数=%d, 总字节=%d, payload=%d字节", len(prompt), validImages, totalBytes, len(payload))

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.deepSeekAPIURL, bytes.NewReader(payload))
	if err != nil {
		return nil, 0, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.deepSeekAPIKey)

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, 0, fmt.Errorf("read response: %w", err)
	}

	logger.Debug("📥 DeepSeek 响应状态: %d, 长度: %d字节", resp.StatusCode, len(body))
	if resp.StatusCode != http.StatusOK {
		return nil, 0, fmt.Errorf("deepseek error: %s", string(body))
	}

	var result aiChatResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, 0, fmt.Errorf("decode response: %w", err)
	}
	if len(result.Choices) == 0 {
		return nil, 0, fmt.Errorf("deepseek returned empty choices")
	}

	rawContent, err := extractAIMessageText(result.Choices[0].Message.Content)
	if err != nil {
		return nil, 0, err
	}

	lines, err := utils.ParseTSVLines(rawContent)
	if err != nil {
		return nil, 0, fmt.Errorf("parse TSV format: %w", err)
	}

	return lines, result.Usage.TotalTokens, nil
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

// GenerateAudio 使用 Microsoft TTS 生成 MP3 音频。
func (s *AIService) GenerateAudio(ctx context.Context, text string, userID string) ([]byte, error) {
	_ = userID

	if strings.TrimSpace(s.microsoftTTSKey) == "" {
		return nil, fmt.Errorf("microsoft tts key not configured")
	}
	if strings.TrimSpace(s.microsoftTTSAPIURL) == "" {
		return nil, fmt.Errorf("microsoft tts endpoint not configured")
	}

	voiceName := s.voiceForText(text)
	ssml := buildSpeechSSML(text, voiceName)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.microsoftTTSAPIURL, strings.NewReader(ssml))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Ocp-Apim-Subscription-Key", s.microsoftTTSKey)
	if strings.TrimSpace(s.microsoftTTSRegion) != "" {
		req.Header.Set("Ocp-Apim-Subscription-Region", s.microsoftTTSRegion)
	}
	req.Header.Set("Content-Type", "application/ssml+xml")
	req.Header.Set("X-Microsoft-OutputFormat", "audio-24khz-48kbitrate-mono-mp3")
	req.Header.Set("User-Agent", "ReadingCoachServer")

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	audioData, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("microsoft tts error: status=%d body=%s", resp.StatusCode, string(audioData))
	}
	if len(audioData) == 0 {
		return nil, fmt.Errorf("empty audio data received")
	}

	logger.Debug("🎵 Microsoft TTS 音频生成完成: voice=%s, text=%d字符, 总大小=%d字节", voiceName, len(text), len(audioData))
	return audioData, nil
}

func (s *AIService) voiceForText(text string) string {
	if containsChinese(text) {
		return "zh-CN-XiaoxiaoNeural"
	}
	return s.microsoftTTSVoice
}

func containsChinese(text string) bool {
	for _, r := range text {
		if r >= 0x4E00 && r <= 0x9FFF {
			return true
		}
	}
	return false
}

func buildSpeechSSML(text, voice string) string {
	return fmt.Sprintf(
		`<speak version="1.0" xml:lang="en-US"><voice name="%s">%s</voice></speak>`,
		voice,
		xmlEscapeText(strings.TrimSpace(text)),
	)
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
