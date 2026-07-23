package main

import (
	"context"
	"database/sql"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"words/server/internal/database"
	"words/server/internal/handlers"
	"words/server/internal/logger"
	"words/server/internal/services"
	"words/server/pkg/config"
)

func main() {
	cfg := config.MustLoadFromEnv()

	logger.InitLogger(cfg.LogsDir)
	logger.GetLogger().SetLevel(logger.DEBUG)
	logger.Info("🚀 启动 ReadingCoach 服务器...")

	ensureAllDirs(&cfg)

	db := database.MustOpen(cfg)
	defer func() {
		if err := db.Close(); err != nil {
			logger.Error("⚠️ 数据库连接关闭时出错: %v", err)
		}
	}()

	appServices := initServices(cfg, db)

	gin.DisableConsoleColor()
	gin.DefaultWriter = logger.GetLogger().GetGinWriter()

	r := gin.New()
	r.Use(gin.Logger())
	r.Use(gin.Recovery())
	r.Use(corsMiddleware())
	r.Use(logger.GinMiddleware())
	r.Use(logger.ResponseDebugMiddleware())

	r.Static("/attachments", cfg.AttachmentsDir)
	r.GET("/health", func(c *gin.Context) { c.String(http.StatusOK, "ok") })

	auth := handlers.NewAuthHandler(db, appServices.codeSvc, cfg)
	apiHandlers := &handlers.Handlers{
		Auth: auth,
		Article: handlers.NewArticleHandler(
			appServices.articleSvc,
			appServices.aiService,
		),
		Review: handlers.NewReviewHandler(appServices.articleSvc),
		Stats:  handlers.NewStatsHandler(appServices.articleSvc),
	}

	api := r.Group("/api")
	api.GET("/health", healthCheck(db))
	// 所有业务接口集中定义在 handlers.Handlers.APIRoutes()，
	// 想查看后台提供了哪些接口，只需查阅 internal/handlers/routes.go。
	apiHandlers.Register(api, auth.VerifyToken)

	logger.Info("✅ 服务器启动成功: http://localhost%s", cfg.HTTPAddr)
	if err := r.Run(cfg.HTTPAddr); err != nil {
		logger.Error("❌ 服务器启动失败: %v", err)
		os.Exit(1)
	}
}

// healthCheck 返回带数据库连通性检测的健康检查处理器。
func healthCheck(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()

		status := http.StatusOK
		overall := "ok"
		dbState := "ok"
		if err := db.PingContext(ctx); err != nil {
			status = http.StatusServiceUnavailable
			overall = "degraded"
			dbState = "error"
		}

		c.JSON(status, gin.H{
			"status":   overall,
			"database": dbState,
			"time":     time.Now().Format(time.RFC3339),
		})
	}
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")
		c.Header("Access-Control-Expose-Headers", "Content-Type")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

type appServices struct {
	codeSvc    services.CodeService
	articleSvc *services.ArticleService
	aiService  *services.AIService
}

func initServices(cfg config.Config, db *sql.DB) *appServices {
	codeSvc := services.NewDBCodeService(db)
	articleSvc := services.NewArticleService(db)
	if err := articleSvc.EnsureWordExplanationCacheTable(context.Background()); err != nil {
		logger.Warn("⚠️ 初始化单词解释缓存表失败: %v", err)
	}
	if err := articleSvc.EnsureReviewTaskTable(context.Background()); err != nil {
		logger.Warn("⚠️ 初始化复习任务表失败: %v", err)
	}

	// DeepSeek 文本能力在未配置 API Key 时不可用。
	aiService := services.NewAIService(
		cfg.DeepSeekAPIKey,
		cfg.DeepSeekAPIURL,
		cfg.DeepSeekModel,
	)

	if strings.TrimSpace(cfg.DeepSeekAPIKey) == "" {
		logger.Warn("⚠️ DeepSeek 未配置，文本能力不可用")
	} else {
		logger.Info("✅ AI 服务初始化成功（DeepSeek 文本处理）")
	}

	return &appServices{
		codeSvc:    codeSvc,
		articleSvc: articleSvc,
		aiService:  aiService,
	}
}

func ensureAllDirs(cfg *config.Config) {
	if err := os.MkdirAll(cfg.LogsDir, 0o755); err != nil {
		logger.Error("❌ 创建日志目录失败 (%s): %v", cfg.LogsDir, err)
		os.Exit(1)
	}

	absAttachmentsDir, err := filepath.Abs(cfg.AttachmentsDir)
	if err != nil {
		logger.Error("❌ 附件目录解析失败: %v", err)
		os.Exit(1)
	}
	cfg.AttachmentsDir = absAttachmentsDir

	requiredDirs := []string{
		cfg.AttachmentsDir,
	}
	for _, dir := range requiredDirs {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			logger.Error("❌ 创建目录失败 (%s): %v", dir, err)
			os.Exit(1)
		}
	}
}
