package services

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

const DailyWordReviewLimit = 20

// WordReviewTask 生词复习任务（一条生词本条目）。
type WordReviewTask struct {
	EntryID             int64
	Word                string
	NormalizedWord      string
	PartOfSpeech        string
	Meaning             string
	Tip                 string
	SentenceOriginal    string
	SentenceTranslation string
	ArticleID           int64
	ArticleTitle        string
	SentenceID          int64
	ReviewStep          int
	NextReviewAt        *time.Time
	MasteryStatus       string
	LastReviewedAt      *time.Time
}

// WordReviewTodaySummary 今日复习概览。
type WordReviewTodaySummary struct {
	DueCount       int `json:"due_count"`
	CompletedCount int `json:"completed_count"`
	DailyLimit     int `json:"daily_limit"`
	StreakDays     int `json:"streak_days"`
}

// WordReviewResult 单次复习提交结果。
type WordReviewResult struct {
	EntryID        int64
	Result         string
	ReviewStep     int
	NextReviewAt   *time.Time
	MasteryStatus  string
	LastReviewedAt *time.Time
}

func (s *ArticleService) GetWordReviewTodaySummary(ctx context.Context, userID int) (*WordReviewTodaySummary, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if userID <= 0 {
		return nil, fmt.Errorf("invalid user id")
	}
	if err := s.EnsureUserWordBookTable(ctx); err != nil {
		return nil, err
	}
	if err := s.ensureStudyLogTable(ctx); err != nil {
		return nil, err
	}

	var dueRaw int
	if err := s.db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM user_word_book
		WHERE user_id = ?
		  AND mastery_status = 'learning'
		  AND next_review_at IS NOT NULL
		  AND next_review_at <= CURDATE()
		  AND (last_reviewed_at IS NULL OR DATE(last_reviewed_at) < CURDATE())
	`, userID).Scan(&dueRaw); err != nil {
		return nil, fmt.Errorf("count due word reviews: %w", err)
	}

	var completedCount int
	if err := s.db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM user_word_book
		WHERE user_id = ?
		  AND last_reviewed_at IS NOT NULL
		  AND DATE(last_reviewed_at) = CURDATE()
	`, userID).Scan(&completedCount); err != nil {
		return nil, fmt.Errorf("count completed word reviews: %w", err)
	}

	remainingSlots := DailyWordReviewLimit - completedCount
	if remainingSlots < 0 {
		remainingSlots = 0
	}
	dueCount := dueRaw
	if dueCount > remainingSlots {
		dueCount = remainingSlots
	}

	stats, err := s.GetUserStudyStats(ctx, userID, 7)
	if err != nil {
		return nil, err
	}

	return &WordReviewTodaySummary{
		DueCount:       dueCount,
		CompletedCount: completedCount,
		DailyLimit:     DailyWordReviewLimit,
		StreakDays:     stats.CurrentStreakDays,
	}, nil
}

func (s *ArticleService) ListWordReviewTasks(ctx context.Context, userID int, status string) ([]WordReviewTask, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if userID <= 0 {
		return nil, fmt.Errorf("invalid user id")
	}
	if status != "pending" && status != "completed" {
		return nil, fmt.Errorf("invalid status")
	}
	if err := s.EnsureUserWordBookTable(ctx); err != nil {
		return nil, err
	}

	var query string
	switch status {
	case "completed":
		query = `
			SELECT
				w.entry_id, w.word, w.normalized_word, w.part_of_speech, w.meaning, w.tip,
				w.sentence_original, w.sentence_translation, w.article_id,
				COALESCE(a.title, ''), w.sentence_id, w.review_step, w.next_review_at,
				w.mastery_status, w.last_reviewed_at
			FROM user_word_book w
			LEFT JOIN articles a ON a.article_id = w.article_id
			WHERE w.user_id = ?
			  AND w.last_reviewed_at IS NOT NULL
			  AND DATE(w.last_reviewed_at) = CURDATE()
			ORDER BY w.last_reviewed_at DESC, w.entry_id DESC
		`
	default:
		query = `
			SELECT
				w.entry_id, w.word, w.normalized_word, w.part_of_speech, w.meaning, w.tip,
				w.sentence_original, w.sentence_translation, w.article_id,
				COALESCE(a.title, ''), w.sentence_id, w.review_step, w.next_review_at,
				w.mastery_status, w.last_reviewed_at
			FROM user_word_book w
			LEFT JOIN articles a ON a.article_id = w.article_id
			WHERE w.user_id = ?
			  AND w.mastery_status = 'learning'
			  AND w.next_review_at IS NOT NULL
			  AND w.next_review_at <= CURDATE()
			  AND (w.last_reviewed_at IS NULL OR DATE(w.last_reviewed_at) < CURDATE())
			ORDER BY w.next_review_at ASC, w.entry_id ASC
			LIMIT ?
		`
	}

	var rows *sql.Rows
	var err error
	if status == "pending" {
		var completedToday int
		if err := s.db.QueryRowContext(ctx, `
			SELECT COUNT(*)
			FROM user_word_book
			WHERE user_id = ?
			  AND last_reviewed_at IS NOT NULL
			  AND DATE(last_reviewed_at) = CURDATE()
		`, userID).Scan(&completedToday); err != nil {
			return nil, fmt.Errorf("count completed word reviews for limit: %w", err)
		}
		limit := DailyWordReviewLimit - completedToday
		if limit <= 0 {
			return []WordReviewTask{}, nil
		}
		rows, err = s.db.QueryContext(ctx, query, userID, limit)
	} else {
		rows, err = s.db.QueryContext(ctx, query, userID)
	}
	if err != nil {
		return nil, fmt.Errorf("query word review tasks: %w", err)
	}
	defer rows.Close()

	tasks := make([]WordReviewTask, 0)
	for rows.Next() {
		task, scanErr := scanWordReviewTask(rows)
		if scanErr != nil {
			return nil, scanErr
		}
		tasks = append(tasks, task)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate word review tasks: %w", err)
	}
	return tasks, nil
}

