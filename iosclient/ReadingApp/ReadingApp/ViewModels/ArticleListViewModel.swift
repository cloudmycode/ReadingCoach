//
//  ArticleListViewModel.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation
import Combine

@MainActor
final class ArticleListViewModel: ObservableObject {
    @Published var articles: [ArticleItem] = []
    @Published var isLoading: Bool = false
    @Published var toastMessage: String?
    @Published var showDeleteConfirmation: Bool = false
    @Published var articleToDelete: ArticleItem?
    @Published var searchKeyword: String = ""
    @Published var currentTab: String = "article"
    
    private var hasLoaded = false
    
    var filteredArticles: [ArticleItem] {
        if searchKeyword.isEmpty {
            return articles
        }
        return articles.filter { article in
            article.title.localizedCaseInsensitiveContains(searchKeyword)
        }
    }
    
    func loadArticlesIfNeeded() async {
        guard !hasLoaded else { return }
        await loadArticles()
        hasLoaded = true
    }
    
    func loadArticles() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response = try await ArticleAPI.shared.listArticles()
            articles = response.items
        } catch {
            toastMessage = error.localizedDescription
        }
    }
    
    func requestDelete(article: ArticleItem) {
        articleToDelete = article
        showDeleteConfirmation = true
    }
    
    func confirmDelete() async {
        guard let article = articleToDelete else { return }
        
        // 立即从列表中移除
        articles.removeAll { $0.id == article.id }
        showDeleteConfirmation = false
        articleToDelete = nil
        
        // 异步调用云接口删除，不等待结果，不处理错误
        Task {
            try? await ArticleAPI.shared.deleteArticle(articleId: article.id)
        }
    }
    
    func cancelDelete() {
        showDeleteConfirmation = false
        articleToDelete = nil
    }
    
    func onSearchInput(_ keyword: String) {
        searchKeyword = keyword
    }
    
    func switchTab(_ tab: String) {
        currentTab = tab
    }
}
