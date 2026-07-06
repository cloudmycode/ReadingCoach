package utils

import (
	"encoding/base64"
	"fmt"
	"strconv"
)

const (
	// idSalt 用于混淆ID，防止简单遍历
	idSalt = 0x5A5A5A5A
)

// EncryptID 加密ID，返回可安全传递的字符串
// 使用简单的XOR加密 + Base64编码，防止直接暴露真实ID
func EncryptID(id int64) string {
	if id <= 0 {
		return ""
	}
	// XOR加密
	encrypted := id ^ idSalt
	// 转换为字符串并Base64编码
	data := []byte(fmt.Sprintf("%d", encrypted))
	return base64.URLEncoding.EncodeToString(data)
}

// DecryptID 解密ID，从加密字符串还原真实ID
func DecryptID(encrypted string) (int64, error) {
	if encrypted == "" {
		return 0, fmt.Errorf("empty encrypted id")
	}

	// Base64解码
	data, err := base64.URLEncoding.DecodeString(encrypted)
	if err != nil {
		return 0, fmt.Errorf("invalid encrypted id: %w", err)
	}

	// 转换为数字
	encryptedNum, err := strconv.ParseInt(string(data), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid encrypted id format: %w", err)
	}

	// XOR解密
	id := encryptedNum ^ idSalt

	if id <= 0 {
		return 0, fmt.Errorf("invalid decrypted id: %d", id)
	}

	return id, nil
}
