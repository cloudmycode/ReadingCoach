import Foundation

final class ArticleCacheStore {
    static let shared = ArticleCacheStore()

    private let userDefaults = UserDefaults.standard

    private init() {}

    func reloadForCurrentUser() {}

    func cachedArticles() -> [ArticleItem] {
        guard let key = listKey(),
              let data = userDefaults.data(forKey: key),
              let items = try? JSONDecoder().decode([ArticleItem].self, from: data) else {
            return []
        }
        return items
    }

    func saveArticles(_ items: [ArticleItem]) {
        guard let key = listKey(),
              let data = try? JSONEncoder().encode(items) else { return }
        userDefaults.set(data, forKey: key)
    }

    func cachedArticleDetail(articleId: String) -> ArticleDetailResponse? {
        cachedArticleDetails()[articleId]
    }

    func saveArticleDetail(_ detail: ArticleDetailResponse, articleId: String) {
        guard let key = detailKey() else { return }
        var cache = cachedArticleDetails()
        cache[articleId] = detail
        guard let data = try? JSONEncoder().encode(cache) else { return }
        userDefaults.set(data, forKey: key)
    }

    func removeArticle(articleId: String) {
        saveArticles(cachedArticles().filter { $0.id != articleId })
        guard let key = detailKey() else { return }
        var cache = cachedArticleDetails()
        cache.removeValue(forKey: articleId)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        userDefaults.set(data, forKey: key)
    }

    func updateArticleTitle(articleId: String, title: String) {
        var items = cachedArticles()
        if let index = items.firstIndex(where: { $0.id == articleId }) {
            items[index].title = title
            saveArticles(items)
        }

        guard let key = detailKey() else { return }
        var details = cachedArticleDetails()
        if let detail = details[articleId] {
            details[articleId] = ArticleDetailResponse(
                articleId: detail.articleId,
                title: title,
                sentenceCount: detail.sentenceCount,
                sentences: detail.sentences
            )
            guard let data = try? JSONEncoder().encode(details) else { return }
            userDefaults.set(data, forKey: key)
        }
    }

    private func cachedArticleDetails() -> [String: ArticleDetailResponse] {
        guard let key = detailKey(),
              let data = userDefaults.data(forKey: key),
              let cache = try? JSONDecoder().decode([String: ArticleDetailResponse].self, from: data) else {
            return [:]
        }
        return cache
    }

    private func listKey() -> String? {
        UserScopedStorage.defaultsKey("article.list.cache")
    }

    private func detailKey() -> String? {
        UserScopedStorage.defaultsKey("article.detail.cache")
    }
}
