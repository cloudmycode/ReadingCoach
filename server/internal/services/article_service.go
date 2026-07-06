package services

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"time"
)

// ArticleAnalysisPrompt 文章图片分析的提示词
const ArticleAnalysisPrompt = `你是一名英语教师，提取图片中的英文，按句意分解成易于理解的意群，并为每个意群提供中文翻译。

		要求：
		1. 按意群断句：根据语义拆分成尽可能短的句子易于学习。
		2. 按照图片顺序解析内容。
		3. 输出格式：使用TSV格式（制表符分隔），每行一个句子对。
		   - 每行格式：英文内容<TAB>中文翻译
		   - 使用制表符（TAB键）分隔英文和中文，不要使用空格或其他字符
		   - 每行一个句子对，换行表示下一个句子
		   - 示例：
		     Hello world	你好世界
		     How are you	你好吗
		     I am fine	我很好
		4. 无内容处理：若图片中无有效英文文章，返回空行或空字符串。
		
		重要：
		- 必须使用制表符（TAB）分隔，不要使用空格、逗号或其他字符
		- 每行只包含一个句子对，英文和中文之间只有一个制表符
		- 如果英文或中文中包含换行符，请保留在文本中
		- 格式简单可靠，不需要引号、转义字符等复杂处理`

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

// marshalAttachmentPaths 将附件路径数组序列化为JSON字符串
func marshalAttachmentPaths(paths []string) (interface{}, error) {
	if len(paths) == 0 {
		return nil, nil
	}
	data, err := json.Marshal(paths)
	if err != nil {
		return nil, fmt.Errorf("marshal attachment paths: %w", err)
	}
	return string(data), nil
}

// SaveAnalyzedArticle 将 AI 识别结果写入 articles 和 article_sentences
// 返回 articleID
func (s *ArticleService) SaveAnalyzedArticle(
	ctx context.Context,
	userID int,
	_ string,
	attachmentPaths []string,
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

	// 序列化附件路径
	attachmentValue, err := marshalAttachmentPaths(attachmentPaths)
	if err != nil {
		return 0, err
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
		`INSERT INTO articles (user_id, title, sentence_count, attachment_paths) VALUES (?,?,?,?)`,
		userID,
		title,
		len(sentences),
		attachmentValue,
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
	ArticleID       int64             `json:"article_id"`
	Title           string            `json:"title"`
	SentenceCount   int               `json:"sentence_count"`
	AttachmentPaths []string          `json:"attachment_paths"`
	Sentences       []ArticleSentence `json:"sentences"`
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
	var attachmentPathsJSON sql.NullString
	row := s.db.QueryRowContext(ctx,
		`SELECT title, sentence_count, attachment_paths FROM articles WHERE article_id = ? AND user_id = ?`,
		articleID, userID)
	if err := row.Scan(&title, &sentenceCount, &attachmentPathsJSON); err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("article not found")
		}
		return nil, fmt.Errorf("query article: %w", err)
	}

	// 解析附件路径
	var attachmentPaths []string
	if attachmentPathsJSON.Valid && attachmentPathsJSON.String != "" {
		if err := json.Unmarshal([]byte(attachmentPathsJSON.String), &attachmentPaths); err != nil {
			// 附件路径解析失败不影响主流程
			attachmentPaths = []string{}
		}
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
		ArticleID:       articleID,
		Title:           title,
		SentenceCount:   sentenceCount,
		AttachmentPaths: attachmentPaths,
		Sentences:       sentences,
	}, nil
}

// UpdateSentenceAudioMeta 更新句子音频的存储信息
// audioType: "original" 或 "translation"
// durationMS: 音频时长（毫秒），若 <=0 则不更新 duration 字段
func (s *ArticleService) UpdateSentenceAudioMeta(ctx context.Context, articleID int64, sentenceOrder int, audioPath string, audioType string, durationMS int) error {
	if err := s.validateService(); err != nil {
		return err
	}
	if articleID <= 0 || sentenceOrder <= 0 {
		return fmt.Errorf("invalid article id or sentence order")
	}

	var (
		sql  string
		args []interface{}
	)
	switch audioType {
	case "original":
		if durationMS > 0 {
			sql = `UPDATE article_sentences SET original_audio_path = ?, original_audio_duration = ? WHERE article_id = ? AND sentence_order = ?`
			args = []interface{}{audioPath, durationMS, articleID, sentenceOrder}
		} else {
			sql = `UPDATE article_sentences SET original_audio_path = ? WHERE article_id = ? AND sentence_order = ?`
			args = []interface{}{audioPath, articleID, sentenceOrder}
		}
	case "translation":
		if durationMS > 0 {
			sql = `UPDATE article_sentences SET translation_audio_path = ?, translation_audio_duration = ? WHERE article_id = ? AND sentence_order = ?`
			args = []interface{}{audioPath, durationMS, articleID, sentenceOrder}
		} else {
			sql = `UPDATE article_sentences SET translation_audio_path = ? WHERE article_id = ? AND sentence_order = ?`
			args = []interface{}{audioPath, articleID, sentenceOrder}
		}
	default:
		return fmt.Errorf("invalid audio type: %s (must be 'original' or 'translation')", audioType)
	}

	_, err := s.db.ExecContext(ctx, sql, args...)
	if err != nil {
		return fmt.Errorf("update sentence audio path: %w", err)
	}

	return nil
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

// articleDataSaver 文章数据保存器实现
type articleDataSaver struct {
	service *ArticleService
}

// NewArticleDataSaver 创建文章数据保存器
func NewArticleDataSaver(service *ArticleService) ImageDataSaver {
	return &articleDataSaver{service: service}
}

// SaveData 保存文章处理结果到数据库
func (s *articleDataSaver) SaveData(ctx context.Context, userID int, attachments []ImageAttachmentInfo, data [][]string) (int64, error) {
	// 解析结构化数据（基础层已经解析了TSV格式）
	sentenceInputs, err := parseArticleSentencesFromData(data)
	if err != nil {
		return 0, err
	}

	if len(sentenceInputs) == 0 {
		return 0, fmt.Errorf("no valid sentences to save")
	}

	// 准备附件路径数组
	attachmentPaths := make([]string, 0, len(attachments))
	for _, att := range attachments {
		attachmentPaths = append(attachmentPaths, att.URL)
	}

	// 生成标题（使用第一张图片的文件名）
	title := ""
	if len(attachments) > 0 && attachments[0].OriginalName != "" {
		title = strings.TrimSuffix(attachments[0].OriginalName, filepath.Ext(attachments[0].OriginalName))
	}

	// 保存到数据库
	return s.service.SaveAnalyzedArticle(ctx, userID, title, attachmentPaths, sentenceInputs)
}
