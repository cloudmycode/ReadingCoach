// Package handlers HTTP请求处理器
// 功能：
//   - Unit相关API：查询unit列表、unit_words列表和例句
//   - ID加密：所有数字ID都进行加解密操作后输出给客户端
package handlers

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"words/server/internal/logger"
	"words/server/internal/services"
	"words/server/pkg/utils"
)

type UnitHandler struct {
	unitService    *services.UnitService
	imageProcessor services.ImageProcessor
}

func NewUnitHandler(unitService *services.UnitService, imageProcessor services.ImageProcessor) *UnitHandler {
	return &UnitHandler{
		unitService:    unitService,
		imageProcessor: imageProcessor,
	}
}

// UnitItem Unit列表项
type UnitItem struct {
	ID        string     `json:"id"`         // 加密后的unit_list_id
	Title     string     `json:"title"`      // 标题
	WordCount int        `json:"word_count"` // 单词数量
	CreatedAt time.Time  `json:"created_at"` // 创建时间
	UpdatedAt *time.Time `json:"updated_at"` // 更新时间
}

// UnitWordItem Unit单词项
type UnitWordItem struct {
	ID          string    `json:"id"`          // 加密后的unit_words_id
	Word        string    `json:"word"`        // 单词（从words表查询或直接使用unit_words.word）
	Translation string    `json:"translation"` // 翻译
	Example     string    `json:"example"`     // 例句
	AddedAt     time.Time `json:"added_at"`    // 添加时间
}

// ListUnits 获取当前用户的unit列表
// GET /api/units
func (h *UnitHandler) ListUnits(c *gin.Context) {
	userID := getUserID(c)
	if userID == 0 {
		return // getUserID 已经处理了错误响应
	}

	// 调用 Service 层获取数据
	units, err := h.unitService.GetUserUnits(c.Request.Context(), userID)
	if err != nil {
		logger.Error("❌ 获取unit列表失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "获取unit列表失败")
		return
	}

	// 转换为 HTTP 响应格式（ID加密）
	items := make([]UnitItem, 0, len(units))
	for _, unit := range units {
		items = append(items, UnitItem{
			ID:        utils.EncryptID(unit.UnitListID),
			Title:     unit.Title,
			WordCount: unit.WordCount,
			CreatedAt: unit.CreatedAt,
			UpdatedAt: unit.UpdatedAt,
		})
	}

	jsonOK(c, "获取成功", gin.H{
		"units": items,
	})
}

// ListUnitWords 获取指定unit的单词列表（包含例句）
// GET /api/units/:id/words
func (h *UnitHandler) ListUnitWords(c *gin.Context) {
	userID := getUserID(c)
	if userID == 0 {
		return // getUserID 已经处理了错误响应
	}

	encryptedUnitID := c.Param("id")
	if encryptedUnitID == "" {
		jsonError(c, http.StatusBadRequest, "unit ID不能为空")
		return
	}

	// 解密unit ID
	unitID, err := utils.DecryptID(encryptedUnitID)
	if err != nil {
		logger.Error("❌ 解密unit ID失败: %v", err)
		jsonError(c, http.StatusBadRequest, "无效的unit ID")
		return
	}

	// 调用 Service 层获取数据（包含权限验证）
	words, err := h.unitService.GetUnitWords(c.Request.Context(), unitID, userID)
	if err != nil {
		logger.Error("❌ 获取unit单词列表失败: %v", err)
		if err.Error() == "unit not found" {
			jsonError(c, http.StatusNotFound, "unit不存在")
		} else if err.Error() == "forbidden: unit does not belong to user" {
			jsonError(c, http.StatusForbidden, "无权访问此unit")
		} else {
			jsonError(c, http.StatusInternalServerError, "获取单词列表失败")
		}
		return
	}

	// 转换为 HTTP 响应格式（ID加密）
	items := make([]UnitWordItem, 0, len(words))
	for _, word := range words {
		items = append(items, UnitWordItem{
			ID:          utils.EncryptID(word.UnitWordsID),
			Word:        word.Word,
			Translation: word.Translation,
			Example:     word.Example,
			AddedAt:     word.AddedAt,
		})
	}

	jsonOK(c, "获取成功", gin.H{
		"words": items,
	})
}

// ProcessUnitImages 处理单词单元图片
// POST /api/units/process
// 参数：
//   - files: 图片文件数组（multipart/form-data）
//
// 响应：
//
//	{
//	  "success": true,
//	  "message": "处理成功",
//	  "data": {
//	    "resource_id": "加密后的unit_list_id",
//	  }
//	}
func (h *UnitHandler) ProcessUnitImages(c *gin.Context) {
	// 解析multipart表单
	if err := c.Request.ParseMultipartForm(32 << 20); err != nil {
		jsonError(c, http.StatusBadRequest, "无法解析上传数据")
		return
	}

	// 收集图片文件
	fileHeaders := collectImageFiles(c.Request.MultipartForm)
	if len(fileHeaders) == 0 {
		jsonError(c, http.StatusBadRequest, "未检测到上传图片")
		return
	}

	// 获取用户ID
	userID := getUserID(c)
	if userID == 0 {
		return // getUserID 已经处理了错误响应
	}

	// 检查服务是否配置
	if h.imageProcessor == nil {
		jsonError(c, http.StatusInternalServerError, "图片处理器未配置")
		return
	}
	if h.unitService == nil {
		jsonError(c, http.StatusInternalServerError, "单元服务未配置")
		return
	}

	// 1. 调用imageProcessor处理图片（保存附件、调用AI）
	result, err := h.imageProcessor.ProcessImages(
		c.Request.Context(),
		fileHeaders,
		services.ImageProcessTypeUnit,
	)
	if err != nil {
		logger.Error("❌ 图片处理失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "处理图片失败: "+err.Error())
		return
	}

	// 2. 解析AI返回的结构化数据
	wordInputs := make([]services.UnitWordInput, 0, len(result.Data))
	for _, line := range result.Data {
		if len(line) >= 3 {
			wordInputs = append(wordInputs, services.UnitWordInput{
				Word:        strings.TrimSpace(line[0]),
				Translation: strings.TrimSpace(line[1]),
				Example:     strings.TrimSpace(line[2]),
			})
		} else if len(line) >= 2 {
			wordInputs = append(wordInputs, services.UnitWordInput{
				Word:        strings.TrimSpace(line[0]),
				Translation: strings.TrimSpace(line[1]),
				Example:     "",
			})
		} else if len(line) == 1 && strings.TrimSpace(line[0]) != "" {
			wordInputs = append(wordInputs, services.UnitWordInput{
				Word:        strings.TrimSpace(line[0]),
				Translation: "",
				Example:     "",
			})
		}
	}

	if len(wordInputs) == 0 {
		jsonError(c, http.StatusBadRequest, "AI未识别到有效单词")
		return
	}

	// 3. 保存到数据库
	unitListID, err := h.unitService.SaveAnalyzedUnit(
		c.Request.Context(),
		userID,
		"", // 使用默认标题
		wordInputs,
	)
	if err != nil {
		logger.Error("❌ 保存单元到数据库失败: %v", err)
		jsonError(c, http.StatusInternalServerError, "保存单元失败: "+err.Error())
		return
	}

	// 返回加密后的单元ID
	encryptedID := utils.EncryptID(unitListID)
	jsonOK(c, "处理成功", gin.H{
		"resource_id": encryptedID,
	})
}
