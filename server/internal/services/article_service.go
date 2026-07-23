package services

import (
	"context"
	"database/sql"
	"fmt"
	"regexp"
	"strings"
	"time"
)

const ArticleTextAnalysisPrompt = `阅读正文，先生成一个准确概括主题的简短标题，再把正文按顺序整理成适合学习的短句并逐句翻译成中文。
标题尽量使用正文的主要语言，控制在 2 至 6 个词，不使用句号，不要直接照抄正文第一句。
只处理用户提供的内容，不补写，不输出说明。
仅输出 TSV：
第一行格式：TITLE<TAB>标题
后续每行格式：SENTENCE<TAB>英文原句<TAB>中文翻译`

const WordExplainPromptTemplate = `解释用户在当前句子里点击的单词，如果在句子中该单词涉及到短语、固定搭配等，则一并解释。
只返回 JSON：
{"word":"单词","part_of_speech":"词性","meaning":"当前句中的中文意思","tip":"结合当前句子的简短提示"}`

const SentenceCoachPromptTemplate = `回答用户关于当前句子的问题。
只返回 JSON：
{"answer":"简洁中文回答","highlights":["要点1","要点2"]}`

// ArticleSentenceInput 表示待写入 article_sentences 的句子
type ArticleSentenceInput struct {
	Original    string
	Translation string
}

// ArticleService 负责将识别结果落库
type ArticleService struct {
	db *sql.DB
}

// NewArticleService 创建 ArticleService
func NewArticleService(db *sql.DB) *ArticleService {
	return &ArticleService{db: db}
}

// validateService 验证服务是否已初始化
func (s *ArticleService) validateService() error {
	if s == nil || s.db == nil {
		return fmt.Errorf("article service not initialized")
	}
	return nil
}

// parseArticleSentencesFromData 从结构化数据解析文章句子数据
// data: 每行 [英文, 中文]
func parseArticleSentencesFromData(data [][]string) ([]ArticleSentenceInput, error) {
	if len(data) == 0 {
		return nil, fmt.Errorf("no valid lines found")
	}

	sentences := make([]ArticleSentenceInput, 0, len(data))
	for _, line := range data {
		if len(line) >= 2 {
			sentences = append(sentences, ArticleSentenceInput{
				Original:    line[0],
				Translation: line[1],
			})
		} else if len(line) == 1 && line[0] != "" {
			// 只有一列，可能是格式错误，但尝试使用
			sentences = append(sentences, ArticleSentenceInput{
				Original:    line[0],
				Translation: "",
			})
		}
	}

	if len(sentences) == 0 {
		return nil, fmt.Errorf("no valid sentences found")
	}

	return sentences, nil
}

