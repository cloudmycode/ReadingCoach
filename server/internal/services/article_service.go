package services

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

const ArticleTextAnalysisPrompt = `你是一名英语教师。用户已经在客户端校对过英文正文，请你不要再做OCR识别，只对文本本身进行整理、断句和翻译。

		要求：
		1. 仅处理用户给出的英文正文，不要补造不存在的内容。
		2. 去掉明显无意义的空行、重复行和孤立页码；保留正文句子顺序。
		3. 按句意拆分成尽可能短、便于学习的意群。
		4. 输出格式必须为TSV：英文内容<TAB>中文翻译。
		5. 每行一个句子对，不要输出标题说明、编号、Markdown 或 JSON。`

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
	ArticleID        int64      `json:"article_id"`
	Title            string     `json:"title"`
	SentenceCount    int        `json:"sentence_count"`
	ReadCount        int        `json:"read_count"`
	SentenceDuration int        `json:"sentence_duration"`
	CreatedAt        time.Time  `json:"created_at"`
	LastReadAt       *time.Time `json:"last_read_at,omitempty"`
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

// SentenceForAudio 用于生成音频的句子信息
type SentenceForAudio struct {
	SentenceID  int64
	Original    string
	Translation string
}

// GetArticleSentencesForAudio 根据文章ID获取所有句子信息（用于生成音频）
func (s *ArticleService) GetArticleSentencesForAudio(ctx context.Context, articleID int64) ([]SentenceForAudio, error) {
	if err := s.validateService(); err != nil {
		return nil, err
	}
	if articleID <= 0 {
		return nil, fmt.Errorf("invalid article id")
	}

	rows, err := s.db.QueryContext(ctx,
		`SELECT sentence_id, original_text, translation 
		 FROM article_sentences 
		 WHERE article_id = ? 
		 ORDER BY sentence_order ASC`,
		articleID)
	if err != nil {
		return nil, fmt.Errorf("query sentences: %w", err)
	}
	defer rows.Close()

	var sentences []SentenceForAudio
	for rows.Next() {
		var sID int64
		var original, translation string
		if err := rows.Scan(&sID, &original, &translation); err != nil {
			return nil, fmt.Errorf("scan sentence: %w", err)
		}
		sentences = append(sentences, SentenceForAudio{
			SentenceID:  sID,
			Original:    original,
			Translation: translation,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate sentences: %w", err)
	}

	return sentences, nil
}

// UpdateArticleAudioStats 更新文章的句子数量与总句子时长
func (s *ArticleService) UpdateArticleAudioStats(ctx context.Context, articleID int64, sentenceCount int, sentenceDurationMS int) error {
	if err := s.validateService(); err != nil {
		return err
	}
	if articleID <= 0 {
		return fmt.Errorf("invalid article id")
	}

	_, err := s.db.ExecContext(ctx,
		`UPDATE articles SET sentence_count = ?, sentence_duration = ? WHERE article_id = ?`,
		sentenceCount, sentenceDurationMS, articleID,
	)
	if err != nil {
		return fmt.Errorf("update article audio stats: %w", err)
	}

	return nil
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
			IFNULL(sentence_duration, 0) AS sentence_duration,
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
		var duration sql.NullInt64
		var lastRead sql.NullTime
		if err := rows.Scan(
			&summary.ArticleID,
			&summary.Title,
			&summary.SentenceCount,
			&summary.ReadCount,
			&duration,
			&summary.CreatedAt,
			&lastRead,
		); err != nil {
			return nil, fmt.Errorf("scan article: %w", err)
		}
		if duration.Valid {
			summary.SentenceDuration = int(duration.Int64)
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

	return summaries, nil
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
