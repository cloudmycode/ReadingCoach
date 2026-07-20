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
    @Published var title: String
    @Published var sentences: [ArticleSentence] = []
    @Published var isLoading: Bool = false
    @Published var toastMessage: String?
    @Published var isPlaying: Bool = false
    @Published var currentSentenceIndex: Int?
    @Published var currentPlayingType: SentenceAudioType?
    
    private let articleId: String
    private var hasLoaded = false
    private var audioTask: Task<Void, Never>?
    init(articleId: String, initialTitle: String) {
        self.articleId = articleId
        self.title = initialTitle
    }
    
    deinit {
        audioTask?.cancel()
        Task { @MainActor in
            ArticleAudioManager.shared.stop()
        }
    }
    
    func loadArticleIfNeeded() async {
        guard !hasLoaded else { return }
        await loadArticle()
        hasLoaded = true
    }
    
    func loadArticle() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let detail = try await ArticleAPI.shared.getArticleDetail(articleId: articleId)
            title = detail.title
            sentences = detail.sentences
        } catch {
            toastMessage = error.localizedDescription
        }
    }
    
    func explainWord(sentenceId: Int, word: String) async throws -> SentenceWordExplanationResponse {
        if let cached = WordExplanationCacheStore.shared.cachedExplanation(sentenceId: sentenceId, word: word) {
            return SentenceWordExplanationResponse(
                word: cached.word.isEmpty ? word : cached.word,
                partOfSpeech: cached.partOfSpeech,
                meaning: cached.meaning,
                tip: cached.tip,
                sentenceId: sentenceId,
                articleId: articleId
            )
        }

        let response = try await ArticleAPI.shared.explainWord(articleId: articleId, sentenceId: sentenceId, word: word)
        WordExplanationCacheStore.shared.save(
            sentenceId: sentenceId,
            word: response.word.isEmpty ? word : response.word,
            partOfSpeech: response.partOfSpeech,
            meaning: response.meaning,
            tip: response.tip
        )
        return response
    }

    func askQuestion(sentenceId: Int, question: String) async throws -> SentenceQuestionResponse {
        try await ArticleAPI.shared.askSentence(articleId: articleId, sentenceId: sentenceId, question: question)
    }
    
    func playSentence(at index: Int) {
        guard sentences.indices.contains(index) else { return }
        let sentence = sentences[index]
        guard !sentence.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            toastMessage = ArticleAudioError.emptyText.errorDescription
            return
        }
        
        stopVoiceReading(resetPosition: true)
        audioTask = Task {
            do {
                currentSentenceIndex = index
                try await playText(sentenceId: sentence.sentenceId, sentence.original, type: .original, style: .focusedSentence)
            } catch is CancellationError {
                // ignore
            } catch {
                toastMessage = error.localizedDescription
            }
            currentSentenceIndex = nil
            currentPlayingType = nil
        }
    }
    
    func toggleVoiceReading() {
        if isPlaying {
            stopVoiceReading()
        } else {
            startVoiceReading()
        }
    }
    
    func stopVoiceReading() {
        stopVoiceReading(resetPosition: true)
    }
    
    private func startVoiceReading() {
        guard !sentences.isEmpty else {
            toastMessage = "暂无可播放的句子"
            return
        }
        stopVoiceReading(resetPosition: false)
        isPlaying = true
        audioTask = Task { [weak self] in
            await self?.playSequence()
        }
    }
    
    private func playSequence() async {
        for (index, sentence) in sentences.enumerated() {
            if Task.isCancelled { return }
            currentSentenceIndex = index

            do {
                try await playText(
                    sentenceId: sentence.sentenceId,
                    sentence.original,
                    type: .original,
                    style: .continuousReading
                )
            } catch is CancellationError {
                return
            } catch {
                toastMessage = error.localizedDescription
                break
            }
        }
        stopVoiceReading(resetPosition: true)
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
        audioTask?.cancel()
        audioTask = nil
        ArticleAudioManager.shared.stop()
        currentPlayingType = nil
        if resetPosition {
            currentSentenceIndex = nil
        }
        isPlaying = false
    }
}
