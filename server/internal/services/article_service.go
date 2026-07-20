package services

import (
	"context"
	"database/sql"
	"fmt"
	"regexp"
	"strings"
	"time"
)

const ArticleTextAnalysisPrompt = `把正文按顺序整理成适合学习的短句，并逐句翻译成中文。
只处理用户提供的内容，不补写，不输出说明。
输出 TSV，每行格式：英文<TAB>中文。`

const WordExplainPromptTemplate = `解释用户在当前句子里点击的单词。
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

	// 生成标题
	title := strings.TrimSpace(sentences[0].Original)
	if title == "" {
		title = fmt.Sprintf("Untitled Article %s", time.Now().Format("20060102150405"))
	}
	if len([]rune(title)) > 200 {
		title = string([]rune(title)[:200])
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
