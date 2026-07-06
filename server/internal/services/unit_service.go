package services

import (
	"context"
	"database/sql"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"words/server/internal/logger"
)

// UnitAnalysisPrompt 单词单元图片分析的提示词
const UnitAnalysisPrompt = `你是一名英语教师，提取图片中的英文单词或短语，并为每个单词提供中文翻译和例句。

		要求：
		1. 提取图片中的所有英文单词或短语。
		2. 按照图片顺序解析内容。
		3. 输出格式：使用TSV格式（制表符分隔），每行一个单词条目。
		   - 每行格式：单词<TAB>翻译<TAB>例句
		   - 使用制表符（TAB键）分隔三个字段，不要使用空格或其他字符
		   - 每行一个单词条目，换行表示下一个单词
		   - 示例：
		     hello	你好	Hello world
		     world	世界	The world is beautiful
		     beautiful	美丽的	She is beautiful
		4. 无内容处理：若图片中无有效英文单词，返回空行或空字符串。
		
		重要：
		- 必须使用制表符（TAB）分隔三个字段，不要使用空格、逗号或其他字符
		- 每行只包含一个单词条目，三个字段之间各有一个制表符
		- 如果字段中包含换行符，请保留在文本中
		- 格式简单可靠，不需要引号、转义字符等复杂处理`

// UnitWordInput 表示待写入 unit_words 的单词
type UnitWordInput struct {
	Word        string
	Translation string
	Example     string
}

// UnitService 负责将unit识别结果落库
type UnitService struct {
	db *sql.DB
}

// NewUnitService 创建 UnitService
func NewUnitService(db *sql.DB) *UnitService {
	return &UnitService{db: db}
}

// SaveAnalyzedUnit 将 AI 识别结果写入 unit_list 和 unit_words
// 返回 unit_list_id
func (s *UnitService) SaveAnalyzedUnit(
	ctx context.Context,
	userID int,
	title string,
	words []UnitWordInput,
) (int64, error) {
	if s == nil || s.db == nil {
		return 0, fmt.Errorf("unit service not initialized")
	}
	if userID <= 0 {
		return 0, fmt.Errorf("invalid user id")
	}
	if len(words) == 0 {
		return 0, fmt.Errorf("no words to save")
	}

	// 如果没有提供标题，使用默认标题
	if title == "" {
		title = fmt.Sprintf("单词单元 %s", time.Now().Format("2006-01-02 15:04"))
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback()

	// 插入 unit_list
	result, err := tx.ExecContext(ctx, `
		INSERT INTO unit_list (owner_id, title, word_count, created_at, updated_at)
		VALUES (?, ?, ?, NOW(), NOW())
	`, userID, title, len(words))
	if err != nil {
		return 0, fmt.Errorf("insert unit_list: %w", err)
	}

	unitListID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("get unit_list_id: %w", err)
	}

	// 插入 unit_words
	stmt, err := tx.PrepareContext(ctx, `
		INSERT INTO unit_words (unit_list_id, word, translation, example, added_at, added_by)
		VALUES (?, ?, ?, ?, NOW(), ?)
	`)
	if err != nil {
		return 0, fmt.Errorf("prepare unit_words stmt: %w", err)
	}
	defer stmt.Close()

	written := 0
	for _, word := range words {
		wordText := strings.TrimSpace(word.Word)
		if wordText == "" {
			continue
		}

		// 注意：unit_words 表中的 word 字段是 int 类型，但实际应该存储单词文本
		// 这里需要根据实际数据库设计调整
		// 如果 word 字段确实是 int（word_id），需要先查找或创建 word 记录
		// 暂时假设可以直接存储文本（可能需要修改数据库结构）

		// 由于 word 字段是 int 类型，我们需要先查找 words 表中的 word_id
		// 如果不存在，可能需要创建新记录或使用其他方式
		// 这里先尝试查找 word_id
		var wordID int
		err := tx.QueryRowContext(ctx, `
			SELECT word_id FROM words WHERE headword = ? LIMIT 1
		`, wordText).Scan(&wordID)

		if err == sql.ErrNoRows {
			// 如果单词不存在，可能需要创建或使用默认值
			// 暂时跳过，或者可以根据需要创建新单词记录
			logger.Warn("⚠️ 单词 '%s' 在 words 表中不存在，跳过", wordText)
			continue
		} else if err != nil {
			return 0, fmt.Errorf("query word_id for '%s': %w", wordText, err)
		}

		translation := strings.TrimSpace(word.Translation)
		example := strings.TrimSpace(word.Example)

		if _, err = stmt.ExecContext(ctx, unitListID, wordID, translation, example, userID); err != nil {
			return 0, fmt.Errorf("insert unit_word '%s': %w", wordText, err)
		}
		written++
	}

	if written == 0 {
		return 0, fmt.Errorf("no valid words inserted")
	}

	// 更新 word_count
	_, err = tx.ExecContext(ctx, `
		UPDATE unit_list SET word_count = ? WHERE unit_list_id = ?
	`, written, unitListID)
	if err != nil {
		return 0, fmt.Errorf("update word_count: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return 0, fmt.Errorf("commit transaction: %w", err)
	}

	logger.Info("✅ Unit已保存到数据库，unit_list_id=%d, word_count=%d", unitListID, written)
	return unitListID, nil
}

// UnitSummary Unit列表项（业务层结构）
type UnitSummary struct {
	UnitListID int64
	Title      string
	WordCount  int
	CreatedAt  time.Time
	UpdatedAt  *time.Time
}

// UnitWord Unit单词项（业务层结构）
type UnitWord struct {
	UnitWordsID int64
	Word        string
	Translation string
	Example     string
	AddedAt     time.Time
}

// GetUserUnits 获取用户的unit列表
func (s *UnitService) GetUserUnits(ctx context.Context, userID int) ([]UnitSummary, error) {
	if s == nil || s.db == nil {
		return nil, fmt.Errorf("unit service not initialized")
	}
	if userID <= 0 {
		return nil, fmt.Errorf("invalid user id")
	}

	query := `
		SELECT unit_list_id, title, word_count, created_at, updated_at
		FROM unit_list
		WHERE owner_id = ?
		ORDER BY created_at DESC
	`

	rows, err := s.db.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("query user units: %w", err)
	}
	defer rows.Close()

	units := make([]UnitSummary, 0)
	for rows.Next() {
		var unitID int64
		var title string
		var wordCount int
		var createdAt time.Time
		var updatedAt sql.NullTime

		if err := rows.Scan(&unitID, &title, &wordCount, &createdAt, &updatedAt); err != nil {
			logger.Error("❌ 扫描unit数据失败: %v", err)
			continue
		}

		var updatedAtPtr *time.Time
		if updatedAt.Valid {
			updatedAtPtr = &updatedAt.Time
		}

		units = append(units, UnitSummary{
			UnitListID: unitID,
			Title:      title,
			WordCount:  wordCount,
			CreatedAt:  createdAt,
			UpdatedAt:  updatedAtPtr,
		})
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate units: %w", err)
	}

	return units, nil
}