// SaveAnalyzedArticle 将 AI 识别结果写入 articles 和 article_sentences
// 返回 articleID
func (s *ArticleService) SaveAnalyzedArticle(
	ctx context.Context,
	userID int,
	title string,
	sentences []ArticleSentenceInput,
) (int64, error) {
	if err := s.validateService(); err != nil {
		return 0, err
	}
	if userID <= 0 {
		return 0, fmt.Errorf("invalid user id")
	}
	if len(sentences) == 0 {
		return 0, fmt.Errorf("no sentences to save")
	}

	title = strings.Trim(strings.TrimSpace(title), "\"'“”‘’")
	if title == "" {
		title = "Untitled Article"
	}
	if len([]rune(title)) > 60 {
		title = string([]rune(title)[:60])
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, fmt.Errorf("begin transaction: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	articleRes, err := tx.ExecContext(
		ctx,
		`INSERT INTO articles (user_id, title, sentence_count) VALUES (?,?,?)`,
		userID,
		title,
		len(sentences),
	)
	if err != nil {
		return 0, fmt.Errorf("insert article: %w", err)
	}

	articleID, err := articleRes.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("fetch article id: %w", err)
	}

	if err = s.createNextDayReviewTaskTx(ctx, tx, userID, articleID, time.Now()); err != nil {
		return 0, err
	}

	stmt, err := tx.PrepareContext(ctx, `
		INSERT INTO article_sentences (article_id, sentence_order, original_text, translation)
		VALUES (?,?,?,?)
	`)
	if err != nil {
		return 0, fmt.Errorf("prepare sentence stmt: %w", err)
	}
	defer stmt.Close()

	written := 0
	for idx, sentence := range sentences {
		original := strings.TrimSpace(sentence.Original)
		translation := strings.TrimSpace(sentence.Translation)
		if original == "" && translation == "" {
			continue
		}

		if _, err = stmt.ExecContext(ctx, articleID, idx+1, original, translation); err != nil {
			return 0, fmt.Errorf("insert sentence %d: %w", idx+1, err)
		}
		written++
	}

	if written == 0 {
		return 0, fmt.Errorf("no valid sentences inserted")
	}

	if err = tx.Commit(); err != nil {
		return 0, fmt.Errorf("commit article transaction: %w", err)
	}

	_ = s.ensureStudyLogTable(ctx)
	_ = recordStudyActivity(ctx, s.db, userID, time.Now(), 1, 0)

	return articleID, nil
}

// ArticleDetail 文章详情结构
type ArticleDetail struct {
	ArticleID     int64             `json:"article_id"`
	Title         string            `json:"title"`
	SentenceCount int               `json:"sentence_count"`
	Sentences     []ArticleSentence `json:"sentences"`
}

// ArticleSentence 文章句子结构
type ArticleSentence struct {
	ID          int    `json:"id"`
	SentenceID  int64  `json:"sentence_id"`
	Original    string `json:"original"`
	Translation string `json:"translation"`
	IsFavorite  bool   `json:"is_favorite"`
}

