import Foundation

// Isolate storage in a temporary directory; use production models, caches and view models.
enum UserScopedStorage {
    static var currentUserId: String? = "a"
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("list-cache-tests-\(UUID())")
    static func applicationSupportUserDirectory(userId: String) -> URL {
        let url = root.appendingPathComponent(userId)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
func isCancellationError(_ error: Error) -> Bool { error is CancellationError }
enum StudyDurationFormat {
    static func minutesText(_ seconds: Int) -> String { "\(seconds / 60) 分钟" }
}
@MainActor final class WordBookAPI {
    static let shared = WordBookAPI()
    var fetch: () async throws -> WordBookListResponse = { WordBookListResponse(items: []) }
    func listEntries() async throws -> WordBookListResponse { try await fetch() }
    func deleteEntry(entryId: Int64) async throws { }
}
@MainActor final class ReviewAPI {
    static let shared = ReviewAPI()
    var summary = WordReviewTodaySummary(dueCount: 1, completedCount: 0, dailyLimit: 30, recommendedCount: 1, streakDays: 0)
    var pending: [WordReviewTaskItem] = []
    var fail = false
    var fetchSummary: (() async throws -> WordReviewTodaySummary)?
    func todaySummary() async throws -> WordReviewTodaySummary {
        if let fetchSummary { return try await fetchSummary() }
        if fail { throw URLError(.notConnectedToInternet) }
        return summary
    }
    func listTasks(status: String) async throws -> WordReviewTasksResponse {
        if fail { throw URLError(.notConnectedToInternet) }
        return WordReviewTasksResponse(items: status == "pending" ? pending : [], status: status)
    }
    func submitResult(entryId: Int64, result: String) async throws -> Bool { true }
}
@MainActor final class ArticleAudioManager {
    enum Kind { case original, translation }
    enum Style { case focusedSentence }
    static let shared = ArticleAudioManager()
    func stop() { }
    func speak(sentenceId: Int?, text: String, type: Kind, style: Style) async throws { }
    func preload(sentenceId: Int?, text: String, type: Kind, style: Style) async { }
}
struct WordBookPlaybackOptions {
    let playWord = false, playWordTranslation = false, playSentence = false, playSentenceTranslation = false
    var hasAnyEnabled: Bool { false }
    static func loadFromUserDefaults() -> Self { Self() }
}
struct ArticleAPI {
    static let shared = Self()
    func explainWord(articleId: String, sentenceId: Int, word: String) async throws -> SentenceWordExplanationResponse { throw URLError(.notConnectedToInternet) }
}
struct WordExplanationCacheStore {
    static let shared = Self()
    func save(sentenceId: Int, word: String, partOfSpeech: String, meaning: String, tip: String) { }
}
struct StatsAPI {
    static let shared = Self()
    func reportReviewDuration(seconds: Int) async throws { }
}
final class StudyDurationTracker {
    init(report: @escaping (Int) async -> Void) { }
    func start() { }
    func stop() { }
    func noteInteraction() { }
    func setAppActive(_ active: Bool) { }
}
enum AppIconBadgeManager {
    static func refresh(pendingCount: Int) async { }
    static func clear() async { }
}

@main struct ListCacheTests {
    static func item(_ id: Int64) -> WordBookAPIItem {
        WordBookAPIItem(entryId: id, articleId: "article", sentenceId: 11, word: "hello", normalizedWord: "hello",
                        sentenceOriginal: "Hello there.", sentenceTranslation: "你好", partOfSpeech: "", meaning: "你好", tip: "",
                        reviewStep: 1, nextReviewAt: "2026-09-23", masteryStatus: "learning", lastReviewedAt: nil,
                        lookedUpAt: "2026-09-22T02:00:00Z")
    }
    @MainActor static func main() async throws {
        defer { try? FileManager.default.removeItem(at: UserScopedStorage.root) }
        let wordsAPI = WordBookAPI.shared
        let words = WordBookViewModel()
        precondition(!words.hasLoadedEntries && words.entries.isEmpty)
        wordsAPI.fetch = { throw URLError(.notConnectedToInternet) }
        await words.refreshEntries()
        precondition(!words.hasLoadedEntries && words.loadError != nil)
        wordsAPI.fetch = { WordBookListResponse(items: [item(1)]) }
        await words.refreshEntries()
        WordBookStore.shared.reloadForCurrentUser()
        let restoredWords = WordBookViewModel()
        precondition(restoredWords.hasLoadedEntries && restoredWords.entries.first?.entryId == 1, "Show persisted words before any network request")
        wordsAPI.fetch = { throw URLError(.notConnectedToInternet) }
        await restoredWords.refreshEntries()
        precondition(restoredWords.entries.first?.entryId == 1 && restoredWords.loadError != nil)

        // The last request to start wins even if an earlier request returns later.
        var oldWords: CheckedContinuation<WordBookListResponse, Error>?
        wordsAPI.fetch = { try await withCheckedThrowingContinuation { oldWords = $0 } }
        let firstFetch = Task { await restoredWords.refreshEntries() }
        while oldWords == nil { await Task.yield() }
        wordsAPI.fetch = { WordBookListResponse(items: [item(2)]) }
        await restoredWords.refreshEntries()
        oldWords!.resume(returning: WordBookListResponse(items: [item(1)]))
        await firstFetch.value
        precondition(restoredWords.entries.first?.entryId == 2 && WordBookStore.shared.allEntries().first?.entryId == 2)

        let reviewAPI = ReviewAPI.shared
        reviewAPI.pending = [WordReviewTaskItem(logId: nil, entryId: 2, word: "hello", normalizedWord: "hello", partOfSpeech: "", meaning: "你好", tip: "",
            sentenceOriginal: "Hello there.", sentenceTranslation: "你好", articleId: "article", articleTitle: "Article", sentenceId: 11,
            reviewStep: 1, masteryStatus: "learning", nextReviewAt: "2026-09-22", lastReviewedAt: nil, result: nil)]
        let reviews = ReviewTasksViewModel()
        precondition(!reviews.hasLoadedTasks)
        reviewAPI.fail = true
        await reviews.loadTasks()
        precondition(!reviews.hasLoadedTasks && reviews.loadError != nil)
        reviewAPI.fail = false
        await reviews.loadTasks()
        let restoredReviews = ReviewTasksViewModel()
        precondition(restoredReviews.hasLoadedTasks && restoredReviews.isShowingCachedTasks && restoredReviews.pendingTasks.count == 1)
        reviewAPI.fail = true
        await restoredReviews.loadTasks()
        precondition(restoredReviews.pendingTasks.count == 1 && restoredReviews.loadError != nil)

        // In-flight responses must not overwrite another account's UI or disk cache.
        reviewAPI.fail = false
        var oldSummary: CheckedContinuation<WordReviewTodaySummary, Error>?
        reviewAPI.fetchSummary = { try await withCheckedThrowingContinuation { oldSummary = $0 } }
        let oldReviewRequest = Task { await restoredReviews.loadTasks() }
        while oldSummary == nil { await Task.yield() }
        oldWords = nil
        wordsAPI.fetch = { try await withCheckedThrowingContinuation { oldWords = $0 } }
        let oldWordRequest = Task { await restoredWords.refreshEntries() }
        while oldWords == nil { await Task.yield() }
        UserScopedStorage.currentUserId = "b"
        WordBookStore.shared.reloadForCurrentUser()
        precondition(!WordBookViewModel().hasLoadedEntries && !ReviewTasksViewModel().hasLoadedTasks)
        oldSummary!.resume(returning: reviewAPI.summary)
        oldWords!.resume(returning: WordBookListResponse(items: [item(3)]))
        await oldReviewRequest.value
        await oldWordRequest.value
        precondition(ReviewTaskCache.load(userID: "b") == nil && WordBookStore.shared.allEntries().isEmpty)

        // Successful empty responses replace stale snapshots; failures never do.
        UserScopedStorage.currentUserId = "a"
        WordBookStore.shared.reloadForCurrentUser()
        wordsAPI.fetch = { WordBookListResponse(items: []) }
        await restoredWords.refreshEntries()
        precondition(restoredWords.hasLoadedEntries && restoredWords.entries.isEmpty && WordBookStore.shared.allEntries().isEmpty)
        reviewAPI.fetchSummary = nil
        reviewAPI.pending = []
        await restoredReviews.loadTasks()
        let emptyReviews = ReviewTasksViewModel()
        precondition(emptyReviews.hasLoadedTasks && emptyReviews.pendingTasks.isEmpty)
        precondition(ReviewTaskCache.load(userID: nil) == nil)
        print("PASS: immediate persistent cache, cold-start loading/error, offline retention, newest response wins, account isolation, authoritative empty lists.")
    }
}
