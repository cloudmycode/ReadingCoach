package logger

import (
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// LogLevel 日志级别
type LogLevel int

const (
	DEBUG LogLevel = iota
	INFO
	WARN
	ERROR
)

// Logger 统一日志记录器
type Logger struct {
	logger *log.Logger
	level  LogLevel
}

// NewLogger 创建新的统一日志记录器
func NewLogger(logsDir string) *Logger {
	// 确保logs目录存在
	if err := os.MkdirAll(logsDir, 0755); err != nil {
		// 如果无法创建日志目录，使用标准输出
		return &Logger{
			logger: log.New(os.Stdout, "", log.LstdFlags|log.Lshortfile),
			level:  INFO,
		}
	}

	// 创建统一的日志文件
	logFile := createLogFile(logsDir, "app.log")

	return &Logger{
		logger: log.New(logFile, "", log.LstdFlags|log.Lshortfile),
		level:  INFO, // 默认INFO级别
	}
}

// createLogFile 创建日志文件
func createLogFile(logsDir, filename string) io.Writer {
	logFile, err := os.OpenFile(
		filepath.Join(logsDir, filename),
		os.O_CREATE|os.O_WRONLY|os.O_APPEND,
		0666,
	)
	if err != nil {
		// 如果无法创建日志文件，使用标准输出
		return os.Stdout
	}
	return logFile
}

// SetLevel 设置日志级别
func (l *Logger) SetLevel(level LogLevel) {
	l.level = level
}

// Debug 记录调试信息
func (l *Logger) Debug(format string, v ...interface{}) {
	if l.level <= DEBUG {
		l.logger.Printf("[DEBUG] "+format, v...)
	}
}

// Info 记录一般信息
func (l *Logger) Info(format string, v ...interface{}) {
	if l.level <= INFO {
		l.logger.Printf("[INFO] "+format, v...)
	}
}

// Warn 记录警告信息
func (l *Logger) Warn(format string, v ...interface{}) {
	if l.level <= WARN {
		l.logger.Printf("[WARN] "+format, v...)
	}
}

// Error 记录错误信息
func (l *Logger) Error(format string, v ...interface{}) {
	if l.level <= ERROR {
		l.logger.Printf("[ERROR] "+format, v...)
	}
}

// Request 记录请求信息（专门用于HTTP请求日志）
func (l *Logger) Request(method, path, clientIP, userAgent string, statusCode int, latency time.Duration) {
	// 请求完成日志
	if statusCode >= 400 {
		l.Error("❌ 请求失败 - 路径: %s | 方法: %s | 状态码: %d | 响应时间: %v",
			path, method, statusCode, latency)
	} else {
		l.Info("✅ 请求完成 - 路径: %s | 方法: %s | 状态码: %d | 响应时间: %v",
			path, method, statusCode, latency)
	}
}

// GinMiddleware 返回Gin中间件函数
func (l *Logger) GinMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 记录请求开始时间
		start := time.Now()

		// 处理请求
		c.Next()

		// 记录请求结束信息
		latency := time.Since(start)

		// 记录请求信息
		l.Request(
			c.Request.Method,
			c.Request.URL.Path,
			c.ClientIP(),
			c.Request.UserAgent(),
			c.Writer.Status(),
			latency,
		)
	}
}

// GetGinWriter 获取Gin框架的日志写入器
func (l *Logger) GetGinWriter() io.Writer {
	// 将Gin的日志也写入到我们的统一日志系统中
	return &ginLogWriter{logger: l}
}

// ginLogWriter 实现io.Writer接口，用于Gin日志
type ginLogWriter struct {
	logger *Logger
}

func (w *ginLogWriter) Write(p []byte) (n int, err error) {
	// 将Gin的日志写入到我们的info日志中
	w.logger.Info("Gin: %s", string(p))
	return len(p), nil
}

// 全局日志实例
var globalLogger *Logger

// InitLogger 初始化全局日志记录器
func InitLogger(logsDir string) {
	globalLogger = NewLogger(logsDir)
}

// GetLogger 获取全局日志记录器
func GetLogger() *Logger {
	if globalLogger == nil {
		// 如果没有初始化，使用默认配置
		globalLogger = NewLogger("./logs")
	}
	return globalLogger
}

// 全局日志函数，方便使用
func Debug(format string, v ...interface{}) {
	GetLogger().Debug(format, v...)
}

func Info(format string, v ...interface{}) {
	GetLogger().Info(format, v...)
}

func Warn(format string, v ...interface{}) {
	GetLogger().Warn(format, v...)
}

func Error(format string, v ...interface{}) {
	GetLogger().Error(format, v...)
}

