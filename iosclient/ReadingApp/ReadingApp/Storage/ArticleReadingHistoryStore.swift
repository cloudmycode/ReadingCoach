import Foundation

/// One local record per account/article, retaining only each sentence's latest completed attempt.
final class ArticleReadingHistoryStore {
    static let shared = ArticleReadingHistoryStore()
    private let defaults: UserDefaults

    struct Entry: Codable {
        let sentenceId: Int?
        let index: Int
        let original: String
        let result: FollowAlongResult
        let recordedAt: Date
    }

    private struct Record: Codable {
        var version = 1
        let entries: [Entry]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(articleId: String, userId: String?, sentences: [ArticleSentence]) -> [Int: Entry] {
        guard let key = storageKey(articleId: articleId, userId: userId),
              let data = defaults.data(forKey: key),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == 1 else { return [:] }
        var matched: [Int: Entry] = [:]
        for (index, sentence) in sentences.enumerated() {
            // Stable sentence IDs survive reordering; the exact source text prevents stale scores.
            // Older articles without sentence IDs can only be matched at their original position.
            if let entry = record.entries.first(where: { entry in
                guard entry.original == sentence.original else { return false }
                if let sentenceId = sentence.sentenceId { return entry.sentenceId == sentenceId }
                return entry.sentenceId == nil && entry.index == index
            }) {
                matched[index] = entry
            }
        }
        return matched
    }

    func save(_ result: FollowAlongResult, at index: Int, articleId: String, userId: String?,
              sentences: [ArticleSentence], recordedAt: Date = Date()) {
        guard sentences.indices.contains(index), let key = storageKey(articleId: articleId, userId: userId) else { return }
        var entries = load(articleId: articleId, userId: userId, sentences: sentences)
        let sentence = sentences[index]
        entries[index] = Entry(sentenceId: sentence.sentenceId, index: index, original: sentence.original,
                               result: result, recordedAt: recordedAt)
        let record = Record(entries: entries.sorted { $0.key < $1.key }.map(\.value))
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    private func storageKey(articleId: String, userId: String?) -> String? {
        UserScopedStorage.defaultsKey("article.reading-history.v1.\(articleId)", userId: userId)
    }
}
