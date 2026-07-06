package handlers

import (
	"net/http"

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
