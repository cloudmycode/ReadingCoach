package services

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"
)

const ArticleTextAnalysisPrompt = `阅读正文，先生成一个准确概括主题的简短标题，再把正文按顺序整理成适合学习的短句并逐句翻译成中文。
标题尽量使用正文的主要语言，控制在 2 至 6 个词，不使用句号，不要直接照抄正文第一句。
只处理用户提供的内容，不补写，不输出说明。
只返回一个 JSON 对象，不要 Markdown 代码块，不要额外说明。格式严格如下：
{"title":"标题","sentences":[{"original":"英文原句","translation":"中文翻译"}]}`

const WordExplainPromptTemplate = `解释用户在当前句子里点击的单词，如果在句子中该单词涉及到短语、固定搭配等，则一并解释。
只返回 JSON：
{"word":"单词","part_of_speech":"词性","meaning":"当前句中的中文意思","tip":"结合当前句子的简短提示"}`

const SentenceCoachPromptTemplate = `回答用户关于当前句子的问题。
只返回 JSON：
{"answer":"简洁中文回答","highlights":["要点1","要点2"]}`

// ArticleSentenceInput 表示待写入 article_sentences 的句子
type ArticleSentenceInput struct {
	Original    string `json:"original"`
	Translation string `json:"translation"`
}

