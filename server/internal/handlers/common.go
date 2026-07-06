package handlers

import (
	"fmt"
	"mime/multipart"
	"sort"
	"strconv"
	"strings"
)

// ============================================================================
// 共享的辅助函数
// ============================================================================

// collectImageFiles 从 multipart 表单中收集所有图片文件（支持多种字段名格式，保持上传顺序）
// 支持以下字段名格式：
//   - "file" - 单文件字段
//   - "files" 或 "files[]" - 多文件数组字段
//   - "file[0]", "file[1]" 等 - 带索引的字段（按索引顺序）
func collectImageFiles(form *multipart.Form) []*multipart.FileHeader {
	if form == nil || len(form.File) == 0 {
		return nil
	}

	var fileHeaders []*multipart.FileHeader

	// 按固定顺序收集文件，确保先上传的文件排在前面
	// 1. 先处理单文件字段 "file"
	if files, ok := form.File["file"]; ok {
		fileHeaders = append(fileHeaders, files...)
	}

	// 2. 处理多文件数组字段 "files" 或 "files[]"
	if files, ok := form.File["files"]; ok {
		fileHeaders = append(fileHeaders, files...)
	}
	if files, ok := form.File["files[]"]; ok {
		fileHeaders = append(fileHeaders, files...)
	}

	// 3. 处理带索引的字段 "file[0]", "file[1]" 等（按索引顺序）
	indexedFiles := make(map[int][]*multipart.FileHeader)
	for field, files := range form.File {
		if strings.HasPrefix(field, "file[") && strings.HasSuffix(field, "]") {
			// 提取索引
			idxStr := field[5 : len(field)-1]
			var idx int
			if _, err := fmt.Sscanf(idxStr, "%d", &idx); err == nil {
				indexedFiles[idx] = files
			}
		}
	}
	// 按索引从小到大排序，确保先上传的文件排在前面
	indices := make([]int, 0, len(indexedFiles))
	for idx := range indexedFiles {
		indices = append(indices, idx)
	}
	sort.Ints(indices)
	for _, idx := range indices {
		fileHeaders = append(fileHeaders, indexedFiles[idx]...)
	}

	return fileHeaders
}

// parseQueryInt 解析查询参数中的整数值
// 如果解析失败或值为空，返回默认值
func parseQueryInt(value string, fallback int) int {
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}
