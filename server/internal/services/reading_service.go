package services

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
	_ "time/tzdata"

	migrations "words/server/db"
	"words/server/pkg/utils"
)

type JSONCompleter interface {
	CompleteJSONPrompt(context.Context, string, string, string) (string, error)
}
type ReadingService struct {
	db    *sql.DB
	ai    JSONCompleter
	model string
	now   func() time.Time
}

func NewReadingService(db *sql.DB, ai JSONCompleter, model string) *ReadingService {
	return &ReadingService{db: db, ai: ai, model: model, now: time.Now}
}
func (s *ReadingService) EnsureSchema(ctx context.Context) error {
	for _, statement := range strings.Split(migrations.ReadingSchema, ";") {
		if strings.TrimSpace(statement) != "" {
			if _, err := s.db.ExecContext(ctx, statement); err != nil {
				return err
			}
		}
	}
	return nil
}
func (s *ReadingService) transaction(ctx context.Context, f func(*sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err = f(tx); err != nil {
		return err
	}
	return tx.Commit()
}
func readingJSON(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return string(data)
}
func readingMissing(err error) error {
	if errors.Is(err, sql.ErrNoRows) {
		return ErrReadingNotFound
	}
	return err
}

type readingDB interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}

// queueArticle runs in the article write transaction, so generation work cannot be lost on restart.
func (s *ReadingService) queueArticle(ctx context.Context, tx *sql.Tx, user int, article int64) (*readingPaper, error) {
	p := &readingPaper{UserID: user, ArticleID: article, Model: s.model}
	if err := tx.QueryRowContext(ctx, `SELECT title FROM articles WHERE article_id=? AND user_id=? FOR UPDATE`, article, user).Scan(&p.Title); err != nil {
		return nil, readingMissing(err)
	}
	rows, err := tx.QueryContext(ctx, `SELECT sentence_id,original_text FROM article_sentences WHERE article_id=? ORDER BY sentence_order,sentence_id`, article)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var v readingSource
		if err = rows.Scan(&v.ID, &v.Text); err != nil {
			rows.Close()
			return nil, err
		}
		if strings.TrimSpace(v.Text) != "" {
			p.Source = append(p.Source, v)
		}
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if len(p.Source) == 0 {
		return nil, ErrReadingInvalid
	}
	p.Hash = readingVersionHash(p.Source)
	_, err = tx.ExecContext(ctx, `INSERT IGNORE INTO reading_article_roots(article_id,user_id,content_hash) VALUES(?,?,?)`, article, user, readingHash(p.Source))
	if err != nil {
		return nil, err
	}
	if err = tx.QueryRowContext(ctx, `SELECT content_hash FROM reading_article_roots WHERE article_id=? AND user_id=?`, article, user).Scan(&p.RootHash); err != nil {
		return nil, err
	}

	var questions sql.NullString
	err = tx.QueryRowContext(ctx, `SELECT id,questions_json FROM reading_papers WHERE user_id=? AND article_id=? AND content_hash=?`, user, article, p.Hash).Scan(&p.ID, &questions)
	if err == nil {
		if questions.Valid {
			if err = json.Unmarshal([]byte(questions.String), &p.Questions); err != nil {
				return nil, err
			}
		}
		return p, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}
	res, err := tx.ExecContext(ctx, `INSERT INTO reading_papers(user_id,article_id,content_hash,title,source_json,model,prompt_version,created_at) VALUES(?,?,?,?,?,?,?,?)`, user, article, p.Hash, p.Title, readingJSON(p.Source), s.model, readingPromptVersion, s.now().Unix())
	if err != nil {
		return nil, err
	}
	p.ID, err = res.LastInsertId()
	if err != nil {
		return nil, err
	}
	if err = s.enqueue(ctx, tx, "generate", p.ID); err != nil {
		return nil, err
	}
	return p, nil
}
func (s *ReadingService) enqueue(ctx context.Context, q readingDB, kind string, ref int64) error {
	_, err := q.ExecContext(ctx, `INSERT IGNORE INTO reading_jobs(kind,ref_id,available_at) VALUES(?,?,?)`, kind, ref, s.now().Unix())
	return err
}
func (s *ReadingService) loadPaper(ctx context.Context, q readingDB, user int, id int64) (*readingPaper, error) {
	p := &readingPaper{ID: id, UserID: user}
	var source string
	var questions sql.NullString
	err := q.QueryRowContext(ctx, `SELECT p.article_id,p.content_hash,r.content_hash,p.title,p.source_json,p.questions_json,p.model FROM reading_papers p JOIN reading_article_roots r ON r.article_id=p.article_id WHERE p.id=? AND p.user_id=?`, id, user).Scan(&p.ArticleID, &p.Hash, &p.RootHash, &p.Title, &source, &questions, &p.Model)
	if err != nil {
		return nil, readingMissing(err)
	}
	if err = json.Unmarshal([]byte(source), &p.Source); err != nil {
		return nil, err
	}
	if questions.Valid {
		err = json.Unmarshal([]byte(questions.String), &p.Questions)
	}
	return p, err
}
func (s *ReadingService) Paper(ctx context.Context, user int, article int64) (*ReadingPaper, error) {
	var p *readingPaper
	err := s.transaction(ctx, func(tx *sql.Tx) error { var e error; p, e = s.queueArticle(ctx, tx, user, article); return e })
	if err != nil {
		return nil, err
	}
	out := &ReadingPaper{ID: p.ID, ArticleID: utils.EncryptID(article), ContentHash: p.Hash, Questions: []ReadingQuestion{}, CompletedSentenceIDs: []int64{}, TotalSentences: len(p.Source)}
	if len(p.Questions) == 5 {
		out.Status = "ready"
		for _, q := range p.Questions {
			out.Questions = append(out.Questions, q.ReadingQuestion)
		}
	} else {
		out.Preparation = &ReadingPreparation{MaxAttempts: readingMaxTries}
		if err = s.db.QueryRowContext(ctx, `SELECT j.state,j.tries,p.created_at FROM reading_jobs j JOIN reading_papers p ON p.id=j.ref_id WHERE j.kind='generate' AND j.ref_id=?`, p.ID).Scan(&out.Status, &out.Preparation.Attempts, &out.Preparation.StartedAt); err != nil {
			return nil, err
		}
	}
	rows, err := s.db.QueryContext(ctx, `SELECT sentence_id FROM reading_listening WHERE user_id=? AND paper_id=? ORDER BY sentence_id`, user, p.ID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id int64
		if err = rows.Scan(&id); err != nil {
			return nil, err
		}
		out.CompletedSentenceIDs = append(out.CompletedSentenceIDs, id)
	}
	out.Unlocked = len(out.CompletedSentenceIDs) == len(p.Source)
	return out, rows.Err()
}
func (s *ReadingService) CompleteListening(ctx context.Context, user int, article, paper, sentence int64, hash string) error {
	return s.transaction(ctx, func(tx *sql.Tx) error {
		p, err := s.queueArticle(ctx, tx, user, article)
		if err != nil {
			return err
		}
		if p.ID != paper || p.Hash != hash {
			return ErrReadingConflict
		}
		valid := false
		for _, v := range p.Source {
			if v.ID == sentence {
				valid = true
				break
			}
		}
		if !valid {
			return ErrReadingInvalid
		}
		_, err = tx.ExecContext(ctx, `INSERT IGNORE INTO reading_listening(user_id,paper_id,sentence_id,completed_at) VALUES(?,?,?,?)`, user, paper, sentence, s.now().Unix())
		return err
	})
}

