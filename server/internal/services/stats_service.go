package services

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"time"
)

type StudyStats struct {
	TotalArticles          int               `json:"total_articles"`
	TodayNewArticles       int               `json:"today_new_articles"`
	TodayReviewCount       int               `json:"today_review_count"`
	TodayReadSeconds       int               `json:"today_read_seconds"`
	TodayReviewSeconds     int               `json:"today_review_seconds"`
	CurrentStreakDays      int               `json:"current_streak_days"`
	TotalReadCount         int               `json:"total_read_count"`
	TotalSentenceCount     int               `json:"total_sentence_count"`
	TotalReadSeconds       int               `json:"total_read_seconds"`
	AverageReadingSpeedWPM *int              `json:"average_reading_speed_wpm,omitempty"`
	RecentDays             []DailyStudyStats `json:"recent_days"`
}

type DailyStudyStats struct {
	Date          string `json:"date"`
	NewArticles   int    `json:"new_articles"`
	ReviewCount   int    `json:"review_count"`
	ReadSeconds   int    `json:"read_seconds"`
	ReviewSeconds int    `json:"review_seconds"`
	Active        bool   `json:"active"`
}

func (s *ArticleService) ensureStudyLogTable(ctx context.Context) error {
	if err := s.validateService(); err != nil {
		return err
	}

	_, err := s.db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS user_study_logs (
			id BIGINT NOT NULL AUTO_INCREMENT,
			user_id INT NOT NULL,
			study_date DATE NOT NULL,
			new_article_count INT NOT NULL DEFAULT 0,
			review_article_count INT NOT NULL DEFAULT 0,
			read_seconds INT NOT NULL DEFAULT 0,
			review_seconds INT NOT NULL DEFAULT 0,
			last_active_at DATETIME NOT NULL,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NULL DEFAULT NULL,
			PRIMARY KEY (id),
			UNIQUE KEY idx_user_study_date (user_id, study_date),
			KEY idx_study_date (study_date)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
	`)
	if err != nil {
		return fmt.Errorf("ensure user_study_logs table: %w", err)
	}

	alters := []string{
		`ALTER TABLE user_study_logs ADD COLUMN read_seconds INT NOT NULL DEFAULT 0 AFTER review_article_count`,
		`ALTER TABLE user_study_logs ADD COLUMN review_seconds INT NOT NULL DEFAULT 0 AFTER read_seconds`,
	}
	for _, stmt := range alters {
		if _, err := s.db.ExecContext(ctx, stmt); err != nil && !isIgnorableSchemaError(err) {
			return fmt.Errorf("ensure user_study_logs duration columns: %w", err)
		}
	}

	return nil
}

func recordStudyActivity(ctx context.Context, execer interface {
	ExecContext(context.Context, string, ...interface{}) (sql.Result, error)
}, userID int, when time.Time, newArticlesDelta int, reviewDelta int) error {
	if userID <= 0 {
		return fmt.Errorf("invalid user id")
	}
	if newArticlesDelta == 0 && reviewDelta == 0 {
		return nil
	}

	_, err := execer.ExecContext(ctx, `
		INSERT INTO user_study_logs (
			user_id,
			study_date,
			new_article_count,
			review_article_count,
			last_active_at
		) VALUES (?, DATE(?), ?, ?, ?)
		ON DUPLICATE KEY UPDATE
			new_article_count = new_article_count + VALUES(new_article_count),
			review_article_count = review_article_count + VALUES(review_article_count),
			last_active_at = GREATEST(last_active_at, VALUES(last_active_at))
	`, userID, when, newArticlesDelta, reviewDelta, when)
	if err != nil {
		return fmt.Errorf("record study activity: %w", err)
	}

	return nil
}

func recordStudyDuration(ctx context.Context, execer interface {
	ExecContext(context.Context, string, ...interface{}) (sql.Result, error)
}, userID int, when time.Time, readSeconds int, reviewSeconds int) error {
	if userID <= 0 {
		return fmt.Errorf("invalid user id")
	}
	if readSeconds == 0 && reviewSeconds == 0 {
		return nil
	}

	_, err := execer.ExecContext(ctx, `
		INSERT INTO user_study_logs (
			user_id,
			study_date,
			new_article_count,
			review_article_count,
			read_seconds,
			review_seconds,
			last_active_at
		) VALUES (?, DATE(?), 0, 0, ?, ?, ?)
		ON DUPLICATE KEY UPDATE
			read_seconds = read_seconds + VALUES(read_seconds),
			review_seconds = review_seconds + VALUES(review_seconds),
			last_active_at = GREATEST(last_active_at, VALUES(last_active_at))
	`, userID, when, readSeconds, reviewSeconds, when)
	if err != nil {
		return fmt.Errorf("record study duration: %w", err)
	}
	return nil
}

// AddReviewDuration 累加当日复习有效秒数。
func (s *ArticleService) AddReviewDuration(ctx context.Context, userID int, seconds int) (int, error) {
	if err := s.validateService(); err != nil {
		return 0, err
	}
	if userID <= 0 {
		return 0, fmt.Errorf("invalid user id")
	}
	seconds = normalizeDurationSeconds(seconds)
	if seconds == 0 {
		return 0, fmt.Errorf("invalid duration seconds")
	}
	if err := s.ensureStudyLogTable(ctx); err != nil {
		return 0, err
	}

	now := time.Now()
	if err := recordStudyDuration(ctx, s.db, userID, now, 0, seconds); err != nil {
		return 0, err
	}

	var total int
	if err := s.db.QueryRowContext(ctx, `
		SELECT COALESCE(review_seconds, 0)
		FROM user_study_logs
		WHERE user_id = ? AND study_date = CURDATE()
	`, userID).Scan(&total); err != nil {
		if err == sql.ErrNoRows {
			return seconds, nil
		}
		return seconds, nil
	}
	return total, nil
}

func (s *ArticleService) GetUserStudyStats(ctx context.Context, userID int, days int) (*StudyStats, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if userID <= 0 {
		return nil, fmt.Errorf("invalid user id")
	}
	if days <= 0 || days > 30 {
		days = 7
	}

	if err := s.ensureStudyLogTable(ctx); err != nil {
		return nil, err
	}
	if err := s.ensureWordReviewLogTable(ctx); err != nil {
		return nil, err
	}
	if err := s.ensureArticleReadSecondsColumn(ctx); err != nil {
		return nil, err
	}

	stats := &StudyStats{
		RecentDays: make([]DailyStudyStats, 0, days),
	}

	row := s.db.QueryRowContext(ctx, `
		SELECT
			COUNT(*) AS total_articles,
			COALESCE(SUM(read_count), 0) AS total_read_count,
			COALESCE(SUM(sentence_count), 0) AS total_sentence_count,
			COALESCE(SUM(read_seconds), 0) AS total_read_seconds
		FROM articles
		WHERE user_id = ?
	`, userID)
	if err := row.Scan(
		&stats.TotalArticles,
		&stats.TotalReadCount,
		&stats.TotalSentenceCount,
		&stats.TotalReadSeconds,
	); err != nil {
		return nil, fmt.Errorf("query aggregate article stats: %w", err)
	}

	todayRow := s.db.QueryRowContext(ctx, `
		SELECT
			COALESCE(new_article_count, 0),
			COALESCE(read_seconds, 0),
			COALESCE(review_seconds, 0)
		FROM user_study_logs
		WHERE user_id = ? AND study_date = CURDATE()
	`, userID)
	switch err := todayRow.Scan(&stats.TodayNewArticles, &stats.TodayReadSeconds, &stats.TodayReviewSeconds); err {
	case nil:
	case sql.ErrNoRows:
		stats.TodayNewArticles = 0
		stats.TodayReadSeconds = 0
		stats.TodayReviewSeconds = 0
	default:
		return nil, fmt.Errorf("query today study stats: %w", err)
	}

	wordReviewCounts, err := s.dailyWordReviewCounts(ctx, userID, days)
	if err != nil {
		return nil, err
	}
	stats.TodayReviewCount = wordReviewCounts[time.Now().Format("2006-01-02")]

	if avg := s.averageReadingSpeedWPM(ctx, userID); avg != nil {
		stats.AverageReadingSpeedWPM = avg
	}

	recentRows, err := s.db.QueryContext(ctx, `
		SELECT
			study_date,
			new_article_count,
			COALESCE(read_seconds, 0),
			COALESCE(review_seconds, 0)
		FROM user_study_logs
		WHERE user_id = ?
		  AND study_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
		ORDER BY study_date ASC
	`, userID, days-1)
	if err != nil {
		return nil, fmt.Errorf("query recent study logs: %w", err)
	}
	defer recentRows.Close()

	recentMap := make(map[string]DailyStudyStats, days)
	for recentRows.Next() {
		var studyDate time.Time
		var item DailyStudyStats
		if err := recentRows.Scan(
			&studyDate,
			&item.NewArticles,
			&item.ReadSeconds,
			&item.ReviewSeconds,
		); err != nil {
			return nil, fmt.Errorf("scan recent study log: %w", err)
		}
		item.Date = studyDate.Format("2006-01-02")
		item.ReviewCount = wordReviewCounts[item.Date]
		item.Active = item.NewArticles > 0 || item.ReviewCount > 0 || item.ReadSeconds > 0 || item.ReviewSeconds > 0
		recentMap[item.Date] = item
	}
	if err := recentRows.Err(); err != nil {
		return nil, fmt.Errorf("iterate recent study logs: %w", err)
	}

	today := time.Now()
	for offset := days - 1; offset >= 0; offset-- {
		date := today.AddDate(0, 0, -offset).Format("2006-01-02")
		reviewCount := wordReviewCounts[date]
		if item, ok := recentMap[date]; ok {
			item.ReviewCount = reviewCount
			item.Active = item.NewArticles > 0 || reviewCount > 0 || item.ReadSeconds > 0 || item.ReviewSeconds > 0
			stats.RecentDays = append(stats.RecentDays, item)
			continue
		}
		stats.RecentDays = append(stats.RecentDays, DailyStudyStats{
			Date:          date,
			NewArticles:   0,
			ReviewCount:   reviewCount,
			ReadSeconds:   0,
			ReviewSeconds: 0,
			Active:        reviewCount > 0,
		})
	}

	streakRows, err := s.db.QueryContext(ctx, `
		SELECT study_date
		FROM user_study_logs
		WHERE user_id = ?
		  AND (
			new_article_count > 0
			OR review_article_count > 0
			OR read_seconds > 0
			OR review_seconds > 0
		  )
		ORDER BY study_date DESC
		LIMIT 365
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("query streak logs: %w", err)
	}
	defer streakRows.Close()

	expectedDate := today.Format("2006-01-02")
	for streakRows.Next() {
		var studyDate time.Time
		if err := streakRows.Scan(&studyDate); err != nil {
			return nil, fmt.Errorf("scan streak log: %w", err)
		}

		actual := studyDate.Format("2006-01-02")
		if actual != expectedDate {
			break
		}

		stats.CurrentStreakDays++
		expectedDate = studyDate.AddDate(0, 0, -1).Format("2006-01-02")
	}
	if err := streakRows.Err(); err != nil {
		return nil, fmt.Errorf("iterate streak logs: %w", err)
	}

	return stats, nil
}

