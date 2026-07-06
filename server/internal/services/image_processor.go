package services

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"

	"github.com/disintegration/imaging"
	"github.com/google/uuid"
	_ "golang.org/x/image/webp"

	"words/server/internal/logger"
)

// ImageProcessType 图片处理类型
type ImageProcessType string

const (
	// ImageProcessTypeArticle 文章类型：提取英文句子和翻译
	ImageProcessTypeArticle ImageProcessType = "article"
	// ImageProcessTypeUnit 单词单元类型：提取单词列表
	ImageProcessTypeUnit ImageProcessType = "unit"
)

const (
	uploadImageSubDir  = "uploadimage"
	articleAudioSubDir = "articleaudio"
	// MaxImageDimension 图片最大尺寸（超过此尺寸将等比压缩）
	MaxImageDimension = 1024
)

// ImageProcessResult 图片处理结果
type ImageProcessResult struct {
	// Type 处理类型
	Type ImageProcessType
	// Data 处理后的结构化数据（TSV格式已解析为行数组）
	// 每行是一个字段数组，例如：
	//   - 文章分析：[[英文, 中文], [英文, 中文], ...]
	//   - 单词分析：[[单词, 翻译, 例句], [单词, 翻译, 例句], ...]
	Data [][]string
	// Attachments 附件信息
	Attachments []ImageAttachmentInfo
}

// ImageAttachmentInfo 图片附件信息
type ImageAttachmentInfo struct {
	FileName     string
	OriginalName string
	URL          string
	Size         int64
	Width        int
	Height       int
}

// ImageDataSaver 数据保存器接口
// 不同处理类型实现此接口，将AI分析结果保存到对应的数据库表
type ImageDataSaver interface {
	// SaveData 保存处理结果到数据库
	// ctx: 上下文
	// userID: 用户ID
	// attachments: 附件信息
	// data: AI返回的结构化数据（TSV格式已解析为行数组）
	// 返回: 保存后的资源ID（如article_id、unit_list_id等）和错误
	SaveData(ctx context.Context, userID int, attachments []ImageAttachmentInfo, data [][]string) (int64, error)
}

// ImageProcessor 图片处理器接口
// 只负责图片处理（压缩、保存）和AI分析，不负责数据保存
type ImageProcessor interface {
	// ProcessImages 处理图片并调用AI分析
	// ctx: 上下文
	// fileHeaders: 上传的文件头列表
	// processType: 处理类型（用于确定保存目录和提示词）
	// 返回: 处理结果（包含附件信息和AI分析结果）和错误
	ProcessImages(ctx context.Context, fileHeaders []*multipart.FileHeader, processType ImageProcessType) (*ImageProcessResult, error)
	// ProcessImagesOnly 仅处理图片（压缩、保存），不调用AI分析
	// ctx: 上下文
	// fileHeaders: 上传的文件头列表
	// 返回: 附件信息列表、图片字节数据列表、错误
	ProcessImagesOnly(ctx context.Context, fileHeaders []*multipart.FileHeader) ([]ImageAttachmentInfo, [][]byte, error)
}

// PostSaveCallback 保存后的回调函数类型
// resourceID: 保存后的资源ID
// processType: 处理类型
type PostSaveCallback func(ctx context.Context, resourceID int64, processType ImageProcessType)

// ImageProcessorConfig 图片处理器配置
type ImageProcessorConfig struct {
	// AttachmentsDir 附件目录
	AttachmentsDir string
	// Analyzer AI分析器
	Analyzer ImageAnalyzer
}

// imageProcessor 图片处理器实现
type imageProcessor struct {
	config       ImageProcessorConfig
	baseImageDir string
}

// NewImageProcessor 创建图片处理器
func NewImageProcessor(config ImageProcessorConfig) ImageProcessor {
	baseImageDir := filepath.Join(config.AttachmentsDir, uploadImageSubDir)

	// 确保基础目录存在
	if err := os.MkdirAll(baseImageDir, 0o755); err != nil {
		logger.Warn("⚠️ 创建图片目录失败: %s, err=%v", baseImageDir, err)
	}

	return &imageProcessor{
		config:       config,
		baseImageDir: baseImageDir,
	}
}

// ProcessImages 处理图片
func (p *imageProcessor) ProcessImages(ctx context.Context, fileHeaders []*multipart.FileHeader, processType ImageProcessType) (*ImageProcessResult, error) {
	if len(fileHeaders) == 0 {
		return nil, fmt.Errorf("no image files provided")
	}

	// 1. 处理图片：压缩、保存（根据类型保存到对应目录）
	attachments, imageBuffers, err := p.processUploadedImages(fileHeaders, processType)
	if err != nil {
		return nil, fmt.Errorf("process uploaded images: %w", err)
	}

	// 2. 根据类型获取提示词并调用AI分析
	prompt := p.getPromptForType(processType)
	analysisResult, err := p.analyzeImages(ctx, imageBuffers, prompt)
	if err != nil {
		return nil, fmt.Errorf("analyze images: %w", err)
	}

	return &ImageProcessResult{
		Type:        processType,
		Data:        analysisResult,
		Attachments: attachments,
	}, nil
}

