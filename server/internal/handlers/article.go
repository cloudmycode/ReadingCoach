package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"words/server/internal/logger"
	"words/server/internal/services"
	"words/server/pkg/utils"
)

type ArticleHandler struct {
	articleService *services.ArticleService
	textAnalyzer   services.TextAnalyzer
	imageExtractor services.ImageTextExtractor
}

// NewArticleHandler 创建文章处理器实例。
func NewArticleHandler(
	articleService *services.ArticleService,
	textAnalyzer services.TextAnalyzer,
	imageExtractor services.ImageTextExtractor,
) *ArticleHandler {
	return &ArticleHandler{
		articleService: articleService,
		textAnalyzer:   textAnalyzer,
		imageExtractor: imageExtractor,
	}
}

type processArticleTextReq struct {
	Text string `json:"text"`
}

type recognizeImageReq struct {
	ImageBase64 string `json:"image_base64"`
	MimeType    string `json:"mime_type"`
}

type updateArticleTitleReq struct {
	Title string `json:"title"`
}

type explainWordReq struct {
	Word string `json:"word"`
}

type askSentenceReq struct {
	Question string `json:"question"`
}

type updateSentenceReq struct {
	Original string `json:"original"`
}

type sentenceTranslationResp struct {
	Translation string `json:"translation"`
}

type explainWordResp struct {
	Word         string `json:"word"`
	PartOfSpeech string `json:"part_of_speech"`
	Meaning      string `json:"meaning"`
	Tip          string `json:"tip"`
	SentenceID   int64  `json:"sentence_id"`
	ArticleID    string `json:"article_id"`
}

