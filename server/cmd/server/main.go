package main

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
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
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	workersDone := make(chan struct{})
	go func() { defer close(workersDone); appServices.readingSvc.Run(ctx, 2) }()

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
			appServices.ocrService,
		),
		Review:   handlers.NewReviewHandler(appServices.articleSvc),
		WordBook: handlers.NewWordBookHandler(appServices.articleSvc),
		Stats:    handlers.NewStatsHandler(appServices.articleSvc),
		Reading:  handlers.NewReadingHandler(appServices.readingSvc),
	}

	api := r.Group("/api")
	api.GET("/health", healthCheck(db))
	// 所有业务接口集中定义在 handlers.Handlers.APIRoutes()，
	// 想查看后台提供了哪些接口，只需查阅 internal/handlers/routes.go。
	apiHandlers.Register(api, auth.VerifyToken)

	logger.Info("✅ 服务器启动成功: http://localhost%s", cfg.HTTPAddr)
	server := &http.Server{Addr: cfg.HTTPAddr, Handler: r, ReadHeaderTimeout: 10 * time.Second}
	shutdownDone := make(chan struct{})
	go func() {
		defer close(shutdownDone)
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdown); err != nil {
			_ = server.Close()
		}
	}()
	serveErr := server.ListenAndServe()
	stop()
	<-shutdownDone
	<-workersDone
	if serveErr != nil && !errors.Is(serveErr, http.ErrServerClosed) {
		logger.Error("服务器启动失败: %v", serveErr)
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
	ocrService *services.OCRService
	readingSvc *services.ReadingService
}

func initServices(cfg config.Config, db *sql.DB) *appServices {
	codeSvc := services.NewDBCodeService(db)
	articleSvc := services.NewArticleService(db)
	if err := articleSvc.EnsureWordExplanationCacheTable(context.Background()); err != nil {
		logger.Warn("⚠️ 初始化单词解释缓存表失败: %v", err)
	}
	if err := articleSvc.EnsureUserWordBookTable(context.Background()); err != nil {
		logger.Warn("⚠️ 初始化用户生词本表失败: %v", err)
	}

	// 文章与小测共用同一个千问客户端、配置及 JSON 请求逻辑。
	aiService := services.NewAIService(cfg.QwenAPIKey, cfg.QwenAPIURL, cfg.QwenModel)
	var readingAI services.JSONCompleter
	if strings.TrimSpace(cfg.QwenAPIKey) == "" {
		logger.Warn("⚠️ 千问文本未配置，拆句/翻译/单词解释不可用；小测任务保留排队")
	} else {
		readingAI = aiService
		logger.Info("✅ AI 服务初始化成功（文章与小测共用千问 model=%s）", cfg.QwenModel)
	}
	readingSvc := services.NewReadingService(db, readingAI, cfg.QwenModel)
	schemaCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	err := readingSvc.EnsureSchema(schemaCtx)
	cancel()
	if err != nil {
		logger.Error("初始化阅读闯关数据表失败: %v", err)
		os.Exit(1)
	}
	articleSvc.SetReadingService(readingSvc)

	// 千问视觉 OCR 在未配置 API Key 时不可用。
	ocrService := services.NewOCRService(
		cfg.QwenVLAPIKey,
		cfg.QwenVLAPIURL,
		cfg.QwenVLModel,
	)
	if strings.TrimSpace(cfg.QwenVLAPIKey) == "" {
		logger.Warn("⚠️ 千问视觉 OCR 未配置，拍照图片识别不可用")
	} else {
		logger.Info("✅ 图片识别服务初始化成功（千问 OCR model=%s）", cfg.QwenVLModel)
	}

	return &appServices{
		codeSvc:    codeSvc,
		articleSvc: articleSvc,
		aiService:  aiService,
		ocrService: ocrService,
		readingSvc: readingSvc,
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
