package services

import "testing"

func TestParseArticleAnalysisJSON(t *testing.T) {
	raw := `{
		"title": "A Short Adventure",
		"sentences": [
			{"original": "The door opened.", "translation": "门打开了。"},
			{"original": "We stepped outside.", "translation": "我们走了出去。"}
		]
	}`

	result, err := ParseArticleAnalysisJSON(raw)
	if err != nil {
		t.Fatalf("ParseArticleAnalysisJSON failed: %v", err)
	}
	if result.Title != "A Short Adventure" {
		t.Fatalf("unexpected title: %q", result.Title)
	}
	if len(result.Sentences) != 2 {
		t.Fatalf("expected 2 sentences, got %d", len(result.Sentences))
	}
	if result.Sentences[0].Original != "The door opened." || result.Sentences[0].Translation != "门打开了。" {
		t.Fatalf("unexpected first sentence: %#v", result.Sentences[0])
	}
}

func TestParseArticleAnalysisJSONStripsMarkdownFence(t *testing.T) {
	raw := "```json\n{\"title\":\"Memory\",\"sentences\":[{\"original\":\"Hello.\",\"translation\":\"你好。\"}]}\n```"

	result, err := ParseArticleAnalysisJSON(raw)
	if err != nil {
		t.Fatalf("ParseArticleAnalysisJSON failed: %v", err)
	}
	if result.Title != "Memory" || len(result.Sentences) != 1 || result.Sentences[0].Original != "Hello." {
		t.Fatalf("unexpected result: %#v", result)
	}
}

func TestParseArticleAnalysisJSONSkipsEmptyOriginal(t *testing.T) {
	raw := `{"title":"T","sentences":[{"original":"","translation":"空"},{"original":"Keep.","translation":"保留。"}]}`

	result, err := ParseArticleAnalysisJSON(raw)
	if err != nil {
		t.Fatalf("ParseArticleAnalysisJSON failed: %v", err)
	}
	if len(result.Sentences) != 1 || result.Sentences[0].Original != "Keep." {
		t.Fatalf("unexpected sentences: %#v", result.Sentences)
	}
}