type askSentenceResp struct {
	Answer     string   `json:"answer"`
	Highlights []string `json:"highlights"`
	SentenceID int64    `json:"sentence_id"`
	ArticleID  string   `json:"article_id"`
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
			"id":             utils.EncryptID(article.ArticleID),
			"article_id":     article.ArticleID,
			"title":          article.Title,
			"sentence_count": article.SentenceCount,
			"word_count":     article.WordCount,
			"read_count":     article.ReadCount,
			"created_at":     article.CreatedAt.Format(time.RFC3339),
			"last_read_at":   lastRead,
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

// UpdateArticleTitle 修改文章标题。
func (h *ArticleHandler) UpdateArticleTitle(c *gin.Context) {
	encryptedID := c.Param("id")
	articleID, err := utils.DecryptID(encryptedID)
	if encryptedID == "" || err != nil {
		jsonError(c, http.StatusBadRequest, "无效的文章ID")
		return
	}
	userID := getUserID(c)
	if userID == 0 {
		return
	}

	var req updateArticleTitleReq
	if err := c.ShouldBindJSON(&req); err != nil {
		jsonError(c, http.StatusBadRequest, "参数错误")
		return
	}
	title := strings.TrimSpace(req.Title)
	if title == "" {
		jsonError(c, http.StatusBadRequest, "标题不能为空")
		return
	}
	if len([]rune(title)) > 60 {
		jsonError(c, http.StatusBadRequest, "标题不能超过60个字符")
		return
	}

	updatedTitle, err := h.articleService.UpdateArticleTitle(c.Request.Context(), articleID, userID, title)
	if err != nil {
		if err.Error() == "article not found" {
			jsonError(c, http.StatusNotFound, "文章不存在")
			return
		}
		logger.Error("❌ 更新文章标题失败 article=%d user=%d: %v", articleID, userID, err)
		jsonError(c, http.StatusInternalServerError, "更新标题失败")
		return
	}

	jsonOK(c, "更新成功", gin.H{"title": updatedTitle})
}

// RecognizeArticleImage 接收拍照/相册上传的图片（base64），
// 调用视觉模型识别并整理为干净的英文正文文本后返回，供客户端校对。
func (h *ArticleHandler) RecognizeArticleImage(c *gin.Context) {
	if getUserID(c) == 0 {
		return
	}
	if h.imageExtractor == nil {
		jsonError(c, http.StatusServiceUnavailable, "图片识别服务未配置")
		return
	}

	var req recognizeImageReq
	if err := c.ShouldBindJSON(&req); err != nil {
		jsonError(c, http.StatusBadRequest, "参数错误")
		return
	}
	image := strings.TrimSpace(req.ImageBase64)
	if image == "" {
		jsonError(c, http.StatusBadRequest, "图片内容不能为空")
		return
	}

	logger.Info("🖼️ 收到图片识别请求 image=%d字节(base64) mime=%q", len(image), req.MimeType)
	started := time.Now()
	text, err := h.imageExtractor.ExtractArticleText(c.Request.Context(), image, req.MimeType)
	if err != nil {
		logger.Error("❌ 图片识别失败（总耗时 %s）: %v", time.Since(started), err)
		jsonError(c, http.StatusInternalServerError, "图片识别失败: "+err.Error())
		return
	}
	if strings.TrimSpace(text) == "" {
		logger.Warn("⚠️ 图片识别返回空正文（总耗时 %s）", time.Since(started))
		jsonError(c, http.StatusUnprocessableEntity, "未识别到正文内容，请重新拍摄")
		return
	}

	logger.Info("✅ 图片识别成功（总耗时 %s），正文 %d 字符", time.Since(started), len(text))
	jsonOK(c, "识别成功", gin.H{"text": text})
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

	title, sentenceInputs := convertAIDataToArticle(result)
	if len(sentenceInputs) == 0 {
		jsonError(c, http.StatusBadRequest, "未识别到有效句子")
		return
	}

	articleID, err := h.articleService.SaveAnalyzedArticle(
		c.Request.Context(),
		userID,
		title,
		sentenceInputs,
	)
	if err != nil {
		logger.Error("❌ 保存文章到数据库失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "保存文章失败: "+err.Error())
		return
	}

	jsonOK(c, "处理成功", gin.H{
		"resource_id": utils.EncryptID(articleID),
	})
}

func (h *ArticleHandler) ExplainSentenceWord(c *gin.Context) {
	articleID, sentenceID, userID, ok := h.parseSentenceRouteContext(c)
	if !ok {
		return
	}
	if h.textAnalyzer == nil {
		jsonError(c, http.StatusServiceUnavailable, "AI 服务未配置")
		return
	}

	var req explainWordReq
	if err := c.ShouldBindJSON(&req); err != nil {
		jsonError(c, http.StatusBadRequest, "参数错误")
		return
	}
	word := strings.TrimSpace(req.Word)
	if word == "" {
		jsonError(c, http.StatusBadRequest, "单词不能为空")
		return
	}

	if cached, err := h.articleService.GetCachedWordExplanation(c.Request.Context(), sentenceID, word); err != nil {
		logger.Error("❌ 查询单词解释缓存失败: %v", err)
	} else if cached != nil {
		jsonOK(c, "获取成功", explainWordResp{
			Word:         cached.Word,
			PartOfSpeech: cached.PartOfSpeech,
			Meaning:      cached.Meaning,
			Tip:          cached.Tip,
			SentenceID:   sentenceID,
			ArticleID:    utils.EncryptID(articleID),
		})
		return
	}

	sentence, err := h.articleService.GetSentenceStudyContext(c.Request.Context(), articleID, sentenceID, userID)
	if err != nil {
		h.handleSentenceContextError(c, err)
		return
	}

	prompt := fmt.Sprintf("%s\n\n文章标题：%s\n英文句子：%s\n中文翻译：%s\n用户点击的单词：%s",
		services.WordExplainPromptTemplate,
		sentence.ArticleTitle,
		sentence.Original,
		sentence.Translation,
		word,
	)

	raw, err := h.textAnalyzer.CompleteTextPrompt(c.Request.Context(), prompt)
	if err != nil {
		logger.Error("❌ 单词解释失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "生成单词解释失败")
		return
	}

	var response explainWordResp
	if err := decodeJSONObject(raw, &response); err != nil {
		logger.Error("❌ 单词解释解析失败: %v raw=%s", err, raw)
		jsonError(c, http.StatusInternalServerError, "单词解释解析失败")
		return
	}
	if strings.TrimSpace(response.Word) == "" {
		response.Word = word
	}
	if saveErr := h.articleService.SaveCachedWordExplanation(c.Request.Context(), services.CachedWordExplanation{
		SentenceID:     sentenceID,
		NormalizedWord: word,
		Word:           response.Word,
		PartOfSpeech:   response.PartOfSpeech,
		Meaning:        response.Meaning,
		Tip:            response.Tip,
	}); saveErr != nil {
		logger.Warn("⚠️ 保存单词解释缓存失败: %v", saveErr)
	}
	response.SentenceID = sentenceID
	response.ArticleID = utils.EncryptID(articleID)

	jsonOK(c, "获取成功", response)
}

func (h *ArticleHandler) UpdateSentence(c *gin.Context) {
	articleID, sentenceID, userID, ok := h.parseSentenceRouteContext(c)
	if !ok {
		return
	}
	if h.textAnalyzer == nil {
		jsonError(c, http.StatusServiceUnavailable, "AI 服务未配置")
		return
	}

	var req updateSentenceReq
	if err := c.ShouldBindJSON(&req); err != nil {
		jsonError(c, http.StatusBadRequest, "参数错误")
		return
	}
	original := strings.TrimSpace(req.Original)
	if original == "" {
		jsonError(c, http.StatusBadRequest, "句子内容不能为空")
		return
	}

	sentence, err := h.articleService.GetSentenceStudyContext(c.Request.Context(), articleID, sentenceID, userID)
	if err != nil {
		h.handleSentenceContextError(c, err)
		return
	}
	prompt := fmt.Sprintf(`请把下面修改后的英文句子准确、自然地翻译为简体中文。
只返回 JSON，不要添加解释或 Markdown：{"translation":"中文翻译"}

文章标题：%s
英文句子：%s`, sentence.ArticleTitle, original)
	raw, err := h.textAnalyzer.CompleteTextPrompt(c.Request.Context(), prompt)
	if err != nil {
		logger.Error("❌ 句子翻译失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "生成句子翻译失败")
		return
	}

	var translated sentenceTranslationResp
	if err := decodeJSONObject(raw, &translated); err != nil || strings.TrimSpace(translated.Translation) == "" {
		logger.Error("❌ 句子翻译解析失败: %v raw=%s", err, raw)
		jsonError(c, http.StatusInternalServerError, "句子翻译解析失败")
		return
	}

	updated, err := h.articleService.UpdateSentenceContent(
		c.Request.Context(), articleID, sentenceID, userID, original, translated.Translation,
	)
	if err != nil {
		if err.Error() == "sentence not found" {
			jsonError(c, http.StatusNotFound, "句子不存在")
			return
		}
		logger.Error("❌ 更新句子失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "更新句子失败")
		return
	}

	jsonOK(c, "更新成功", updated)
}

func (h *ArticleHandler) AskSentenceQuestion(c *gin.Context) {
	articleID, sentenceID, userID, ok := h.parseSentenceRouteContext(c)
	if !ok {
		return
	}
	if h.textAnalyzer == nil {
		jsonError(c, http.StatusServiceUnavailable, "AI 服务未配置")
		return
	}

	var req askSentenceReq
	if err := c.ShouldBindJSON(&req); err != nil {
		jsonError(c, http.StatusBadRequest, "参数错误")
		return
	}
	question := strings.TrimSpace(req.Question)
	if question == "" {
		jsonError(c, http.StatusBadRequest, "问题不能为空")
		return
	}

	sentence, err := h.articleService.GetSentenceStudyContext(c.Request.Context(), articleID, sentenceID, userID)
	if err != nil {
		h.handleSentenceContextError(c, err)
		return
	}

	prompt := fmt.Sprintf("%s\n\n文章标题：%s\n英文句子：%s\n中文翻译：%s\n用户问题：%s",
		services.SentenceCoachPromptTemplate,
		sentence.ArticleTitle,
		sentence.Original,
		sentence.Translation,
		question,
	)

	raw, err := h.textAnalyzer.CompleteTextPrompt(c.Request.Context(), prompt)
	if err != nil {
		logger.Error("❌ 句子问答失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "生成问答失败")
		return
	}

	var response askSentenceResp
	if err := decodeJSONObject(raw, &response); err != nil {
		logger.Error("❌ 句子问答解析失败: %v raw=%s", err, raw)
		jsonError(c, http.StatusInternalServerError, "问答解析失败")
		return
	}
	response.SentenceID = sentenceID
	response.ArticleID = utils.EncryptID(articleID)
	if response.Highlights == nil {
		response.Highlights = []string{}
	}

	jsonOK(c, "获取成功", response)
}

// ============================================================================
// 辅助函数
// ============================================================================

// convertAIDataToArticle 解析新版带标题格式，并兼容旧版英文/中文两列格式。
func convertAIDataToArticle(data [][]string) (string, []services.ArticleSentenceInput) {
	var title string
	sentences := make([]services.ArticleSentenceInput, 0, len(data))
	for _, line := range data {
		if len(line) >= 2 && strings.EqualFold(strings.TrimSpace(line[0]), "TITLE") {
			title = strings.TrimSpace(line[1])
			continue
		}
		if len(line) >= 3 && strings.EqualFold(strings.TrimSpace(line[0]), "SENTENCE") {
			sentences = append(sentences, services.ArticleSentenceInput{
				Original:    strings.TrimSpace(line[1]),
				Translation: strings.TrimSpace(line[2]),
			})
		} else if len(line) >= 2 {
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
	return title, sentences
}

func (h *ArticleHandler) parseSentenceRouteContext(c *gin.Context) (articleID int64, sentenceID int64, userID int, ok bool) {
	encryptedArticleID := c.Param("id")
	if encryptedArticleID == "" {
		jsonError(c, http.StatusBadRequest, "文章ID不能为空")
		return 0, 0, 0, false
	}

	articleID, err := utils.DecryptID(encryptedArticleID)
	if err != nil {
		jsonError(c, http.StatusBadRequest, "无效的文章ID")
		return 0, 0, 0, false
	}

	sentenceID = parseParamInt64(c.Param("sentence_id"))
	if sentenceID <= 0 {
		jsonError(c, http.StatusBadRequest, "无效的句子ID")
		return 0, 0, 0, false
	}

	userID = getUserID(c)
	if userID == 0 {
		return 0, 0, 0, false
	}
	return articleID, sentenceID, userID, true
}

func (h *ArticleHandler) handleSentenceContextError(c *gin.Context, err error) {
	logger.Error("❌ 获取句子上下文失败: %v", err)
	if err.Error() == "sentence not found" {
		jsonError(c, http.StatusNotFound, "句子不存在")
		return
	}
	jsonError(c, http.StatusInternalServerError, "获取句子信息失败")
}

func decodeJSONObject(raw string, target interface{}) error {
	trimmed := strings.TrimSpace(raw)
	start := strings.Index(trimmed, "{")
	end := strings.LastIndex(trimmed, "}")
	if start >= 0 && end > start {
		trimmed = trimmed[start : end+1]
	}
	return json.Unmarshal([]byte(trimmed), target)
}
