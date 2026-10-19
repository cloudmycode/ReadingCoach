package services

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestReadingFailureCode(t *testing.T) {
	for _, tc := range []struct {
		err  error
		want string
	}{
		{errors.New("private raw answer"), "ai_or_validation_failed"},
		{&readingStageError{"question_validation", errors.New("private quote")}, "question_validation"},
		{&readingStageError{"generation_request", &url.Error{Op: "Post", URL: "private", Err: context.DeadlineExceeded}}, "generation_request_timeout"},
		{&readingStageError{"quality_rejected", errors.New("private rubric")}, "quality_rejected"},
	} {
		if got := readingFailureCode(tc.err); got != tc.want {
			t.Fatalf("got %s, want %s", got, tc.want)
		}
	}
}

func testReadingQuestions(source []readingSource) []readingQuestion {
	kinds := []string{"translation", "vocabulary", "sentence_meaning", "comprehension", "summary"}
	questions := make([]readingQuestion, 5)
	for i, kind := range kinds {
		questions[i] = readingQuestion{ReadingQuestion: ReadingQuestion{ID: i + 1, Type: kind, Prompt: "题目 " + kind, SentenceIDs: []int64{source[0].ID}, Quote: source[0].Text}, Reference: "PRIVATE ANSWER", Points: []string{"要点"}, Variants: []string{"同义答案"}, CriticalErrors: []string{"错误意思"}, Explanation: "解析"}
	}
	return questions
}
func testReadingAnswers() []ReadingAnswer {
	a := make([]ReadingAnswer, 5)
	for i := range a {
		a[i] = ReadingAnswer{i + 1, "学生的回答"}
	}
	return a
}
func testReadingResults(correct int, review bool) string {
	results := make([]ReadingVerdict, 5)
	for i := range results {
		v := "incorrect"
		if i < correct {
			v = "correct"
		}
		if review && i == 4 {
			v = "needs_review"
		}
		results[i] = ReadingVerdict{i + 1, v, "理由"}
	}
	return readingJSON(map[string]any{"results": results})
}
func TestReadingScoring(t *testing.T) {
	for _, want := range []int{0, 20, 60, 80, 100} {
		t.Run(string(rune('a'+want/20)), func(t *testing.T) {
			_, score, err := validateReadingGrade(testReadingResults(want/20, false), testReadingAnswers())
			if err != nil || score == nil || *score != want {
				t.Fatalf("score=%v err=%v", score, err)
			}
		})
	}
	results, score, err := validateReadingGrade(testReadingResults(4, true), testReadingAnswers())
	if err != nil || score != nil || results[4].Verdict != "needs_review" {
		t.Fatal("uncertainty must not be graded as wrong")
	}
	answers := testReadingAnswers()
	answers[0].Answer = "  "
	_, score, err = validateReadingGrade(testReadingResults(5, false), answers)
	if err != nil || *score != 80 {
		t.Fatal("blank answer cannot earn points")
	}
	for _, raw := range []string{`{}`, strings.Replace(testReadingResults(5, false), `"question_id":5`, `"question_id":1`, 1), strings.Replace(testReadingResults(5, false), `"correct"`, `"maybe"`, 1)} {
		if _, _, err = validateReadingGrade(raw, answers); err == nil {
			t.Fatal("invalid AI grade accepted")
		}
	}
}
func TestReadingQuestionValidation(t *testing.T) {
	source := []readingSource{{71, "Ben helped a friend."}}
	questions := testReadingQuestions(source)
	validate := func(q []readingQuestion) error {
		_, err := validateReadingQuestions(readingJSON(map[string]any{"questions": q}), source)
		return err
	}
	if err := validate(questions); err != nil {
		t.Fatal(err)
	}
	cases := []func([]readingQuestion){func(q []readingQuestion) { q[0].Quote = "invented" }, func(q []readingQuestion) { q[0].Points = nil }, func(q []readingQuestion) { q[0].Prompt = q[1].Prompt }, func(q []readingQuestion) {
		for i := range q {
			q[i].Type = "translation"
		}
	}}
	for _, mutate := range cases {
		q := testReadingQuestions(source)
		mutate(q)
		if validate(q) == nil {
			t.Fatal("invalid questions accepted")
		}
	}
	public := ReadingPaper{Questions: []ReadingQuestion{questions[0].ReadingQuestion}}
	raw, _ := json.Marshal(public)
	if strings.Contains(string(raw), "PRIVATE") || strings.Contains(string(raw), "required_points") {
		t.Fatal("answer keys leaked")
	}
}
func TestReadingAnswerValidation(t *testing.T) {
	a := testReadingAnswers()
	a[0], a[4] = a[4], a[0]
	a[4].Answer = "  answer  "
	out, err := normalizeReadingAnswers(a)
	if err != nil || out[0].Answer != "answer" || out[4].QuestionID != 5 {
		t.Fatal("answers not normalized")
	}
	for _, bad := range [][]ReadingAnswer{a[:4], append(a, ReadingAnswer{6, "x"}), {{1, "a"}, {1, "b"}, {3, "c"}, {4, "d"}, {5, "e"}}} {
		if _, err = normalizeReadingAnswers(bad); err == nil {
			t.Fatal("invalid answers accepted")
		}
	}
	a[0].Answer = strings.Repeat("字", 2001)
	if _, err = normalizeReadingAnswers(a); err == nil {
		t.Fatal("oversize answer accepted")
	}
}
func TestReadingCycleDates(t *testing.T) {
	for _, tc := range []struct{ start, today, zone, wantStart, wantEnd string }{
		{"2026-09-20", "2026-10-19", "Asia/Shanghai", "2026-09-20", "2026-10-19"},
		{"2026-09-20", "2026-10-20", "Asia/Shanghai", "2026-10-20", "2026-11-18"},
		{"2026-03-01", "2026-03-31", "America/New_York", "2026-03-31", "2026-04-29"},
		{"2028-02-01", "2028-03-01", "Asia/Shanghai", "2028-02-01", "2028-03-01"},
	} {
		loc, e := time.LoadLocation(tc.zone)
		if e != nil {
			t.Fatal(e)
		}
		start, end, e := readingCycleDates(tc.start, tc.today, loc)
		if e != nil || start != tc.wantStart || end != tc.wantEnd {
			t.Fatalf("%+v got %s %s %v", tc, start, end, e)
		}
	}
}
func TestReadingFingerprints(t *testing.T) {
	a := []readingSource{{1, "Hello, World."}, {2, "A new day."}}
	b := []readingSource{{99, "hello,   world. A new day."}}
	if readingHash(a) != readingHash(b) {
		t.Fatal("reimport can evade fingerprint")
	}
	if readingVersionHash(a) == readingVersionHash(b) {
		t.Fatal("changed source reused quiz version")
	}
	for days := 0; days <= 30; days++ {
		tier := readingTier(days)
		if tier.Days > days {
			t.Fatal("unearned tier")
		}
		if days == 30 && tier.AmountFen != 5000 {
			t.Fatal("highest tier wrong")
		}
	}
}

