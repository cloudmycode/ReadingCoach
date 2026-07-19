package handlers

import "strconv"

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
