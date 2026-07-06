// Package handlers HTTP请求处理器
// 功能：
//   - 认证相关API：获取验证码、用户登录
//   - 用户管理：查找或创建用户、更新登录时间
//   - JWT令牌：签发和验证用户身份令牌
//   - 数据验证：手机号格式化、参数校验
//   - 统一响应：成功/错误响应格式
package handlers

import (
	"database/sql"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"

	"words/server/internal/logger"
	"words/server/internal/services"
	"words/server/pkg/config"
)

type AuthHandler struct {
	db    *sql.DB
	codes services.CodeService
	cfg   config.Config
}

func NewAuthHandler(db *sql.DB, codes services.CodeService, cfg config.Config) *AuthHandler {
	return &AuthHandler{
		db:    db,
		codes: codes,
		cfg:   cfg,
	}
}

type sendCodeReq struct {
	Phone string `json:"phone"`
}

type loginReq struct {
	Phone       string `json:"phone"`
	Code        string `json:"code"`
	AgreePolicy bool   `json:"agreePolicy"`
}

func (h *AuthHandler) SendCode(c *gin.Context) {
	var req sendCodeReq
	if err := c.ShouldBindJSON(&req); err != nil || len(req.Phone) == 0 {
		jsonError(c, http.StatusBadRequest, "参数错误")
		return
	}
	phone := normalizePhone(req.Phone)

	code, exp, err := h.codes.GenerateAndSave(phone, 3*time.Minute)
	if err != nil {
		jsonError(c, http.StatusTooManyRequests, err.Error())
		return
	}
	jsonOK(c, "验证码已发送", gin.H{
		"expiresIn": int(time.Until(exp).Seconds()),
		"debugCode": code, // 开发环境显示验证码
	})
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req loginReq
	if err := c.ShouldBindJSON(&req); err != nil {
		jsonError(c, http.StatusBadRequest, "参数错误")
		return
	}
	if !req.AgreePolicy {
		jsonError(c, http.StatusBadRequest, "请先同意隐私政策")
		return
	}
	phone := normalizePhone(req.Phone)
	if phone == "" || req.Code == "" {
		jsonError(c, http.StatusBadRequest, "手机号或验证码为空")
		return
	}

	// 验证验证码
	valid, err := h.codes.Verify(phone, req.Code)
	if err != nil {
		jsonError(c, http.StatusInternalServerError, "验证码验证失败")
		return
	}
	if !valid {
		jsonError(c, http.StatusUnauthorized, "验证码错误或已过期")
		return
	}

	// 查找或创建用户
	userID, nickname, avatar, err := h.findOrCreateUser(phone)
	if err != nil {
		jsonError(c, http.StatusInternalServerError, "登录失败")
		return
	}

	// 签发JWT令牌
	token, err := h.issueJWT(userID, phone)
	if err != nil {
		jsonError(c, http.StatusInternalServerError, "签发令牌失败")
		return
	}

	// 设置HTTP Cookie (7天有效期)
	c.SetCookie("token", token, 7*24*3600, "/", "", false, true)

	jsonOK(c, "登录成功", gin.H{
		"token": token,
		"userInfo": gin.H{
			"id":       userID,
			"nickname": nickname,
			"avatar":   avatar,
		},
	})
}

func (h *AuthHandler) issueJWT(userID int64, phone string) (string, error) {
	claims := jwt.MapClaims{
		"sub":   userID,
		"phone": phone,
		"exp":   time.Now().Add(7 * 24 * time.Hour).Unix(),
		"iat":   time.Now().Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.cfg.JWTSecret))
}

