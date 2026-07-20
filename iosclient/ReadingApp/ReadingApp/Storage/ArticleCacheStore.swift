import Foundation

final class ArticleCacheStore {
    static let shared = ArticleCacheStore()

    private let userDefaults = UserDefaults.standard
    private let articleListKey = "readingcoach.article.list.cache"
    private let articleDetailKey = "readingcoach.article.detail.cache"

    private init() {}

    func cachedArticles() -> [ArticleItem] {
        guard let data = userDefaults.data(forKey: articleListKey),
              let items = try? JSONDecoder().decode([ArticleItem].self, from: data) else {
            return []
        }
        return items
    }

    func saveArticles(_ items: [ArticleItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        userDefaults.set(data, forKey: articleListKey)
    }

    func cachedArticleDetail(articleId: String) -> ArticleDetailResponse? {
        guard let data = userDefaults.data(forKey: articleDetailKey),
              let cache = try? JSONDecoder().decode([String: ArticleDetailResponse].self, from: data) else {
            return nil
        }
        return cache[articleId]
    }

    func saveArticleDetail(_ detail: ArticleDetailResponse, articleId: String) {
        var cache = cachedArticleDetails()
        cache[articleId] = detail
        guard let data = try? JSONEncoder().encode(cache) else { return }
        userDefaults.set(data, forKey: articleDetailKey)
    }

    func removeArticle(articleId: String) {
        saveArticles(cachedArticles().filter { $0.id != articleId })
        var cache = cachedArticleDetails()
        cache.removeValue(forKey: articleId)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        userDefaults.set(data, forKey: articleDetailKey)
    }

    private func cachedArticleDetails() -> [String: ArticleDetailResponse] {
        guard let data = userDefaults.data(forKey: articleDetailKey),
              let cache = try? JSONDecoder().decode([String: ArticleDetailResponse].self, from: data) else {
            return [:]
        }
        return cache
    }
}
