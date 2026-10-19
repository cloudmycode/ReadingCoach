import Foundation

enum StudyDurationFormat {
    static func minutesText(_ seconds: Int) -> String { "\(seconds)" }
}

enum UserScopedStorage {
    static func defaultsKey(_ base: String, userId: String?) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return "readingcoach.\(userId).\(base)"
    }
}

@main struct ArticleReadingHistoryChecks {
    static func sentence(_ id: Int?, _ original: String) -> ArticleSentence {
        var json: [String: Any] = ["original": original, "translation": "", "is_favorite": false]
        if let id { json["sentence_id"] = id }
        return try! JSONDecoder().decode(ArticleSentence.self, from: JSONSerialization.data(withJSONObject: json))
    }

    static func main() {
        let suite = "ReadingHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ArticleReadingHistoryStore(defaults: defaults)
        let source = [sentence(10, "Hello world"), sentence(11, "Good morning")]
        let first = FollowAlongResult(reference: "Hello world", transcript: "hello world")
        let second = FollowAlongResult(reference: "Good morning", transcript: "good")
        let time = Date(timeIntervalSince1970: 100)
        store.save(first, at: 0, articleId: "1", userId: "alice", sentences: source, recordedAt: time)
        let reopened = ArticleReadingHistoryStore(defaults: UserDefaults(suiteName: suite)!)
        var loaded = reopened.load(articleId: "1", userId: "alice", sentences: source)
        precondition(loaded.count == 1 && loaded[0]?.result == first && loaded[0]?.recordedAt == time)
        store.save(second, at: 1, articleId: "1", userId: "alice", sentences: source)
        loaded = reopened.load(articleId: "1", userId: "alice", sentences: source)
        precondition(loaded.count == 2 && loaded[1]?.result.score == 5)
        precondition(reopened.load(articleId: "2", userId: "alice", sentences: source).isEmpty)
        precondition(reopened.load(articleId: "1", userId: "bob", sentences: source).isEmpty)
        store.save(second, at: 0, articleId: "1", userId: "bob", sentences: source)
        precondition(reopened.load(articleId: "1", userId: "alice", sentences: source)[0]?.result == first)
        precondition(reopened.load(articleId: "1", userId: nil, sentences: source).isEmpty)
        store.save(first, at: 0, articleId: "1", userId: nil, sentences: source)

        // Stable IDs follow reordering, but a changed source or replaced sentence must not inherit a score.
        let reordered = reopened.load(articleId: "1", userId: "alice", sentences: source.reversed())
        precondition(reordered[1]?.result == first && reordered[0]?.result == second)
        precondition(reopened.load(articleId: "1", userId: "alice", sentences: [sentence(10, "Changed"), source[1]]).count == 1)
        precondition(reopened.load(articleId: "1", userId: "alice", sentences: [sentence(99, "Hello world")]).isEmpty)
        let missing = FollowAlongResult(reference: "Hello world", transcript: "", failureMessage: "未评分")
        store.save(missing, at: 0, articleId: "1", userId: "alice", sentences: source)
        loaded = reopened.load(articleId: "1", userId: "alice", sentences: source)
        precondition(loaded.count == 2 && loaded[0]?.result == missing && loaded[1]?.result == second)

        let legacy = [sentence(nil, "Hello world"), sentence(nil, "Good morning")]
        store.save(first, at: 0, articleId: "legacy", userId: "alice", sentences: legacy)
        precondition(reopened.load(articleId: "legacy", userId: "alice", sentences: legacy).count == 1)
        precondition(reopened.load(articleId: "legacy", userId: "alice", sentences: legacy.reversed()).isEmpty)
        defaults.set(Data("broken".utf8), forKey: UserScopedStorage.defaultsKey("article.reading-history.v1.bad", userId: "alice")!)
        precondition(reopened.load(articleId: "bad", userId: "alice", sentences: source).isEmpty)
        print("PASS: local history round trip, partial progress, latest attempt replacement, transcript/date/unscored results, article/account isolation, reordered/edited/missing-ID sentences, corrupt storage")
    }
}
