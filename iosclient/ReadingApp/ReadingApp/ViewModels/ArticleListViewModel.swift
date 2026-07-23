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
    @Published private(set) var deletingArticleId: String?
    @Published var showTitleEditor = false
    @Published var articleToEdit: ArticleItem?
    @Published var titleDraft = ""
    @Published private(set) var updatingTitleArticleId: String?
    @Published var searchKeyword: String = ""
    @Published var currentTab: String = "list"
    
    private var hasLoaded = false
    private var toastDismissWorkItem: DispatchWorkItem?

    init() {
        articles = ArticleCacheStore.shared.cachedArticles()
    }
    
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
            ArticleCacheStore.shared.saveArticles(response.items)
        } catch is CancellationError {
            return
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func refreshArticles() async {
        // 不用 isLoading 提前 return：下拉刷新需要真正 await 网络请求完成，
        // 这样系统的下拉菊花才会一直显示到刷新结束，而不是松手就收起。
        do {
            let response = try await ArticleAPI.shared.listArticles()
            articles = response.items
            ArticleCacheStore.shared.saveArticles(response.items)
            showToast("刷新成功")
        } catch is CancellationError {
            return
        } catch {
            showToast("刷新失败：\(error.localizedDescription)")
        }
    }
    
    func requestDelete(article: ArticleItem) {
        guard !isMutatingArticle else { return }
        articleToDelete = article
        showDeleteConfirmation = true
    }
    
    @discardableResult
    func confirmDelete() async -> Bool {
        guard let article = articleToDelete, deletingArticleId == nil else { return false }

        showDeleteConfirmation = false
        articleToDelete = nil
        deletingArticleId = article.id
        defer { deletingArticleId = nil }

        do {
            try await ArticleAPI.shared.deleteArticle(articleId: article.id)
            articles.removeAll { $0.id == article.id }
            ArticleCacheStore.shared.removeArticle(articleId: article.id)
            await MainActor.run {
                NotificationCenter.default.post(name: .reviewTasksDidChange, object: nil)
            }
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }
    
    func cancelDelete() {
        showDeleteConfirmation = false
        articleToDelete = nil
    }

    func requestTitleEdit(article: ArticleItem) {
        guard !isMutatingArticle else { return }
        articleToEdit = article
        titleDraft = article.title
        showTitleEditor = true
    }

    func cancelTitleEdit() {
        showTitleEditor = false
        articleToEdit = nil
        titleDraft = ""
    }

    func confirmTitleEdit() async {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let article = articleToEdit, !title.isEmpty, title != article.title, !isMutatingArticle else { return }

        showTitleEditor = false
        articleToEdit = nil
        titleDraft = ""
        updatingTitleArticleId = article.id
        defer { updatingTitleArticleId = nil }

        do {
            let response = try await ArticleAPI.shared.updateArticleTitle(articleId: article.id, title: title)
            if let index = articles.firstIndex(where: { $0.id == article.id }) {
                articles[index].title = response.title
                ArticleCacheStore.shared.saveArticles(articles)
            }
            ArticleCacheStore.shared.updateArticleTitle(articleId: article.id, title: response.title)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    var canSaveTitle: Bool {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title.count <= 60 && title != articleToEdit?.title
    }

    var isMutatingArticle: Bool {
        deletingArticleId != nil || updatingTitleArticleId != nil
    }
    
    func onSearchInput(_ keyword: String) {
        searchKeyword = keyword
    }
    
    func switchTab(_ tab: String) {
        currentTab = tab
    }

    private func showToast(_ message: String, duration: TimeInterval = 2.0) {
        toastDismissWorkItem?.cancel()
        toastMessage = message
        let workItem = DispatchWorkItem { [weak self] in
            self?.toastMessage = nil
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}
