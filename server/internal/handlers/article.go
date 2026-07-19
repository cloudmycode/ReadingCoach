package handlers

import (
	"bytes"
	"context"
	"fmt"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/hajimehoshi/go-mp3"

	"words/server/internal/logger"
	"words/server/internal/services"
	"words/server/pkg/utils"
)

const (
	articleAudioSubDir = "articleaudio"
)

type ArticleHandler struct {
	attachmentsDir string
	audioDir       string
	articleService *services.ArticleService
	ttsService     services.TTSService
	textAnalyzer   services.TextAnalyzer
}

// NewArticleHandler 创建文章处理器实例
func NewArticleHandler(attachmentsDir string, articleService *services.ArticleService, ttsService services.TTSService, textAnalyzer services.TextAnalyzer) *ArticleHandler {
	audioDir := filepath.Join(attachmentsDir, articleAudioSubDir)

	if err := os.MkdirAll(audioDir, 0o755); err != nil {
		logger.Warn("⚠️ 创建音频目录失败: %s, err=%v", audioDir, err)
	}

	return &ArticleHandler{
		attachmentsDir: attachmentsDir,
		audioDir:       audioDir,
		articleService: articleService,
		ttsService:     ttsService,
		textAnalyzer:   textAnalyzer,
	}
}

type processArticleTextReq struct {
	Text string `json:"text"`
}

// GetArticleDetail 根据加密的文章ID获取文章详情（包括标题和所有句子）
// 参数:
//   - id: 加密后的文章ID（URL路径参数）
//
// 返回:
//   - ArticleDetail: 包含文章ID、标题、句子数量和句子列表
//
// 注意:
//   - 需要用户登录认证
//   - 只能获取当前用户自己的文章
func (h *ArticleHandler) GetArticleDetail(c *gin.Context) {
	encryptedID := c.Param("id")
	if encryptedID == "" {
		jsonError(c, http.StatusBadRequest, "文章ID不能为空")
		return
	}

	// 解密文章ID
	articleID, err := utils.DecryptID(encryptedID)
	if err != nil {
		logger.Error("❌ 解密文章ID失败: %v", err)
		jsonError(c, http.StatusBadRequest, "无效的文章ID")
		return
	}

	// 获取用户ID
	userID := getUserID(c)
	if userID == 0 {
		return // getUserID 已经处理了错误响应
	}

	// 获取文章详情
	detail, err := h.articleService.GetArticleDetail(c.Request.Context(), articleID, userID)
	if err != nil {
		logger.Error("❌ 获取文章详情失败: %v", err)
		if err.Error() == "article not found" {
			jsonError(c, http.StatusNotFound, "文章不存在")
		} else {
			jsonError(c, http.StatusInternalServerError, "获取文章详情失败")
		}
		return
	}

	// 更新阅读统计
	if err := h.articleService.UpdateArticleReadStats(c.Request.Context(), articleID, userID); err != nil {
		logger.Warn("⚠️ 更新文章阅读统计失败 article=%d user=%d: %v", articleID, userID, err)
	}

	jsonOK(c, "获取成功", detail)
}

