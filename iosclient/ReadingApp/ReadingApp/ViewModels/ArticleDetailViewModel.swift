//
//  ArticleDetailViewModel.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation
import Combine
import AVFoundation

@MainActor
final class ArticleDetailViewModel: NSObject, ObservableObject {
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
    private var audioPlayer: AVAudioPlayer?
    private var audioContinuation: CheckedContinuation<Void, Error>?
    private let audioOrder: [SentenceAudioType] = [.original, .translation]
    
    init(articleId: String, initialTitle: String) {
        self.articleId = articleId
        self.title = initialTitle
        super.init()
    }
    
    deinit {
        // 同步清理资源，避免异步任务在对象释放后执行
        audioTask?.cancel()
        audioTask = nil
        audioPlayer?.stop()
        audioPlayer?.delegate = nil  // 关键：清除 delegate 引用，避免崩溃
        audioPlayer = nil
        if let continuation = audioContinuation {
            continuation.resume(throwing: CancellationError())
            audioContinuation = nil
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
    
    func toggleFavorite(sentence: ArticleSentence) {
        guard let index = sentences.firstIndex(where: { $0.id == sentence.id }) else { return }
        sentences[index].isFavorite.toggle()
        // TODO: 调用后台收藏接口
    }
    
    func playSentence(at index: Int) {
        guard sentences.indices.contains(index) else { return }
        guard let sentenceId = sentences[index].sentenceId else {
            toastMessage = ArticleAudioError.missingSentenceID.errorDescription
            return
        }
        
        stopVoiceReading(resetPosition: true)
        audioTask = Task {
            do {
                currentSentenceIndex = index
                try await playAudio(for: sentenceId, type: .original)
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
            guard let sentenceId = sentence.sentenceId else { continue }
            currentSentenceIndex = index
            
            for type in audioOrder {
                if Task.isCancelled { return }
                do {
                    try await playAudio(for: sentenceId, type: type)
                } catch is CancellationError {
                    return
                } catch {
                    toastMessage = error.localizedDescription
                    break
                }
            }
        }
        stopVoiceReading(resetPosition: true)
    }
    
    private func playAudio(for sentenceId: Int, type: SentenceAudioType) async throws {
        let fileURL = try await ArticleAudioManager.shared.fetchAudioURL(sentenceId: sentenceId, type: type)
        try await withCheckedThrowingContinuation { continuation in
            do {
                let player = try AVAudioPlayer(contentsOf: fileURL)
                audioPlayer?.stop()
                audioPlayer = player
                audioContinuation = continuation
                currentPlayingType = type
                player.delegate = self
                player.prepareToPlay()
                player.play()
            } catch {
                continuation.resume(throwing: ArticleAudioError.playbackFailed)
            }
        }
    }
    
    private func stopVoiceReading(resetPosition: Bool) {
        audioTask?.cancel()
        audioTask = nil
        audioPlayer?.stop()
        audioPlayer?.delegate = nil  // 关键：清除 delegate 引用，避免在对象释放后回调导致崩溃
        audioPlayer = nil
        if let continuation = audioContinuation {
            continuation.resume(throwing: CancellationError())
            audioContinuation = nil
        }
        currentPlayingType = nil
        if resetPosition {
            currentSentenceIndex = nil
        }
        isPlaying = false
    }
}

extension ArticleDetailViewModel: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // 安全检查：确保 continuation 存在且有效
        guard let continuation = audioContinuation else { return }
        continuation.resume()
        audioContinuation = nil
        currentPlayingType = nil
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        // 安全检查：确保 continuation 存在且有效
        guard let continuation = audioContinuation else { return }
        continuation.resume(throwing: error ?? ArticleAudioError.playbackFailed)
        audioContinuation = nil
        currentPlayingType = nil
    }
}

