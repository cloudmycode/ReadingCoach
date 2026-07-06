//
//  ArticleAPI.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation

struct ArticleAPI {
    static let shared = ArticleAPI()
    private let networkManager = NetworkManager.shared
    
    func listArticles(limit: Int = 50, offset: Int = 0) async throws -> ArticleListResponse {
        // 构建带查询参数的 endpoint
        var endpoint = "articles"
        var queryItems: [String] = []
        queryItems.append("limit=\(limit)")
        queryItems.append("offset=\(offset)")
        if !queryItems.isEmpty {
            endpoint += "?" + queryItems.joined(separator: "&")
        }
        
        return try await networkManager.request(
            endpoint: endpoint,
            method: "GET",
            responseType: ArticleListResponse.self
        )
    }
    
    func getArticleDetail(articleId: String) async throws -> ArticleDetailResponse {
        return try await networkManager.request(
            endpoint: "articles/\(articleId)",
            method: "GET",
            responseType: ArticleDetailResponse.self
        )
    }
    
    func deleteArticle(articleId: String) async throws {
        // 对于 DELETE 请求，我们只需要确保没有错误即可
        let _: EmptyResponse = try await networkManager.request(
            endpoint: "articles/\(articleId)",
            method: "DELETE",
            responseType: EmptyResponse.self
        )
    }
}

// 用于不需要返回数据的响应
private struct EmptyResponse: Decodable {}