// UpdateSentenceContent 更新当前用户文章中的单句原文和翻译。
func (s *ArticleService) UpdateSentenceContent(
	ctx context.Context,
	articleID, sentenceID int64,
	userID int,
	original, translation string,
) (*ArticleSentence, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	original = strings.TrimSpace(original)
	translation = strings.TrimSpace(translation)
	if articleID <= 0 || sentenceID <= 0 || userID <= 0 || original == "" || translation == "" {
		return nil, fmt.Errorf("invalid sentence update")
	}

	result, err := s.db.ExecContext(ctx, `
		UPDATE article_sentences s
		JOIN articles a ON a.article_id = s.article_id
		SET s.original_text = ?, s.translation = ?, s.updated_at = NOW(), a.updated_at = NOW()
		WHERE s.article_id = ? AND s.sentence_id = ? AND a.user_id = ?
	`, original, translation, articleID, sentenceID, userID)
	if err != nil {
		return nil, fmt.Errorf("update sentence: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("read update result: %w", err)
	}
	if rowsAffected == 0 {
		return nil, fmt.Errorf("sentence not found")
	}

	// Existing explanations were generated from the previous sentence content.
	_, _ = s.db.ExecContext(ctx, `DELETE FROM word_explanations_cache WHERE sentence_id = ?`, sentenceID)

	row := s.db.QueryRowContext(ctx, `
		SELECT sentence_order, is_favorite
		FROM article_sentences
		WHERE article_id = ? AND sentence_id = ?
	`, articleID, sentenceID)
	var order int
	var isFavorite bool
	if err := row.Scan(&order, &isFavorite); err != nil {
		return nil, fmt.Errorf("query updated sentence: %w", err)
	}

	return &ArticleSentence{
		ID:          order - 1,
		SentenceID:  sentenceID,
		Original:    original,
		Translation: translation,
		IsFavorite:  isFavorite,
	}, nil
}

// ArticleSummary 文章列表项
type ArticleSummary struct {
	ArticleID     int64      `json:"article_id"`
	Title         string     `json:"title"`
	SentenceCount int        `json:"sentence_count"`
	WordCount     int        `json:"word_count"`
	ReadCount     int        `json:"read_count"`
	CreatedAt     time.Time  `json:"created_at"`
	LastReadAt    *time.Time `json:"last_read_at,omitempty"`
}

type ReviewTask struct {
	TaskID        int64      `json:"task_id"`
	ArticleID     int64      `json:"article_id"`
	ArticleTitle  string     `json:"article_title"`
	SentenceCount int        `json:"sentence_count"`
	WordCount     int        `json:"word_count"`
	ScheduledFor  time.Time  `json:"scheduled_for"`
	Status        string     `json:"status"`
	StartedAt     *time.Time `json:"started_at,omitempty"`
	CompletedAt   *time.Time `json:"completed_at,omitempty"`
}

// GetArticleDetail 根据文章ID获取文章详情（包括所有句子）
func (s *ArticleService) GetArticleDetail(ctx context.Context, articleID int64, userID int) (*ArticleDetail, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if articleID <= 0 {
		return nil, fmt.Errorf("invalid article id")
	}

	// 查询文章基本信息
	var title string
	var sentenceCount int
	row := s.db.QueryRowContext(ctx,
		`SELECT title, sentence_count FROM articles WHERE article_id = ? AND user_id = ?`,
		articleID, userID)
	if err := row.Scan(&title, &sentenceCount); err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("article not found")
		}
		return nil, fmt.Errorf("query article: %w", err)
	}

	// 查询所有句子
	rows, err := s.db.QueryContext(ctx,
		`SELECT sentence_id, sentence_order, original_text, translation, is_favorite 
		 FROM article_sentences 
		 WHERE article_id = ? 
		 ORDER BY sentence_order ASC`,
		articleID)
	if err != nil {
		return nil, fmt.Errorf("query sentences: %w", err)
	}
	defer rows.Close()

	var sentences []ArticleSentence
	for rows.Next() {
		var sID int64
		var order int
		var original, translation string
		var isFavorite bool
		if err := rows.Scan(&sID, &order, &original, &translation, &isFavorite); err != nil {
			return nil, fmt.Errorf("scan sentence: %w", err)
		}
		sentences = append(sentences, ArticleSentence{
			ID:          order - 1, // 前端使用0-based索引
			SentenceID:  sID,
			Original:    original,
			Translation: translation,
			IsFavorite:  isFavorite,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate sentences: %w", err)
	}

	return &ArticleDetail{
		ArticleID:     articleID,
		Title:         title,
		SentenceCount: sentenceCount,
		Sentences:     sentences,
	}, nil
}

func (s *ArticleService) EnsureReviewTaskTable(ctx context.Context) error {
	if err := s.validateService(); err != nil {
		return err
	}

	_, err := s.db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS article_review_tasks (
			task_id BIGINT NOT NULL AUTO_INCREMENT,
			user_id INT NOT NULL,
			article_id INT NOT NULL,
			task_type VARCHAR(32) NOT NULL DEFAULT 'review',
			scheduled_for DATE NOT NULL,
			status VARCHAR(16) NOT NULL DEFAULT 'pending',
			started_at DATETIME DEFAULT NULL,
			completed_at DATETIME DEFAULT NULL,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME NOT NULL,
			PRIMARY KEY (task_id),
			UNIQUE KEY idx_user_article_day_type (user_id, article_id, scheduled_for, task_type),
			KEY idx_user_status_schedule (user_id, status, scheduled_for),
			KEY idx_user_completed_at (user_id, completed_at),
			CONSTRAINT fk_article_review_tasks_article FOREIGN KEY (article_id) REFERENCES articles(article_id) ON DELETE CASCADE,
			CONSTRAINT fk_article_review_tasks_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
	`)
	if err != nil {
		return fmt.Errorf("ensure review task table: %w", err)
	}
	return nil
}

type SentenceStudyContext struct {
	ArticleID    int64
	ArticleTitle string
	SentenceID   int64
	Order        int
	Original     string
	Translation  string
}

type CachedWordExplanation struct {
	SentenceID     int64
	NormalizedWord string
	Word           string
	PartOfSpeech   string
	Meaning        string
	Tip            string
}

// GetArticleSentencesForAudio 根据文章ID获取所有句子信息（用于生成音频）
func (s *ArticleService) GetSentenceStudyContext(ctx context.Context, articleID, sentenceID int64, userID int) (*SentenceStudyContext, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if articleID <= 0 || sentenceID <= 0 || userID <= 0 {
		return nil, fmt.Errorf("invalid article id, sentence id or user id")
	}

	row := s.db.QueryRowContext(ctx, `
		SELECT a.article_id, a.title, s.sentence_id, s.sentence_order, s.original_text, s.translation
		FROM articles a
		JOIN article_sentences s ON s.article_id = a.article_id
		WHERE a.article_id = ? AND s.sentence_id = ? AND a.user_id = ?
	`, articleID, sentenceID, userID)

	var result SentenceStudyContext
	if err := row.Scan(
		&result.ArticleID,
		&result.ArticleTitle,
		&result.SentenceID,
		&result.Order,
		&result.Original,
		&result.Translation,
	); err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("sentence not found")
		}
		return nil, fmt.Errorf("query sentence context: %w", err)
	}

	return &result, nil
}

func (s *ArticleService) EnsureWordExplanationCacheTable(ctx context.Context) error {
	if err := s.validateService(); err != nil {
		return err
	}

	_, err := s.db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS word_explanations_cache (
			cache_id INT NOT NULL AUTO_INCREMENT,
			sentence_id BIGINT NOT NULL DEFAULT 0,
			normalized_word VARCHAR(128) NOT NULL,
			word VARCHAR(128) NOT NULL DEFAULT '',
			part_of_speech VARCHAR(32) NOT NULL DEFAULT '',
			meaning TEXT NOT NULL,
			tip TEXT NOT NULL,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NULL DEFAULT NULL,
			PRIMARY KEY (cache_id),
			UNIQUE KEY idx_sentence_word (sentence_id, normalized_word)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
	`)
	if err != nil {
		return fmt.Errorf("ensure word explanation cache table: %w", err)
	}

	if _, err := s.db.ExecContext(ctx, `ALTER TABLE word_explanations_cache ADD COLUMN sentence_id BIGINT NOT NULL DEFAULT 0 AFTER cache_id`); err != nil && !isIgnorableSchemaError(err) {
		return fmt.Errorf("ensure sentence_id column on word explanation cache: %w", err)
	}
	if _, err := s.db.ExecContext(ctx, `ALTER TABLE word_explanations_cache DROP INDEX idx_normalized_word`); err != nil && !isIgnorableSchemaError(err) {
		return fmt.Errorf("drop legacy normalized_word index: %w", err)
	}
	if _, err := s.db.ExecContext(ctx, `ALTER TABLE word_explanations_cache ADD UNIQUE KEY idx_sentence_word (sentence_id, normalized_word)`); err != nil && !isIgnorableSchemaError(err) {
		return fmt.Errorf("ensure sentence_id + normalized_word unique index: %w", err)
	}

	return nil
}

func (s *ArticleService) NormalizeWord(word string) string {
	trimmed := strings.TrimSpace(strings.ToLower(word))
	return strings.Trim(trimmed, " \t\r\n.,!?;:\"'()[]{}<>")
}

func (s *ArticleService) GetCachedWordExplanation(ctx context.Context, sentenceID int64, word string) (*CachedWordExplanation, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if sentenceID <= 0 {
		return nil, nil
	}

	normalized := s.NormalizeWord(word)
	if normalized == "" {
		return nil, nil
	}

	if cached, err := s.getWordExplanationFromCacheTable(ctx, sentenceID, normalized); err != nil {
		return nil, err
	} else if cached != nil {
		return cached, nil
	}
	return nil, nil
}

func (s *ArticleService) SaveCachedWordExplanation(ctx context.Context, explanation CachedWordExplanation) error {
	if err := s.validateService(); err != nil {
		return err
	}
	if explanation.SentenceID <= 0 {
		return fmt.Errorf("sentence id is empty")
	}

	normalized := s.NormalizeWord(explanation.NormalizedWord)
	if normalized == "" {
		normalized = s.NormalizeWord(explanation.Word)
	}
	if normalized == "" {
		return fmt.Errorf("normalized word is empty")
	}

	word := strings.TrimSpace(explanation.Word)
	if word == "" {
		word = normalized
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO word_explanations_cache (sentence_id, normalized_word, word, part_of_speech, meaning, tip, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, NOW())
		ON DUPLICATE KEY UPDATE
			word = VALUES(word),
			part_of_speech = VALUES(part_of_speech),
			meaning = VALUES(meaning),
			tip = VALUES(tip),
			updated_at = NOW()
	`, explanation.SentenceID, normalized, word, strings.TrimSpace(explanation.PartOfSpeech), strings.TrimSpace(explanation.Meaning), strings.TrimSpace(explanation.Tip))
	if err != nil {
		return fmt.Errorf("save cached word explanation: %w", err)
	}
	return nil
}

func (s *ArticleService) getWordExplanationFromCacheTable(ctx context.Context, sentenceID int64, normalizedWord string) (*CachedWordExplanation, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT sentence_id, normalized_word, word, part_of_speech, meaning, tip
		FROM word_explanations_cache
		WHERE sentence_id = ? AND normalized_word = ?
		LIMIT 1
	`, sentenceID, normalizedWord)

	var result CachedWordExplanation
	if err := row.Scan(
		&result.SentenceID,
		&result.NormalizedWord,
		&result.Word,
		&result.PartOfSpeech,
		&result.Meaning,
		&result.Tip,
	); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("query word explanation cache: %w", err)
	}
	return &result, nil
}

