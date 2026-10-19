import Foundation
import Combine

/// Only drafts, pending listening receipts and idempotency keys live locally; scores stay on the server.
@MainActor
final class ReadingQuizStore: ObservableObject {
    private struct Submission: Codable {
        let requestID: String
        let answers: [ReadingAnswer]
    }
    private struct Draft: Codable {
        var hash = ""
        var listened: Set<Int> = []
        var answers = Array(repeating: "", count: 5)
        var submission: Submission?
        var attemptID: Int?
        var ignoredAttemptID = 0
    }
    let articleID: String
    @Published private(set) var title = ""
    @Published private(set) var source: [ReadingSource] = []
    @Published private var draft = Draft()
    @Published private(set) var paper: ReadingPaper?
    @Published private(set) var attempt: ReadingAttempt?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    private let api: ReadingServing
    private let defaults: UserDefaults
    private let userID: String?
    private let currentUser: @MainActor () -> String?
    private let storageKey: String?

    init(articleID: String, api: ReadingServing? = nil, defaults: UserDefaults = .standard,
         currentUser: @escaping @MainActor () -> String? = { UserScopedStorage.currentUserId }) {
        self.articleID = articleID
        self.api = api ?? ReadingAPI.shared
        self.defaults = defaults
        self.currentUser = currentUser
        userID = currentUser()
        storageKey = userID.map { "readingcoach.\($0).quiz.v2.\(articleID)" }
        if let storageKey, let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Draft.self, from: data), saved.answers.count == 5 { draft = saved }
    }
    var contextID: String { draft.hash }
    var articleText: String { source.map(\.text).joined(separator: "\n\n") }
    var questions: [ReadingQuizQuestion] { paper?.questions ?? [] }
    var answers: [String] { draft.answers }
    var answeredCount: Int { answers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }
    var emptyIndices: [Int] { answers.indices.filter { answers[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var isGrading: Bool { isSubmitting || attempt?.isPending == true }
    var answersLocked: Bool { isGrading || draft.submission != nil || attempt != nil }
    var canOpen: Bool { isCurrent(draft.hash) && paper?.isReady == true && paper?.unlocked == true }
    var listenedCount: Int { Set(paper?.completedSentenceIDs ?? []).union(draft.listened).count }
    var listeningComplete: Bool { !source.isEmpty && listenedCount >= source.count }
    var isPreparing: Bool { paper?.status == "queued" || paper?.status == "running" }
    var statusText: String {
        if let attempt, attempt.isPending { return "答案已提交，正在批改；退出后仍会继续。" }
        if attempt?.status == "failed" { return "批改暂时失败，答案已保留，可重试。" }
        if draft.submission != nil { return "提交结果尚未确认，答案已锁定；重试不会重复提交。" }
        if paper?.status == "failed" { return "题目暂未生成成功，听读记录已保留，请重试。" }
        if canOpen { return "全文音频已听完 · 5 道开放题 · 80 分过关" }
        if listeningComplete {
            if paper?.isReady == true { return "听读记录正在同步…" }
            guard let paper else { return "音频已听完，正在获取小测状态…" }
            if let progress = paper.preparation {
                if progress.attempts > 1 {
                    return "题目正在自动重试（第 \(progress.attempts) / \(progress.maxAttempts) 次），不用重新听读。"
                }
                if Date().timeIntervalSince1970 - progress.startedAt >= 90 {
                    return "题目准备时间较长，可稍后回来；听读记录已保留。"
                }
            }
            return paper.status == "queued" ? "音频已听完，小测正在排队准备…" : "音频已听完，正在出题与检查题目…"
        }
        return "请先听完全文音频（已听完 \(listenedCount) / \(source.count) 句）"
    }
    private func isCurrent(_ hash: String) -> Bool { userID != nil && currentUser() == userID && draft.hash == hash }

    func prepare(title: String, source: [ReadingSource]) {
        self.title = title
        self.source = source.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hash = ReadingSource.hash(self.source)
        if draft.hash != hash {
            draft = Draft(hash: hash)
            paper = nil
            attempt = nil
            errorMessage = nil
        }
        save()
    }
    func recordListened(sentenceID: Int) {
        guard userID != nil, currentUser() == userID, source.contains(where: { $0.id == sentenceID }) else { return }
        draft.listened.insert(sentenceID)
        save()
    }
    func answer(_ text: String, at index: Int) {
        guard answers.indices.contains(index), !answersLocked else { return }
        // Server limits by Unicode scalar count; use the same limit for typed and dictated answers.
        draft.answers[index] = String(String.UnicodeScalarView(text.unicodeScalars.prefix(2000)))
        save()
    }
    func refresh() async {
        let hash = draft.hash
        guard !isRefreshing, !source.isEmpty, isCurrent(hash) else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var value = try await api.paper(articleID: articleID)
            guard isCurrent(hash) else { return }
            guard value.contentHash == hash else {
                paper = nil
                errorMessage = "文章原文已更新，请退出文章后重新打开，再听读新版原文。"
                return
            }
            paper = value
            let pending = draft.listened.subtracting(value.completedSentenceIDs)
            for id in pending.sorted() {
                try Task.checkCancellation()
                guard isCurrent(hash) else { return }
                try await api.completeListening(articleID: articleID, paper: value, sentenceID: id)
            }
            if !pending.isEmpty {
                value = try await api.paper(articleID: articleID)
                guard isCurrent(hash), value.contentHash == hash else { return }
                paper = value
            }
            let attempts = try await api.attempts(articleID: articleID)
            guard isCurrent(hash) else { return }
            var latest = attempts.filter { $0.paperID == value.id && $0.id > draft.ignoredAttemptID }.max { $0.id < $1.id }
            if latest == nil, let id = draft.attemptID, id > draft.ignoredAttemptID {
                let saved = try await api.attempt(id: id)
                guard isCurrent(hash) else { return }
                if saved.paperID == value.id { latest = saved }
            }
            if let latest,
               draft.submission == nil || latest.isPending || latest.answers == draft.submission?.answers {
                apply(latest)
            }
            errorMessage = nil
        } catch is CancellationError { }
        catch { if isCurrent(hash) { errorMessage = error.localizedDescription } }
    }
    /// Called by visible pages only; cancellation stops polling, never the server task.
    func watch() async {
        repeat {
            if attempt?.isPending == true { await pollAttempt() } else { await refresh() }
            if Task.isCancelled || userID == nil || currentUser() != userID { return }
            let seconds = (attempt?.isPending == true || paper?.status == "queued" || paper?.status == "running") ? 4 : 15
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        } while !Task.isCancelled
    }
    func submit() async {
        let hash = draft.hash
        guard isCurrent(hash), canOpen, let paper, !isSubmitting, attempt == nil else { return }
        if draft.submission == nil {
            draft.submission = Submission(requestID: UUID().uuidString, answers: questions.map { .init(questionID: $0.id, answer: answers[$0.index].trimmingCharacters(in: .whitespacesAndNewlines)) })
            save() // Persist before sending, including when the response is lost or the app quits.
        }
        guard let submission = draft.submission else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let accepted = try await api.submit(articleID: articleID, paperID: paper.id, requestID: submission.requestID, answers: submission.answers)
            guard isCurrent(hash) else { return }
            apply(accepted)
        } catch is CancellationError { }
        catch {
            guard isCurrent(hash) else { return }
            if case APIError.http(let status, _) = error, (400..<500).contains(status) {
                draft.submission = nil
                save()
                await refresh()
            }
            errorMessage = error.localizedDescription
        }
    }
    func pollAttempt() async {
        let hash = draft.hash
        guard isCurrent(hash), let id = attempt?.id else { return }
        do {
            let value = try await api.attempt(id: id)
            guard isCurrent(hash), attempt?.id == id else { return }
            apply(value)
        } catch is CancellationError { }
        catch { if isCurrent(hash) { errorMessage = error.localizedDescription } }
    }
    func retrySystemTask() async {
        let hash = draft.hash
        guard isCurrent(hash), !isSubmitting else { return }
        let kind: String
        let id: Int
        if let attempt, attempt.status == "failed" { kind = "attempts"; id = attempt.id }
        else if let paper, paper.status == "failed" { kind = "papers"; id = paper.id }
        else { await refresh(); return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await api.retry(kind: kind, id: id)
            guard isCurrent(hash) else { return }
            if kind == "attempts" { await pollAttempt() } else { await refresh() }
        } catch { if isCurrent(hash) { errorMessage = error.localizedDescription } }
    }
    func retry() {
        guard let attempt, attempt.isResult else { return }
        draft.ignoredAttemptID = attempt.id
        draft.attemptID = nil
        draft.submission = nil
        draft.answers = Array(repeating: "", count: 5)
        self.attempt = nil
        errorMessage = nil
        save()
    }
    private func apply(_ value: ReadingAttempt) {
        attempt = value
        draft.attemptID = value.id
        draft.submission = nil
        for answer in value.answers where (1...5).contains(answer.questionID) { draft.answers[answer.questionID - 1] = answer.answer }
        save()
    }
    private func save() {
        guard let storageKey, currentUser() == userID, let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
