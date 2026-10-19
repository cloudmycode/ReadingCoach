package services

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestReadingUsesSharedQwenJSONClient(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.Header.Get("Authorization") != "Bearer test-key" {
			t.Error("missing provider authorization")
		}
		var body map[string]json.RawMessage
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
			return
		}
		if _, ok := body["reasoning_effort"]; ok {
			t.Error("DeepSeek-only settings leaked into shared Qwen request")
		}
		var req aiChatRequest
		raw, _ := json.Marshal(body)
		if err := json.Unmarshal(raw, &req); err != nil {
			t.Error(err)
		}
		if req.Model != "qwen-plus" || req.ResponseFormat == nil || req.ResponseFormat.Type != "json_object" || req.MaxTokens != 8192 {
			t.Errorf("wrong request: %+v", req)
		}
		if len(req.Messages) != 1 || !strings.Contains(strings.ToLower(req.Messages[0].Content), "json") {
			t.Error("JSON instruction missing")
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": `{"approved":true,"reasons":[]}`}}}})
	}))
	defer server.Close()
	ai := NewAIService("test-key", server.URL, "qwen-plus")
	for _, schema := range []string{"reading_questions", "reading_quality", "reading_grade", "reading_grade_review"} {
		raw, err := ai.CompleteJSONPrompt(context.Background(), "返回审核结果", schema, "")
		if err != nil || !strings.Contains(raw, `"approved":true`) {
			t.Fatalf("%s: %v", schema, err)
		}
	}
	if calls != 4 {
		t.Fatalf("expected four requests through the same client, got %d", calls)
	}
	if strings.Contains(aiResponseForLog("reading_grade", "private answer"), "private answer") {
		t.Fatal("student answer logged")
	}
}
