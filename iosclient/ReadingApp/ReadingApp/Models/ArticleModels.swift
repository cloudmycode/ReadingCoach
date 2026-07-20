//
//  ArticleModels.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation

struct PhotoUploadItem {
    let data: Data
    let fileName: String
    let mimeType: String
}

struct ArticleListResponse: Codable {
    let items: [ArticleItem]
    let limit: Int
    let offset: Int
}

struct ArticleItem: Codable, Identifiable, Hashable {
    let id: String  // 加密ID
    let articleId: Int
    let title: String
    let sentenceCount: Int
    let wordCount: Int
    let readCount: Int
    let createdAt: String
    let lastReadAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case articleId = "article_id"
        case title
        case sentenceCount = "sentence_count"
        case wordCount = "word_count"
        case readCount = "read_count"
        case createdAt = "created_at"
        case lastReadAt = "last_read_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        articleId = try container.decodeIfPresent(Int.self, forKey: .articleId) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        sentenceCount = try container.decodeIfPresent(Int.self, forKey: .sentenceCount) ?? 0
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount) ?? 0
        readCount = try container.decodeIfPresent(Int.self, forKey: .readCount) ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        lastReadAt = try container.decodeIfPresent(String.self, forKey: .lastReadAt)
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

struct ArticleDetailResponse: Codable {
    let articleId: Int
    let title: String
    let sentenceCount: Int
    let sentences: [ArticleSentence]
    
    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case title
        case sentenceCount = "sentence_count"
        case sentences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        articleId = try container.decodeIfPresent(Int.self, forKey: .articleId) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        sentences = try container.decodeIfPresent([ArticleSentence].self, forKey: .sentences) ?? []
        sentenceCount = try container.decodeIfPresent(Int.self, forKey: .sentenceCount) ?? sentences.count
    }
}

struct ProcessArticleResponse: Decodable {
    let resourceId: String
    
    enum CodingKeys: String, CodingKey {
        case resourceId = "resource_id"
    }
}

struct SentenceWordExplanationResponse: Codable {
    let word: String
    let partOfSpeech: String
    let meaning: String
    let tip: String
    let sentenceId: Int
    let articleId: String
    
    enum CodingKeys: String, CodingKey {
        case word
        case partOfSpeech = "part_of_speech"
        case meaning
        case tip
        case sentenceId = "sentence_id"
        case articleId = "article_id"
    }
}

struct SentenceQuestionResponse: Codable {
    let answer: String
    let highlights: [String]
    let sentenceId: Int
    let articleId: String
    
    enum CodingKeys: String, CodingKey {
        case answer
        case highlights
        case sentenceId = "sentence_id"
        case articleId = "article_id"
    }
}

struct ArticleSentence: Identifiable, Codable {
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