func (s *ArticleService) averageReadingSpeedWPM(ctx context.Context, userID int) *int {
	rows, err := s.db.QueryContext(ctx, `
		SELECT article_id, COALESCE(read_seconds, 0)
		FROM articles
		WHERE user_id = ?
		  AND COALESCE(read_seconds, 0) >= 30
	`, userID)
	if err != nil {
		return nil
	}
	defer rows.Close()

	type articleDur struct {
		id      int64
		seconds int
	}
	items := make([]articleDur, 0)
	for rows.Next() {
		var item articleDur
		if err := rows.Scan(&item.id, &item.seconds); err != nil {
			return nil
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil || len(items) == 0 {
		return nil
	}

	summaries := make([]ArticleSummary, 0, len(items))
	for _, item := range items {
		summaries = append(summaries, ArticleSummary{ArticleID: item.id, ReadSeconds: item.seconds})
	}
	if err := s.populateArticleWordCounts(ctx, summaries); err != nil {
		return nil
	}

	totalWords := 0
	totalSeconds := 0
	for _, summary := range summaries {
		if summary.WordCount <= 0 || summary.ReadSeconds < 30 {
			continue
		}
		totalWords += summary.WordCount
		totalSeconds += summary.ReadSeconds
	}
	if totalWords <= 0 || totalSeconds < 30 {
		return nil
	}
	wpm := int(math.Round(float64(totalWords) / (float64(totalSeconds) / 60.0)))
	if wpm <= 0 {
		return nil
	}
	return &wpm
}

func (s *ArticleService) dailyWordReviewCounts(ctx context.Context, userID int, days int) (map[string]int, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT DATE(reviewed_at) AS review_date, COUNT(*) AS review_count
		FROM user_word_review_logs
		WHERE user_id = ?
		  AND reviewed_at >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
		GROUP BY DATE(reviewed_at)
	`, userID, days-1)
	if err != nil {
		return nil, fmt.Errorf("query daily word review counts: %w", err)
	}
	defer rows.Close()

	counts := make(map[string]int, days)
	for rows.Next() {
		var reviewDate time.Time
		var count int
		if err := rows.Scan(&reviewDate, &count); err != nil {
			return nil, fmt.Errorf("scan daily word review count: %w", err)
		}
		counts[reviewDate.Format("2006-01-02")] = count
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate daily word review counts: %w", err)
	}
	return counts, nil
}
