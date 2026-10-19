package services

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"
)

var (
	ErrReadingNotFound = errors.New("reading resource not found")
	ErrReadingInvalid  = errors.New("invalid reading request")
	ErrReadingConflict = errors.New("reading state conflict")
	ErrReadingLocked   = errors.New("complete all article audio first")
)

const readingPromptVersion = "reading-v1"
const readingQuestionCount = 5

type ReadingTier struct {
	Days      int `json:"days"`
	Stars     int `json:"stars"`
	AmountFen int `json:"amount_fen"`
}

var readingTiers = []ReadingTier{{5, 1, 500}, {14, 2, 1000}, {21, 3, 1500}, {26, 4, 2000}, {28, 5, 2500}, {29, 6, 3500}, {30, 7, 5000}}

func readingTier(days int) ReadingTier {
	var t ReadingTier
	for _, v := range readingTiers {
		if days >= v.Days {
			t = v
		}
	}
	return t
}

type readingSource struct {
	ID   int64  `json:"id"`
	Text string `json:"text"`
}
type ReadingQuestion struct {
	ID          int     `json:"id"`
	Type        string  `json:"type"`
	Prompt      string  `json:"prompt"`
	SentenceIDs []int64 `json:"source_sentence_ids"`
	Quote       string  `json:"source_quote"`
}
type readingQuestion struct {
	ReadingQuestion
	Reference      string   `json:"reference_answer"`
	Points         []string `json:"required_points"`
	Variants       []string `json:"acceptable_variants"`
	CriticalErrors []string `json:"critical_errors"`
	Explanation    string   `json:"explanation"`
}
type ReadingPreparation struct {
	Attempts    int   `json:"attempts"`
	MaxAttempts int   `json:"max_attempts"`
	StartedAt   int64 `json:"started_at"`
}
type ReadingPaper struct {
	ID                   int64               `json:"id"`
	Preparation          *ReadingPreparation `json:"preparation,omitempty"`
	ArticleID            string              `json:"article_id"`
	ContentHash          string              `json:"content_hash"`
	Status               string              `json:"status"`
	Questions            []ReadingQuestion   `json:"questions"`
	CompletedSentenceIDs []int64             `json:"completed_sentence_ids"`
	TotalSentences       int                 `json:"total_sentences"`
	Unlocked             bool                `json:"unlocked"`
}
type readingPaper struct {
	ID        int64
	UserID    int
	ArticleID int64
	Hash      string
	RootHash  string
	Title     string
	Source    []readingSource
	Questions []readingQuestion
	Model     string
}
type ReadingAnswer struct {
	QuestionID int    `json:"question_id"`
	Answer     string `json:"answer"`
}
type ReadingVerdict struct {
	QuestionID int    `json:"question_id"`
	Verdict    string `json:"verdict"`
	Feedback   string `json:"feedback"`
}
type ReadingAttempt struct {
	ID          int64            `json:"id"`
	PaperID     int64            `json:"paper_id"`
	CycleID     int64            `json:"cycle_id"`
	Status      string           `json:"status"`
	Answers     []ReadingAnswer  `json:"answers"`
	Results     []ReadingVerdict `json:"results"`
	Score       *int             `json:"score"`
	Passed      bool             `json:"passed"`
	SubmittedAt int64            `json:"submitted_at"`
	SubmittedOn string           `json:"submitted_on"`
	GradedAt    *int64           `json:"graded_at"`
}
type ReadingCycle struct {
	Today           string        `json:"today"`
	ID              int64         `json:"id"`
	StartsOn        string        `json:"starts_on"`
	EndsOn          string        `json:"ends_on"`
	Timezone        string        `json:"timezone"`
	Status          string        `json:"status"`
	CompletedDays   []string      `json:"completed_dates"`
	PendingAttempts int           `json:"pending_attempts"`
	Tier            ReadingTier   `json:"tier"`
	Tiers           []ReadingTier `json:"tiers"`
}
type ReadingVoucher struct {
	ID            int64  `json:"id"`
	CycleID       int64  `json:"cycle_id"`
	Stars         int    `json:"stars"`
	CompletedDays int    `json:"completed_days"`
	AmountFen     int    `json:"amount_fen"`
	IssuedAt      int64  `json:"issued_at"`
	RedeemedAt    *int64 `json:"redeemed_at"`
	Status        string `json:"status"`
}

