// Package config 应用配置管理
// 功能：
//   - 从配置文件加载配置参数（如果不存在则生成默认配置）
//   - 提供数据库连接字符串(DSN)生成
//   - 设置默认配置值(数据库、JWT密钥等)
//   - 配置验证和错误处理
package config

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
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

	DeepSeekAPIKey string
	DeepSeekAPIURL string
	DeepSeekModel  string

	MicrosoftTTSKey    string
	MicrosoftTTSRegion string
	MicrosoftTTSVoice  string
	MicrosoftTTSAPIURL string
}

const configFileName = "config.json"

// MustLoadFromEnv 从配置文件加载配置，如果配置文件不存在则生成默认配置
// 保持函数名不变以保持向后兼容
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

	return cfg
}

// getDefaultConfig 返回默认配置
func getDefaultConfig() Config {
	return Config{
		HTTPAddr:           ":8080",
		MySQLHost:          "127.0.0.1",
		MySQLPort:          "3306",
		MySQLUser:          "root",
		MySQLPass:          "change-me",
		MySQLDB:            "readingcoach",
		JWTSecret:          "dev-secret-change-me",
		LogsDir:            "./logs",
		AttachmentsDir:     "./web/static/attachments",
		DeepSeekAPIKey:     "replace-with-deepseek-api-key",
		DeepSeekAPIURL:     "https://api.deepseek.com/v1/chat/completions",
		DeepSeekModel:      "replace-with-deepseek-vision-model",
		MicrosoftTTSKey:    "replace-with-microsoft-tts-key",
		MicrosoftTTSRegion: "eastasia",
		MicrosoftTTSVoice:  "en-US-JennyNeural",
		MicrosoftTTSAPIURL: "",
	}
}

// loadConfigFromFile 从JSON文件加载配置
func loadConfigFromFile(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("读取配置文件失败: %w", err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, fmt.Errorf("解析配置文件失败: %w", err)
	}

	return cfg, nil
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