// GetUnitWords 获取unit的单词列表（包含例句）
// 会验证unit是否属于指定用户
func (s *UnitService) GetUnitWords(ctx context.Context, unitID int64, userID int) ([]UnitWord, error) {
	if s == nil || s.db == nil {
		return nil, fmt.Errorf("unit service not initialized")
	}
	if unitID <= 0 {
		return nil, fmt.Errorf("invalid unit id")
	}
	if userID <= 0 {
		return nil, fmt.Errorf("invalid user id")
	}

	// 验证unit是否属于当前用户
	var ownerID int
	err := s.db.QueryRowContext(ctx, "SELECT owner_id FROM unit_list WHERE unit_list_id = ?", unitID).Scan(&ownerID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("unit not found")
		}
		return nil, fmt.Errorf("query unit owner: %w", err)
	}

	if ownerID != userID {
		return nil, fmt.Errorf("forbidden: unit does not belong to user")
	}

	// 查询unit_words，同时关联words表获取单词文本
	query := `
		SELECT 
			uw.unit_words_id,
			COALESCE(w.headword, CAST(uw.word AS CHAR)) as word,
			COALESCE(uw.translation, '') as translation,
			COALESCE(uw.example, '') as example,
			uw.added_at
		FROM unit_words uw
		LEFT JOIN words w ON uw.word = w.word_id
		WHERE uw.unit_list_id = ?
		ORDER BY uw.added_at ASC
	`

	rows, err := s.db.QueryContext(ctx, query, unitID)
	if err != nil {
		return nil, fmt.Errorf("query unit words: %w", err)
	}
	defer rows.Close()

	words := make([]UnitWord, 0)
	for rows.Next() {
		var wordID int64
		var word, translation, example string
		var addedAt time.Time

		if err := rows.Scan(&wordID, &word, &translation, &example, &addedAt); err != nil {
			logger.Error("❌ 扫描unit_word数据失败: %v", err)
			continue
		}

		words = append(words, UnitWord{
			UnitWordsID: wordID,
			Word:        word,
			Translation: translation,
			Example:     example,
			AddedAt:     addedAt,
		})
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate unit words: %w", err)
	}

	return words, nil
}

// unitDataSaver unit数据保存器实现
type unitDataSaver struct {
	service *UnitService
}

// NewUnitDataSaver 创建unit数据保存器
func NewUnitDataSaver(service *UnitService) ImageDataSaver {
	return &unitDataSaver{service: service}
}

// SaveData 保存unit处理结果到数据库
func (s *unitDataSaver) SaveData(ctx context.Context, userID int, attachments []ImageAttachmentInfo, data [][]string) (int64, error) {
	// 使用结构化数据（基础层已经解析了TSV格式）
	if len(data) == 0 {
		return 0, fmt.Errorf("no valid lines found")
	}

	wordInputs := make([]UnitWordInput, 0, len(data))
	for _, line := range data {
		if len(line) >= 3 {
			wordInputs = append(wordInputs, UnitWordInput{
				Word:        strings.TrimSpace(line[0]),
				Translation: strings.TrimSpace(line[1]),
				Example:     strings.TrimSpace(line[2]),
			})
		} else if len(line) >= 2 {
			// 只有两列，缺少例句
			wordInputs = append(wordInputs, UnitWordInput{
				Word:        strings.TrimSpace(line[0]),
				Translation: strings.TrimSpace(line[1]),
				Example:     "",
			})
		}
	}

	if len(wordInputs) == 0 {
		return 0, fmt.Errorf("no valid words found")
	}

	// 生成标题并保存
	title := ""
	if len(attachments) > 0 && attachments[0].OriginalName != "" {
		title = strings.TrimSuffix(attachments[0].OriginalName, filepath.Ext(attachments[0].OriginalName))
	}

	return s.service.SaveAnalyzedUnit(ctx, userID, title, wordInputs)
}
