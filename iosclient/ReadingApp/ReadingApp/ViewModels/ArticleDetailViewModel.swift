//
//  ArticleDetailViewModel.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation
import Combine

@MainActor
final class ArticleDetailViewModel: ObservableObject {
    enum PlaybackMode {
        case continuous
        case singleSentence
    }

    @Published var title: String
    @Published var sentences: [ArticleSentence] = []
    @Published var wordCount: Int = 0
    @Published var readSeconds: Int = 0
    @Published var readingSpeedWpm: Int?
    @Published var isLoading: Bool = false
    @Published var toastMessage: String?
    @Published var isPlaying: Bool = false
    @Published var currentSentenceIndex: Int?
    @Published var currentPlayingType: SentenceAudioType?
    @Published private(set) var playbackMode: PlaybackMode?
    @Published private(set) var nextArticleToRead: ArticleItem?
    @Published private(set) var followAlongResults: [Int: FollowAlongResult] = [:]
    @Published private(set) var followAlongDeadline: Date?
    @Published private(set) var isScoringFollowAlong = false
    @Published private(set) var isFollowingAlong = false
    @Published private(set) var isFollowAlongMicrophoneReady = false
    @Published private(set) var lastFollowAlongIndex: Int?
    @Published private(set) var lastFollowAlongDate: Date?
    
    let quizStore: ReadingQuizStore
    private let articleId: String
    private let historyUserId: String?
    private let readingHistory: ArticleReadingHistoryStore
    private var hasLoaded = false
    private var audioTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var continuousPlaybackStartIndex = 0
    private var continuousPlaybackRun = 0
    private var durationTracker: StudyDurationTracker?
    private let followAlongInput = SpeechInputManager(localeIdentifier: "en-US")
    private var isReadingAppActive = true

    private func playbackLog(_ message: String) {
#if DEBUG
        print("[ArticlePlayback][Sequence] \(message)")
#endif
    }

    var readingMetaText: String {
        var parts: [String] = []
        if wordCount > 0 {
            parts.append("\(wordCount) 词")
        }
        if readSeconds > 0 {
            parts.append(StudyDurationFormat.minutesText(readSeconds))
        }
        if let readingSpeedWpm {
            parts.append("\(readingSpeedWpm) 词/分")
        }
        return parts.joined(separator: " · ")
    }

    init(
        articleId: String,
        initialTitle: String,
        readingHistory: ArticleReadingHistoryStore? = nil
    ) {
        self.articleId = articleId
        self.historyUserId = UserScopedStorage.currentUserId
        self.readingHistory = readingHistory ?? .shared
        self.quizStore = ReadingQuizStore(articleID: articleId)
        if let cachedDetail = ArticleCacheStore.shared.cachedArticleDetail(articleId: articleId) {
            self.title = cachedDetail.title.isEmpty ? initialTitle : cachedDetail.title
            self.sentences = cachedDetail.sentences
            self.wordCount = cachedDetail.wordCount
            self.readSeconds = cachedDetail.readSeconds
            self.readingSpeedWpm = cachedDetail.readingSpeedWpm
            restoreReadingHistory()
            prepareReadingQuiz()
            scheduleSentenceAudioPreload()
        } else {
            self.title = initialTitle
        }
    }
    
    deinit {
        audioTask?.cancel()
        preloadTask?.cancel()
        // The view stops audio on disappearance. A deferred global stop here
        // can interrupt the next article after its player has already started.
    }
    
    func loadArticleIfNeeded() async {
        guard !hasLoaded else { return }
        await loadArticle()
        hasLoaded = true
        startReadingDurationTracking()
    }
    
    func loadArticle() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let detail = try await ArticleAPI.shared.getArticleDetail(articleId: articleId)
            if sentences.map(\.original) != detail.sentences.map(\.original) ||
                sentences.map(\.sentenceId) != detail.sentences.map(\.sentenceId) {
                stopVoiceReading()
                followAlongResults = [:]
                lastFollowAlongIndex = nil
            }
            title = detail.title
            sentences = detail.sentences
            restoreReadingHistory()
            prepareReadingQuiz()
            wordCount = detail.wordCount
            readSeconds = detail.readSeconds
            readingSpeedWpm = detail.readingSpeedWpm
            ArticleCacheStore.shared.saveArticleDetail(detail, articleId: articleId)
            scheduleSentenceAudioPreload()
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    func noteReadingInteraction() {
        durationTracker?.noteInteraction()
    }