// ListArticles 获取文章列表
func (h *ArticleHandler) ListArticles(c *gin.Context) {
	if h.articleService == nil {
		jsonError(c, http.StatusServiceUnavailable, "文章服务未配置")
		return
	}

	// 获取用户ID
	userID := getUserID(c)
	if userID == 0 {
		return // getUserID 已经处理了错误响应
	}

	limit := parseQueryInt(c.Query("limit"), 50)
	offset := parseQueryInt(c.Query("offset"), 0)

	articles, err := h.articleService.ListUserArticles(c.Request.Context(), userID, limit, offset)
	if err != nil {
		logger.Error("❌ 获取文章列表失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "获取文章列表失败")
		return
	}

	items := make([]gin.H, 0, len(articles))
	for _, article := range articles {
		var lastRead string
		if article.LastReadAt != nil {
			lastRead = article.LastReadAt.Format(time.RFC3339)
		}
		items = append(items, gin.H{
			"id":                utils.EncryptID(article.ArticleID),
			"article_id":        article.ArticleID,
			"title":             article.Title,
			"sentence_count":    article.SentenceCount,
			"read_count":        article.ReadCount,
			"sentence_duration": article.SentenceDuration,
			"created_at":        article.CreatedAt.Format(time.RFC3339),
			"last_read_at":      lastRead,
		})
	}

	jsonOK(c, "获取成功", gin.H{
		"items":  items,
		"limit":  limit,
		"offset": offset,
	})
}

// DeleteArticle 删除文章。
func (h *ArticleHandler) DeleteArticle(c *gin.Context) {
	encryptedID := c.Param("id")
	if encryptedID == "" {
		jsonError(c, http.StatusBadRequest, "文章ID不能为空")
		return
	}

	articleID, err := utils.DecryptID(encryptedID)
	if err != nil {
		logger.Error("❌ 解密文章ID失败: %v", err)
		jsonError(c, http.StatusBadRequest, "无效的文章ID")
		return
	}

	userID := getUserID(c)
	if userID == 0 {
		return
	}

	if err := h.articleService.DeleteArticle(c.Request.Context(), articleID, userID); err != nil {
		logger.Error("❌ 删除文章失败 article=%d user=%d: %v", articleID, userID, err)
		if err.Error() == "article not found" {
			jsonError(c, http.StatusNotFound, "文章不存在")
			return
		}
		jsonError(c, http.StatusInternalServerError, "删除文章失败")
		return
	}

	jsonOK(c, "删除成功", gin.H{})
}

func (h *ArticleHandler) ProcessArticleText(c *gin.Context) {
	var req processArticleTextReq
	if err := c.ShouldBindJSON(&req); err != nil {
		jsonError(c, http.StatusBadRequest, "参数错误")
		return
	}

	userID := getUserID(c)
	if userID == 0 {
		return
	}
	if h.articleService == nil {
		jsonError(c, http.StatusInternalServerError, "文章服务未配置")
		return
	}
	if h.textAnalyzer == nil {
		jsonError(c, http.StatusInternalServerError, "文本分析服务未配置")
		return
	}

	rawText := strings.TrimSpace(req.Text)
	if rawText == "" {
		jsonError(c, http.StatusBadRequest, "正文内容不能为空")
		return
	}

	result, err := h.textAnalyzer.AnalyzeTextWithPrompt(
		c.Request.Context(),
		rawText,
		services.ArticleTextAnalysisPrompt,
	)
	if err != nil {
		logger.Error("❌ 文本解析失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "解析文本失败: "+err.Error())
		return
	}

	sentenceInputs := convertAIDataToSentences(result)
	if len(sentenceInputs) == 0 {
		jsonError(c, http.StatusBadRequest, "未识别到有效句子")
		return
	}

	articleID, err := h.articleService.SaveAnalyzedArticle(
		c.Request.Context(),
		userID,
		sentenceInputs,
	)
	if err != nil {
		logger.Error("❌ 保存文章到数据库失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "保存文章失败: "+err.Error())
		return
	}

	if articleID > 0 {
		go h.GenerateAudioForSentences(articleID)
	}

	jsonOK(c, "处理成功", gin.H{
		"resource_id": utils.EncryptID(articleID),
	})
}

// GenerateAudioForSentences 在协程中为文章的句子生成音频（公开方法，供回调使用）
// 参数:
//   - articleID: 文章ID
//
// 注意:
//   - 此方法在协程中异步执行，不会阻塞主流程
//   - 如果生成失败，会记录错误日志但不影响主流程
//   - 使用 sentence_id 生成音频文件名，不再更新数据库中的 original_audio_path 和 translation_audio_path
//   - 从数据库查询获取句子信息和 sentence_id
func (h *ArticleHandler) GenerateAudioForSentences(articleID int64) {
	logger.Info("🎵 开始为文章 %d 生成音频", articleID)

	// 检查 TTS 服务
	if h.ttsService == nil {
		logger.Warn("⚠️ TTS 服务未配置，跳过音频生成")
		return
	}

	// 检查文章服务
	if h.articleService == nil {
		logger.Error("❌ 文章服务未配置，无法获取句子信息")
		return
	}

	// 从数据库获取句子信息
	sentences, err := h.articleService.GetArticleSentencesForAudio(context.Background(), articleID)
	if err != nil {
		logger.Error("❌ 获取文章句子信息失败 article=%d: %v", articleID, err)
		return
	}

	if len(sentences) == 0 {
		logger.Warn("⚠️ 文章 %d 没有句子，跳过音频生成", articleID)
		return
	}

	logger.Info("🎵 文章 %d 共 %d 个句子，开始生成音频", articleID, len(sentences))

	// 生成所有句子的音频并统计
	validSentenceCount, totalSentenceDuration := h.generateAllSentencesAudio(sentences)

	// 更新文章音频统计
	if err := h.articleService.UpdateArticleAudioStats(context.Background(), articleID, validSentenceCount, totalSentenceDuration); err != nil {
		logger.Error("❌ 更新文章音频统计失败 article=%d: %v", articleID, err)
	} else {
		logger.Info("📝 已更新文章 %d 的句子数=%d，总音频时长=%dms", articleID, validSentenceCount, totalSentenceDuration)
	}

	logger.Info("🎵 文章 %d 的音频生成完成", articleID)
}

// ============================================================================
// 辅助函数
// ============================================================================

// convertAIDataToSentences 将AI返回的结构化数据转换为句子输入
func convertAIDataToSentences(data [][]string) []services.ArticleSentenceInput {
	sentences := make([]services.ArticleSentenceInput, 0, len(data))
	for _, line := range data {
		if len(line) >= 2 {
			sentences = append(sentences, services.ArticleSentenceInput{
				Original:    strings.TrimSpace(line[0]),
				Translation: strings.TrimSpace(line[1]),
			})
		} else if len(line) == 1 && strings.TrimSpace(line[0]) != "" {
			sentences = append(sentences, services.ArticleSentenceInput{
				Original:    strings.TrimSpace(line[0]),
				Translation: "",
			})
		}
	}
	return sentences
}

// generateAllSentencesAudio 为所有句子生成音频
// 返回有效句子数量和总音频时长（毫秒）
func (h *ArticleHandler) generateAllSentencesAudio(sentences []services.SentenceForAudio) (int, int) {
	validSentenceCount := 0
	totalSentenceDuration := 0
	ctx := context.Background()

	for idx, sent := range sentences {
		originalText := strings.TrimSpace(sent.Original)
		translationText := strings.TrimSpace(sent.Translation)

		if originalText != "" || translationText != "" {
			validSentenceCount++
		}

		sentenceOrder := idx + 1
		originalDuration := h.generateSentenceAudio(ctx, originalText, sent.SentenceID, "original", sentenceOrder)
		translationDuration := h.generateSentenceAudio(ctx, translationText, sent.SentenceID, "translation", sentenceOrder)

		// 句子总时长使用原句优先，没有原句则用翻译
		if originalDuration > 0 {
			totalSentenceDuration += originalDuration
		} else if translationDuration > 0 {
			totalSentenceDuration += translationDuration
		}
	}

	return validSentenceCount, totalSentenceDuration
}

// generateSentenceAudio 为单个句子生成音频（原句或翻译）
// 返回音频时长（毫秒），失败返回0
func (h *ArticleHandler) generateSentenceAudio(ctx context.Context, text string, sentenceID int64, audioType string, sentenceOrder int) int {
	if text == "" {
		return 0
	}

	audioPath, durationMS, err := h.generateTTSAudio(ctx, text, sentenceID, audioType)
	if err != nil {
		logger.Error("❌ 生成句子 %d (sentence_id=%d) %s音频失败: %v", sentenceOrder, sentenceID, audioType, err)
		return 0
	}

	logger.Info("✅ 句子 %d (sentence_id=%d) %s音频生成成功: %s (duration=%dms)", sentenceOrder, sentenceID, audioType, audioPath, durationMS)
	return durationMS
}

// generateTTSAudio 为单个句子生成音频文件并保存
// 使用 sentence_id 来生成文件名，不再依赖数据库中的 original_audio_path 和 translation_audio_path
func (h *ArticleHandler) generateTTSAudio(ctx context.Context, text string, sentenceID int64, audioType string) (string, int, error) {
	// 调用 TTS 服务生成音频
	audioData, err := h.ttsService.GenerateAudio(ctx, text, fmt.Sprintf("%d", sentenceID))
	if err != nil {
		return "", 0, fmt.Errorf("generate audio: %w", err)
	}

	// 使用 sentence_id 生成文件名（根据类型区分：original 或 translation）
	fileName := fmt.Sprintf("audio_%d_%s.mp3", sentenceID, audioType)
	targetPath := filepath.Join(h.audioDir, fileName)
	if err := os.WriteFile(targetPath, audioData, 0644); err != nil {
		return "", 0, fmt.Errorf("save audio file: %w", err)
	}

	durationMS, err := calculateMP3DurationMillis(audioData)
	if err != nil {
		logger.Warn("⚠️ 计算音频时长失败 sentence_id=%d type=%s: %v", sentenceID, audioType, err)
		durationMS = 0
	}

	// 返回相对路径与时长
	return "/attachments/" + articleAudioSubDir + "/" + fileName, durationMS, nil
}

func calculateMP3DurationMillis(audioData []byte) (int, error) {
	if len(audioData) == 0 {
		return 0, fmt.Errorf("empty audio data")
	}

	decoder, err := mp3.NewDecoder(bytes.NewReader(audioData))
	if err != nil {
		return 0, fmt.Errorf("decode mp3: %w", err)
	}

	length := decoder.Length()
	sampleRate := decoder.SampleRate()
	if length <= 0 || sampleRate <= 0 {
		return 0, fmt.Errorf("invalid decoder metadata length=%d sampleRate=%d", length, sampleRate)
	}

	durationSeconds := float64(length) / float64(sampleRate*4)
	return int(math.Round(durationSeconds * 1000)), nil
}
