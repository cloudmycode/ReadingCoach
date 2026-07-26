package services

import "testing"

func TestFilterChineseFromOCRText(t *testing.T) {
	raw := "I love reading.\n我喜欢阅读。\n\nMemory is important. 记忆很重要。"
	got := filterChineseFromOCRText(raw)
	want := "I love reading.\n\nMemory is important."
	if got != want {
		t.Fatalf("unexpected filtered text:\n got: %q\nwant: %q", got, want)
	}
}

func TestFilterChineseFromOCRTextKeepsEnglishPunctuation(t *testing.T) {
	raw := `She said, "Hello." It's fine—really…`
	got := filterChineseFromOCRText(raw)
	if got != raw {
		t.Fatalf("english punctuation should be kept, got %q", got)
	}
}

func TestFilterChineseFromOCRTextRemovesChineseParentheses(t *testing.T) {
	raw := "Memory (记忆) is important. （很重要） Keep going."
	got := filterChineseFromOCRText(raw)
	want := "Memory is important. Keep going."
	if got != want {
		t.Fatalf("unexpected filtered text:\n got: %q\nwant: %q", got, want)
	}
}

func TestFilterChineseFromOCRTextRemovesEmptyParentheses(t *testing.T) {
	raw := "Hello () world（ ）and (  ) done."
	got := filterChineseFromOCRText(raw)
	want := "Hello world and done."
	if got != want {
		t.Fatalf("unexpected filtered text:\n got: %q\nwant: %q", got, want)
	}
}
