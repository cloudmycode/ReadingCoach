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

	tasks, err := h.articleService.ListReviewTasks(c.Request.Context(), userID, status)
	if err != nil {
		logger.Error("❌ 获取复习任务失败 user=%d status=%s: %v", userID, status, err)
		jsonError(c, http.StatusInternalServerError, "获取复习任务失败")
		return
	}

	items := make([]gin.H, 0, len(tasks))
	for _, task := range tasks {
		item := gin.H{
			"task_id":        task.TaskID,
			"article_id":     utils.EncryptID(task.ArticleID),
			"article_title":  task.ArticleTitle,
			"sentence_count": task.SentenceCount,
			"word_count":     task.WordCount,
			"scheduled_for":  task.ScheduledFor.Format("2006-01-02"),
			"status":         task.Status,
		}
		if task.StartedAt != nil {
			item["started_at"] = task.StartedAt.Format(time.RFC3339)
		}
		if task.CompletedAt != nil {
			item["completed_at"] = task.CompletedAt.Format(time.RFC3339)
		}
		items = append(items, item)
	}

	jsonOK(c, "获取成功", gin.H{
		"items":  items,
		"status": status,
	})
}

func (h *ReviewHandler) CompleteArticleTask(c *gin.Context) {
	if h.articleService == nil {
		jsonError(c, http.StatusServiceUnavailable, "复习任务服务未配置")
		return
	}

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

	task, completed, err := h.articleService.CompleteReviewTaskByArticleID(c.Request.Context(), int64(articleID), userID)
	if err != nil {
		logger.Error("❌ 完成复习任务失败 article=%d user=%d: %v", articleID, userID, err)
		jsonError(c, http.StatusInternalServerError, "完成复习任务失败")
		return
	}

	if !completed || task == nil {
		jsonOK(c, "当前没有可完成的复习任务", gin.H{
			"completed":  false,
			"article_id": utils.EncryptID(int64(articleID)),
		})
		return
	}

	payload := gin.H{
		"completed":      true,
		"task_id":        task.TaskID,
		"article_id":     utils.EncryptID(task.ArticleID),
		"article_title":  task.ArticleTitle,
		"sentence_count": task.SentenceCount,
		"word_count":     task.WordCount,
		"scheduled_for":  task.ScheduledFor.Format("2006-01-02"),
		"status":         task.Status,
	}
	if task.CompletedAt != nil {
		payload["completed_at"] = task.CompletedAt.Format(time.RFC3339)
	}
	jsonOK(c, "复习任务已完成", payload)
}