// ProcessImagesOnly 仅处理图片（压缩、保存），不调用AI分析
// 使用默认的article类型目录保存图片
func (p *imageProcessor) ProcessImagesOnly(ctx context.Context, fileHeaders []*multipart.FileHeader) ([]ImageAttachmentInfo, [][]byte, error) {
	if len(fileHeaders) == 0 {
		return nil, nil, fmt.Errorf("no image files provided")
	}

	// 使用article类型保存图片（可以后续扩展支持自定义目录）
	return p.processUploadedImages(fileHeaders, ImageProcessTypeArticle)
}

// getPromptForType 根据处理类型获取提示词
func (p *imageProcessor) getPromptForType(processType ImageProcessType) string {
	switch processType {
	case ImageProcessTypeArticle:
		return ArticleAnalysisPrompt
	case ImageProcessTypeUnit:
		return UnitAnalysisPrompt
	default:
		return ArticleAnalysisPrompt // 默认使用文章提示词
	}
}

// analyzeImages 调用AI分析图片
// 返回解析后的结构化数据（TSV格式已解析为行数组）
func (p *imageProcessor) analyzeImages(ctx context.Context, images [][]byte, prompt string) ([][]string, error) {
	if p.config.Analyzer == nil {
		return nil, fmt.Errorf("analyzer not configured")
	}

	// 使用支持自定义提示词的接口，基础层已经解析了TSV格式
	return p.config.Analyzer.AnalyzeImagesWithPrompt(ctx, images, prompt)
}

// processUploadedImages 处理上传的图片（压缩、保存）
// 根据处理类型保存到对应的子目录
// 返回: 附件信息列表、图片字节数据列表、错误
func (p *imageProcessor) processUploadedImages(fileHeaders []*multipart.FileHeader, processType ImageProcessType) ([]ImageAttachmentInfo, [][]byte, error) {
	attachments := make([]ImageAttachmentInfo, 0, len(fileHeaders))
	imageBuffers := make([][]byte, 0, len(fileHeaders))

	for _, fh := range fileHeaders {
		info, data, err := p.processSingleImage(fh, processType)
		if err != nil {
			return nil, nil, fmt.Errorf("process image %s: %w", fh.Filename, err)
		}
		attachments = append(attachments, info)
		if len(data) > 0 {
			imageBuffers = append(imageBuffers, data)
		}
	}

	return attachments, imageBuffers, nil
}

// processSingleImage 处理单张上传的图片：读取、解码、压缩、保存，并返回压缩后的字节数据
// 根据处理类型保存到对应的子目录
func (p *imageProcessor) processSingleImage(fh *multipart.FileHeader, processType ImageProcessType) (ImageAttachmentInfo, []byte, error) {
	src, err := fh.Open()
	if err != nil {
		return ImageAttachmentInfo{}, nil, fmt.Errorf("打开上传文件失败: %w", err)
	}
	defer src.Close()

	data, err := io.ReadAll(src)
	if err != nil {
		return ImageAttachmentInfo{}, nil, fmt.Errorf("读取上传文件失败: %w", err)
	}

	img, format, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return ImageAttachmentInfo{}, nil, fmt.Errorf("解析图片失败: %w", err)
	}

	// 使用工具函数处理图片
	resized := ResizeImageIfNeeded(img, MaxImageDimension)
	fileName := GenerateImageFileName(fh.Filename, format)

	// 根据处理类型选择保存目录（使用工具函数）
	targetSubDir, urlSubDir := GetImageSubDir(processType)
	targetDir := filepath.Join(p.baseImageDir, targetSubDir)
	targetPath := filepath.Join(targetDir, fileName)

	// 确保目录存在
	if err := os.MkdirAll(targetDir, 0o755); err != nil {
		return ImageAttachmentInfo{}, nil, fmt.Errorf("创建目录失败: %w", err)
	}

	// 使用工具函数保存图片
	if err := SaveImage(resized, targetPath); err != nil {
		return ImageAttachmentInfo{}, nil, err
	}

	stat, err := os.Stat(targetPath)
	if err != nil {
		return ImageAttachmentInfo{}, nil, fmt.Errorf("获取文件信息失败: %w", err)
	}

	compressedData, err := os.ReadFile(targetPath)
	if err != nil {
		return ImageAttachmentInfo{}, nil, fmt.Errorf("读取压缩图片失败: %w", err)
	}

	return ImageAttachmentInfo{
		FileName:     fileName,
		OriginalName: fh.Filename,
		URL:          "/attachments/" + urlSubDir + "/" + fileName,
		Size:         stat.Size(),
		Width:        resized.Bounds().Dx(),
		Height:       resized.Bounds().Dy(),
	}, compressedData, nil
}

// ============================================================================
// 图片处理工具函数（纯函数，不依赖状态）
// ============================================================================