func Request(method, path, clientIP, userAgent string, statusCode int, latency time.Duration) {
	GetLogger().Request(method, path, clientIP, userAgent, statusCode, latency)
}

// GinMiddleware 全局Gin中间件函数
func GinMiddleware() gin.HandlerFunc {
	return GetLogger().GinMiddleware()
}

// ResponseDebugMiddleware 响应调试中间件，记录请求和响应内容
func ResponseDebugMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 记录请求信息
		GetLogger().Debug("📥 请求: %s %s | IP: %s", c.Request.Method, c.Request.URL.Path, c.ClientIP())

		// 记录GET参数（URL查询参数）
		if len(c.Request.URL.RawQuery) > 0 {
			GetLogger().Debug("  GET参数: %s", c.Request.URL.RawQuery)
		}

		// 记录POST/PUT/PATCH参数
		if c.Request.Method == "POST" || c.Request.Method == "PUT" || c.Request.Method == "PATCH" {
			contentType := c.GetHeader("Content-Type")

			if contentType == "application/json" {
				// JSON请求体
				body, err := c.GetRawData()
				if err == nil && len(body) > 0 {
					GetLogger().Debug("  POST参数(JSON): %s", string(body))
				}
				c.Request.Body = io.NopCloser(strings.NewReader(string(body)))
			} else if contentType == "application/x-www-form-urlencoded" {
				// 表单数据
				if err := c.Request.ParseForm(); err == nil {
					if len(c.Request.PostForm) > 0 {
						GetLogger().Debug("  POST参数(表单):")
						for key, values := range c.Request.PostForm {
							GetLogger().Debug("    %s: %v", key, values)
						}
					}
				}
			} else if strings.HasPrefix(contentType, "multipart/form-data") {
				// 文件上传表单
				GetLogger().Debug("  POST参数(文件上传): %s", contentType)
			}
		}

		// 创建响应写入器包装器
		writer := &responseWriter{
			ResponseWriter: c.Writer,
			body:           make([]byte, 0),
		}
		c.Writer = writer

		// 处理请求
		c.Next()

		// 记录响应信息
		if len(writer.body) > 0 {
			if isStaticFile(c.Request.URL.Path) {
				GetLogger().Debug("📤 静态文件: %s | 大小: %d bytes", c.Request.URL.Path, len(writer.body))
			} else {
				GetLogger().Debug("📤 响应: %d | 大小: %d bytes", writer.Status(), len(writer.body))
				if isTextContent(writer.body) {
					GetLogger().Debug("  内容: %s", string(writer.body))
				}
			}
		}
	}
}

// responseWriter 响应写入器包装器
type responseWriter struct {
	gin.ResponseWriter
	body []byte
}

func (w *responseWriter) Write(data []byte) (int, error) {
	w.body = append(w.body, data...)
	return w.ResponseWriter.Write(data)
}

func (w *responseWriter) WriteString(s string) (int, error) {
	w.body = append(w.body, []byte(s)...)
	return w.ResponseWriter.WriteString(s)
}

// isTextContent 检查是否为文本内容
func isTextContent(data []byte) bool {
	if len(data) == 0 {
		return true
	}

	// 检查是否为JSON格式（以{或[开头）
	if len(data) > 0 && (data[0] == '{' || data[0] == '[') {
		return true
	}

	// 检查是否为纯文本（不包含null字节）
	for _, b := range data {
		if b == 0 {
			return false
		}
	}

	// 检查是否包含可打印字符
	printableCount := 0
	for _, b := range data {
		if b >= 32 && b <= 126 || b == 9 || b == 10 || b == 13 {
			printableCount++
		}
	}

	// 更严格的检查：可打印字符占比必须超过95%，且数据不能太大
	if len(data) > 10000 {
		return false // 大文件很可能是二进制
	}

	// 如果可打印字符占比超过95%，认为是文本
	return float64(printableCount)/float64(len(data)) > 0.95
}

// isStaticFile 检查是否为静态文件
func isStaticFile(path string) bool {
	// 检查是否为静态文件路径
	staticExtensions := []string{".mp3", ".wav", ".m4a", ".ogg", ".mp4", ".avi", ".mov", ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".ico", ".pdf", ".zip", ".rar", ".exe", ".dll", ".so", ".dylib"}

	for _, ext := range staticExtensions {
		if len(path) >= len(ext) && path[len(path)-len(ext):] == ext {
			return true
		}
	}

	// 检查是否为静态文件目录
	staticPaths := []string{"/static/", "/assets/", "/public/", "/uploads/"}
	for _, staticPath := range staticPaths {
		if len(path) >= len(staticPath) && path[:len(staticPath)] == staticPath {
			return true
		}
	}

	return false
}