var readingRequestKey = regexp.MustCompile(`^[a-zA-Z0-9_-]{8,80}$`)

func (s *ReadingService) Submit(ctx context.Context, user int, article, paper int64, key string, answers []ReadingAnswer) (*ReadingAttempt, error) {
	if !readingRequestKey.MatchString(key) {
		return nil, ErrReadingInvalid
	}
	answers, err := normalizeReadingAnswers(answers)
	if err != nil {
		return nil, err
	}
	var id int64
	err = s.transaction(ctx, func(tx *sql.Tx) error {
		p, e := s.queueArticle(ctx, tx, user, article)
		if e != nil {
			return e
		}
		now := s.now()
		cycle, e := s.currentCycle(ctx, tx, user, now)
		if e != nil {
			return e
		}
		var oldPaper int64
		var oldAnswers string
		e = tx.QueryRowContext(ctx, `SELECT id,paper_id,answers_json FROM reading_attempts WHERE user_id=? AND request_key=?`, user, key).Scan(&id, &oldPaper, &oldAnswers)
		if e == nil {
			if oldPaper != paper || oldAnswers != readingJSON(answers) {
				return ErrReadingConflict
			}
			return nil
		}
		if !errors.Is(e, sql.ErrNoRows) {
			return e
		}
		if p.ID != paper || len(p.Questions) != 5 {
			return ErrReadingConflict
		}
		var count int
		if e = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM reading_listening WHERE user_id=? AND paper_id=?`, user, paper).Scan(&count); e != nil {
			return e
		}
		if count != len(p.Source) {
			return ErrReadingLocked
		}
		var pending int
		if e = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM reading_attempts WHERE user_id=? AND paper_id=? AND status='pending'`, user, paper).Scan(&pending); e != nil {
			return e
		}
		if pending > 0 {
			return ErrReadingConflict
		}
		var daily int
		loc, _ := time.LoadLocation(cycle.Timezone)
		today := now.In(loc).Format("2006-01-02")
		if e = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM reading_attempts WHERE user_id=? AND submitted_on=?`, user, today).Scan(&daily); e != nil {
			return e
		}
		if daily >= 30 {
			return fmt.Errorf("%w: daily attempt limit", ErrReadingConflict)
		}
		res, e := tx.ExecContext(ctx, `INSERT INTO reading_attempts(user_id,paper_id,cycle_id,request_key,answers_json,submitted_at,submitted_on) VALUES(?,?,?,?,?,?,?)`, user, paper, cycle.ID, key, readingJSON(answers), now.Unix(), today)
		if e != nil {
			return e
		}
		id, e = res.LastInsertId()
		if e != nil {
			return e
		}
		return s.enqueue(ctx, tx, "grade", id)
	})
	if err != nil {
		return nil, err
	}
	return s.Attempt(ctx, user, id)
}

const readingAttemptSelect = `SELECT a.id,a.paper_id,a.cycle_id,a.status,a.answers_json,a.results_json,a.score,a.passed,a.submitted_at,a.submitted_on,a.graded_at,j.state FROM reading_attempts a JOIN reading_jobs j ON j.kind='grade' AND j.ref_id=a.id`

func scanReadingAttempt(row interface{ Scan(...any) error }) (*ReadingAttempt, error) {
	out := &ReadingAttempt{Results: []ReadingVerdict{}}
	var answers string
	var results sql.NullString
	var score, graded sql.NullInt64
	var job string
	if err := row.Scan(&out.ID, &out.PaperID, &out.CycleID, &out.Status, &answers, &results, &score, &out.Passed, &out.SubmittedAt, &out.SubmittedOn, &graded, &job); err != nil {
		return nil, readingMissing(err)
	}
	if err := json.Unmarshal([]byte(answers), &out.Answers); err != nil {
		return nil, err
	}
	if results.Valid {
		if err := json.Unmarshal([]byte(results.String), &out.Results); err != nil {
			return nil, err
		}
	}
	if score.Valid {
		n := int(score.Int64)
		out.Score = &n
	}
	if graded.Valid {
		out.GradedAt = &graded.Int64
	}
	if out.Status == "pending" {
		out.Status = job
	}
	return out, nil
}
func (s *ReadingService) Attempt(ctx context.Context, user int, id int64) (*ReadingAttempt, error) {
	return scanReadingAttempt(s.db.QueryRowContext(ctx, readingAttemptSelect+` WHERE a.user_id=? AND a.id=?`, user, id))
}
func (s *ReadingService) Attempts(ctx context.Context, user int, article int64) ([]ReadingAttempt, error) {
	var owns int
	if err := s.db.QueryRowContext(ctx, `SELECT 1 FROM articles WHERE article_id=? AND user_id=?`, article, user).Scan(&owns); err != nil {
		return nil, readingMissing(err)
	}
	rows, err := s.db.QueryContext(ctx, readingAttemptSelect+` JOIN reading_papers p ON p.id=a.paper_id WHERE a.user_id=? AND p.article_id=? ORDER BY a.id DESC LIMIT 50`, user, article)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ReadingAttempt{}
	for rows.Next() {
		a, err := scanReadingAttempt(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *a)
	}
	return out, rows.Err()
}

// Retry reuses the same immutable input and only accepts exhausted system failures.
func (s *ReadingService) Retry(ctx context.Context, user int, kind string, id int64) error {
	table := "reading_papers"
	if kind == "grade" {
		table = "reading_attempts"
	} else if kind != "generate" {
		return ErrReadingInvalid
	}
	var owns int
	if err := s.db.QueryRowContext(ctx, `SELECT 1 FROM `+table+` WHERE id=? AND user_id=?`, id, user).Scan(&owns); err != nil {
		return readingMissing(err)
	}
	res, err := s.db.ExecContext(ctx, `UPDATE reading_jobs SET state='queued',tries=0,available_at=?,last_error='' WHERE kind=? AND ref_id=? AND state='failed' AND available_at<=?`, s.now().Unix(), kind, id, s.now().Unix())
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrReadingConflict
	}
	return nil
}
