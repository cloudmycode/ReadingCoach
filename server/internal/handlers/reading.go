package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"words/server/internal/logger"
	"words/server/internal/services"
	"words/server/pkg/utils"
)

type ReadingHandler struct{ service *services.ReadingService }

func NewReadingHandler(s *services.ReadingService) *ReadingHandler {
	return &ReadingHandler{service: s}
}
func (h *ReadingHandler) respond(c *gin.Context, status int, run func(int) (any, error)) {
	user := getUserID(c)
	if user <= 0 {
		return
	}
	data, err := run(user)
	if err != nil {
		status, message := http.StatusInternalServerError, "服务暂时不可用，请稍后重试"
		switch {
		case errors.Is(err, services.ErrReadingNotFound):
			status, message = 404, "内容不存在"
		case errors.Is(err, services.ErrReadingInvalid):
			status, message = 400, "请求参数不正确"
		case errors.Is(err, services.ErrReadingLocked):
			status, message = 409, "请先听完全文音频"
		case errors.Is(err, services.ErrReadingConflict):
			status, message = 409, "当前状态无法执行此操作，请刷新后重试"
		default:
			logger.Error("阅读接口失败: %v", err)
		}
		jsonError(c, status, message)
		return
	}

	c.JSON(status, gin.H{"success": true, "message": "ok", "data": data})
}
func readingArticleID(c *gin.Context) (int64, error) {
	id, err := utils.DecryptID(c.Param("id"))
	if err != nil || id <= 0 {
		return 0, services.ErrReadingInvalid
	}
	return id, nil
}
func readingBody(c *gin.Context, value any) error {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 64<<10)
	if err := c.ShouldBindJSON(value); err != nil {
		return services.ErrReadingInvalid
	}
	return nil
}
func (h *ReadingHandler) Paper(c *gin.Context) {
	h.respond(c, http.StatusOK, func(user int) (any, error) {
		id, e := readingArticleID(c)
		if e != nil {
			return nil, e
		}
		return h.service.Paper(c.Request.Context(), user, id)
	})
}
func (h *ReadingHandler) Listening(c *gin.Context) {
	h.respond(c, http.StatusOK, func(user int) (any, error) {
		id, e := readingArticleID(c)
		if e != nil {
			return nil, e
		}
		var body struct {
			PaperID    int64  `json:"paper_id"`
			SentenceID int64  `json:"sentence_id"`
			Hash       string `json:"content_hash"`
		}
		if e = readingBody(c, &body); e != nil {
			return nil, e
		}
		e = h.service.CompleteListening(c.Request.Context(), user, id, body.PaperID, body.SentenceID, body.Hash)
		return gin.H{"recorded": e == nil}, e
	})
}
func (h *ReadingHandler) Submit(c *gin.Context) {
	h.respond(c, http.StatusAccepted, func(user int) (any, error) {
		id, e := readingArticleID(c)
		if e != nil {
			return nil, e
		}
		var body struct {
			PaperID   int64                    `json:"paper_id"`
			RequestID string                   `json:"request_id"`
			Answers   []services.ReadingAnswer `json:"answers"`
		}
		if e = readingBody(c, &body); e != nil {
			return nil, e
		}
		return h.service.Submit(c.Request.Context(), user, id, body.PaperID, body.RequestID, body.Answers)
	})
}
func (h *ReadingHandler) Attempts(c *gin.Context) {
	h.respond(c, http.StatusOK, func(user int) (any, error) {
		id, e := readingArticleID(c)
		if e != nil {
			return nil, e
		}
		return h.service.Attempts(c.Request.Context(), user, id)
	})
}
func (h *ReadingHandler) Attempt(c *gin.Context) {
	h.respond(c, http.StatusOK, func(user int) (any, error) {
		return h.service.Attempt(c.Request.Context(), user, parseParamInt64(c.Param("attempt_id")))
	})
}
func (h *ReadingHandler) Retry(kind string) gin.HandlerFunc {
	return func(c *gin.Context) {
		h.respond(c, http.StatusOK, func(user int) (any, error) {
			id := parseParamInt64(c.Param("paper_id"))
			if kind == "grade" {
				id = parseParamInt64(c.Param("attempt_id"))
			}
			e := h.service.Retry(c.Request.Context(), user, kind, id)
			return gin.H{"queued": e == nil}, e
		})
	}
}
func (h *ReadingHandler) Challenge(c *gin.Context) {
	h.respond(c, http.StatusOK, func(user int) (any, error) { return h.service.Challenge(c.Request.Context(), user) })
}
func (h *ReadingHandler) Cycles(c *gin.Context) {
	h.respond(c, http.StatusOK, func(user int) (any, error) { return h.service.Cycles(c.Request.Context(), user) })
}
func (h *ReadingHandler) Vouchers(c *gin.Context) {
	h.respond(c, http.StatusOK, func(user int) (any, error) {
		return h.service.Vouchers(c.Request.Context(), user, c.Query("status"), parseQueryInt(c.Query("limit"), 50), parseQueryInt(c.Query("offset"), 0))
	})
}
func (h *ReadingHandler) Redeem(c *gin.Context) {
	h.respond(c, http.StatusOK, func(user int) (any, error) {
		return h.service.Redeem(c.Request.Context(), user, parseParamInt64(c.Param("voucher_id")))
	})
}