func isIgnorableSchemaError(err error) bool {
	if err == nil {
		return false
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "duplicate column") ||
		strings.Contains(message, "duplicate key name") ||
		strings.Contains(message, "check that column/key exists") ||
		strings.Contains(message, "can't drop") ||
		strings.Contains(message, "already exists")
}

// UpdateArticleReadStats 更新文章阅读统计
func (s *ArticleService) UpdateArticleReadStats(ctx context.Context, articleID int64, userID int) error {
	if err := s.validateService(); err != nil {
		return err
	}
	if articleID <= 0 || userID <= 0 {
		return fmt.Errorf("invalid article id or user id")
	}

	_, err := s.db.ExecContext(ctx, `
		UPDATE articles 
		SET read_count = read_count + 1, last_read_at = NOW() 
		WHERE article_id = ? AND user_id = ?`, articleID, userID)
	if err != nil {
		return fmt.Errorf("update article read stats: %w", err)
	}

	_ = s.ensureStudyLogTable(ctx)
	_ = recordStudyActivity(ctx, s.db, userID, time.Now(), 0, 1)

	return nil
}

// ListUserArticles 获取用户的文章列表
func (s *ArticleService) ListUserArticles(ctx context.Context, userID int, limit, offset int) ([]ArticleSummary, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if userID <= 0 {
		return nil, fmt.Errorf("invalid user id")
	}
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT 
			article_id,
			title,
			sentence_count,
			read_count,
			created_at,
			last_read_at
		FROM articles
		WHERE user_id = ?
		ORDER BY COALESCE(last_read_at, created_at) DESC
		LIMIT ? OFFSET ?
	`, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("query articles: %w", err)
	}
	defer rows.Close()

	var summaries []ArticleSummary
	for rows.Next() {
		var summary ArticleSummary
		var lastRead sql.NullTime
		if err := rows.Scan(
			&summary.ArticleID,
			&summary.Title,
			&summary.SentenceCount,
			&summary.ReadCount,
			&summary.CreatedAt,
			&lastRead,
		); err != nil {
			return nil, fmt.Errorf("scan article: %w", err)
		}
		if lastRead.Valid {
			t := lastRead.Time
			summary.LastReadAt = &t
		}
		summaries = append(summaries, summary)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate articles: %w", err)
	}
	if err := s.populateArticleWordCounts(ctx, summaries); err != nil {
		return nil, err
	}

	return summaries, nil
}

var articleWordPattern = regexp.MustCompile(`[A-Za-z]+(?:'[A-Za-z]+)?`)

func (s *ArticleService) populateArticleWordCounts(ctx context.Context, summaries []ArticleSummary) error {
	if len(summaries) == 0 {
		return nil
	}

	ids := make([]any, 0, len(summaries))
	placeholders := make([]string, 0, len(summaries))
	indexByArticleID := make(map[int64]int, len(summaries))
	for index, summary := range summaries {
		ids = append(ids, summary.ArticleID)
		placeholders = append(placeholders, "?")
		indexByArticleID[summary.ArticleID] = index
	}

	query := fmt.Sprintf(
		`SELECT article_id, original_text FROM article_sentences WHERE article_id IN (%s)`,
		strings.Join(placeholders, ","),
	)
	rows, err := s.db.QueryContext(ctx, query, ids...)
	if err != nil {
		return fmt.Errorf("query article sentences for word count: %w", err)
	}
	defer rows.Close()

	counts := make(map[int64]int, len(summaries))
	for rows.Next() {
		var articleID int64
		var original string
		if err := rows.Scan(&articleID, &original); err != nil {
			return fmt.Errorf("scan article sentence word count: %w", err)
		}
		counts[articleID] += len(articleWordPattern.FindAllString(original, -1))
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("iterate article sentences for word count: %w", err)
	}

	for articleID, count := range counts {
		if index, ok := indexByArticleID[articleID]; ok {
			summaries[index].WordCount = count
		}
	}

	return nil
}

// DeleteArticle 删除用户自己的文章及其句子数据。
func (s *ArticleService) DeleteArticle(ctx context.Context, articleID int64, userID int) error {
	if err := s.validateService(); err != nil {
		return err
	}
	if articleID <= 0 || userID <= 0 {
		return fmt.Errorf("invalid article id or user id")
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	result, err := tx.ExecContext(ctx, `DELETE FROM articles WHERE article_id = ? AND user_id = ?`, articleID, userID)
	if err != nil {
		return fmt.Errorf("delete article: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("fetch rows affected: %w", err)
	}
	if rowsAffected == 0 {
		return fmt.Errorf("article not found")
	}

	if _, err = tx.ExecContext(ctx, `DELETE FROM article_sentences WHERE article_id = ?`, articleID); err != nil {
		return fmt.Errorf("delete article sentences: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit delete transaction: %w", err)
	}

	return nil
}

// UpdateArticleTitle 更新用户自己的文章标题。
func (s *ArticleService) UpdateArticleTitle(ctx context.Context, articleID int64, userID int, title string) (string, error) {
	if err := s.validateService(); err != nil {
		return "", err
	}
	title = strings.TrimSpace(title)
	if articleID <= 0 || userID <= 0 || title == "" {
		return "", fmt.Errorf("invalid article title update")
	}
	if len([]rune(title)) > 60 {
		return "", fmt.Errorf("article title too long")
	}

	result, err := s.db.ExecContext(ctx, `
		UPDATE articles
		SET title = ?, updated_at = NOW()
		WHERE article_id = ? AND user_id = ?
	`, title, articleID, userID)
	if err != nil {
		return "", fmt.Errorf("update article title: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return "", fmt.Errorf("fetch rows affected: %w", err)
	}
	if rowsAffected == 0 {
		return "", fmt.Errorf("article not found")
	}
	return title, nil
}

func (s *ArticleService) ListReviewTasks(ctx context.Context, userID int, status string) ([]ReviewTask, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if userID <= 0 {
		return nil, fmt.Errorf("invalid user id")
	}
	if status != "pending" && status != "completed" {
		return nil, fmt.Errorf("invalid status")
	}

	var query string
	switch status {
	case "completed":
		query = `
			SELECT
				t.task_id,
				t.article_id,
				a.title,
				a.sentence_count,
				t.scheduled_for,
				t.status,
				t.started_at,
				t.completed_at
			FROM article_review_tasks t
			JOIN articles a ON a.article_id = t.article_id
			WHERE t.user_id = ? AND t.task_type = 'review' AND t.status = 'completed'
			ORDER BY t.completed_at DESC, t.task_id DESC
		`
	default:
		query = `
			SELECT
				t.task_id,
				t.article_id,
				a.title,
				a.sentence_count,
				t.scheduled_for,
				t.status,
				t.started_at,
				t.completed_at
			FROM article_review_tasks t
			JOIN articles a ON a.article_id = t.article_id
			WHERE t.user_id = ? AND t.task_type = 'review' AND t.status = 'pending' AND t.scheduled_for <= CURDATE()
			ORDER BY t.scheduled_for ASC, t.task_id ASC
		`
	}

	rows, err := s.db.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("query review tasks: %w", err)
	}
	defer rows.Close()

	var tasks []ReviewTask
	for rows.Next() {
		var task ReviewTask
		var startedAt sql.NullTime
		var completedAt sql.NullTime
		if err := rows.Scan(
			&task.TaskID,
			&task.ArticleID,
			&task.ArticleTitle,
			&task.SentenceCount,
			&task.ScheduledFor,
			&task.Status,
			&startedAt,
			&completedAt,
		); err != nil {
			return nil, fmt.Errorf("scan review task: %w", err)
		}
		if startedAt.Valid {
			t := startedAt.Time
			task.StartedAt = &t
		}
		if completedAt.Valid {
			t := completedAt.Time
			task.CompletedAt = &t
		}
		tasks = append(tasks, task)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate review tasks: %w", err)
	}

	if err := s.populateReviewTaskWordCounts(ctx, tasks); err != nil {
		return nil, err
	}
	return tasks, nil
}

func (s *ArticleService) CompleteReviewTaskByArticleID(ctx context.Context, articleID int64, userID int) (*ReviewTask, bool, error) {
	if err := s.validateService(); err != nil {
		return nil, false, err
	}
	if articleID <= 0 || userID <= 0 {
		return nil, false, fmt.Errorf("invalid article id or user id")
	}

	result, err := s.db.ExecContext(ctx, `
		UPDATE article_review_tasks
		SET
			started_at = COALESCE(started_at, NOW()),
			completed_at = COALESCE(completed_at, NOW()),
			status = 'completed',
			updated_at = NOW()
		WHERE user_id = ? AND article_id = ? AND task_type = 'review' AND status = 'pending' AND scheduled_for <= CURDATE()
		ORDER BY scheduled_for ASC, task_id ASC
		LIMIT 1
	`, userID, articleID)
	if err != nil {
		return nil, false, fmt.Errorf("complete review task: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, false, fmt.Errorf("read review task completion result: %w", err)
	}
	if rowsAffected == 0 {
		return nil, false, nil
	}

	_ = s.ensureStudyLogTable(ctx)
	_ = recordStudyActivity(ctx, s.db, userID, time.Now(), 0, 1)

	tasks, err := s.ListReviewTasksByArticleID(ctx, userID, articleID)
	if err != nil {
		return nil, false, err
	}
	if len(tasks) == 0 {
		return nil, false, nil
	}
	return &tasks[0], true, nil
}

func (s *ArticleService) ListReviewTasksByArticleID(ctx context.Context, userID int, articleID int64) ([]ReviewTask, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT
			t.task_id,
			t.article_id,
			a.title,
			a.sentence_count,
			t.scheduled_for,
			t.status,
			t.started_at,
			t.completed_at
		FROM article_review_tasks t
		JOIN articles a ON a.article_id = t.article_id
		WHERE t.user_id = ? AND t.article_id = ? AND t.task_type = 'review'
		ORDER BY CASE WHEN t.status = 'completed' THEN 0 ELSE 1 END, t.completed_at DESC, t.scheduled_for DESC, t.task_id DESC
	`, userID, articleID)
	if err != nil {
		return nil, fmt.Errorf("query review tasks by article: %w", err)
	}
	defer rows.Close()

	var tasks []ReviewTask
	for rows.Next() {
		var task ReviewTask
		var startedAt sql.NullTime
		var completedAt sql.NullTime
		if err := rows.Scan(
			&task.TaskID,
			&task.ArticleID,
			&task.ArticleTitle,
			&task.SentenceCount,
			&task.ScheduledFor,
			&task.Status,
			&startedAt,
			&completedAt,
		); err != nil {
			return nil, fmt.Errorf("scan review task by article: %w", err)
		}
		if startedAt.Valid {
			t := startedAt.Time
			task.StartedAt = &t
		}
		if completedAt.Valid {
			t := completedAt.Time
			task.CompletedAt = &t
		}
		tasks = append(tasks, task)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate review tasks by article: %w", err)
	}
	if err := s.populateReviewTaskWordCounts(ctx, tasks); err != nil {
		return nil, err
	}
	return tasks, nil
}

func (s *ArticleService) createNextDayReviewTaskTx(ctx context.Context, tx *sql.Tx, userID int, articleID int64, createdAt time.Time) error {
	scheduledFor := createdAt.In(time.Local).AddDate(0, 0, 1).Format("2006-01-02")
	_, err := tx.ExecContext(ctx, `
		INSERT INTO article_review_tasks (user_id, article_id, task_type, scheduled_for, status, updated_at)
		VALUES (?, ?, 'review', ?, 'pending', NOW())
		ON DUPLICATE KEY UPDATE updated_at = NOW()
	`, userID, articleID, scheduledFor)
	if err != nil {
		return fmt.Errorf("create next-day review task: %w", err)
	}
	return nil
}

func (s *ArticleService) populateReviewTaskWordCounts(ctx context.Context, tasks []ReviewTask) error {
	if len(tasks) == 0 {
		return nil
	}

	ids := make([]any, 0, len(tasks))
	placeholders := make([]string, 0, len(tasks))
	indexByArticleID := make(map[int64][]int, len(tasks))
	for index, task := range tasks {
		ids = append(ids, task.ArticleID)
		placeholders = append(placeholders, "?")
		indexByArticleID[task.ArticleID] = append(indexByArticleID[task.ArticleID], index)
	}

	query := fmt.Sprintf(
		`SELECT article_id, original_text FROM article_sentences WHERE article_id IN (%s)`,
		strings.Join(placeholders, ","),
	)
	rows, err := s.db.QueryContext(ctx, query, ids...)
	if err != nil {
		return fmt.Errorf("query review task sentences for word count: %w", err)
	}
	defer rows.Close()

	counts := make(map[int64]int, len(tasks))
	for rows.Next() {
		var articleID int64
		var original string
		if err := rows.Scan(&articleID, &original); err != nil {
			return fmt.Errorf("scan review task sentence word count: %w", err)
		}
		counts[articleID] += len(articleWordPattern.FindAllString(original, -1))
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("iterate review task sentences for word count: %w", err)
	}

	for articleID, count := range counts {
		for _, index := range indexByArticleID[articleID] {
			tasks[index].WordCount = count
		}
	}
	return nil
}
