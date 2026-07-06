//
//  ArticleModels.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation

struct ArticleListResponse: Decodable {
    let items: [ArticleItem]
    let limit: Int
    let offset: Int
}

struct ArticleItem: Decodable, Identifiable, Hashable {
    let id: String  // 加密ID
    let articleId: Int
    let title: String
    let sentenceCount: Int
    let readCount: Int
    let sentenceDuration: Int  // 毫秒
    let createdAt: String
    let lastReadAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case articleId = "article_id"
        case title
        case sentenceCount = "sentence_count"
        case readCount = "read_count"
        case sentenceDuration = "sentence_duration"
        case createdAt = "created_at"
        case lastReadAt = "last_read_at"
    }
    
    // 格式化时长显示（秒）
    var durationDisplay: String {
        let seconds = sentenceDuration / 1000
        guard seconds > 0 else { return "--:--" }
        let minutes = seconds / 60
        let remain = seconds % 60
        return String(format: "%d:%02d", minutes, remain)
    }
    
    // 格式化日期显示
    var lastReadDisplay: String {
        guard let lastReadAt = lastReadAt else { return "" }
        
        // 使用 ISO8601DateFormatter 解析 RFC3339 格式
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = parser.date(from: lastReadAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            return displayFormatter.string(from: date)
        }
        
        // 如果解析失败，尝试不带毫秒的格式
        let parser2 = ISO8601DateFormatter()
        if let date = parser2.date(from: lastReadAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            return displayFormatter.string(from: date)
        }
        
        // 如果都失败，返回原始字符串（简单处理）
        return String(lastReadAt.prefix(16).replacingOccurrences(of: "T", with: " "))
    }
}

struct ArticleDetailResponse: Decodable {
    let articleId: Int
    let title: String
    let sentences: [ArticleSentence]
    
    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case title
        case sentences
    }
}

struct AnalyzeImageResponse: Decodable {
    let articleId: String?
    let resourceId: String?
    let type: String?
    
    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case resourceId = "resource_id"
        case type
    }
    
    // 兼容性：优先使用 resource_id，如果没有则使用 article_id
    var id: String? {
        return resourceId ?? articleId
    }
}

struct ArticleSentence: Identifiable, Decodable {
    private let internalID: Int?
    let sentenceId: Int?
    let original: String
    let translation: String
    var isFavorite: Bool
    
    enum CodingKeys: String, CodingKey {
        case internalID = "id"
        case sentenceId = "sentence_id"
        case original
        case translation
        case isFavorite = "is_favorite"
    }
    
    var id: String {
        if let sentenceId = sentenceId {
            return "sentence_\(sentenceId)"
        }
        if let internalID = internalID {
            return "idx_\(internalID)"
        }
        return UUID().uuidString
    }
}

