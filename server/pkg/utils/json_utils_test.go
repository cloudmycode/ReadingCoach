package utils

import "testing"

func TestParseTSVLinesAcceptsLiteralTABPlaceholder(t *testing.T) {
	lines, err := ParseTSVLines("TITLE<TAB>Memory and the Mind\nSENTENCE<TAB>Hello.<TAB>你好。")
	if err != nil {
		t.Fatalf("ParseTSVLines failed: %v", err)
	}
	if len(lines) != 2 {
		t.Fatalf("expected 2 lines, got %d", len(lines))
	}
	if len(lines[0]) != 2 || lines[0][0] != "TITLE" || lines[0][1] != "Memory and the Mind" {
		t.Fatalf("unexpected title line: %#v", lines[0])
	}
	if len(lines[1]) != 3 || lines[1][0] != "SENTENCE" || lines[1][1] != "Hello." || lines[1][2] != "你好。" {
		t.Fatalf("unexpected sentence line: %#v", lines[1])
	}
}

func TestParseTSVLinesAcceptsRealTabs(t *testing.T) {
	lines, err := ParseTSVLines("TITLE\tMemory\nSENTENCE\tHello.\t你好。")
	if err != nil {
		t.Fatalf("ParseTSVLines failed: %v", err)
	}
	if len(lines) != 2 || lines[0][1] != "Memory" || lines[1][2] != "你好。" {
		t.Fatalf("unexpected lines: %#v", lines)
	}
}
