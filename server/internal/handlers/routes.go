package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// Handlers 聚合了所有业务 HTTP 处理器，便于统一注册路由。
type Handlers struct {
	Auth    *AuthHandler
	Article *ArticleHandler
	Review  *ReviewHandler
	Stats   *StatsHandler
}

// Route 描述单个 HTTP 接口。
// 这里刻意用一张“接口表”来集中声明所有接口，
// 只要看这一个文件就能直观了解后台对外提供了哪些能力。
type Route struct {
	Method  string          // 请求方法：GET / POST / DELETE ...
	Path    string          // 相对所在分组前缀的路径
	Auth    bool            // 是否需要登录认证（携带有效 JWT）
	Summary string          // 接口用途简述
	Handler gin.HandlerFunc // 具体处理函数
}

// APIGroup 表示共享同一路径前缀的一组接口。
type APIGroup struct {
	Prefix string  // 分组前缀，例如 /auth、/articles
	Desc   string  // 分组用途简述
	Routes []Route // 该分组下的接口列表
}

// APIRoutes 返回后台所有对外接口的完整定义。
//
// ┌─────────┬──────────────────────────┬──────┬──────────────────────────┐
// │ 方法    │ 路径                     │ 鉴权 │ 说明                     │
// ├─────────┼──────────────────────────┼──────┼──────────────────────────┤
// │ POST    │ /api/auth/code           │  否  │ 发送短信验证码           │
// │ POST    │ /api/auth/login          │  否  │ 手机号 + 验证码登录      │
// │ GET     │ /api/auth/user           │  是  │ 获取当前登录用户信息     │
// │ POST    │ /api/auth/logout         │  是  │ 退出登录                 │
// │ GET     │ /api/articles            │  是  │ 获取文章列表             │
// │ GET     │ /api/articles/:id        │  是  │ 获取文章详情             │
// │ DELETE  │ /api/articles/:id        │  是  │ 删除文章                 │
// │ POST    │ /api/articles/process-text│ 是  │ 解析正文并生成文章       │
// │ POST    │ /api/articles/:id/sentences/:sentence_id              │ 是 │ 修改句子并重译 │
// │ POST    │ /api/articles/:id/sentences/:sentence_id/explain-word │ 是 │ 解释句子单词 │
// │ POST    │ /api/articles/:id/sentences/:sentence_id/ask          │ 是 │ 围绕句子提问 │
// │ GET     │ /api/stats/overview      │  是  │ 获取学习统计概览         │
// └─────────┴──────────────────────────┴──────┴──────────────────────────┘
func (h *Handlers) APIRoutes() []APIGroup {
	return []APIGroup{
		{
			Prefix: "/auth",
			Desc:   "认证与账号",
			Routes: []Route{
				{http.MethodPost, "/code", false, "发送短信验证码", h.Auth.SendCode},
				{http.MethodPost, "/login", false, "手机号 + 验证码登录", h.Auth.Login},
				{http.MethodGet, "/user", true, "获取当前登录用户信息", h.Auth.GetUserInfo},
				{http.MethodPost, "/logout", true, "退出登录", h.Auth.Logout},
			},
		},
		{
			Prefix: "/articles",
			Desc:   "文章",
			Routes: []Route{
				{http.MethodGet, "", true, "获取文章列表", h.Article.ListArticles},
				{http.MethodGet, "/:id", true, "获取文章详情", h.Article.GetArticleDetail},
				{http.MethodDelete, "/:id", true, "删除文章", h.Article.DeleteArticle},
				{http.MethodPost, "/:id/title", true, "修改文章标题", h.Article.UpdateArticleTitle},
				{http.MethodPost, "/ocr", true, "拍照图片识别正文", h.Article.RecognizeArticleImage},
				{http.MethodPost, "/process-text", true, "解析正文并生成文章", h.Article.ProcessArticleText},
				{http.MethodPost, "/:id/sentences/:sentence_id", true, "修改句子并重新翻译", h.Article.UpdateSentence},
				{http.MethodPost, "/:id/sentences/:sentence_id/explain-word", true, "解释句子中的单词", h.Article.ExplainSentenceWord},
				{http.MethodPost, "/:id/sentences/:sentence_id/ask", true, "围绕句子提问", h.Article.AskSentenceQuestion},
			},
		},
		{
			Prefix: "/review",
			Desc:   "复习任务",
			Routes: []Route{
				{http.MethodGet, "/tasks", true, "获取复习任务列表", h.Review.ListTasks},
				{http.MethodPost, "/articles/:id/complete", true, "完成文章复习任务", h.Review.CompleteArticleTask},
			},
		},
		{
			Prefix: "/stats",
			Desc:   "学习统计",
			Routes: []Route{
				{http.MethodGet, "/overview", true, "获取学习统计概览", h.Stats.GetOverview},
			},
		},
	}
}

// Register 将接口表中的所有接口注册到 api 分组下。
// authMiddleware 为登录校验中间件，仅对 Auth == true 的接口生效。
func (h *Handlers) Register(api *gin.RouterGroup, authMiddleware gin.HandlerFunc) {
	for _, group := range h.APIRoutes() {
		g := api.Group(group.Prefix)
		for _, route := range group.Routes {
			chain := make([]gin.HandlerFunc, 0, 2)
			if route.Auth {
				chain = append(chain, authMiddleware)
			}
			chain = append(chain, route.Handler)
			g.Handle(route.Method, route.Path, chain...)
		}
	}
}
