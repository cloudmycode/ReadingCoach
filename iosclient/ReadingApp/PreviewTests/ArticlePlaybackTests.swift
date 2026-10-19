import Foundation

enum UserScopedStorage {
    static var currentUserId: String?
    static func defaultsKey(_ base: String, userId: String?) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return "readingcoach.\(userId).\(base)"
    }
}

// Exercise the production detail view model with deterministic audio and in-memory dependencies.
enum SentenceAudioType { case original, translation }
enum SpeechPlaybackStyle { case focusedSentence, continuousReading, followAlong }
enum ArticleAudioError: LocalizedError {
    case emptyText
    var errorDescription: String? { "empty" }
}
enum APIError: Error { case server(message: String) }
enum StudyDurationFormat { static func minutesText(_ seconds: Int) -> String { "\(seconds)" } }
final class StudyDurationTracker {
    init(_ report: @escaping (Int) async -> Void) {}
    func start() {}
    func stop() {}
    func noteInteraction() {}
    func setAppActive(_ active: Bool) {}
}
extension Notification.Name { static let wordBookDidChange = Notification.Name("test.wordBookDidChange") }
struct ReadingSource { let id: Int; let text: String }
@MainActor final class ReadingQuizStore {
    var contextID = "test"
    var listened: [Int] = []
    init(articleID: String) {}
    func prepare(title: String, source: [ReadingSource]) {}
    func recordListened(sentenceID: Int) { listened.append(sentenceID) }
}
final class ArticleCacheStore {
    static let shared = ArticleCacheStore()
    var articles: [ArticleItem] = []
    var details: [String: ArticleDetailResponse] = [:]
    func cachedArticles() -> [ArticleItem] { articles }
    func cachedArticleDetail(articleId: String) -> ArticleDetailResponse? { details[articleId] }
    func saveArticleDetail(_ detail: ArticleDetailResponse, articleId: String) {}
}
final class WordExplanationCacheStore {
    static let shared = WordExplanationCacheStore()
    func cachedExplanation(sentenceId: Int, word: String) -> SentenceWordExplanationResponse? { nil }
    func save(sentenceId: Int, word: String, partOfSpeech: String, meaning: String, tip: String) {}
    func removeExplanations(sentenceId: Int) {}
}
final class ArticleAPI {
    static let shared = ArticleAPI()
    var detailResponse: ArticleDetailResponse?
    func getArticleDetail(articleId: String) async throws -> ArticleDetailResponse {
        guard let detailResponse else { fatalError("Unused") }
        return detailResponse
    }
    func reportReadDuration(articleId: String, seconds: Int) async throws {}
    func explainWord(articleId: String, sentenceId: Int, word: String) async throws -> SentenceWordExplanationResponse { fatalError("Unused") }
    func askSentence(articleId: String, sentenceId: Int, question: String) async throws -> SentenceQuestionResponse { fatalError("Unused") }
    func updateSentence(articleId: String, sentenceId: Int, original: String) async throws -> ArticleSentence { fatalError("Unused") }
}
@MainActor final class ArticleAudioManager {
    static let shared = ArticleAudioManager()
    var spoken: [String] = []
    var stops = 0
    var fail = false
    var cancelPlayback = false
    var lastFinished = Date.distantPast
    var duration: TimeInterval = 0.08
    var events: [String] = []
    var isCuePlaying = false
    var styles: [SpeechPlaybackStyle] = []
    var cueFinishedAt: [Date] = []
    func stop(reason: String = "", deactivateAudioSession: Bool = true) {
        stops += 1
        if reason == "follow-along-listen" { precondition(!deactivateAudioSession) }
    }
    func playArticleStartCue() async {}
    func playFollowAlongCue() async throws {
        precondition(SpeechInputManager.activeRecorders == 1, "The microphone must already be running when the beep starts")
        events.append("beep-start")
        isCuePlaying = true
        defer { isCuePlaying = false }
        try await Task.sleep(for: .milliseconds(30))
        events.append("beep-end")
        cueFinishedAt.append(Date())
    }
    func preload(sentenceId: Int?, text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) async {}
    func speakWithDuration(sentenceId: Int?, text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) async throws -> TimeInterval {
        if cancelPlayback { throw CancellationError() }
        if fail { throw URLError(.badServerResponse) }
        spoken.append(text)
        styles.append(style)
        try await Task.sleep(nanoseconds: 10_000_000)
        lastFinished = Date()
        events.append("demo-end")
        return duration
    }
}

