package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadingUsesExistingQwenConfig(t *testing.T) {
	// Stale quiz settings must not override the shared Qwen configuration.
	t.Setenv("QUIZ_AI_API_KEY", "obsolete-quiz-key")
	t.Setenv("QUIZ_AI_API_URL", "https://obsolete.invalid")
	t.Setenv("QUIZ_AI_MODEL", "obsolete-model")
	path := filepath.Join(t.TempDir(), "config.json")
	data := `{"QwenAPIKey":"shared-key","QwenAPIURL":"https://qwen.example/chat/completions","QwenModel":"qwen-plus","QuizAI":{"APIKey":"obsolete-key","Model":"obsolete-model"}}`
	if err := os.WriteFile(path, []byte(data), 0600); err != nil {
		t.Fatal(err)
	}
	c, err := loadConfigFromFile(path)
	if err != nil {
		t.Fatal(err)
	}
	c.normalizeDashScopeKeys()
	if c.QwenAPIKey != "shared-key" || c.QwenAPIURL != "https://qwen.example/chat/completions" || c.QwenModel != "qwen-plus" {
		t.Fatal("obsolete quiz configuration changed the shared provider")
	}
}

func TestSharedQwenConfigDefaults(t *testing.T) {
	c := Config{QwenVLAPIKey: "shared-dashscope-key"}
	c.normalizeDashScopeKeys()
	if c.QwenAPIKey != c.QwenVLAPIKey || c.QwenModel != "qwen-plus" || c.QwenAPIURL == "" {
		t.Fatal("existing DashScope key/defaults not reused")
	}
}