func (s *ArticleService) SubmitWordReviewResult(ctx context.Context, userID int, entryID int64, result string) (*WordReviewResult, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if userID <= 0 || entryID <= 0 {
		return nil, fmt.Errorf("invalid user id or entry id")
	}
	result = strings.ToLower(strings.TrimSpace(result))
	if result != "mastered" && result != "again" {
		return nil, fmt.Errorf("invalid review result")
	}
	if err := s.EnsureUserWordBookTable(ctx); err != nil {
		return nil, err
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin review result tx: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var reviewStep int
	var masteryStatus string
	var nextReview sql.NullTime
	row := tx.QueryRowContext(ctx, `
		SELECT review_step, mastery_status, next_review_at
		FROM user_word_book
		WHERE user_id = ? AND entry_id = ?
		FOR UPDATE
	`, userID, entryID)
	if err = row.Scan(&reviewStep, &masteryStatus, &nextReview); err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("word book entry not found")
		}
		return nil, fmt.Errorf("load word review entry: %w", err)
	}
	if masteryStatus == "paused" {
		return nil, fmt.Errorf("word review is paused")
	}

	now := time.Now()
	newStep := reviewStep
	newStatus := "learning"
	var nextDate *time.Time

	switch result {
	case "again":
		tomorrow := dateOnly(now.AddDate(0, 0, 1))
		nextDate = &tomorrow
	case "mastered":
		newStep = reviewStep + 1
		if newStep >= 4 {
			newStatus = "mastered"
			nextDate = nil
		} else {
			intervalDays := wordReviewIntervalDays(newStep)
			next := dateOnly(now.AddDate(0, 0, intervalDays))
			nextDate = &next
		}
	}

	var execErr error
	if nextDate == nil {
		_, execErr = tx.ExecContext(ctx, `
			UPDATE user_word_book
			SET review_step = ?,
			    mastery_status = ?,
			    next_review_at = NULL,
			    last_reviewed_at = ?,
			    updated_at = NOW()
			WHERE user_id = ? AND entry_id = ?
		`, newStep, newStatus, now, userID, entryID)
	} else {
		_, execErr = tx.ExecContext(ctx, `
			UPDATE user_word_book
			SET review_step = ?,
			    mastery_status = ?,
			    next_review_at = ?,
			    last_reviewed_at = ?,
			    updated_at = NOW()
			WHERE user_id = ? AND entry_id = ?
		`, newStep, newStatus, nextDate.Format("2006-01-02"), now, userID, entryID)
	}
	if execErr != nil {
		err = fmt.Errorf("update word review result: %w", execErr)
		return nil, err
	}

	if err = tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit word review result: %w", err)
	}

	_ = s.ensureStudyLogTable(ctx)
	_ = recordStudyActivity(ctx, s.db, userID, now, 0, 1)

	out := &WordReviewResult{
		EntryID:        entryID,
		Result:         result,
		ReviewStep:     newStep,
		MasteryStatus:  newStatus,
		LastReviewedAt: &now,
		NextReviewAt:   nextDate,
	}
	return out, nil
}

func wordReviewIntervalDays(reviewStep int) int {
	switch reviewStep {
	case 1:
		return 2
	case 2:
		return 4
	case 3:
		return 7
	default:
		return 7
	}
}

func dateOnly(t time.Time) time.Time {
	y, m, d := t.In(time.Local).Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.Local)
}

func scanWordReviewTask(rows *sql.Rows) (WordReviewTask, error) {
	var task WordReviewTask
	var nextReview sql.NullTime
	var lastReviewed sql.NullTime
	if err := rows.Scan(
		&task.EntryID,
		&task.Word,
		&task.NormalizedWord,
		&task.PartOfSpeech,
		&task.Meaning,
		&task.Tip,
		&task.SentenceOriginal,
		&task.SentenceTranslation,
		&task.ArticleID,
		&task.ArticleTitle,
		&task.SentenceID,
		&task.ReviewStep,
		&nextReview,
		&task.MasteryStatus,
		&lastReviewed,
	); err != nil {
		return WordReviewTask{}, fmt.Errorf("scan word review task: %w", err)
	}
	if nextReview.Valid {
		t := nextReview.Time
		task.NextReviewAt = &t
	}
	if lastReviewed.Valid {
		t := lastReviewed.Time
		task.LastReviewedAt = &t
	}
	return task, nil
}
