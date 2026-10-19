package services

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-sql-driver/mysql"
)

type readingFakeAI struct {
	mu            sync.Mutex
	fail          bool
	correct       int
	review        bool
	wrongSourceID bool
}

func (f *readingFakeAI) CompleteJSONPrompt(_ context.Context, prompt, schema, _ string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fail {
		return "", errors.New("simulated provider outage")
	}
	switch schema {
	case "reading_questions":
		var source []readingSource
		if err := json.Unmarshal([]byte(strings.Split(prompt, "文章数据：")[1]), &source); err != nil {
			return "", err
		}
		questions := testReadingQuestions(source)
		if f.wrongSourceID {
			questions[0].SentenceIDs = []int64{source[1].ID}
		}
		return readingJSON(map[string]any{"questions": questions}), nil
	case "reading_quality":
		return `{"approved":true,"reasons":[]}`, nil
	case "reading_grade", "reading_grade_review":
		return testReadingResults(f.correct, f.review), nil
	}
	return "", fmt.Errorf("unexpected schema %s", schema)
}

type readingFixture struct {
	s   *ReadingService
	a   *ArticleService
	ai  *readingFakeAI
	now time.Time
	db  *sql.DB
}

func newReadingFixture(t *testing.T) *readingFixture {
	t.Helper()
	dsn := os.Getenv("READING_TEST_DSN")
	if dsn == "" {
		t.Skip("READING_TEST_DSN not set; use a disposable MySQL 8 database")
	}
	cfg, err := mysql.ParseDSN(dsn)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(cfg.DBName, "reading_test") {
		t.Fatal("integration DSN must use a reading_test* database")
	}
	admin, err := sql.Open("mysql", cfg.FormatDSN())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { admin.Close() })
	name := fmt.Sprintf("reading_test_%d", time.Now().UnixNano())
	if _, err = admin.Exec("CREATE DATABASE " + name + " CHARACTER SET utf8mb4"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, e := admin.Exec("DROP DATABASE " + name); e != nil {
			t.Error(e)
		}
	})
	cfg.DBName = name
	db, err := sql.Open("mysql", cfg.FormatDSN())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	db.SetMaxOpenConns(16)
	for _, ddl := range []string{
		`CREATE TABLE articles(article_id BIGINT AUTO_INCREMENT PRIMARY KEY,user_id INT NOT NULL,title VARCHAR(255),sentence_count INT,updated_at DATETIME DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB`,
		`CREATE TABLE article_sentences(sentence_id BIGINT AUTO_INCREMENT PRIMARY KEY,article_id BIGINT,sentence_order INT,original_text TEXT,translation TEXT,is_favorite BOOLEAN DEFAULT FALSE,updated_at DATETIME DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB`,
	} {
		if _, err = db.Exec(ddl); err != nil {
			t.Fatal(err)
		}
	}
	f := &readingFixture{db: db, ai: &readingFakeAI{correct: 4}, now: time.Date(2026, 9, 20, 12, 0, 0, 0, time.FixedZone("CST", 8*3600))}
	f.s = NewReadingService(db, f.ai, "test-model")
	f.s.now = func() time.Time { return f.now }
	f.a = NewArticleService(db)
	f.a.SetReadingService(f.s)
	if err = f.s.EnsureSchema(context.Background()); err != nil {
		t.Fatal(err)
	}
	return f
}
func (f *readingFixture) article(t *testing.T, user int, text string) (int64, *ReadingPaper) {
	t.Helper()
	id, err := f.a.SaveAnalyzedArticle(context.Background(), user, "Test article", []ArticleSentenceInput{{Original: text, Translation: "测试句"}, {Original: "He was happy.", Translation: "他很开心"}})
	if err != nil {
		t.Fatal(err)
	}
	p, err := f.s.Paper(context.Background(), user, id)
	if err != nil {
		t.Fatal(err)
	}
	return id, p
}
func (f *readingFixture) run(t *testing.T) {
	t.Helper()
	did, err := f.s.RunOne(context.Background())
	if err != nil || !did {
		t.Fatalf("run did=%t err=%v", did, err)
	}
}
func (f *readingFixture) listen(t *testing.T, user int, id int64, p *ReadingPaper) {
	t.Helper()
	internal, err := f.s.loadPaper(context.Background(), f.db, user, p.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, sentence := range internal.Source {
		if err = f.s.CompleteListening(context.Background(), user, id, p.ID, sentence.ID, p.ContentHash); err != nil {
			t.Fatal(err)
		}
	}
}
func (f *readingFixture) submit(t *testing.T, user int, id int64, p *ReadingPaper, key string) *ReadingAttempt {
	t.Helper()
	a, err := f.s.Submit(context.Background(), user, id, p.ID, key, testReadingAnswers())
	if err != nil {
		t.Fatal(err)
	}
	return a
}
func TestReadingIntegrationFlow(t *testing.T) {
	f := newReadingFixture(t)
	ctx := context.Background()
	id, p := f.article(t, 1, "Ben helped a friend.")
	if p.Status != "queued" || p.Unlocked {
		t.Fatalf("initial %+v", p)
	}
	if _, e := f.s.Paper(ctx, 2, id); !errors.Is(e, ErrReadingNotFound) {
		t.Fatal("ownership bypass", e)
	}
	f.run(t)
	p, e := f.s.Paper(ctx, 1, id)
	if e != nil || p.Status != "ready" || len(p.Questions) != 5 {
		t.Fatalf("ready %+v %v", p, e)
	}
	if strings.Contains(readingJSON(p), "PRIVATE") {
		t.Fatal("rubric leaked")
	}
	if _, e = f.s.Submit(ctx, 1, id, p.ID, "locked-submit", testReadingAnswers()); !errors.Is(e, ErrReadingLocked) {
		t.Fatal("audio gate bypass", e)
	}
	internal, _ := f.s.loadPaper(ctx, f.db, 1, p.ID)
	if e = f.s.CompleteListening(ctx, 1, id, p.ID, internal.Source[1].ID, p.ContentHash); e != nil {
		t.Fatal(e)
	}
	if _, e = f.s.Submit(ctx, 1, id, p.ID, "last-only-xx", testReadingAnswers()); !errors.Is(e, ErrReadingLocked) {
		t.Fatal("last sentence unlocked whole article")
	}
	f.listen(t, 1, id, p)
	var wg sync.WaitGroup
	ids := make(chan int64, 12)
	errs := make(chan error, 12)
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			a, err := f.s.Submit(ctx, 1, id, p.ID, "same-request", testReadingAnswers())
			if err != nil {
				errs <- err
			} else {
				ids <- a.ID
			}
		}()
	}
	wg.Wait()
	close(ids)
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	var attempt int64
	for value := range ids {
		if attempt != 0 && value != attempt {
			t.Fatal("duplicate attempt")
		}
		attempt = value
	}
	if attempt == 0 {
		t.Fatal("no attempt")
	}
	altered := testReadingAnswers()
	altered[0].Answer = "different"
	if _, e = f.s.Submit(ctx, 1, id, p.ID, "same-request", altered); !errors.Is(e, ErrReadingConflict) {
		t.Fatal("idempotency input changed")
	}
	if _, e = f.s.Attempt(ctx, 2, attempt); !errors.Is(e, ErrReadingNotFound) {
		t.Fatal("attempt ownership bypass")
	}
	f.run(t)
	a, e := f.s.Attempt(ctx, 1, attempt)
	if e != nil || a.Score == nil || *a.Score != 80 || !a.Passed || a.Status != "graded" {
		t.Fatalf("grade %+v %v", a, e)
	}
	c, e := f.s.Challenge(ctx, 1)
	if e != nil || len(c.CompletedDays) != 1 {
		t.Fatalf("day %+v %v", c, e)
	}
	// Re-reading the same article tomorrow cannot earn another day.
	f.now = f.now.AddDate(0, 0, 1)
	f.submit(t, 1, id, p, "repeat-tomorrow")
	f.run(t)
	c, _ = f.s.Challenge(ctx, 1)
	if len(c.CompletedDays) != 1 {
		t.Fatal("same article earned twice")
	}
	// Identical reimports have distinct sentence IDs but the same reward fingerprint.
	copyID, copyPaper := f.article(t, 1, "ben  helped a friend.")
	f.run(t)
	f.listen(t, 1, copyID, copyPaper)
	f.submit(t, 1, copyID, copyPaper, "duplicate-import")
	f.run(t)
	c, _ = f.s.Challenge(ctx, 1)
	if len(c.CompletedDays) != 1 {
		t.Fatal("reimport earned twice")
	}
	// Editing original text creates a new paper with a locked listening gate.
	_, e = f.a.UpdateSentenceContent(ctx, id, internal.Source[0].ID, 1, "Ben read a new book.", "本读了一本新书")
	if e != nil {
		t.Fatal(e)
	}
	next, e := f.s.Paper(ctx, 1, id)
	if e != nil || next.ID == p.ID || next.Unlocked {
		t.Fatal("stale paper reused", e)
	}
	if e = f.s.CompleteListening(ctx, 1, id, p.ID, internal.Source[0].ID, p.ContentHash); !errors.Is(e, ErrReadingConflict) {
		t.Fatal("old listening accepted")
	}
	if _, e = f.s.Submit(ctx, 1, id, p.ID, "old-version-xx", testReadingAnswers()); !errors.Is(e, ErrReadingConflict) {
		t.Fatal("old paper accepted")
	}
}
func TestReadingIntegrationSettlement(t *testing.T) {
	f := newReadingFixture(t)
	ctx := context.Background()
	c, e := f.s.Challenge(ctx, 1)
	if e != nil {
		t.Fatal(e)
	}
	// Fourteen distinct days, with the final submission still awaiting AI at period end.
	for i := 0; i < 13; i++ {
		day := f.now.AddDate(0, 0, i).Format("2006-01-02")
		if _, e = f.db.Exec(`INSERT INTO reading_days VALUES(?,?,?,?)`, 1, day, c.ID, i+1); e != nil {
			t.Fatal(e)
		}
	}
	f.now = f.now.AddDate(0, 0, 29)
	id, p := f.article(t, 1, "The last day of the challenge.")
	f.run(t)
	f.listen(t, 1, id, p)
	a := f.submit(t, 1, id, p, "period-final-day")
	f.now = f.now.AddDate(0, 0, 1)
	if e = f.s.SettleDue(ctx); e != nil {
		t.Fatal(e)
	}
	v, _ := f.s.Vouchers(ctx, 1, "", 50, 0)
	if len(v) != 0 {
		t.Fatal("settled before pending grade")
	}
	f.run(t)
	graded, _ := f.s.Attempt(ctx, 1, a.ID)
	if graded.SubmittedOn != "2026-10-19" {
		t.Fatal("submission shifted into next day")
	}
	for i := 0; i < 3; i++ {
		if e = f.s.SettleDue(ctx); e != nil {
			t.Fatal(e)
		}
	}
	v, e = f.s.Vouchers(ctx, 1, "available", 50, 0)
	if e != nil || len(v) != 1 || v[0].AmountFen != 1000 || v[0].Stars != 2 || v[0].CompletedDays != 14 {
		t.Fatalf("vouchers %+v %v", v, e)
	}
	if _, e = f.s.Redeem(ctx, 2, v[0].ID); !errors.Is(e, ErrReadingNotFound) {
		t.Fatal("cross-user redeem")
	}
	var wg sync.WaitGroup
	errs := make(chan error, 10)
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r, err := f.s.Redeem(ctx, 1, v[0].ID)
			if err != nil {
				errs <- err
			} else if r.Status != "redeemed" {
				errs <- errors.New("not redeemed")
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	original, _ := f.s.Redeem(ctx, 1, v[0].ID)
	f.now = f.now.Add(time.Hour)
	again, _ := f.s.Redeem(ctx, 1, v[0].ID)
	if *original.RedeemedAt != *again.RedeemedAt {
		t.Fatal("redemption timestamp changed")
	}
	v, _ = f.s.Vouchers(ctx, 1, "redeemed", 50, 0)
	if len(v) != 1 {
		t.Fatal("redeemed filter")
	}
	next, _ := f.s.Challenge(ctx, 1)
	if next.ID == c.ID || len(next.CompletedDays) != 0 {
		t.Fatal("next cycle not independent")
	}
}
func TestReadingIntegrationLeasesAndFailures(t *testing.T) {
	f := newReadingFixture(t)
	ctx := context.Background()
	_, p := f.article(t, 1, "A retryable article.")
	old, e := f.s.claim(ctx)
	if e != nil || old == nil {
		t.Fatal(e)
	}
	f.now = f.now.Add(301 * time.Second)
	current, e := f.s.claim(ctx)
	if e != nil || current == nil || old.Token == current.Token {
		t.Fatal("lease not recovered")
	}
	if e = f.s.finish(ctx, old, func(*sql.Tx) error { t.Error("stale worker wrote result"); return nil }); !errors.Is(e, errReadingLeaseLost) {
		t.Fatal("stale worker accepted", e)
	}
	if e = f.s.generate(ctx, current); e != nil {
		t.Fatal(e)
	}
	if e = f.s.Retry(ctx, 1, "generate", p.ID); !errors.Is(e, ErrReadingConflict) {
		t.Fatal("successful task rerolled")
	}
	_, failed := f.article(t, 1, "A failing article.")
	f.ai.fail = true
	for i := 0; i < readingMaxTries; i++ {
		f.run(t)
		f.now = f.now.Add(time.Hour)
	}
	got, e := f.s.Paper(ctx, 1, 2)
	if e != nil || got.Status != "failed" || got.Preparation == nil || got.Preparation.Attempts != readingMaxTries {
		t.Fatal("retry exhaustion", got, e)
	}
	if e = f.s.Retry(ctx, 2, "generate", failed.ID); !errors.Is(e, ErrReadingNotFound) {
		t.Fatal("retry ownership")
	}
	if e = f.s.Retry(ctx, 1, "generate", failed.ID); e != nil {
		t.Fatal(e)
	}
	f.ai.fail = false
	f.run(t)
	got, e = f.s.Paper(ctx, 1, 2)
	if e != nil || got.Status != "ready" || got.Preparation != nil {
		t.Fatal("manual retry did not recover")
	}
}

func TestReadingIntegrationSourceIDRecovery(t *testing.T) {
	f := newReadingFixture(t)
	ctx := context.Background()
	id, p := f.article(t, 1, "The school just held its first career fair.")
	if p.Preparation == nil || p.Preparation.Attempts != 0 || p.Preparation.MaxAttempts != readingMaxTries || p.Preparation.StartedAt != f.now.Unix() {
		t.Fatalf("missing preparation metadata: %+v", p.Preparation)
	}
	f.listen(t, 1, id, p)
	f.ai.wrongSourceID = true
	job, err := f.s.claim(ctx)
	if err != nil || job == nil {
		t.Fatal("claim failed", err)
	}
	pending, err := f.s.Paper(ctx, 1, id)
	if err != nil || pending.Status != "running" || pending.Preparation.Attempts != 1 || len(pending.CompletedSentenceIDs) != 2 {
		t.Fatal("pending listening/progress lost", err)
	}
	if err = f.s.generate(ctx, job); err != nil {
		t.Fatal(err)
	}
	ready, err := f.s.Paper(ctx, 1, id)
	if err != nil || ready.Status != "ready" || ready.Preparation != nil || !ready.Unlocked || ready.ID != p.ID || ready.ContentHash != p.ContentHash || len(ready.Questions) != 5 {
		t.Fatal("repaired paper did not unlock", err)
	}
	saved, err := f.s.loadPaper(ctx, f.db, 1, p.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Questions[0].SentenceIDs[0] != saved.Source[0].ID || saved.Questions[0].Quote != saved.Source[0].Text {
		t.Fatal("repaired source ID was not persisted")
	}
}
func TestReadingIntegrationUncertainAndSameDay(t *testing.T) {
	f := newReadingFixture(t)
	ctx := context.Background()
	id, p := f.article(t, 1, "An uncertain question.")
	f.run(t)
	f.listen(t, 1, id, p)
	f.ai.review = true
	a := f.submit(t, 1, id, p, "uncertain-first")
	f.run(t)
	a, _ = f.s.Attempt(ctx, 1, a.ID)
	if a.Score != nil || a.Status != "review_required" || a.Passed {
		t.Fatal("uncertainty became a score")
	}
	f.ai.review = false
	f.submit(t, 1, id, p, "uncertain-retry")
	f.run(t)
	second, p2 := f.article(t, 1, "Another article today.")
	f.run(t)
	f.listen(t, 1, second, p2)
	f.submit(t, 1, second, p2, "another-same-day")
	f.run(t)
	c, _ := f.s.Challenge(ctx, 1)
	if len(c.CompletedDays) != 1 {
		t.Fatal("multiple completions counted on one day")
	}
	// Deletion does not erase the reward fingerprint or immutable result history.
	if _, e := f.db.Exec(`DELETE FROM articles WHERE article_id=?`, id); e != nil {
		t.Fatal(e)
	}
	if _, e := f.s.Attempt(ctx, 1, a.ID); e != nil {
		t.Fatal("history lost on delete", e)
	}
	f.now = f.now.AddDate(0, 0, 1)
	again, p3 := f.article(t, 1, "An uncertain question.")
	f.run(t)
	f.listen(t, 1, again, p3)
	f.submit(t, 1, again, p3, "deleted-reimport")
	f.run(t)
	c, _ = f.s.Challenge(ctx, 1)
	if len(c.CompletedDays) != 1 {
		t.Fatal("delete/reimport earned twice")
	}
}

func TestReadingIntegrationConcurrentArticles(t *testing.T) {
	f := newReadingFixture(t)
	ctx := context.Background()
	type input struct {
		id int64
		p  *ReadingPaper
	}
	var articles []input
	for i := 0; i < 6; i++ {
		id, p := f.article(t, 1, fmt.Sprintf("Different story number %d.", i))
		f.run(t)
		f.listen(t, 1, id, p)
		articles = append(articles, input{id, p})
	}
	var wg sync.WaitGroup
	errs := make(chan error, 6)
	for i, item := range articles {
		wg.Add(1)
		go func(i int, item input) {
			defer wg.Done()
			_, err := f.s.Submit(ctx, 1, item.id, item.p.ID, fmt.Sprintf("concurrent-%d", i), testReadingAnswers())
			if err != nil {
				errs <- err
			}
		}(i, item)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	errs = make(chan error, 6)
	for range articles {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := f.s.RunOne(ctx)
			if err != nil {
				errs <- err
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	var graded int
	if e := f.db.QueryRow(`SELECT COUNT(*) FROM reading_attempts WHERE status='graded'`).Scan(&graded); e != nil || graded != 6 {
		rows, _ := f.db.Query(`SELECT id,kind,state,tries,last_error FROM reading_jobs`)
		for rows.Next() {
			var id, tries int
			var kind, state, last string
			_ = rows.Scan(&id, &kind, &state, &tries, &last)
			t.Log(id, kind, state, tries, last)
		}
		rows.Close()
		t.Fatalf("graded %d: %v", graded, e)
	}
	c, e := f.s.Challenge(ctx, 1)
	if e != nil || len(c.CompletedDays) != 1 {
		t.Fatalf("concurrent completions: %+v %v", c, e)
	}
}
func TestReadingIntegrationArticleQueueAtomicity(t *testing.T) {
	f := newReadingFixture(t)
	if _, err := f.db.Exec(`RENAME TABLE reading_jobs TO reading_jobs_offline`); err != nil {
		t.Fatal(err)
	}
	_, err := f.a.SaveAnalyzedArticle(context.Background(), 1, "Must rollback", []ArticleSentenceInput{{Original: "A valid sentence.", Translation: "有效句子"}})
	if err == nil {
		t.Fatal("upload succeeded without durable job")
	}
	for _, table := range []string{"articles", "article_sentences", "reading_papers", "reading_article_roots"} {
		var count int
		if err = f.db.QueryRow("SELECT COUNT(*) FROM " + table).Scan(&count); err != nil || count != 0 {
			t.Fatalf("partial write in %s: %d %v", table, count, err)
		}
	}
}
func TestReadingIntegrationAllRewardTiers(t *testing.T) {
	f := newReadingFixture(t)
	ctx := context.Background()
	for _, days := range []int{0, 4, 5, 13, 14, 20, 21, 25, 26, 27, 28, 29, 30} {
		user := 100 + days
		c, err := f.s.Challenge(ctx, user)
		if err != nil {
			t.Fatal(err)
		}
		for i := 0; i < days; i++ {
			day := f.now.AddDate(0, 0, i).Format("2006-01-02")
			if _, err = f.db.Exec(`INSERT INTO reading_days VALUES(?,?,?,?)`, user, day, c.ID, i+1); err != nil {
				t.Fatal(err)
			}
		}
	}
	f.now = f.now.AddDate(0, 0, 30)
	if err := f.s.SettleDue(ctx); err != nil {
		t.Fatal(err)
	}
	for _, days := range []int{0, 4, 5, 13, 14, 20, 21, 25, 26, 27, 28, 29, 30} {
		v, err := f.s.Vouchers(ctx, 100+days, "", 50, 0)
		if err != nil {
			t.Fatal(err)
		}
		tier := readingTier(days)
		if tier.Stars == 0 {
			if len(v) != 0 {
				t.Fatal("unearned voucher")
			}
		} else if len(v) != 1 || v[0].Stars != tier.Stars || v[0].AmountFen != tier.AmountFen {
			t.Fatalf("day %d: %+v", days, v)
		}
	}
}