// VerifyToken 验证JWT令牌
func (h *AuthHandler) VerifyToken(c *gin.Context) {
	logger.Info("🔍 开始JWT验证 - 路径: %s", c.Request.URL.Path)

	// 优先从Authorization header获取token
	token := ""
	authHeader := c.GetHeader("Authorization")
	logger.Info("🔍 Authorization header: %s", authHeader)

	if authHeader != "" && len(authHeader) > 7 && authHeader[:7] == "Bearer " {
		token = authHeader[7:]
		logger.Info("🔍 从Authorization header获取token: %s", token[:10]+"...")
	} else {
		// 如果header中没有，则从Cookie获取
		if cookieToken, err := c.Cookie("token"); err == nil {
			token = cookieToken
			logger.Info("🔍 从Cookie获取token: %s", token[:10]+"...")
		} else {
			logger.Info("🔍 Cookie获取失败: %v", err)
		}
	}

	if token == "" {
		logger.Error("❌ 未找到token")
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "message": "未登录"})
		c.Abort()
		return
	}

	// 解析JWT
	logger.Info("🔍 开始解析JWT token")
	claims, err := jwt.Parse(token, func(token *jwt.Token) (interface{}, error) {
		logger.Info("🔍 JWT解析回调函数被调用")
		return []byte(h.cfg.JWTSecret), nil
	})

	if err != nil {
		logger.Error("❌ JWT解析失败: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "message": "令牌无效"})
		c.Abort()
		return
	}

	logger.Info("🔍 JWT解析成功")
	if !claims.Valid {
		logger.Error("❌ JWT令牌无效")
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "message": "令牌无效"})
		c.Abort()
		return
	}

	// 将用户信息存储到上下文
	if claimsMap, ok := claims.Claims.(jwt.MapClaims); ok {
		logger.Info("🔍 JWT Claims: %+v", claimsMap)

		// 将 user_id 转换为 int 类型并存储到上下文
		var userID int
		switch v := claimsMap["sub"].(type) {
		case float64:
			userID = int(v)
		case int64:
			userID = int(v)
		case int:
			userID = v
		default:
			logger.Error("❌ 用户ID类型转换失败，类型: %T, 值: %v", v, v)
			c.JSON(http.StatusUnauthorized, gin.H{"success": false, "message": "令牌无效"})
			c.Abort()
			return
		}

		c.Set("user_id", userID)
		c.Set("userID", userID) // 保持向后兼容
		if phone, ok := claimsMap["phone"].(string); ok {
			c.Set("phone", phone)
		}

		logger.Info("✅ 用户ID已设置到上下文: %d", userID)
	}

	c.Next()
}

// getUserID 从上下文获取用户ID（由认证中间件设置）
// 如果获取失败，返回错误并设置HTTP响应
func getUserID(c *gin.Context) int {
	userID, exists := c.Get("user_id")
	if !exists {
		logger.Error("❌ 用户ID不存在")
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"message": "用户未登录",
		})
		c.Abort()
		return 0
	}

	userIDInt, ok := userID.(int)
	if !ok {
		logger.Error("❌ 用户ID类型错误，类型: %T, 值: %v", userID, userID)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": "用户ID类型错误",
		})
		c.Abort()
		return 0
	}

	return userIDInt
}

// GetUserInfo 获取当前用户信息
func (h *AuthHandler) GetUserInfo(c *gin.Context) {
	// 从上下文获取用户ID（由认证中间件设置）
	userID := getUserID(c)
	if userID == 0 {
		return // getUserID 已经处理了错误响应
	}

	// 从数据库获取用户信息
	var nickname, avatar sql.NullString
	row := h.db.QueryRow("SELECT nickname, avatar_url FROM users WHERE user_id = ?", userID)
	if err := row.Scan(&nickname, &avatar); err != nil {
		jsonError(c, http.StatusInternalServerError, "获取用户信息失败")
		return
	}

	jsonOK(c, "获取成功", gin.H{
		"id":       userID,
		"nickname": nullOrDefault(nickname, "用户"),
		"avatar":   nullOrDefault(avatar, ""),
	})
}

// Logout 用户登出
func (h *AuthHandler) Logout(c *gin.Context) {
	// 清除Cookie
	c.SetCookie("token", "", -1, "/", "", false, true)
	jsonOK(c, "登出成功", nil)
}

func (h *AuthHandler) findOrCreateUser(phone string) (int64, string, string, error) {
	// 查找用户
	var id int64
	var nickname, avatar sql.NullString
	row := h.db.QueryRow("SELECT user_id, nickname, avatar_url FROM users WHERE phone = ?", phone)
	if err := row.Scan(&id, &nickname, &avatar); err != nil {
		if err == sql.ErrNoRows {
			// 创建用户默认昵称
			res, err := h.db.Exec("INSERT INTO users (phone, nickname, created_at, updated_at) VALUES (?,?,NOW(),NOW())", phone, defaultNickname(phone))
			if err != nil {
				return 0, "", "", err
			}
			newID, _ := res.LastInsertId()
			return newID, defaultNickname(phone), "", nil
		}
		return 0, "", "", err
	}
	// 更新最后登录时间
	_, _ = h.db.Exec("UPDATE users SET last_login_at = NOW() WHERE user_id = ?", id)
	return id, nullOrDefault(nickname, defaultNickname(phone)), nullOrDefault(avatar, ""), nil
}

func defaultNickname(phone string) string {
	if len(phone) >= 4 {
		return "用户" + phone[len(phone)-4:]
	}
	return "新用户"
}

func nullOrDefault(ns sql.NullString, def string) string {
	if ns.Valid {
		return ns.String
	}
	return def
}

func normalizePhone(p string) string {
	p = strings.TrimSpace(p)
	p = strings.ReplaceAll(p, "-", "")
	return p
}

// 统一响应
func jsonOK(c *gin.Context, message string, data any) {
	c.JSON(http.StatusOK, gin.H{"success": true, "message": message, "data": data})
}

func jsonError(c *gin.Context, status int, message string) {
	c.JSON(status, gin.H{"success": false, "message": message})
}
