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
    
    private let articleId: String
    private var hasLoaded = false
    private var audioTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var continuousPlaybackStartIndex = 0
    private var continuousPlaybackRun = 0
    private var durationTracker: StudyDurationTracker?
    private let onContinuousPlaybackFinished: (() -> Void)?

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
        onContinuousPlaybackFinished: (() -> Void)? = nil
    ) {
        self.articleId = articleId
        self.onContinuousPlaybackFinished = onContinuousPlaybackFinished
        if let cachedDetail = ArticleCacheStore.shared.cachedArticleDetail(articleId: articleId) {
            self.title = cachedDetail.title.isEmpty ? initialTitle : cachedDetail.title
            self.sentences = cachedDetail.sentences
            self.wordCount = cachedDetail.wordCount
            self.readSeconds = cachedDetail.readSeconds
            self.readingSpeedWpm = cachedDetail.readingSpeedWpm
            scheduleSentenceAudioPreload()
        } else {
            self.title = initialTitle
        }
    }
    
    deinit {
        audioTask?.cancel()
        preloadTask?.cancel()
        Task { @MainActor in
            ArticleAudioManager.shared.stop()
        }
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
            title = detail.title
            sentences = detail.sentences
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

    func setReadingAppActive(_ active: Bool) {
        durationTracker?.setAppActive(active)
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
        sentences[index] = updated
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
        audioTask = Task {
            do {
                isPlaying = false
                currentSentenceIndex = index
                try await playText(sentenceId: sentence.sentenceId, sentence.original, type: .original, style: .focusedSentence)
            } catch is CancellationError {
                // ignore
            } catch {
                toastMessage = error.localizedDescription
            }
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
        for index in startIndex..<sentences.count {
            if Task.isCancelled {
                playbackLog("run cancelled before sentence run=\(run) index=\(index)")
                return
            }
            let sentence = sentences[index]
            currentSentenceIndex = index
            continuousPlaybackStartIndex = index
            playbackLog("sentence started run=\(run) index=\(index) sentenceId=\(sentence.sentenceId.map(String.init) ?? "nil")")

            do {
                try await playText(
                    sentenceId: sentence.sentenceId,
                    sentence.original,
                    type: .original,
                    style: .continuousReading
                )
                playbackLog("sentence completed run=\(run) index=\(index) taskCancelled=\(Task.isCancelled)")
            } catch is CancellationError {
                playbackLog("sentence cancelled run=\(run) index=\(index)")
                return
            } catch {
                playbackLog("sentence failed run=\(run) index=\(index) error=\(String(describing: error))")
                toastMessage = error.localizedDescription
                return
            }
        }

        playbackLog("run finished run=\(run) taskCancelled=\(Task.isCancelled)")
        finishCompletedSequence()
        playbackLog("waiting before next article run=\(run) seconds=2")
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            playbackLog("next article cancelled during wait run=\(run)")
            return
        }
        guard !Task.isCancelled, run == continuousPlaybackRun else { return }
        playbackLog("request next article run=\(run)")
        onContinuousPlaybackFinished?()
    }

    private func finishCompletedSequence() {
        ArticleAudioManager.shared.stop(reason: "detail-sequence-completed")
        currentSentenceIndex = nil
        currentPlayingType = nil
        continuousPlaybackStartIndex = 0
        isPlaying = false
        playbackMode = nil
    }
    
    private func playText(
        sentenceId: Int?,
        _ text: String,
        type: SentenceAudioType,
        style: SpeechPlaybackStyle
    ) async throws {
        currentPlayingType = type
        try await ArticleAudioManager.shared.speak(sentenceId: sentenceId, text: text, type: type, style: style)
    }
    
    private func stopVoiceReading(resetPosition: Bool) {
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
