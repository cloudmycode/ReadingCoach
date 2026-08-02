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

type ReviewHandler struct {
	articleService *services.ArticleService
}

func NewReviewHandler(articleService *services.ArticleService) *ReviewHandler {
	return &ReviewHandler{articleService: articleService}
}

func (h *ReviewHandler) GetToday(c *gin.Context) {
	if h.articleService == nil {
		jsonError(c, http.StatusServiceUnavailable, "复习任务服务未配置")
		return
	}

	userID := getUserID(c)
	if userID == 0 {
		return
	}

	summary, err := h.articleService.GetWordReviewTodaySummary(c.Request.Context(), userID)
	if err != nil {
		logger.Error("❌ 获取今日生词复习概览失败 user=%d: %v", userID, err)
		jsonError(c, http.StatusInternalServerError, "获取今日复习概览失败")
		return
	}

	jsonOK(c, "获取成功", gin.H{
		"due_count":       summary.DueCount,
		"completed_count": summary.CompletedCount,
		"daily_limit":     summary.DailyLimit,
		"streak_days":     summary.StreakDays,
	})
}

func (h *ReviewHandler) ListTasks(c *gin.Context) {
	if h.articleService == nil {
		jsonError(c, http.StatusServiceUnavailable, "复习任务服务未配置")
		return
	}

	userID := getUserID(c)
	if userID == 0 {
		return
	}

	status := strings.TrimSpace(strings.ToLower(c.DefaultQuery("status", "pending")))
	if status != "pending" && status != "completed" {
		jsonError(c, http.StatusBadRequest, "任务状态不支持")
		return
	}

	tasks, err := h.articleService.ListWordReviewTasks(c.Request.Context(), userID, status)
	if err != nil {
		logger.Error("❌ 获取生词复习任务失败 user=%d status=%s: %v", userID, status, err)
		jsonError(c, http.StatusInternalServerError, "获取复习任务失败")
		return
	}

	items := make([]gin.H, 0, len(tasks))
	for _, task := range tasks {
		items = append(items, wordReviewTaskPayload(task))
	}

	jsonOK(c, "获取成功", gin.H{
		"items":  items,
		"status": status,
	})
}

type submitWordReviewReq struct {
	Result string `json:"result"`
}

func (h *ReviewHandler) SubmitResult(c *gin.Context) {
	if h.articleService == nil {
		jsonError(c, http.StatusServiceUnavailable, "复习任务服务未配置")
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

	var req submitWordReviewReq
	if err := c.ShouldBindJSON(&req); err != nil {
		jsonError(c, http.StatusBadRequest, "参数错误")
		return
	}

	result, err := h.articleService.SubmitWordReviewResult(c.Request.Context(), userID, entryID, req.Result)
	if err != nil {
		msg := err.Error()
		switch {
		case strings.Contains(msg, "not found"):
			jsonError(c, http.StatusNotFound, "生词不存在")
		case strings.Contains(msg, "paused"):
			jsonError(c, http.StatusBadRequest, "该生词已暂停复习")
		case strings.Contains(msg, "invalid review result"):
			jsonError(c, http.StatusBadRequest, "复习结果不支持")
		default:
			logger.Error("❌ 提交生词复习结果失败 user=%d entry=%d: %v", userID, entryID, err)
			jsonError(c, http.StatusInternalServerError, "提交复习结果失败")
		}
		return
	}

	payload := gin.H{
		"entry_id":       result.EntryID,
		"result":         result.Result,
		"review_step":    result.ReviewStep,
		"mastery_status": result.MasteryStatus,
	}
	if result.NextReviewAt != nil {
		payload["next_review_at"] = result.NextReviewAt.Format("2006-01-02")
	}
	if result.LastReviewedAt != nil {
		payload["last_reviewed_at"] = result.LastReviewedAt.Format(time.RFC3339)
	}
	jsonOK(c, "复习结果已保存", payload)
}

func wordReviewTaskPayload(task services.WordReviewTask) gin.H {
	item := gin.H{
		"entry_id":             task.EntryID,
		"word":                 task.Word,
		"normalized_word":      task.NormalizedWord,
		"part_of_speech":       task.PartOfSpeech,
		"meaning":              task.Meaning,
		"tip":                  task.Tip,
		"sentence_original":    task.SentenceOriginal,
		"sentence_translation": task.SentenceTranslation,
		"article_id":           utils.EncryptID(task.ArticleID),
		"article_title":        task.ArticleTitle,
		"sentence_id":          task.SentenceID,
		"review_step":          task.ReviewStep,
		"mastery_status":       task.MasteryStatus,
	}
	if task.LogID > 0 {
		item["log_id"] = task.LogID
	}
	if task.Result != "" {
		item["result"] = task.Result
	}
	if task.NextReviewAt != nil {
		item["next_review_at"] = task.NextReviewAt.Format("2006-01-02")
	}
	if task.LastReviewedAt != nil {
		item["last_reviewed_at"] = task.LastReviewedAt.Format(time.RFC3339)
	}
	return item
}
