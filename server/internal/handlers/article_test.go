package handlers

import "testing"

func TestConvertAIDataToArticle(t *testing.T) {
	title, sentences := convertAIDataToArticle([][]string{
		{"TITLE", "A Short Adventure"},
		{"SENTENCE", "The door opened.", "门打开了。"},
		{"SENTENCE", "We stepped outside.", "我们走了出去。"},
	})

	if title != "A Short Adventure" {
		t.Fatalf("unexpected title: %q", title)
	}
	if len(sentences) != 2 {
		t.Fatalf("expected 2 sentences, got %d", len(sentences))
	}
	if sentences[0].Original != "The door opened." || sentences[0].Translation != "门打开了。" {
		t.Fatalf("unexpected first sentence: %#v", sentences[0])
	}
}

func TestConvertAIDataToArticleSupportsLegacyRows(t *testing.T) {
	title, sentences := convertAIDataToArticle([][]string{
		{"The door opened.", "门打开了。"},
	})

	if title != "" {
		t.Fatalf("legacy response should not infer a title, got %q", title)
	}
	if len(sentences) != 1 || sentences[0].Original != "The door opened." {
		t.Fatalf("unexpected legacy sentences: %#v", sentences)
	}
}
