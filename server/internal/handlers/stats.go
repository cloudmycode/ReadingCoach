package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"words/server/internal/logger"
	"words/server/internal/services"
)

type StatsHandler struct {
	articleService *services.ArticleService
}

func NewStatsHandler(articleService *services.ArticleService) *StatsHandler {
	return &StatsHandler{
		articleService: articleService,
	}
}

func (h *StatsHandler) GetOverview(c *gin.Context) {
	if h.articleService == nil {
		jsonError(c, http.StatusServiceUnavailable, "统计服务未配置")
		return
	}

	userID := getUserID(c)
	if userID == 0 {
		return
	}

	days := parseQueryInt(c.Query("days"), 7)
	stats, err := h.articleService.GetUserStudyStats(c.Request.Context(), userID, days)
	if err != nil {
		logger.Error("❌ 获取学习统计失败 user=%d: %v", userID, err)
		jsonError(c, http.StatusInternalServerError, "获取学习统计失败")
		return
	}

	jsonOK(c, "获取成功", stats)
}

type reportReviewDurationReq struct {
	Seconds int `json:"seconds"`
}

// ReportReviewDuration 上报词卡复习有效时长（整场会话心跳累计）。
func (h *StatsHandler) ReportReviewDuration(c *gin.Context) {
	if h.articleService == nil {
		jsonError(c, http.StatusServiceUnavailable, "统计服务未配置")
		return
	}

	userID := getUserID(c)
	if userID == 0 {
		return
	}

	var req reportReviewDurationReq
	if err := c.ShouldBindJSON(&req); err != nil {
		jsonError(c, http.StatusBadRequest, "参数错误")
		return
	}

	total, err := h.articleService.AddReviewDuration(c.Request.Context(), userID, req.Seconds)
	if err != nil {
		if strings.Contains(err.Error(), "invalid duration") {
			jsonError(c, http.StatusBadRequest, "时长无效")
			return
		}
		logger.Error("❌ 上报复习时长失败 user=%d: %v", userID, err)
		jsonError(c, http.StatusInternalServerError, "上报复习时长失败")
		return
	}

	jsonOK(c, "已记录", gin.H{
		"review_seconds": total,
		"added":          req.Seconds,
	})
}