func TestReadingEvidenceCorrection(t *testing.T) {
	source := []readingSource{{1014, "The student answered right away."}, {1015, "The school just held its first career fair."}, {1016, "Many booths offered activities."}}
	for _, declared := range [][]int64{{1014}, {1}, {1015}} {
		ids, err := readingEvidenceIDs(source[1].Text, declared, source)
		if err != nil || len(ids) != 1 || ids[0] != 1015 {
			t.Fatalf("wrong correction: %v %v", ids, err)
		}
	}
	ids, err := readingEvidenceIDs("career fair. Many booths", []int64{1014}, source)
	if err != nil || len(ids) != 2 || ids[0] != 1015 || ids[1] != 1016 {
		t.Fatalf("multi-sentence quote: %v %v", ids, err)
	}
	for _, quote := range []string{"invented quote", "", "The school just held its first career fair!"} {
		if _, err := readingEvidenceIDs(quote, []int64{1015}, source); err == nil {
			t.Fatal("invented/modified quote accepted")
		}
	}
	repeated := []readingSource{{1, "Same words."}, {2, "Different words."}, {3, "Same words."}}
	if _, err := readingEvidenceIDs("Same words.", []int64{2}, repeated); err == nil {
		t.Fatal("ambiguous correction accepted")
	}
	if _, err := readingEvidenceIDs("Same words.", []int64{3}, repeated); err != nil {
		t.Fatal("valid declared location rejected")
	}
	questions := testReadingQuestions(source)
	questions[0].Quote = source[1].Text
	checked, err := validateReadingQuestions(readingJSON(map[string]any{"questions": questions}), source)
	if err != nil || checked[0].SentenceIDs[0] != 1015 || checked[0].Quote != questions[0].Quote || checked[0].Reference != questions[0].Reference {
		t.Fatal("correction changed question content", err)
	}
}
