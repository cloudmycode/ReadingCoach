// Package services 业务服务层
// 功能：
//   - 验证码服务：生成、存储、验证短信验证码
//   - 数据库存储：生产环境使用数据库存储验证码
//   - 过期管理：自动清理过期验证码
//   - 防重复：同一手机号限制验证码频率
package services

import (
	"database/sql"
	"fmt"
	"math/rand"
	"sync"
	"time"
)

type CodeService interface {
	GenerateAndSave(phone string, ttl time.Duration) (code string, expiresAt time.Time, err error)
	Verify(phone, code string) (bool, error)
	SetCode(phone, code string, expiresAt time.Time) error
}

// 数据库版本的验证码服务
type dbCodeService struct {
	db *sql.DB
}

func NewDBCodeService(db *sql.DB) CodeService {
	return &dbCodeService{db: db}
}

func (s *dbCodeService) GenerateAndSave(phone string, ttl time.Duration) (string, time.Time, error) {
	// 清理过期的验证码
	s.cleanExpiredCodes()

	// 检查是否在限制时间内重复发送
	if s.isRateLimited(phone) {
		return "", time.Time{}, fmt.Errorf("验证码发送过于频繁，请稍后再试")
	}

	// 生成6位数字验证码
	code := s.generateCode()
	expiresAt := time.Now().Add(ttl)

	// 将新验证码插入数据库
	query := `INSERT INTO verification_codes (phone, code, expires_at, created_at) VALUES (?, ?, ?, NOW())`
	_, err := s.db.Exec(query, phone, code, expiresAt)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("保存验证码失败: %v", err)
	}

	return code, expiresAt, nil
}

func (s *dbCodeService) Verify(phone, code string) (bool, error) {
	query := `SELECT id, expires_at FROM verification_codes 
			  WHERE phone = ? AND code = ? AND is_used = 0 AND expires_at > NOW() 
			  ORDER BY created_at DESC LIMIT 1`

	var id int64
	var expiresAt time.Time
	err := s.db.QueryRow(query, phone, code).Scan(&id, &expiresAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, fmt.Errorf("验证码查询失败: %v", err)
	}

	// 标记验证码为已使用
	updateQuery := `UPDATE verification_codes SET is_used = 1, used_at = NOW() WHERE id = ?`
	_, err = s.db.Exec(updateQuery, id)
	if err != nil {
		return false, fmt.Errorf("更新验证码状态失败: %v", err)
	}

	return true, nil
}

func (s *dbCodeService) SetCode(phone, code string, expiresAt time.Time) error {
	query := `INSERT INTO verification_codes (phone, code, expires_at, created_at) VALUES (?, ?, ?, NOW())`
	_, err := s.db.Exec(query, phone, code, expiresAt)
	return err
}

func (s *dbCodeService) generateCode() string {
	// 生成6位数字验证码
	return fmt.Sprintf("%06d", rand.Intn(1000000))
}

func (s *dbCodeService) cleanExpiredCodes() {
	// 清理过期的验证码
	query := `DELETE FROM verification_codes WHERE expires_at < NOW()`
	s.db.Exec(query)
}

func (s *dbCodeService) isRateLimited(phone string) bool {
	// 检查1分钟内是否已发送过验证码
	query := `SELECT COUNT(*) FROM verification_codes 
			  WHERE phone = ? AND created_at > DATE_SUB(NOW(), INTERVAL 1 MINUTE)`

	var count int
	err := s.db.QueryRow(query, phone).Scan(&count)
	if err != nil {
		return false
	}

	return count > 0
}

// 内存版本的验证码服务（保留用于开发环境）
type inMemoryCodeService struct {
	mu    sync.Mutex
	store map[string]CodeEntry
}

type CodeEntry struct {
	Code      string
	ExpiresAt time.Time
}

func NewInMemoryCodeService() CodeService {
	return &inMemoryCodeService{store: make(map[string]CodeEntry)}
}

func (s *inMemoryCodeService) GenerateAndSave(phone string, ttl time.Duration) (string, time.Time, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	// 开发环境使用固定验证码
	code := "123456"
	exp := time.Now().Add(ttl)
	s.store[phone] = CodeEntry{Code: code, ExpiresAt: exp}
	return code, exp, nil
}

func (s *inMemoryCodeService) Verify(phone, code string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	entry, ok := s.store[phone]
	if !ok {
		return false, nil
	}
	if time.Now().After(entry.ExpiresAt) {
		delete(s.store, phone)
		return false, nil
	}
	if entry.Code != code {
		return false, nil
	}
	delete(s.store, phone)
	return true, nil
}

func (s *inMemoryCodeService) SetCode(phone, code string, expiresAt time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.store[phone] = CodeEntry{Code: code, ExpiresAt: expiresAt}
	return nil
}