    func readingAccountDidChange() {
        stopVoiceReading()
        restoreReadingHistory()
    }

    private func restoreReadingHistory() {
        guard historyUserId == UserScopedStorage.currentUserId else {
            followAlongResults = [:]
            lastFollowAlongIndex = nil
            lastFollowAlongDate = nil
            return
        }
        let entries = readingHistory.load(articleId: articleId, userId: historyUserId, sentences: sentences)
        followAlongResults = entries.mapValues(\.result)
        let latest = entries.max { $0.value.recordedAt < $1.value.recordedAt }
        lastFollowAlongIndex = latest?.key
        lastFollowAlongDate = latest?.value.recordedAt
    }

    func setReadingAppActive(_ active: Bool) {
        isReadingAppActive = active
        durationTracker?.setAppActive(active)
        if !active, isFollowingAlong {
            pauseContinuousPlayback()
        }
    }

    func stopReadingDurationTracking() {
        durationTracker?.stop()
        durationTracker = nil
    }

    private func startReadingDurationTracking() {
        stopReadingDurationTracking()
        let trackedArticleId = articleId
        durationTracker = StudyDurationTracker { [weak self] seconds in
            guard let self else { return }
            do {
                try await ArticleAPI.shared.reportReadDuration(articleId: trackedArticleId, seconds: seconds)
                self.readSeconds += seconds
                if self.readSeconds >= 30, self.wordCount > 0 {
                    self.readingSpeedWpm = Int((Double(self.wordCount) / (Double(self.readSeconds) / 60.0)).rounded())
                }
            } catch {
                // 时长上报失败不打断阅读
            }
        }
        durationTracker?.start()
    }
    
    func explainWord(sentenceId: Int, word: String) async throws -> SentenceWordExplanationResponse {
        let response: SentenceWordExplanationResponse
        if let cached = WordExplanationCacheStore.shared.cachedExplanation(sentenceId: sentenceId, word: word) {
            response = SentenceWordExplanationResponse(
                word: cached.word.isEmpty ? word : cached.word,
                partOfSpeech: cached.partOfSpeech,
                meaning: cached.meaning,
                tip: cached.tip,
                sentenceId: sentenceId,
                articleId: articleId
            )
        } else {
            response = try await ArticleAPI.shared.explainWord(articleId: articleId, sentenceId: sentenceId, word: word)
            WordExplanationCacheStore.shared.save(
                sentenceId: sentenceId,
                word: response.word.isEmpty ? word : response.word,
                partOfSpeech: response.partOfSpeech,
                meaning: response.meaning,
                tip: response.tip
            )
        }

        // 生词本由服务端在 explain-word 时写入 user_word_book。
        NotificationCenter.default.post(name: .wordBookDidChange, object: nil)
        return response
    }

    func askQuestion(sentenceId: Int, question: String) async throws -> SentenceQuestionResponse {
        try await ArticleAPI.shared.askSentence(articleId: articleId, sentenceId: sentenceId, question: question)
    }

    func updateSentence(at index: Int, original: String) async throws {
        guard sentences.indices.contains(index), let sentenceId = sentences[index].sentenceId else {
            throw APIError.server(message: "句子信息无效")
        }

        let updated = try await ArticleAPI.shared.updateSentence(
            articleId: articleId,
            sentenceId: sentenceId,
            original: original
        )
        stopVoiceReading()
        followAlongResults[index] = nil
        sentences[index] = updated
        restoreReadingHistory()
        prepareReadingQuiz()
        WordExplanationCacheStore.shared.removeExplanations(sentenceId: sentenceId)
        ArticleCacheStore.shared.saveArticleDetail(
            ArticleDetailResponse(
                articleId: cachedNumericArticleId,
                title: title,
                sentenceCount: sentences.count,
                wordCount: wordCount,
                readSeconds: readSeconds,
                readingSpeedWpm: readingSpeedWpm,
                sentences: sentences
            ),
            articleId: articleId
        )
        scheduleSentenceAudioPreload()
    }

