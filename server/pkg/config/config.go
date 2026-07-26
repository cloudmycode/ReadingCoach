// Package config 应用配置管理。
package config

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	HTTPAddr       string
	MySQLHost      string
	MySQLPort      string
	MySQLUser      string
	MySQLPass      string
	MySQLDB        string
	JWTSecret      string
	LogsDir        string
	AttachmentsDir string

	// 千问文本（阿里 DashScope，OpenAI 兼容）：拆句、翻译、单词解释、句子问答。
	QwenAPIKey string
	QwenAPIURL string
	QwenModel  string

	// 千问视觉 OCR（同一 DashScope 账号，模型不同）。
	QwenVLAPIKey string
	QwenVLAPIURL string
	QwenVLModel  string

	TTSVoice string
}

const configFileName = "config.json"

// MustLoadFromEnv 从配置文件加载配置，如果配置文件不存在则生成默认配置。
func MustLoadFromEnv() Config {
	configPath := configFileName

	// 如果配置文件不存在，生成默认配置
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		log.Printf("📝 配置文件 %s 不存在，正在生成默认配置文件...", configPath)
		defaultCfg := getDefaultConfig()
		if err := saveConfigToFile(configPath, defaultCfg); err != nil {
			log.Fatalf("❌ 生成默认配置文件失败: %v", err)
		}
		log.Printf("✅ 已生成默认配置文件: %s", configPath)
		return defaultCfg
	}

	// 读取配置文件
	cfg, err := loadConfigFromFile(configPath)
	if err != nil {
		log.Fatalf("❌ 读取配置文件失败: %v", err)
	}

	// 验证配置
	if cfg.JWTSecret == "" {
		log.Fatal("❌ JWT_SECRET 不能为空，请检查配置文件")
	}

	cfg.normalizeDashScopeKeys()
	return cfg
}

// getDefaultConfig 返回默认配置
func getDefaultConfig() Config {
	return Config{
		HTTPAddr:       ":8080",
		MySQLHost:      "127.0.0.1",
		MySQLPort:      "3306",
		MySQLUser:      "root",
		MySQLPass:      "change-me",
		MySQLDB:        "ReadingCoach",
		JWTSecret:      "dev-secret-change-me",
		LogsDir:        "./logs",
		AttachmentsDir: "./attachments",
		QwenAPIKey:     "replace-with-dashscope-api-key",
		QwenAPIURL:     "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
		QwenModel:      "qwen-plus",
		QwenVLAPIKey:   "replace-with-dashscope-api-key",
		QwenVLAPIURL:   "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
		QwenVLModel:    "qwen-vl-ocr",
		TTSVoice:       "en-US-JennyNeural",
	}
}

// loadConfigFromFile 从JSON文件加载配置
func loadConfigFromFile(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("读取配置文件失败: %w", err)
	}

	// 兼容旧字段：DeepSeek* → Qwen*
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return Config{}, fmt.Errorf("解析配置文件失败: %w", err)
	}
	migrateLegacyDeepSeekFields(raw)

	migrated, err := json.Marshal(raw)
	if err != nil {
		return Config{}, fmt.Errorf("迁移配置失败: %w", err)
	}

	var cfg Config
	if err := json.Unmarshal(migrated, &cfg); err != nil {
		return Config{}, fmt.Errorf("解析配置文件失败: %w", err)
	}

	return cfg, nil
}

// migrateLegacyDeepSeekFields 将旧 DeepSeek 配置映射为千问文本配置（仅当新字段缺失时）。
func migrateLegacyDeepSeekFields(raw map[string]json.RawMessage) {
	if _, ok := raw["QwenAPIKey"]; !ok {
		if v, ok := raw["DeepSeekAPIKey"]; ok {
			raw["QwenAPIKey"] = v
		}
	}
	if _, ok := raw["QwenAPIURL"]; !ok {
		// 旧 DeepSeek URL 不能直接复用，缺省时走千问默认地址
		raw["QwenAPIURL"] = json.RawMessage(`"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"`)
	}
	if _, ok := raw["QwenModel"]; !ok {
		raw["QwenModel"] = json.RawMessage(`"qwen-plus"`)
	}
}

// normalizeDashScopeKeys 文本/视觉共用同一 DashScope Key 时可互为缺省。
func (c *Config) normalizeDashScopeKeys() {
	if strings.TrimSpace(c.QwenAPIKey) == "" && strings.TrimSpace(c.QwenVLAPIKey) != "" {
		c.QwenAPIKey = c.QwenVLAPIKey
	}
	if strings.TrimSpace(c.QwenVLAPIKey) == "" && strings.TrimSpace(c.QwenAPIKey) != "" {
		c.QwenVLAPIKey = c.QwenAPIKey
	}
	if strings.TrimSpace(c.QwenAPIURL) == "" {
		c.QwenAPIURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
	}
	if strings.TrimSpace(c.QwenVLAPIURL) == "" {
		c.QwenVLAPIURL = c.QwenAPIURL
	}
}

// saveConfigToFile 将配置保存到JSON文件
func saveConfigToFile(path string, cfg Config) error {
	// 确保目录存在
	dir := filepath.Dir(path)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("创建配置目录失败: %w", err)
		}
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("序列化配置失败: %w", err)
	}

	if err := os.WriteFile(path, data, 0o644); err != nil {
		return fmt.Errorf("写入配置文件失败: %w", err)
	}

	return nil
}

func (c Config) DSN() string {
	return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=true&loc=Local",
		c.MySQLUser, c.MySQLPass, c.MySQLHost, c.MySQLPort, c.MySQLDB,
	)
}

func (c Config) DSNWithoutDB() string {
	return fmt.Sprintf("%s:%s@tcp(%s:%s)/?charset=utf8mb4&parseTime=true&loc=Local",
		c.MySQLUser, c.MySQLPass, c.MySQLHost, c.MySQLPort,
	)
}
