package services

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

type StudyStats struct {
	TotalArticles      int               `json:"total_articles"`
	TodayNewArticles   int               `json:"today_new_articles"`
	TodayReviewCount   int               `json:"today_review_count"`
	CurrentStreakDays  int               `json:"current_streak_days"`
	TotalReadCount     int               `json:"total_read_count"`
	TotalSentenceCount int               `json:"total_sentence_count"`
	RecentDays         []DailyStudyStats `json:"recent_days"`
}

type DailyStudyStats struct {
	Date        string `json:"date"`
	NewArticles int    `json:"new_articles"`
	ReviewCount int    `json:"review_count"`
	Active      bool   `json:"active"`
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

	stats := &StudyStats{
		RecentDays: make([]DailyStudyStats, 0, days),
	}

	row := s.db.QueryRowContext(ctx, `
		SELECT
			COUNT(*) AS total_articles,
			COALESCE(SUM(read_count), 0) AS total_read_count,
			COALESCE(SUM(sentence_count), 0) AS total_sentence_count
		FROM articles
		WHERE user_id = ?
	`, userID)
	if err := row.Scan(&stats.TotalArticles, &stats.TotalReadCount, &stats.TotalSentenceCount); err != nil {
		return nil, fmt.Errorf("query aggregate article stats: %w", err)
	}

	todayRow := s.db.QueryRowContext(ctx, `
		SELECT
			COALESCE(new_article_count, 0),
			COALESCE(review_article_count, 0)
		FROM user_study_logs
		WHERE user_id = ? AND study_date = CURDATE()
	`, userID)
	switch err := todayRow.Scan(&stats.TodayNewArticles, &stats.TodayReviewCount); err {
	case nil:
	case sql.ErrNoRows:
		stats.TodayNewArticles = 0
		stats.TodayReviewCount = 0
	default:
		return nil, fmt.Errorf("query today study stats: %w", err)
	}

	recentRows, err := s.db.QueryContext(ctx, `
		SELECT
			study_date,
			new_article_count,
			review_article_count
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
		if err := recentRows.Scan(&studyDate, &item.NewArticles, &item.ReviewCount); err != nil {
			return nil, fmt.Errorf("scan recent study log: %w", err)
		}
		item.Date = studyDate.Format("2006-01-02")
		item.Active = item.NewArticles > 0 || item.ReviewCount > 0
		recentMap[item.Date] = item
	}
	if err := recentRows.Err(); err != nil {
		return nil, fmt.Errorf("iterate recent study logs: %w", err)
	}

	today := time.Now()
	for offset := days - 1; offset >= 0; offset-- {
		date := today.AddDate(0, 0, -offset).Format("2006-01-02")
		if item, ok := recentMap[date]; ok {
			stats.RecentDays = append(stats.RecentDays, item)
			continue
		}
		stats.RecentDays = append(stats.RecentDays, DailyStudyStats{
			Date:        date,
			NewArticles: 0,
			ReviewCount: 0,
			Active:      false,
		})
	}

	streakRows, err := s.db.QueryContext(ctx, `
		SELECT study_date
		FROM user_study_logs
		WHERE user_id = ?
		  AND (new_article_count > 0 OR review_article_count > 0)
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