@MainActor final class SpeechInputManager {
    static var transcript = "English 3"
    static var failPermission = false
    static var failRecognition = false
    static var failStart = false
    static var finalizeDelay: Duration = .zero
    static var started: [Date] = []
    static var capturedDurations: [TimeInterval] = []
    static var activeRecorders = 0
    private var startedAt: Date?
    init(localeIdentifier: String) { precondition(localeIdentifier == "en-US") }
    func prepareRecording() async throws {
        if Self.failPermission { throw URLError(.noPermissionsToReadFile) }
    }
    func startRecording(allowsPlayback: Bool = false) async throws {
        precondition(allowsPlayback, "The microphone session must allow the beep to play")
        if Self.failStart { throw URLError(.cannotOpenFile) }
        ArticleAudioManager.shared.events.append("record-start")
        startedAt = Date()
        Self.started.append(startedAt!)
        Self.activeRecorders += 1
    }
    func finishRecording() async throws -> String {
        ArticleAudioManager.shared.events.append("record-end")
        Self.capturedDurations.append(Date().timeIntervalSince(ArticleAudioManager.shared.cueFinishedAt.last!))
        cancelRecording()
        try await Task.sleep(for: Self.finalizeDelay)
        if Self.failRecognition { throw URLError(.timedOut) }
        return Self.transcript
    }
    func cancelRecording() {
        if startedAt != nil { Self.activeRecorders -= 1 }
        startedAt = nil
    }
}

