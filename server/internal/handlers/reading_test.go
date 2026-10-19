package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"words/server/pkg/utils"
)

func TestReadingRouteRegistrationAndAuth(t *testing.T) {
	gin.SetMode(gin.TestMode)
	h := &Handlers{Auth: &AuthHandler{}, Article: &ArticleHandler{}, Review: &ReviewHandler{}, WordBook: &WordBookHandler{}, Stats: &StatsHandler{}, Reading: &ReadingHandler{}}
	r := gin.New()
	h.Register(r.Group("/api"), func(c *gin.Context) { c.AbortWithStatus(http.StatusUnauthorized) })
	routes := []struct{ method, path string }{{"GET", "/api/articles/x/quiz"}, {"POST", "/api/articles/x/quiz/attempts"}, {"POST", "/api/articles/x/listening-completions"}, {"GET", "/api/reading/challenge"}, {"GET", "/api/reading/cycles"}, {"GET", "/api/reading/attempts/1"}, {"POST", "/api/reading/attempts/1/retry"}, {"POST", "/api/reading/papers/1/retry"}, {"GET", "/api/reading/vouchers"}, {"POST", "/api/reading/vouchers/1/redeem"}}
	for _, route := range routes {
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest(route.method, route.path, nil))
		if w.Code != 401 {
			t.Errorf("%s: %d", route.path, w.Code)
		}
	}
}
func TestReadingRejectsBadAndLargeBodies(t *testing.T) {
	gin.SetMode(gin.TestMode)
	h := &ReadingHandler{}
	r := gin.New()
	r.Use(func(c *gin.Context) { c.Set("user_id", 1) })
	r.POST("/api/articles/:id/quiz/attempts", h.Submit)
	for _, body := range []string{`{`, `{"answers":"invalid"}`, `{"unused":"` + strings.Repeat("x", 65<<10) + `"}`} {
		req := httptest.NewRequest("POST", "/api/articles/"+utils.EncryptID(1)+"/quiz/attempts", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if w.Code != 400 {
			t.Fatalf("bad body accepted: %d", w.Code)
		}
	}
}
