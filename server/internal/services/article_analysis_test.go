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

func TestParseArticleAnalysisJSONStripsTrailingGarbage(t *testing.T) {
	raw := `{"title":"T","sentences":[{"original":"Hi.","translation":"你好。"}]}ok`

	result, err := ParseArticleAnalysisJSON(raw)
	if err != nil {
		t.Fatalf("ParseArticleAnalysisJSON failed: %v", err)
	}
	if result.Title != "T" || len(result.Sentences) != 1 {
		t.Fatalf("unexpected result: %#v", result)
	}
}

func TestValidateRawJSONArticleAnalysis(t *testing.T) {
	valid := `{"title":"T","sentences":[{"original":"Hi.","translation":"你好。"}]}`
	if err := validateRawJSON(valid, "article_analysis", ArticleAnalysisJSONSchema); err != nil {
		t.Fatalf("expected valid json, got %v", err)
	}

	invalid := `{"title":"T","sentences":[{"original":"Hi.","translation":"你好。"}]}ok`
	if err := validateRawJSON(invalid, "article_analysis", ArticleAnalysisJSONSchema); err == nil {
		t.Fatal("expected invalid json to fail")
	}

	extracted := extractJSONObject(invalid)
	if err := validateRawJSON(extracted, "article_analysis", ArticleAnalysisJSONSchema); err != nil {
		t.Fatalf("extracted json should validate: %v", err)
	}
}

func TestBuildResponseFormatPrefersSchema(t *testing.T) {
	format := buildResponseFormat(true, "article_analysis", ArticleAnalysisJSONSchema)
	if format.Type != "json_schema" || format.JSONSchema == nil || !format.JSONSchema.Strict {
		t.Fatalf("unexpected format: %#v", format)
	}

	fallback := buildResponseFormat(false, "article_analysis", ArticleAnalysisJSONSchema)
	if fallback.Type != "json_object" || fallback.JSONSchema != nil {
		t.Fatalf("unexpected fallback format: %#v", fallback)
	}
}

func TestIsStructuredFormatUnsupported(t *testing.T) {
	if !isStructuredFormatUnsupported(`qwen error(status=400): response_format json_schema unsupported`) {
		t.Fatal("expected unsupported detection")
	}
	if isStructuredFormatUnsupported(`qwen error(status=500): internal error`) {
		t.Fatal("did not expect unsupported detection")
	}
}
