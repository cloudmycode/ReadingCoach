package utils

import (
	"fmt"
	"strings"
)

// ParseTSV 解析TSV格式（制表符分隔）的文本
// 支持2列格式（用于文章：英文\t中文）和3列格式（用于单词：单词\t翻译\t例句）
// 返回清理后的文本，去除空行和前后空白
func ParseTSV(raw string) (string, error) {
	clean := strings.TrimSpace(raw)
	if clean == "" {
		return "", fmt.Errorf("empty input")
	}

	// 清理可能的markdown代码块标记
	if strings.HasPrefix(clean, "```") {
		clean = strings.TrimPrefix(clean, "```tsv")
		clean = strings.TrimPrefix(clean, "```")
		clean = strings.TrimSpace(clean)
		if idx := strings.LastIndex(clean, "```"); idx >= 0 {
			clean = strings.TrimSpace(clean[:idx])
		}
	}

	return strings.TrimSpace(clean), nil
}

// ParseTSVLines 解析TSV格式的文本，返回行数组
// 每行按制表符分割成字段数组
func ParseTSVLines(raw string) ([][]string, error) {
	clean, err := ParseTSV(raw)
	if err != nil {
		return nil, err
	}

	lines := strings.Split(clean, "\n")
	result := make([][]string, 0, len(lines))

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue // 跳过空行
		}

		// 按制表符分割
		fields := strings.Split(line, "\t")
		// 清理每个字段的前后空白
		cleanedFields := make([]string, 0, len(fields))
		for _, field := range fields {
			cleanedFields = append(cleanedFields, strings.TrimSpace(field))
		}
		result = append(result, cleanedFields)
	}

	if len(result) == 0 {
		return nil, fmt.Errorf("no valid lines found")
	}

	return result, nil
}