@main struct ArticlePlaybackChecks {
    @MainActor static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
        precondition(predicate(), "Playback did not reach the expected state")
    }
    @MainActor static func model(_ id: String, translation: String = "中文") -> ArticleDetailViewModel {
        let result = ArticleDetailViewModel(articleId: id, initialTitle: id)
        result.sentences = [try! JSONDecoder().decode(ArticleSentence.self, from: JSONSerialization.data(withJSONObject: [
            "sentence_id": 1, "original": "English \(id)", "translation": translation, "is_favorite": false
        ]))]
        return result
    }
    @MainActor static func main() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ArticleReadingLanguage.storageKey)
        defer {
            if let previous { defaults.set(previous, forKey: ArticleReadingLanguage.storageKey) }
            else { defaults.removeObject(forKey: ArticleReadingLanguage.storageKey) }
        }
        defaults.set(ArticleReadingLanguage.englishAndChinese.rawValue, forKey: ArticleReadingLanguage.storageKey)
        ArticleCacheStore.shared.articles = (1...3).map { number in
            ArticleItem(id: "\(number)", articleId: number, title: "Article \(number)", sentenceCount: 1,
                        wordCount: 2, readCount: 0, createdAt: "2026-10-\(20 - number)", lastReadAt: nil)
        }
        let audio = ArticleAudioManager.shared

        // Natural completion must keep emitting the next item, including the second -> third hop.
        for id in ["1", "2", "3"] {
            var vm: ArticleDetailViewModel? = model(id)
            vm!.toggleVoiceReading(startingAt: 0)
            try await waitUntil { !vm!.isPlaying }
            let expectedNext = id == "3" ? nil : String(Int(id)! + 1)
            precondition(vm!.nextArticleToRead?.id == expectedNext)
            precondition(vm!.quizStore.listened == [1], "Translation must not double-count listening")
            if expectedNext != nil {
                precondition(Date().timeIntervalSince(audio.lastFinished) >= 0.99, "Missing one-second pause")
            }
            vm!.stopVoiceReading() // Same cleanup as the departing detail view.
            let stopsBeforeDeinit = audio.stops
            vm = nil
            try await Task.sleep(nanoseconds: 20_000_000)
            precondition(audio.stops == stopsBeforeDeinit, "Old model deinit must not stop the next player")
        }
        precondition(audio.spoken == ["English 1", "中文", "English 2", "中文", "English 3", "中文"])

        // Pausing or leaving while waiting for the next article must cancel navigation.
        for stopInsteadOfPause in [false, true] {
            let vm = model("1")
            let count = audio.spoken.count
            vm.toggleVoiceReading(startingAt: 0)
            try await waitUntil { audio.spoken.count == count + 2 }
            try await Task.sleep(nanoseconds: 30_000_000)
            if stopInsteadOfPause { vm.stopVoiceReading() }
            else { vm.toggleVoiceReading(startingAt: nil) }
            try await Task.sleep(nanoseconds: 1_100_000_000)
            precondition(vm.nextArticleToRead == nil && !vm.isPlaying)
        }

        let failed = model("1")
        audio.fail = true
        failed.toggleVoiceReading(startingAt: 0)
        try await waitUntil { !failed.isPlaying }
        precondition(failed.toastMessage != nil && failed.nextArticleToRead == nil)
        audio.fail = false

        // A shared-player cancellation must not leave the button stuck on Pause.
        audio.cancelPlayback = true
        for continuous in [true, false] {
            let stopped = model("1")
            if continuous { stopped.toggleVoiceReading(startingAt: 0) }
            else { stopped.playSentence(at: 0) }
            let stopCount = audio.stops
            try await waitUntil { stopped.playbackMode == nil }
            precondition(!stopped.isPlaying && stopped.currentSentenceIndex == nil)
            precondition(stopped.toastMessage == nil && stopped.nextArticleToRead == nil)
            precondition(audio.stops == stopCount, "Cancellation cleanup must not stop the replacement player's audio")
        }
        audio.cancelPlayback = false

        let single = model("1")
        single.playSentence(at: 0)
        try await waitUntil { single.playbackMode == nil }
        precondition(single.nextArticleToRead == nil)

        audio.spoken = []
        defaults.set(ArticleReadingLanguage.english.rawValue, forKey: ArticleReadingLanguage.storageKey)
        let englishOnly = model("3")
        englishOnly.toggleVoiceReading(startingAt: 0)
        try await waitUntil { !englishOnly.isPlaying }
        precondition(audio.spoken == ["English 3"])
        precondition(audio.styles.last == .continuousReading)

        audio.spoken = []
        defaults.set(ArticleReadingLanguage.englishAndChinese.rawValue, forKey: ArticleReadingLanguage.storageKey)
        let missingTranslation = model("3", translation: " \n ")
        missingTranslation.toggleVoiceReading(startingAt: 0)
        try await waitUntil { !missingTranslation.isPlaying }
        precondition(audio.spoken == ["English 3"])
        print("PASS: articles 1 -> 2 -> 3, one-second gap, end of list, pause/exit cancellation, errors/single taps do not navigate, safe old-model cleanup, bilingual order and missing translation")

        defaults.set(ArticleReadingLanguage.followAlong.rawValue, forKey: ArticleReadingLanguage.storageKey)
        audio.spoken = []
        audio.events = []
        audio.styles = []
        let following = model("3")
        following.sentences.append(following.sentences[0])
        following.toggleVoiceReading(startingAt: 0)
        try await waitUntil { !following.isPlaying }
        precondition(audio.spoken == ["English 3", "English 3"], "Following never plays Chinese")
        precondition(audio.styles == [.followAlong, .followAlong], "Only follow-along uses the slower demonstration style")
        precondition(following.followAlongResults.count == 2)
        precondition(following.followAlongResults[0]?.score == 10 && following.followAlongResults[1]?.score == 10)
        precondition(SpeechInputManager.capturedDurations.allSatisfy { $0 >= audio.duration * 1.3 && $0 < audio.duration * 1.3 + 0.2 })
        let sentenceEvents = ["demo-end", "record-start", "beep-start", "beep-end", "record-end"]
        precondition(audio.events == sentenceEvents + sentenceEvents)
        precondition(SpeechInputManager.activeRecorders == 0)

        let cancelledCue = model("3")
        let recordingsBeforeCue = SpeechInputManager.started.count
        cancelledCue.toggleVoiceReading(startingAt: 0)
        try await waitUntil { audio.isCuePlaying }
        cancelledCue.toggleVoiceReading(startingAt: nil)
        try await Task.sleep(for: .milliseconds(80))
        precondition(SpeechInputManager.started.count == recordingsBeforeCue + 1)
        precondition(SpeechInputManager.activeRecorders == 0 && !cancelledCue.isFollowAlongMicrophoneReady)
        precondition(cancelledCue.followAlongResults.isEmpty && !cancelledCue.isPlaying)

        SpeechInputManager.failStart = true
        let failedMicrophone = model("3")
        audio.events = []
        failedMicrophone.toggleVoiceReading(startingAt: 0)
        try await waitUntil { !failedMicrophone.isPlaying }
        precondition(!audio.events.contains("beep-start"), "Never signal readiness if the microphone failed to start")
        precondition(failedMicrophone.toastMessage != nil && SpeechInputManager.activeRecorders == 0)
        SpeechInputManager.failStart = false

        // Pause, page departure and backgrounding release the microphone without scoring/navigating.
        for action in 0...2 {
            let vm = model("1")
            vm.toggleVoiceReading(startingAt: 0)
            try await waitUntil { vm.followAlongDeadline != nil }
            if action == 0 { vm.toggleVoiceReading(startingAt: nil) }
            else if action == 1 { vm.stopVoiceReading() }
            else { vm.setReadingAppActive(false) }
            try await Task.sleep(for: .milliseconds(150))
            precondition(!vm.isPlaying && vm.followAlongResults.isEmpty && vm.nextArticleToRead == nil)
            precondition(vm.followAlongDeadline == nil && SpeechInputManager.activeRecorders == 0)
        }

        SpeechInputManager.failPermission = true
        let denied = model("3")
        let beforeDenied = audio.spoken.count
        denied.toggleVoiceReading(startingAt: 0)
        try await waitUntil { !denied.isPlaying }
        precondition(denied.toastMessage != nil && audio.spoken.count == beforeDenied)
        SpeechInputManager.failPermission = false

        SpeechInputManager.finalizeDelay = .milliseconds(200)
        let interruptedScore = model("3")
        interruptedScore.toggleVoiceReading(startingAt: 0)
        try await waitUntil { interruptedScore.isScoringFollowAlong }
        interruptedScore.toggleVoiceReading(startingAt: nil)
        interruptedScore.toggleVoiceReading(startingAt: 0)
        try await waitUntil { !interruptedScore.isPlaying }
        precondition(interruptedScore.followAlongResults[0]?.score == 10)
        precondition(SpeechInputManager.activeRecorders == 0 && !interruptedScore.isScoringFollowAlong)
        SpeechInputManager.finalizeDelay = .zero

        for failure in [false, true] {
            SpeechInputManager.transcript = ""
            SpeechInputManager.failRecognition = failure
            let vm = model("3")
            vm.toggleVoiceReading(startingAt: 0)
            try await waitUntil { !vm.isPlaying }
            precondition(vm.followAlongResults[0] != nil && vm.followAlongResults[0]?.score == nil)
            precondition(SpeechInputManager.activeRecorders == 0)
        }
        SpeechInputManager.failRecognition = false
        SpeechInputManager.transcript = "English 1"
        let completedPractice = model("1")
        completedPractice.sentences.append(completedPractice.sentences[0])
        completedPractice.toggleVoiceReading(startingAt: 0)
        try await waitUntil { !completedPractice.isPlaying }
        try await Task.sleep(for: .milliseconds(1100))
        precondition(completedPractice.nextArticleToRead == nil, "Follow-along must stay on this article even when a next article exists")
        precondition(completedPractice.followAlongResults.count == 2)
        precondition(completedPractice.followAlongResults.values.allSatisfy { $0.score == 10 })
        precondition(completedPractice.lastFollowAlongIndex == 1)

        // A settings change during the final practice turn must not discard its result by navigating.
        let changedDuringPractice = model("1")
        changedDuringPractice.toggleVoiceReading(startingAt: 0)
        try await waitUntil { changedDuringPractice.followAlongDeadline != nil }
        defaults.set(ArticleReadingLanguage.english.rawValue, forKey: ArticleReadingLanguage.storageKey)
        try await waitUntil { !changedDuringPractice.isPlaying }
        precondition(changedDuringPractice.nextArticleToRead == nil && changedDuringPractice.followAlongResults[0]?.score == 10)

        let changedDuringGap = model("1")
        let spokenBeforeGap = audio.spoken.count
        changedDuringGap.toggleVoiceReading(startingAt: 0)
        try await waitUntil { audio.spoken.count > spokenBeforeGap }
        try await Task.sleep(for: .milliseconds(30))
        defaults.set(ArticleReadingLanguage.followAlong.rawValue, forKey: ArticleReadingLanguage.storageKey)
        try await waitUntil { !changedDuringGap.isPlaying }
        precondition(changedDuringGap.nextArticleToRead == nil)
        let suite = "ReadingHistoryIntegration.\(UUID().uuidString)"
        let historyDefaults = UserDefaults(suiteName: suite)!
        defer {
            historyDefaults.removePersistentDomain(forName: suite)
            UserScopedStorage.currentUserId = nil
            ArticleCacheStore.shared.details = [:]
            ArticleAPI.shared.detailResponse = nil
        }
        UserScopedStorage.currentUserId = "alice"
        let history = ArticleReadingHistoryStore(defaults: historyDefaults)
        ArticleCacheStore.shared.details["1"] = ArticleDetailResponse(articleId: 1, title: "Saved", sentenceCount: 1, sentences: model("1").sentences)
        let persisted = ArticleDetailViewModel(articleId: "1", initialTitle: "Saved", readingHistory: history)
        persisted.toggleVoiceReading(startingAt: 0)
        try await waitUntil { !persisted.isPlaying }
        persisted.stopVoiceReading()
        let restored = ArticleDetailViewModel(articleId: "1", initialTitle: "Saved", readingHistory: ArticleReadingHistoryStore(defaults: historyDefaults))
        precondition(restored.followAlongResults[0]?.score == 10 && restored.lastFollowAlongDate != nil)
        precondition(restored.lastFollowAlongIndex == 0 && !restored.isPlaying)
        restored.toggleVoiceReading(startingAt: 0)
        try await waitUntil { restored.followAlongDeadline != nil }
        restored.stopVoiceReading()
        precondition(restored.followAlongResults[0]?.score == 10, "Cancelling a retry must keep the last completed score")
        UserScopedStorage.currentUserId = "bob"
        restored.readingAccountDidChange()
        precondition(restored.followAlongResults.isEmpty && restored.lastFollowAlongDate == nil)
        let otherAccount = ArticleDetailViewModel(articleId: "1", initialTitle: "Saved", readingHistory: history)
        precondition(otherAccount.followAlongResults.isEmpty)
        UserScopedStorage.currentUserId = "alice"
        restored.readingAccountDidChange()
        precondition(restored.followAlongResults[0]?.score == 10)
        ArticleAPI.shared.detailResponse = ArticleCacheStore.shared.details["1"]
        ArticleCacheStore.shared.details = [:]
        let coldOpen = ArticleDetailViewModel(articleId: "1", initialTitle: "Cold", readingHistory: history)
        precondition(coldOpen.followAlongResults.isEmpty)
        await coldOpen.loadArticle()
        precondition(coldOpen.followAlongResults[0]?.score == 10 && coldOpen.lastFollowAlongDate != nil)
        print("PASS: detail model saves each result, restores on cached open, retains completed score on cancelled retry, isolates accounts")
        print("PASS: slow follow-along demos, microphone-before-beep without session deactivation, 130% duration after beep, cue cancellation, pause/exit/background cleanup, denied permission, silence/error unscored, practice stays on article with all scores, mode changes prevent unwanted navigation")
    }
}