// ResizeImageIfNeeded 按需压缩图片：如果图片尺寸超过 maxDimension，则等比缩放
// 这是一个纯函数，不依赖任何状态，可以直接调用
func ResizeImageIfNeeded(img image.Image, maxDimension int) image.Image {
	if maxDimension <= 0 {
		maxDimension = MaxImageDimension
	}

	bounds := img.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()

	if width <= maxDimension && height <= maxDimension {
		return img
	}

	widthScale := float64(maxDimension) / float64(width)
	heightScale := float64(maxDimension) / float64(height)

	scale := widthScale
	if heightScale < widthScale {
		scale = heightScale
	}

	newWidth := int(float64(width) * scale)
	if newWidth < 1 {
		newWidth = 1
	}
	newHeight := int(float64(height) * scale)
	if newHeight < 1 {
		newHeight = 1
	}

	return imaging.Resize(img, newWidth, newHeight, imaging.Lanczos)
}

// GenerateImageFileName 生成唯一的图片文件名：使用 UUID + 原始扩展名
// 如果原始文件名没有扩展名，则根据解码格式自动添加
// 这是一个纯函数，不依赖任何状态，可以直接调用
func GenerateImageFileName(originalName, decodedFormat string) string {
	ext := strings.ToLower(filepath.Ext(originalName))
	switch ext {
	case ".jpg", ".jpeg", ".png", ".webp", ".gif":
		// 有效的图片扩展名
	default:
		ext = ""
	}

	// 如果没有扩展名，根据解码格式添加
	if ext == "" {
		switch strings.ToLower(decodedFormat) {
		case "jpeg":
			ext = ".jpg"
		case "png":
			ext = ".png"
		case "gif":
			ext = ".gif"
		default:
			ext = ".jpg" // 默认使用 jpg
		}
	}

	return uuid.NewString() + ext
}

// SaveImage 将图片保存到指定路径
// JPEG 格式使用 85% 质量压缩，其他格式保持原样
// 这是一个纯函数，不依赖任何状态，可以直接调用
func SaveImage(img image.Image, path string) error {
	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".jpg", ".jpeg":
		return imaging.Save(img, path, imaging.JPEGQuality(85))
	case ".png", ".gif", ".webp":
		return imaging.Save(img, path)
	default:
		// 未知格式，尝试保存
		return imaging.Save(img, path)
	}
}

// GetImageSubDir 根据处理类型获取图片子目录路径
// 这是一个纯函数，用于确定图片保存位置
func GetImageSubDir(processType ImageProcessType) (targetSubDir, urlSubDir string) {
	switch processType {
	case ImageProcessTypeArticle:
		return "uploadimage/article", "uploadimage/article"
	case ImageProcessTypeUnit:
		return "uploadimage/unit", "uploadimage/unit"
	default:
		return "uploadimage", "uploadimage"
	}
}

// ValidateImageFormat 验证图片格式是否支持
// 这是一个纯函数，用于验证上传的图片格式
func ValidateImageFormat(filename string) error {
	ext := strings.ToLower(filepath.Ext(filename))
	switch ext {
	case ".jpg", ".jpeg", ".png", ".webp", ".gif":
		return nil
	default:
		return fmt.Errorf("不支持的图片格式: %s，支持的格式: jpg, jpeg, png, webp, gif", ext)
	}
}

// ============================================================================
// 图片处理记录服务（数据库操作）
// ============================================================================

// ImageProcessRecordService 图片处理记录服务
type ImageProcessRecordService struct {
	db *sql.DB
}

// NewImageProcessRecordService 创建图片处理记录服务
func NewImageProcessRecordService(db *sql.DB) *ImageProcessRecordService {
	return &ImageProcessRecordService{db: db}
}

// SaveImageProcessRecord 保存图片处理记录
// attachmentPaths: 图片附件路径数组（JSON格式）
// userID: 上传附件的用户ID
// tokenUsage: AI消耗的token数量
func (s *ImageProcessRecordService) SaveImageProcessRecord(
	ctx context.Context,
	attachmentPaths []string,
	userID int,
	tokenUsage int,
) (int64, error) {
	if s.db == nil {
		return 0, fmt.Errorf("database connection not initialized")
	}
	if userID <= 0 {
		return 0, fmt.Errorf("invalid user id")
	}
	if len(attachmentPaths) == 0 {
		return 0, fmt.Errorf("no attachment paths provided")
	}

	// 将附件路径数组转换为JSON
	attachmentPathsJSON, err := json.Marshal(attachmentPaths)
	if err != nil {
		return 0, fmt.Errorf("marshal attachment paths: %w", err)
	}

	// 插入记录
	result, err := s.db.ExecContext(ctx, `
		INSERT INTO image_process_records (attachment_paths, user_id, token_usage, created_at)
		VALUES (?, ?, ?, NOW())
	`, string(attachmentPathsJSON), userID, tokenUsage)
	if err != nil {
		return 0, fmt.Errorf("insert image process record: %w", err)
	}

	recordID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("get record id: %w", err)
	}

	logger.Info("✅ 图片处理记录已保存: record_id=%d, user_id=%d, token_usage=%d", recordID, userID, tokenUsage)
	return recordID, nil
}