// ArticleAnalysisResult 表示 AI 拆句/翻译后的结构化结果。
type ArticleAnalysisResult struct {
	Title     string                 `json:"title"`
	Sentences []ArticleSentenceInput `json:"sentences"`
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

// ParseArticleAnalysisJSON 解析 AI 返回的文章分析 JSON。
func ParseArticleAnalysisJSON(raw string) (ArticleAnalysisResult, error) {
	trimmed := extractJSONObject(raw)
	if trimmed == "" {
		return ArticleAnalysisResult{}, fmt.Errorf("empty article analysis response")
	}

	var result ArticleAnalysisResult
	if err := json.Unmarshal([]byte(trimmed), &result); err != nil {
		return ArticleAnalysisResult{}, fmt.Errorf("decode article analysis json: %w", err)
	}

	result.Title = strings.TrimSpace(result.Title)
	cleaned := make([]ArticleSentenceInput, 0, len(result.Sentences))
	for _, sentence := range result.Sentences {
		original := strings.TrimSpace(sentence.Original)
		translation := strings.TrimSpace(sentence.Translation)
		if original == "" {
			continue
		}
		cleaned = append(cleaned, ArticleSentenceInput{
			Original:    original,
			Translation: translation,
		})
	}
	result.Sentences = cleaned

	if len(result.Sentences) == 0 {
		return ArticleAnalysisResult{}, fmt.Errorf("no valid sentences found")
	}
	return result, nil
}

func extractJSONObject(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}

	// 兼容模型偶发包裹的 ```json ... ```
	if strings.HasPrefix(trimmed, "```") {
		trimmed = strings.TrimPrefix(trimmed, "```json")
		trimmed = strings.TrimPrefix(trimmed, "```JSON")
		trimmed = strings.TrimPrefix(trimmed, "```")
		trimmed = strings.TrimSpace(trimmed)
		if idx := strings.LastIndex(trimmed, "```"); idx >= 0 {
			trimmed = strings.TrimSpace(trimmed[:idx])
		}
	}

	start := strings.Index(trimmed, "{")
	end := strings.LastIndex(trimmed, "}")
	if start >= 0 && end > start {
		return trimmed[start : end+1]
	}
	return trimmed
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

// UserWordBookEntry 用户生词本条目（按用户归属，独立于 AI 释义缓存）。
type UserWordBookEntry struct {
	EntryID             int64
	UserID              int
	ArticleID           int64
	SentenceID          int64
	NormalizedWord      string
	Word                string
	SentenceOriginal    string
	SentenceTranslation string
	PartOfSpeech        string
	Meaning             string
	Tip                 string
	ReviewStep          int
	NextReviewAt        *time.Time
	MasteryStatus       string
	LastReviewedAt      *time.Time
	LookedUpAt          time.Time
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

func (s *ArticleService) EnsureUserWordBookTable(ctx context.Context) error {
	if err := s.validateService(); err != nil {
		return err
	}
	_, err := s.db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS user_word_book (
			entry_id BIGINT NOT NULL AUTO_INCREMENT,
			user_id INT NOT NULL,
			article_id BIGINT NOT NULL,
			sentence_id BIGINT NOT NULL,
			normalized_word VARCHAR(128) NOT NULL,
			word VARCHAR(128) NOT NULL DEFAULT '',
			sentence_original TEXT NOT NULL,
			sentence_translation TEXT NOT NULL,
			part_of_speech VARCHAR(32) NOT NULL DEFAULT '',
			meaning TEXT NOT NULL,
			tip TEXT NOT NULL,
			review_step TINYINT NOT NULL DEFAULT 0,
			next_review_at DATE DEFAULT NULL,
			mastery_status VARCHAR(16) NOT NULL DEFAULT 'learning',
			last_reviewed_at DATETIME DEFAULT NULL,
			looked_up_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NULL DEFAULT NULL,
			PRIMARY KEY (entry_id),
			UNIQUE KEY idx_user_sentence_word (user_id, article_id, sentence_id, normalized_word),
			KEY idx_user_looked_up (user_id, looked_up_at),
			KEY idx_user_review_due (user_id, mastery_status, next_review_at)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
	`)
	if err != nil {
		return fmt.Errorf("ensure user word book table: %w", err)
	}

	alters := []string{
		`ALTER TABLE user_word_book ADD COLUMN review_step TINYINT NOT NULL DEFAULT 0 AFTER tip`,
		`ALTER TABLE user_word_book ADD COLUMN next_review_at DATE DEFAULT NULL AFTER review_step`,
		`ALTER TABLE user_word_book ADD COLUMN mastery_status VARCHAR(16) NOT NULL DEFAULT 'learning' AFTER next_review_at`,
		`ALTER TABLE user_word_book ADD COLUMN last_reviewed_at DATETIME DEFAULT NULL AFTER mastery_status`,
		`ALTER TABLE user_word_book ADD KEY idx_user_review_due (user_id, mastery_status, next_review_at)`,
	}
	for _, stmt := range alters {
		if _, err := s.db.ExecContext(ctx, stmt); err != nil && !isIgnorableSchemaError(err) {
			return fmt.Errorf("ensure user word book review columns: %w", err)
		}
	}

	// 兼容旧数据：尚未安排复习的生词立刻进入今日待复习池。
	if _, err := s.db.ExecContext(ctx, `
		UPDATE user_word_book
		SET next_review_at = CURDATE(),
		    mastery_status = 'learning',
		    review_step = COALESCE(review_step, 0)
		WHERE next_review_at IS NULL
		  AND mastery_status = 'learning'
	`); err != nil {
		return fmt.Errorf("backfill word review schedule: %w", err)
	}

	// 清理已废弃的文章复习任务表（若仍存在）。
	if _, err := s.db.ExecContext(ctx, `DROP TABLE IF EXISTS article_review_tasks`); err != nil {
		return fmt.Errorf("drop legacy article review tasks: %w", err)
	}

	if err := s.ensureWordReviewLogTable(ctx); err != nil {
		return err
	}
	if err := s.backfillWordReviewLogs(ctx); err != nil {
		return err
	}
	return nil
}

func (s *ArticleService) UpsertUserWordBookEntry(ctx context.Context, entry UserWordBookEntry) error {
	if err := s.validateService(); err != nil {
		return err
	}
	if entry.UserID <= 0 || entry.ArticleID <= 0 || entry.SentenceID <= 0 {
		return fmt.Errorf("invalid user/article/sentence id")
	}
	normalized := s.NormalizeWord(entry.Word)
	if normalized == "" {
		normalized = s.NormalizeWord(entry.NormalizedWord)
	}
	if normalized == "" {
		return fmt.Errorf("word is empty")
	}
	word := strings.TrimSpace(entry.Word)
	if word == "" {
		word = normalized
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO user_word_book (
			user_id, article_id, sentence_id, normalized_word, word,
			sentence_original, sentence_translation,
			part_of_speech, meaning, tip,
			review_step, next_review_at, mastery_status,
			looked_up_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, DATE_ADD(CURDATE(), INTERVAL 1 DAY), 'learning', NOW(), NOW())
		ON DUPLICATE KEY UPDATE
			word = VALUES(word),
			sentence_original = VALUES(sentence_original),
			sentence_translation = VALUES(sentence_translation),
			part_of_speech = VALUES(part_of_speech),
			meaning = VALUES(meaning),
			tip = VALUES(tip),
			looked_up_at = NOW(),
			updated_at = NOW()
	`,
		entry.UserID,
		entry.ArticleID,
		entry.SentenceID,
		normalized,
		word,
		strings.TrimSpace(entry.SentenceOriginal),
		strings.TrimSpace(entry.SentenceTranslation),
		strings.TrimSpace(entry.PartOfSpeech),
		strings.TrimSpace(entry.Meaning),
		strings.TrimSpace(entry.Tip),
	)
	if err != nil {
		return fmt.Errorf("upsert user word book: %w", err)
	}
	return nil
}

func (s *ArticleService) DeleteUserWordBookEntry(ctx context.Context, userID int, entryID int64) error {
	if err := s.validateService(); err != nil {
		return err
	}
	if userID <= 0 || entryID <= 0 {
		return fmt.Errorf("invalid user id or entry id")
	}

	result, err := s.db.ExecContext(ctx, `
		DELETE FROM user_word_book
		WHERE user_id = ? AND entry_id = ?
	`, userID, entryID)
	if err != nil {
		return fmt.Errorf("delete user word book entry: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("delete user word book rows affected: %w", err)
	}
	if affected == 0 {
		return fmt.Errorf("word book entry not found")
	}
	return nil
}

func (s *ArticleService) ListUserWordBook(ctx context.Context, userID int) ([]UserWordBookEntry, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if userID <= 0 {
		return nil, fmt.Errorf("invalid user id")
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT entry_id, user_id, article_id, sentence_id, normalized_word, word,
		       sentence_original, sentence_translation, part_of_speech, meaning, tip,
		       review_step, next_review_at, mastery_status, last_reviewed_at, looked_up_at
		FROM user_word_book
		WHERE user_id = ?
		ORDER BY looked_up_at DESC, entry_id DESC
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("list user word book: %w", err)
	}
	defer rows.Close()

	entries := make([]UserWordBookEntry, 0)
	for rows.Next() {
		var item UserWordBookEntry
		var nextReview sql.NullTime
		var lastReviewed sql.NullTime
		if err := rows.Scan(
			&item.EntryID,
			&item.UserID,
			&item.ArticleID,
			&item.SentenceID,
			&item.NormalizedWord,
			&item.Word,
			&item.SentenceOriginal,
			&item.SentenceTranslation,
			&item.PartOfSpeech,
			&item.Meaning,
			&item.Tip,
			&item.ReviewStep,
			&nextReview,
			&item.MasteryStatus,
			&lastReviewed,
			&item.LookedUpAt,
		); err != nil {
			return nil, fmt.Errorf("scan user word book: %w", err)
		}
		if nextReview.Valid {
			t := nextReview.Time
			item.NextReviewAt = &t
		}
		if lastReviewed.Valid {
			t := lastReviewed.Time
			item.LastReviewedAt = &t
		}
		if item.MasteryStatus == "" {
			item.MasteryStatus = "learning"
		}
		entries = append(entries, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate user word book: %w", err)
	}
	return entries, nil
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