    private var cachedNumericArticleId: Int {
        ArticleCacheStore.shared.cachedArticleDetail(articleId: articleId)?.articleId ?? 0
    }
    
    func playSentence(at index: Int) {
        guard sentences.indices.contains(index) else { return }
        let sentence = sentences[index]
        guard !sentence.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            toastMessage = ArticleAudioError.emptyText.errorDescription
            return
        }
        
        stopContinuousPlayback(resetProgress: true)
        stopVoiceReading(resetPosition: true)
        playbackMode = .singleSentence
        let run = continuousPlaybackRun
        let fingerprint = quizStore.contextID
        audioTask = Task {
            do {
                isPlaying = true
                currentSentenceIndex = index
                try await playText(sentenceId: sentence.sentenceId, sentence.original, type: .original, style: .focusedSentence)
                guard !Task.isCancelled, run == continuousPlaybackRun else { return }
                recordListenedSentence(at: index, fingerprint: fingerprint)
            } catch is CancellationError {
                if run == continuousPlaybackRun { clearPlaybackState() }
                return
            } catch {
                guard run == continuousPlaybackRun else { return }
                toastMessage = error.localizedDescription
            }
            guard run == continuousPlaybackRun else { return }
            isPlaying = false
            currentSentenceIndex = nil
            currentPlayingType = nil
            playbackMode = nil
        }
    }
    
    func toggleVoiceReading(startingAt preferredIndex: Int?) {
        playbackLog("toggle preferredIndex=\(preferredIndex.map(String.init) ?? "nil") mode=\(String(describing: playbackMode)) isPlaying=\(isPlaying)")
        if playbackMode == .continuous, isPlaying {
            pauseContinuousPlayback()
        } else {
            startContinuousPlayback(startingAt: preferredIndex)
        }
    }
    
    func stopVoiceReading() {
        stopContinuousPlayback(resetProgress: true)
        stopVoiceReading(resetPosition: true)
    }
    
    private func startContinuousPlayback(startingAt preferredIndex: Int?) {
        nextArticleToRead = nil
        guard !sentences.isEmpty else {
            toastMessage = "暂无可播放的句子"
            return
        }
        if let preferredIndex, sentences.indices.contains(preferredIndex) {
            continuousPlaybackStartIndex = preferredIndex
        } else if continuousPlaybackStartIndex >= sentences.count {
            continuousPlaybackStartIndex = 0
        }
        let shouldPlayArticleStartCue = currentSentenceIndex == nil
        playbackMode = .continuous
        stopVoiceReading(resetPosition: false)
        isPlaying = true
        continuousPlaybackRun += 1
        let run = continuousPlaybackRun
        let startIndex = continuousPlaybackStartIndex
        playbackLog("run started run=\(run) startIndex=\(startIndex) sentenceCount=\(sentences.count)")
        audioTask = Task { [weak self] in
            if shouldPlayArticleStartCue {
                await ArticleAudioManager.shared.playArticleStartCue()
                guard !Task.isCancelled else { return }
            }
            await self?.playSequence(startingAt: startIndex, run: run)
        }
    }
    
    private func playSequence(startingAt startIndex: Int, run: Int) async {
        let fingerprint = quizStore.contextID
        var lastSentenceWasFollowAlong = false
        for index in startIndex..<sentences.count {
            if Task.isCancelled || run != continuousPlaybackRun {
                playbackLog("run cancelled before sentence run=\(run) index=\(index)")
                return
            }
            let sentence = sentences[index]
            // Apply settings at sentence boundaries so changing the menu never interrupts audio.
            let readingLanguage = ArticleReadingLanguage.saved
            lastSentenceWasFollowAlong = readingLanguage == .followAlong
            currentSentenceIndex = index
            continuousPlaybackStartIndex = index
            playbackLog("sentence started run=\(run) index=\(index) sentenceId=\(sentence.sentenceId.map(String.init) ?? "nil")")

            do {
                if readingLanguage == .followAlong {
                    try await followAlongInput.prepareRecording()
                    try Task.checkCancellation()
                    guard run == continuousPlaybackRun else { return }
                    guard isReadingAppActive else { throw CancellationError() }
                    isFollowingAlong = true
                    // Keep the previous completed result until this attempt finishes.
                }
                let duration = try await playText(
                    sentenceId: sentence.sentenceId,
                    sentence.original,
                    type: .original,
                    style: readingLanguage == .followAlong ? .followAlong : .continuousReading
                )
                guard !Task.isCancelled, run == continuousPlaybackRun else { return }
                recordListenedSentence(at: index, fingerprint: fingerprint)
                if readingLanguage == .followAlong {
                    try await followAlong(sentence: sentence, index: index, duration: duration, run: run)
                    guard !Task.isCancelled, run == continuousPlaybackRun else { return }
                }
                if readingLanguage == .englishAndChinese,
                   !sentence.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try await playText(
                        sentenceId: sentence.sentenceId,
                        sentence.translation,
                        type: .translation,
                        style: .continuousReading
                    )
                    guard !Task.isCancelled, run == continuousPlaybackRun else { return }
                }
                playbackLog("sentence completed run=\(run) index=\(index) taskCancelled=\(Task.isCancelled)")
            } catch is CancellationError {
                playbackLog("sentence cancelled run=\(run) index=\(index)")
                // The shared player can be stopped without this task being cancelled.
                // Reset this run's UI, but never stop a newer owner's player.
                if run == continuousPlaybackRun { clearPlaybackState() }
                return
            } catch {
                playbackLog("sentence failed run=\(run) index=\(index) error=\(String(describing: error))")
                guard run == continuousPlaybackRun else { return }
                toastMessage = error.localizedDescription
                finishCompletedSequence()
                return
            }
        }

        guard !Task.isCancelled, run == continuousPlaybackRun else { return }
        playbackLog("run finished run=\(run) taskCancelled=\(Task.isCancelled)")
        // Stay on the finished practice article so every sentence's score remains available.
        if lastSentenceWasFollowAlong || ArticleReadingLanguage.saved == .followAlong {
            finishCompletedSequence()
            return
        }
        guard let nextArticle = ArticleCacheStore.shared.cachedArticles().nextArticle(after: articleId) else {
            finishCompletedSequence()
            return
        }
        // Keep the same cancellable playback task during the inter-article pause.
        // Pausing, leaving this page or starting another sentence cancels the transition.
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled, run == continuousPlaybackRun,
              fingerprint == quizStore.contextID else { return }
        finishCompletedSequence()
        guard ArticleReadingLanguage.saved != .followAlong else { return }
        nextArticleToRead = nextArticle
    }

    private func finishCompletedSequence() {
        ArticleAudioManager.shared.stop(reason: "detail-sequence-completed")
        clearPlaybackState()
    }

    private func clearPlaybackState() {
        stopFollowAlong()
        currentSentenceIndex = nil
        currentPlayingType = nil
        continuousPlaybackStartIndex = 0
        isPlaying = false
        playbackMode = nil
    }
    
    @discardableResult
    private func playText(
        sentenceId: Int?,
        _ text: String,
        type: SentenceAudioType,
        style: SpeechPlaybackStyle
    ) async throws -> TimeInterval {
        currentPlayingType = type
        return try await ArticleAudioManager.shared.speakWithDuration(sentenceId: sentenceId, text: text, type: type, style: style)
    }

    private func followAlong(sentence: ArticleSentence, index: Int, duration: TimeInterval, run: Int) async throws {
        guard isReadingAppActive else { throw CancellationError() }
        currentPlayingType = nil
        // Hand the active session directly to the microphone, without a deactivate/reactivate gap.
        ArticleAudioManager.shared.stop(reason: "follow-along-listen", deactivateAudioSession: false)
        try await followAlongInput.startRecording(allowsPlayback: true)
        try Task.checkCancellation()
        guard run == continuousPlaybackRun, isReadingAppActive else { throw CancellationError() }
        isFollowAlongMicrophoneReady = true
        // The beep means the microphone is already running, not that it is about to start.
        try await ArticleAudioManager.shared.playFollowAlongCue()
        try Task.checkCancellation()
        guard run == continuousPlaybackRun else { throw CancellationError() }
        let followAlongDuration = duration * 1.3
        followAlongDeadline = Date().addingTimeInterval(followAlongDuration)
        try await Task.sleep(for: .seconds(followAlongDuration))
        try Task.checkCancellation()
        guard run == continuousPlaybackRun else { throw CancellationError() }
        followAlongDeadline = nil
        isFollowAlongMicrophoneReady = false
        isScoringFollowAlong = true
        let result: FollowAlongResult
        do {
            let transcript = try await followAlongInput.finishRecording()
            result = FollowAlongResult(reference: sentence.original, transcript: transcript)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Recognition failure isn't a bad pronunciation score and shouldn't stop the article.
            result = FollowAlongResult(reference: sentence.original, transcript: "",
                                       failureMessage: "未识别到有效语音或识别失败，未评分")
        }
        try Task.checkCancellation()
        guard run == continuousPlaybackRun else { throw CancellationError() }
        guard historyUserId == UserScopedStorage.currentUserId else { throw CancellationError() }
        isScoringFollowAlong = false
        followAlongResults[index] = result
        lastFollowAlongIndex = index
        let recordedAt = Date()
        lastFollowAlongDate = recordedAt
        readingHistory.save(result, at: index, articleId: articleId, userId: historyUserId,
                            sentences: sentences, recordedAt: recordedAt)
        isFollowingAlong = false
    }

    private func stopFollowAlong() {
        followAlongInput.cancelRecording()
        followAlongDeadline = nil
        isScoringFollowAlong = false
        isFollowingAlong = false
        isFollowAlongMicrophoneReady = false
    }
    
    private func stopVoiceReading(resetPosition: Bool) {
        stopFollowAlong()
        continuousPlaybackRun += 1
        playbackLog("stop voice resetPosition=\(resetPosition) mode=\(String(describing: playbackMode)) currentIndex=\(currentSentenceIndex.map(String.init) ?? "nil")")
        audioTask?.cancel()
        audioTask = nil
        ArticleAudioManager.shared.stop(reason: "detail-stop-voice")
        currentPlayingType = nil
        if resetPosition {
            currentSentenceIndex = nil
        }
        isPlaying = false
    }

    private func pauseContinuousPlayback() {
        guard playbackMode == .continuous else { return }
        stopFollowAlong()
        continuousPlaybackRun += 1
        playbackLog("pause currentIndex=\(currentSentenceIndex.map(String.init) ?? "nil")")
        audioTask?.cancel()
        audioTask = nil
        ArticleAudioManager.shared.stop(reason: "detail-pause-continuous")
        currentPlayingType = nil
        isPlaying = false
        if let currentSentenceIndex {
            continuousPlaybackStartIndex = currentSentenceIndex
        }
    }

    private func stopContinuousPlayback(resetProgress: Bool) {
        if playbackMode == .continuous {
            stopFollowAlong()
            playbackLog("stop continuous resetProgress=\(resetProgress) currentIndex=\(currentSentenceIndex.map(String.init) ?? "nil")")
            audioTask?.cancel()
            audioTask = nil
            ArticleAudioManager.shared.stop(reason: "detail-stop-continuous")
            currentPlayingType = nil
            isPlaying = false
            playbackMode = nil
        }
        if resetProgress {
            continuousPlaybackStartIndex = 0
        }
    }

    private func prepareReadingQuiz() {
        quizStore.prepare(title: title, source: sentences.compactMap { sentence in
            sentence.sentenceId.map { ReadingSource(id: $0, text: sentence.original) }
        })
    }

    private func recordListenedSentence(at index: Int, fingerprint: String) {
        guard fingerprint == quizStore.contextID else { return }
        if sentences.indices.contains(index), let id = sentences[index].sentenceId {
            quizStore.recordListened(sentenceID: id)
        }
    }

    private func scheduleSentenceAudioPreload() {
        let pendingSentences = sentences.compactMap { sentence -> (Int?, String)? in
            let text = sentence.original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return (sentence.sentenceId, text)
        }
        guard !pendingSentences.isEmpty else { return }

        preloadTask?.cancel()
        preloadTask = Task {
            for (sentenceId, text) in pendingSentences {
                if Task.isCancelled { return }
                await ArticleAudioManager.shared.preload(
                    sentenceId: sentenceId,
                    text: text,
                    type: .original,
                    style: .focusedSentence
                )
            }
        }
    }
}