// Version hashes include exact text and sentence IDs; reward fingerprints ignore casing/spacing.
func readingVersionHash(source []readingSource) string {
	sum := sha256.Sum256([]byte(readingJSON(source)))
	return hex.EncodeToString(sum[:])
}
func readingHash(source []readingSource) string {
	var text []string
	for _, sentence := range source {
		text = append(text, strings.Join(strings.Fields(sentence.Text), " "))
	}
	sum := sha256.Sum256([]byte(strings.ToLower(strings.Join(text, " "))))
	return hex.EncodeToString(sum[:])
}
func readingCycleDates(start, today string, loc *time.Location) (string, string, error) {
	anchor, e := time.ParseInLocation("2006-01-02", start, loc)
	if e != nil {
		return "", "", e
	}
	now, e := time.ParseInLocation("2006-01-02", today, loc)
	if e != nil {
		return "", "", e
	}
	if now.Before(anchor) {
		return "", "", ErrReadingConflict
	}
	// Count calendar days in UTC to avoid DST changing a day's length.
	a := time.Date(anchor.Year(), anchor.Month(), anchor.Day(), 0, 0, 0, 0, time.UTC)
	n := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	offset := int(n.Sub(a).Hours()/24) / 30 * 30
	first := anchor.AddDate(0, 0, offset)
	return first.Format("2006-01-02"), first.AddDate(0, 0, 29).Format("2006-01-02"), nil
}
func normalizeReadingAnswers(answers []ReadingAnswer) ([]ReadingAnswer, error) {
	if len(answers) != readingQuestionCount {
		return nil, ErrReadingInvalid
	}
	out := make([]ReadingAnswer, readingQuestionCount)
	seen := map[int]bool{}
	for _, a := range answers {
		if a.QuestionID < 1 || a.QuestionID > 5 || seen[a.QuestionID] || utf8.RuneCountInString(a.Answer) > 2000 {
			return nil, ErrReadingInvalid
		}
		seen[a.QuestionID] = true
		a.Answer = strings.TrimSpace(a.Answer)
		out[a.QuestionID-1] = a
	}
	return out, nil
}
func validateReadingQuestions(raw string, source []readingSource) ([]readingQuestion, error) {
	var body struct {
		Questions []readingQuestion `json:"questions"`
	}
	if err := json.Unmarshal([]byte(raw), &body); err != nil {
		return nil, err
	}
	if len(body.Questions) != 5 {
		return nil, fmt.Errorf("expected five questions")
	}
	kinds := map[string]bool{}
	prompts := map[string]bool{}
	for i := range body.Questions {
		q := &body.Questions[i]
		q.ID = i + 1
		switch q.Type {
		case "translation", "vocabulary", "sentence_meaning", "comprehension", "summary":
		default:
			return nil, fmt.Errorf("invalid question type")
		}
		if strings.TrimSpace(q.Prompt) == "" || strings.TrimSpace(q.Reference) == "" || strings.TrimSpace(q.Explanation) == "" || len(q.Points) == 0 || len(q.SentenceIDs) == 0 {
			return nil, fmt.Errorf("missing question rubric")
		}
		if len(q.Prompt) > 3000 || len(q.Reference) > 6000 || prompts[strings.TrimSpace(q.Prompt)] {
			return nil, fmt.Errorf("duplicate or excessive question")
		}
		for _, p := range q.Points {
			if strings.TrimSpace(p) == "" {
				return nil, fmt.Errorf("empty rubric point")
			}
		}
		ids, err := readingEvidenceIDs(q.Quote, q.SentenceIDs, source)
		if err != nil {
			return nil, err
		}
		q.SentenceIDs = ids
		prompts[strings.TrimSpace(q.Prompt)] = true
		kinds[q.Type] = true
	}
	if len(kinds) < 3 {
		return nil, fmt.Errorf("insufficient question variety")
	}
	return body.Questions, nil
}

// Fix model-generated sentence IDs only when the unchanged quote identifies one exact
// contiguous span of the original. Never fuzzy-match or rewrite an invented quote.
func readingEvidenceIDs(quote string, declared []int64, source []readingSource) ([]int64, error) {
	invalid := fmt.Errorf("quote not uniquely grounded in source")
	if strings.TrimSpace(quote) == "" {
		return nil, invalid
	}
	byID := make(map[int64]string, len(source))
	texts := make([]string, len(source))
	for i, sentence := range source {
		byID[sentence.ID] = sentence.Text
		texts[i] = sentence.Text
	}
	article := strings.Join(texts, " ")
	start := strings.Index(article, quote)
	if start < 0 {
		return nil, invalid
	}
	evidence := make([]string, 0, len(declared))
	for _, id := range declared {
		if text, ok := byID[id]; ok {
			evidence = append(evidence, text)
		}
	}
	if len(evidence) == len(declared) && strings.Contains(strings.Join(evidence, " "), quote) {
		return declared, nil
	}
	if strings.LastIndex(article, quote) != start {
		return nil, invalid
	}
	end, offset := start+len(quote), 0
	var ids []int64
	evidence = nil
	for _, sentence := range source {
		if offset < end && offset+len(sentence.Text) > start {
			ids = append(ids, sentence.ID)
			evidence = append(evidence, sentence.Text)
		}
		offset += len(sentence.Text) + 1
	}
	if !strings.Contains(strings.Join(evidence, " "), quote) {
		return nil, invalid
	}
	return ids, nil
}

func validateReadingGrade(raw string, answers []ReadingAnswer) ([]ReadingVerdict, *int, error) {
	var body struct {
		Results []ReadingVerdict `json:"results"`
	}
	if err := json.Unmarshal([]byte(raw), &body); err != nil {
		return nil, nil, err
	}
	if len(body.Results) != 5 {
		return nil, nil, fmt.Errorf("expected five verdicts")
	}
	results := make([]ReadingVerdict, 5)
	seen := map[int]bool{}
	score := 0
	pending := false
	for _, r := range body.Results {
		if r.QuestionID < 1 || r.QuestionID > 5 || seen[r.QuestionID] || strings.TrimSpace(r.Feedback) == "" || len(r.Feedback) > 6000 {
			return nil, nil, fmt.Errorf("invalid verdict id/feedback")
		}
		seen[r.QuestionID] = true
		switch r.Verdict {
		case "correct", "incorrect", "needs_review":
		default:
			return nil, nil, fmt.Errorf("invalid verdict")
		}
		if strings.TrimSpace(answers[r.QuestionID-1].Answer) == "" {
			r.Verdict = "incorrect"
			r.Feedback = "本题未作答。"
		}
		if r.Verdict == "correct" {
			score += 20
		}
		if r.Verdict == "needs_review" {
			pending = true
		}
		results[r.QuestionID-1] = r
	}
	if pending {
		return results, nil, nil
	}
	return results, &score, nil
}
