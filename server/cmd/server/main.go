package main

import (
	"database/sql"
	"net/http"
	"os"
	"path/filepath"

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

	api := r.Group("/api")
	{
		auth := handlers.NewAuthHandler(db, appServices.codeSvc, cfg)
		authGroup := api.Group("/auth")
		{
			authGroup.POST("/code", auth.SendCode)
			authGroup.POST("/login", auth.Login)
			authGroup.GET("/user", auth.VerifyToken, auth.GetUserInfo)
			authGroup.POST("/logout", auth.VerifyToken, auth.Logout)
		}

		articleHandler := handlers.NewArticleHandler(
			cfg.AttachmentsDir,
			appServices.articleSvc,
			appServices.ttsService,
			appServices.imageProcessor,
		)
		unitHandler := handlers.NewUnitHandler(appServices.unitSvc, appServices.imageProcessor)
		statsHandler := handlers.NewStatsHandler(appServices.articleSvc)

		articleGroup := api.Group("/articles")
		{
			articleGroup.GET("", auth.VerifyToken, articleHandler.ListArticles)
			articleGroup.GET("/:id", auth.VerifyToken, articleHandler.GetArticleDetail)
			articleGroup.DELETE("/:id", auth.VerifyToken, articleHandler.DeleteArticle)
			articleGroup.POST("/process-images", auth.VerifyToken, articleHandler.ProcessArticleImages)
		}

		unitGroup := api.Group("/units")
		{
			unitGroup.GET("", auth.VerifyToken, unitHandler.ListUnits)
			unitGroup.GET("/:id/words", auth.VerifyToken, unitHandler.ListUnitWords)
			unitGroup.POST("/process-images", auth.VerifyToken, unitHandler.ProcessUnitImages)
		}

		imageGroup := api.Group("/image")
		{
			imageGroup.POST("/process", auth.VerifyToken, func(c *gin.Context) {
				processType := c.PostForm("type")
				switch processType {
				case "", "article":
					articleHandler.ProcessArticleImages(c)
				case "unit":
					unitHandler.ProcessUnitImages(c)
				default:
					c.JSON(http.StatusBadRequest, gin.H{
						"success": false,
						"message": "不支持的图片处理类型",
					})
				}
			})
		}

		statsGroup := api.Group("/stats")
		{
			statsGroup.GET("/overview", auth.VerifyToken, statsHandler.GetOverview)
		}
	}

	logger.Info("✅ 服务器启动成功: http://localhost%s", cfg.HTTPAddr)
	if err := r.Run(cfg.HTTPAddr); err != nil {
		logger.Error("❌ 服务器启动失败: %v", err)
		os.Exit(1)
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
	codeSvc        services.CodeService
	articleSvc     *services.ArticleService
	unitSvc        *services.UnitService
	aiService      *services.AIService
	ttsService     services.TTSService
	imageProcessor services.ImageProcessor
}

func initServices(cfg config.Config, db *sql.DB) *appServices {
	codeSvc := services.NewDBCodeService(db)
	articleSvc := services.NewArticleService(db)
	unitSvc := services.NewUnitService(db)

	var aiService *services.AIService
	var analyzer services.ImageAnalyzer
	var ttsService services.TTSService

	if aiService = services.NewAIService(
		cfg.DeepSeekAPIKey,
		cfg.DeepSeekAPIURL,
		cfg.DeepSeekModel,
		cfg.MicrosoftTTSKey,
		cfg.MicrosoftTTSRegion,
		cfg.MicrosoftTTSVoice,
		cfg.MicrosoftTTSAPIURL,
	); aiService != nil {
		analyzer = aiService
		ttsService = aiService
		logger.Info("✅ AI 服务初始化成功（DeepSeek + Microsoft TTS）")
	} else {
		logger.Warn("⚠️ AI 配置缺失，图片解析和 TTS 功能不可用")
	}

	imageProcessor := services.NewImageProcessor(services.ImageProcessorConfig{
		AttachmentsDir: cfg.AttachmentsDir,
		Analyzer:       analyzer,
	})

	return &appServices{
		codeSvc:        codeSvc,
		articleSvc:     articleSvc,
		unitSvc:        unitSvc,
		aiService:      aiService,
		ttsService:     ttsService,
		imageProcessor: imageProcessor,
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
		filepath.Join(cfg.AttachmentsDir, "uploadimage"),
		filepath.Join(cfg.AttachmentsDir, "articleaudio"),
	}
	for _, dir := range requiredDirs {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			logger.Error("❌ 创建目录失败 (%s): %v", dir, err)
			os.Exit(1)
		}
	}
}
