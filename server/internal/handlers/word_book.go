package handlers

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"words/server/internal/logger"
	"words/server/internal/services"
	"words/server/pkg/utils"
)

type WordBookHandler struct {
	articleService *services.ArticleService
}

func NewWordBookHandler(articleService *services.ArticleService) *WordBookHandler {
	return &WordBookHandler{articleService: articleService}
}

func (h *WordBookHandler) ListWordBook(c *gin.Context) {
	if h.articleService == nil {
		jsonError(c, http.StatusServiceUnavailable, "生词本服务未配置")
		return
	}

	userID := getUserID(c)
	if userID == 0 {
		return
	}

	entries, err := h.articleService.ListUserWordBook(c.Request.Context(), userID)
	if err != nil {
		logger.Error("❌ 获取生词本失败 user=%d: %v", userID, err)
		jsonError(c, http.StatusInternalServerError, "获取生词本失败")
		return
	}

	items := make([]gin.H, 0, len(entries))
	for _, entry := range entries {
		items = append(items, gin.H{
			"entry_id":             entry.EntryID,
			"article_id":           utils.EncryptID(entry.ArticleID),
			"sentence_id":          entry.SentenceID,
			"word":                 entry.Word,
			"normalized_word":      entry.NormalizedWord,
			"sentence_original":    entry.SentenceOriginal,
			"sentence_translation": entry.SentenceTranslation,
			"part_of_speech":       entry.PartOfSpeech,
			"meaning":              entry.Meaning,
			"tip":                  entry.Tip,
			"looked_up_at":         entry.LookedUpAt.Format(time.RFC3339),
		})
	}

	jsonOK(c, "获取成功", gin.H{"items": items})
}

func (h *WordBookHandler) DeleteWordBookEntry(c *gin.Context) {
	if h.articleService == nil {
		jsonError(c, http.StatusServiceUnavailable, "生词本服务未配置")
		return
	}

	userID := getUserID(c)
	if userID == 0 {
		return
	}

	entryID := parseParamInt64(c.Param("entry_id"))
	if entryID <= 0 {
		jsonError(c, http.StatusBadRequest, "无效的生词ID")
		return
	}

	if err := h.articleService.DeleteUserWordBookEntry(c.Request.Context(), userID, entryID); err != nil {
		if strings.Contains(err.Error(), "not found") {
			jsonError(c, http.StatusNotFound, "生词不存在")
			return
		}
		logger.Error("❌ 删除生词失败 user=%d entry=%d: %v", userID, entryID, err)
		jsonError(c, http.StatusInternalServerError, "删除生词失败")
		return
	}

	jsonOK(c, "删除成功", gin.H{"entry_id": entryID})
}
