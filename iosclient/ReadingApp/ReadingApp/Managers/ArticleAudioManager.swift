//
//  ArticleAudioManager.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/27.
//

import Foundation
import AVFoundation
import CryptoKit
import Combine

enum SentenceAudioType: String, CaseIterable {
    case original = "original"
    case translation = "translation"
}

enum SpeechPlaybackStyle {
    case focusedSentence
    case continuousReading
    case followAlong
}

enum ArticleAudioError: LocalizedError {
    case emptyText
    case synthesisFailed
    case playbackInterrupted
    case playbackStalled

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "该句子暂时没有可朗读内容"
        case .synthesisFailed:
            return "语音生成失败，请稍后重试"
        case .playbackInterrupted:
            return "朗读已中断，请稍后重试"
        case .playbackStalled:
            return "播放已停止响应，请点播放重试当前句"
        }
    }
}

@MainActor
final class ArticleAudioManager: NSObject, ObservableObject {
    @Published private(set) var currentWord: SpokenWordHighlight?
    private var wordTrackingTask: Task<Void, Never>?
    private var playbackWatchdog: Task<Void, Never>?
    private var audioSessionObservers: [NSObjectProtocol] = []
    private var playbackGeneration = UUID()
    static let shared = ArticleAudioManager()

    private enum EdgeTTSConfig {
        static let outputFormat = "audio-24khz-48kbitrate-mono-mp3"
    }

    private let fileManager = FileManager.default
    private var audioPlayer: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Error>?
    private var activeWebSocketTask: URLSessionWebSocketTask?
    private var warmingCacheKeys: Set<String> = []
    private var playbackAttempt = 0
    private var activePlaybackAttempt: Int?
    private var isAudioSessionConfigured = false

    override init() {
        super.init()
        audioSessionObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
                self.handleAudioSessionInterruption(reason: "system-interruption")
            }
        })
        audioSessionObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleAudioSessionInterruption(reason: "media-services-reset")
            }
        })
    }

    private func handleAudioSessionInterruption(reason: String) {
        isAudioSessionConfigured = false
        playbackLog("audio session interrupted reason=\(reason) attempt=\(activePlaybackAttempt.map(String.init) ?? "nil")")
        if let player = audioPlayer {
            finishPlayback(player, result: .failure(ArticleAudioError.playbackInterrupted))
        }
    }

    private func playbackLog(_ message: String) {
#if DEBUG
        print("[ArticlePlayback][Audio] \(message)")
#endif
    }

    private var cacheDirectoryURL: URL? {
        guard let userId = UserScopedStorage.currentUserId else { return nil }
        return UserScopedStorage.audioCacheDirectory(userId: userId)
    }

    func speak(sentenceId: Int?, text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) async throws {
        _ = try await speakWithDuration(sentenceId: sentenceId, text: text, type: type, style: style)
    }

    /// Returns the decoded audio duration, excluding synthesis and network wait time.
    func speakWithDuration(sentenceId: Int?, text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) async throws -> TimeInterval {
        playbackAttempt += 1
        let attempt = playbackAttempt
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        playbackLog("speak requested attempt=\(attempt) sentenceId=\(sentenceId.map(String.init) ?? "nil") style=\(String(describing: style)) taskCancelled=\(Task.isCancelled)")
        guard !trimmed.isEmpty else {
            playbackLog("speak rejected attempt=\(attempt) reason=emptyText")
            throw ArticleAudioError.emptyText
        }

        // A naturally completed sentence has already released its player and
        // continuation. Keep the audio session active in that case so cached
        // sentences can transition without rapidly deactivating/reactivating the
        // session, which can interrupt the next AVAudioPlayer immediately.
        if audioPlayer != nil || playbackContinuation != nil || activeWebSocketTask != nil {
            playbackLog("speak replacing active playback attempt=\(attempt)")
            stop(reason: "speak-replacing-active-playback")
        }

        clearWordHighlight()
        let generation = UUID()
        playbackGeneration = generation
        let speech = try await ensureAudioCached(sentenceId: sentenceId, text: trimmed, type: type, style: style)
        playbackLog("audio ready attempt=\(attempt) type=\(type.rawValue) bytes=\(speech.audio.count)")
        try Task.checkCancellation()
        guard playbackGeneration == generation else { throw CancellationError() }

        if !isAudioSessionConfigured {
            try configureAudioSession()
            isAudioSessionConfigured = true
            playbackLog("audio session activated attempt=\(attempt)")
        } else {
            playbackLog("audio session reused attempt=\(attempt)")
        }
        activePlaybackAttempt = attempt
        do {
            let duration = try await playAudio(
                data: speech.audio, attempt: attempt,
                sentenceId: sentenceId, sourceText: text,
                boundaries: type == .original ? speech.boundaries : []
            )
            playbackLog("speak completed attempt=\(attempt) sentenceId=\(sentenceId.map(String.init) ?? "nil")")
            return duration
        } catch {
            playbackLog("speak failed attempt=\(attempt) error=\(String(describing: error)) taskCancelled=\(Task.isCancelled)")
            throw error
        }
    }

    func preload(sentenceId: Int?, text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let cacheKey = cacheIdentifier(sentenceId: sentenceId, text: trimmed, type: type, style: style)
        guard !warmingCacheKeys.contains(cacheKey) else { return }

        warmingCacheKeys.insert(cacheKey)
        defer { warmingCacheKeys.remove(cacheKey) }

        do {
            _ = try await ensureAudioCached(
                sentenceId: sentenceId,
                text: trimmed,
                type: type,
                style: style,
                tracksActiveTask: false
            )
        } catch {
            // Ignore warmup failures. Tap-to-play will retry on demand.
        }
    }

    func playArticleStartCue() async {
        playbackAttempt += 1
        let attempt = playbackAttempt

        if audioPlayer != nil || playbackContinuation != nil || activeWebSocketTask != nil {
            stop(reason: "article-start-cue-replacing-active-playback")
        }

        do {
            let cueURL = try articleStartCueURL()
            if !isAudioSessionConfigured {
                try configureAudioSession()
                isAudioSessionConfigured = true
            }
            activePlaybackAttempt = attempt
            playbackLog("article start cue started attempt=\(attempt)")
            try await playAudio(data: Data(contentsOf: cueURL), attempt: attempt)
            playbackLog("article start cue completed attempt=\(attempt)")
        } catch is CancellationError {
            playbackLog("article start cue cancelled attempt=\(attempt)")
        } catch {
            // A cue failure must never prevent the next article from starting.
            playbackLog("article start cue failed attempt=\(attempt) error=\(String(describing: error))")
        }
    }

    /// The microphone owns an active play-and-record session here. Do not reconfigure it.
    func playFollowAlongCue() async throws {
        try Task.checkCancellation()
        playbackAttempt += 1
        let attempt = playbackAttempt
        activePlaybackAttempt = attempt
        try await playAudio(data: makeCueWAV(isFollowAlong: true), attempt: attempt)
    }

    func stop(reason: String = "external", deactivateAudioSession: Bool = true) {
        playbackGeneration = UUID()
        playbackWatchdog?.cancel()
        playbackWatchdog = nil
        clearWordHighlight()
        playbackLog(
            "stop reason=\(reason) activeAttempt=\(activePlaybackAttempt.map(String.init) ?? "nil") " +
            "hasPlayer=\(audioPlayer != nil) isPlaying=\(audioPlayer?.isPlaying ?? false) " +
            "hasContinuation=\(playbackContinuation != nil) hasWebSocket=\(activeWebSocketTask != nil)"
        )
        activeWebSocketTask?.cancel(with: .goingAway, reason: nil)
        activeWebSocketTask = nil

        if let player = audioPlayer {
            // AVAudioPlayer may deliver a delayed delegate callback after stop().
            // Detach it before replacing the shared player/continuation so an old
            // sentence cannot complete the continuation of the next sentence.
            player.delegate = nil
            if player.isPlaying {
                player.stop()
            }
        }
        audioPlayer = nil
        activePlaybackAttempt = nil

        if let playbackContinuation {
            playbackContinuation.resume(throwing: CancellationError())
            self.playbackContinuation = nil
        }

        if deactivateAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        isAudioSessionConfigured = false
    }

    private func cacheFileURL(sentenceId: Int?, text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) -> URL? {
        guard let cacheDirectoryURL else { return nil }
        let idComponent = sentenceId.map(String.init) ?? "adhoc"
        let digest = sha256Hex("\(text)|\(type.rawValue)|\(voiceName(for: type))|\(rateValue(for: type, style: style))")
        let fileName = "sentence_\(idComponent)_\(type.rawValue)_\(digest).mp3"
        return cacheDirectoryURL.appendingPathComponent(fileName)
    }

    private func articleStartCueURL() throws -> URL {
        guard let cacheDirectoryURL else {
            throw ArticleAudioError.playbackInterrupted
        }
        let url = cacheDirectoryURL.appendingPathComponent("article_start_cue.wav")
        if !fileManager.fileExists(atPath: url.path) {
            try makeCueWAV(isFollowAlong: false).write(to: url, options: .atomic)
        }
        return url
    }

    private func makeCueWAV(isFollowAlong: Bool) -> Data {
        let sampleRate = 22_050
        let duration = isFollowAlong ? 0.16 : 0.42
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: sampleCount * MemoryLayout<Int16>.size)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let frequency = isFollowAlong ? 880.0 : (time < 0.19 ? 659.25 : 880.0)
            let localTime = isFollowAlong ? time : (time < 0.19 ? time : time - 0.19)
            let toneDuration = isFollowAlong ? duration : (time < 0.19 ? 0.19 : duration - 0.19)
            let fadeIn = min(localTime / 0.018, 1)
            let fadeOut = min((toneDuration - localTime) / 0.055, 1)
            let envelope = max(0, min(fadeIn, fadeOut))
            let value = Int16(sin(2 * Double.pi * frequency * time) * envelope * 8_500)
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { pcm.append(contentsOf: $0) }
        }

        var wav = Data()
        func appendASCII(_ value: String) {
            wav.append(contentsOf: value.utf8)
        }
        func appendUInt16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wav.append(contentsOf: $0) }
        }
        func appendUInt32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wav.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + pcm.count))
        appendASCII("WAVEfmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * MemoryLayout<Int16>.size))
        appendUInt16(UInt16(MemoryLayout<Int16>.size))
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }

    private func cacheIdentifier(sentenceId: Int?, text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) -> String {
        cacheFileURL(sentenceId: sentenceId, text: text, type: type, style: style)?.lastPathComponent
            ?? "unscoped-\(type.rawValue)"
    }

    private func ensureAudioCached(
        sentenceId: Int?,
        text: String,
        type: SentenceAudioType,
        style: SpeechPlaybackStyle,
        tracksActiveTask: Bool = true
    ) async throws -> TimedSpeechAudio {
        guard let legacyURL = cacheFileURL(sentenceId: sentenceId, text: text, type: type, style: style) else {
            throw ArticleAudioError.synthesisFailed
        }
        let cacheURL = legacyURL.deletingPathExtension().appendingPathExtension("words-v1.plist")
        if let data = try? Data(contentsOf: cacheURL),
           let speech = try? PropertyListDecoder().decode(TimedSpeechAudio.self, from: data),
           !speech.audio.isEmpty {
            playbackLog("cache hit sentenceId=\(sentenceId.map(String.init) ?? "nil") type=\(type.rawValue)")
            return speech
        }
        playbackLog("cache miss sentenceId=\(sentenceId.map(String.init) ?? "nil") type=\(type.rawValue) foreground=\(tracksActiveTask)")
        do {
            let speech = try await synthesizeAudio(text: text, type: type, style: style, tracksActiveTask: tracksActiveTask)
            try Task.checkCancellation()
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            // A single atomic record keeps the audio and boundaries from the same request.
            try encoder.encode(speech).write(to: cacheURL, options: .atomic)
            return speech
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            // Existing downloads remain playable offline; no fabricated word timings.
            if let audio = try? Data(contentsOf: legacyURL), !audio.isEmpty {
                playbackLog("legacy cache fallback sentenceId=\(sentenceId.map(String.init) ?? "nil") type=\(type.rawValue)")
                return TimedSpeechAudio(audio: audio, boundaries: [])
            }
            throw error
        }
    }

    private func synthesizeAudio(
        text: String,
        type: SentenceAudioType,
        style: SpeechPlaybackStyle,
        tracksActiveTask: Bool
    ) async throws -> TimedSpeechAudio {
        try await SpeechSynthesisPolicy.retryOnce { attempt in
            playbackLog("synthesis attempt=\(attempt)/2 idleTimeout=5s")
            return try await synthesizeAudioAttempt(text: text, type: type, style: style, tracksActiveTask: tracksActiveTask)
        }
    }

    private func synthesizeAudioAttempt(
        text: String,
        type: SentenceAudioType,
        style: SpeechPlaybackStyle,
        tracksActiveTask: Bool
    ) async throws -> TimedSpeechAudio {
        let request = try EdgeSpeechProtocol.request()
        playbackLog("connecting host=\(request.url?.host ?? "unknown") protocol=\(EdgeSpeechProtocol.tokenVersion)")
        let webSocketTask = URLSession.shared.webSocketTask(with: request)
        if tracksActiveTask {
            activeWebSocketTask = webSocketTask
        }
        let timeout = SpeechInactivityTimeout {
            webSocketTask.cancel(with: .goingAway, reason: nil)
        }
        defer {
            timeout.cancel()
            webSocketTask.cancel(with: .normalClosure, reason: nil)
            if tracksActiveTask, activeWebSocketTask === webSocketTask {
                activeWebSocketTask = nil
            }
        }
        webSocketTask.resume()

        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await sendSpeechConfig(to: webSocketTask)
                try await sendSSML(text: text, type: type, style: style, to: webSocketTask)
                return try await receiveAudioData(from: webSocketTask, timeout: timeout)
            } onCancel: {
                // Also cancel background preloads, which are not activeWebSocketTask.
                webSocketTask.cancel(with: .goingAway, reason: nil)
            }
        } catch {
            try Task.checkCancellation()
            let failure = error as NSError
            let httpStatus = (webSocketTask.response as? HTTPURLResponse)?.statusCode
            playbackLog("synthesis failed domain=\(failure.domain) code=\(failure.code) httpStatus=\(httpStatus.map(String.init) ?? "none") closeCode=\(webSocketTask.closeCode.rawValue) idleTimeout=\(timeout.didTimeOut)")
            if timeout.didTimeOut {
                throw URLError(.timedOut)
            }
            throw error
        }
    }

    private func sendSpeechConfig(to task: URLSessionWebSocketTask) async throws {
        let configMessage = """
        X-Timestamp:\(edgeDateString())
        Content-Type:application/json; charset=utf-8
        Path:speech.config

        {"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"true"},"outputFormat":"\(EdgeTTSConfig.outputFormat)"}}}}
        """
        try await task.send(.string(configMessage.replacingOccurrences(of: "\n", with: "\r\n")))
    }

    private func sendSSML(text: String, type: SentenceAudioType, style: SpeechPlaybackStyle, to task: URLSessionWebSocketTask) async throws {
        let ssmlMessage = """
        X-RequestId:\(randomHexID())
        Content-Type:application/ssml+xml
        X-Timestamp:\(edgeDateString())Z
        Path:ssml

        \(makeSSML(text: text, type: type, style: style))
        """
        try await task.send(.string(ssmlMessage.replacingOccurrences(of: "\n", with: "\r\n")))
    }

    private func receiveAudioData(from task: URLSessionWebSocketTask, timeout: SpeechInactivityTimeout) async throws -> TimedSpeechAudio {
        var audioData = Data()
        var boundaries: [SpeechWordBoundary] = []

        while true {
            try Task.checkCancellation()
            let message = try await task.receive()
            if timeout.didTimeOut { throw URLError(.timedOut) }
            switch message {
            case .string(let string):
                guard let separator = string.range(of: "\r\n\r\n") else { continue }
                let headers = string[..<separator.lowerBound].components(separatedBy: "\r\n")
                if headers.contains("Path:audio.metadata") {
                    boundaries.append(contentsOf: SpeechWordBoundary.parse(metadata: Data(string[separator.upperBound...].utf8)))
                } else if headers.contains("Path:turn.end") {
                    guard !audioData.isEmpty else { throw ArticleAudioError.synthesisFailed }
                    playbackLog("synthesis finished bytes=\(audioData.count) wordBoundaries=\(boundaries.count)")
                    return TimedSpeechAudio(audio: audioData, boundaries: boundaries)
                }
            case .data(let data):
                guard data.count >= 2 else { continue }
                let headerLength = Int(data[data.startIndex]) * 256 + Int(data[data.startIndex + 1])
                guard 2 + headerLength <= data.count,
                      let headers = String(data: data.subdata(in: 2..<(2 + headerLength)), encoding: .utf8),
                      headers.components(separatedBy: "\r\n").contains("Path:audio") else { continue }
                let chunk = data[(2 + headerLength)...]
                if !chunk.isEmpty {
                    if audioData.isEmpty { playbackLog("synthesis first audio bytes=\(chunk.count)") }
                    audioData.append(chunk)
                    timeout.receivedAudio()
                }
            @unknown default:
                continue
            }
        }
    }

    @discardableResult
    private func playAudio(
        data: Data, attempt: Int, sentenceId: Int? = nil,
        sourceText: String = "", boundaries: [SpeechWordBoundary] = []
    ) async throws -> TimeInterval {
        let player = try AVAudioPlayer(data: data)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do {
                    guard player.prepareToPlay() else { throw ArticleAudioError.playbackInterrupted }
                    player.delegate = self
                    audioPlayer = player
                    playbackContinuation = continuation
                    guard player.play() else {
                        finishPlayback(player, result: .failure(ArticleAudioError.playbackInterrupted))
                        return
                    }
                    monitorPlayback(player: player, attempt: attempt)
                    trackWords(player: player, attempt: attempt, sentenceId: sentenceId, text: sourceText, boundaries: boundaries)
                    playbackLog("player started attempt=\(attempt) duration=\(player.duration) wordBoundaries=\(boundaries.count)")
                } catch {
                    activePlaybackAttempt = nil
                    clearWordHighlight()
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.activePlaybackAttempt == attempt, let player = self.audioPlayer else { return }
                self.finishPlayback(player, result: .failure(CancellationError()))
            }
        }
        return player.duration
    }

    private func monitorPlayback(player: AVAudioPlayer, attempt: Int) {
        playbackWatchdog?.cancel()
        playbackWatchdog = Task { @MainActor [weak self, weak player] in
            var progress = AudioPlaybackProgress(now: ProcessInfo.processInfo.systemUptime)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, let player,
                      self.audioPlayer === player, self.activePlaybackAttempt == attempt else { return }
                if progress.isStalled(position: player.currentTime, now: ProcessInfo.processInfo.systemUptime) {
                    self.playbackLog("player stalled attempt=\(attempt) isPlaying=\(player.isPlaying) position=\(player.currentTime) duration=\(player.duration)")
                    self.finishPlayback(player, result: .failure(ArticleAudioError.playbackStalled))
                    return
                }
            }
        }
    }

    /// All playback exits release the waiter exactly once; stale callbacks cannot affect a new player.
    private func finishPlayback(_ player: AVAudioPlayer, result: Result<Void, Error>) {
        guard audioPlayer === player, let continuation = playbackContinuation else { return }
        playbackContinuation = nil
        playbackWatchdog?.cancel()
        playbackWatchdog = nil
        clearWordHighlight()
        player.delegate = nil
        player.stop()
        audioPlayer = nil
        activePlaybackAttempt = nil
        if case .failure = result { isAudioSessionConfigured = false }
        continuation.resume(with: result)
    }

    private func clearWordHighlight() {
        wordTrackingTask?.cancel()
        wordTrackingTask = nil
        if currentWord != nil { currentWord = nil }
    }

    private func trackWords(player: AVAudioPlayer, attempt: Int, sentenceId: Int?, text: String, boundaries: [SpeechWordBoundary]) {
        clearWordHighlight()
        let timings = SpeechWordTiming.align(boundaries, to: text)
        guard !timings.isEmpty else { return }
        wordTrackingTask = Task { @MainActor [weak self, weak player] in
            while !Task.isCancelled {
                guard let self, let player,
                      self.audioPlayer === player, self.activePlaybackAttempt == attempt else { return }
                // Sample the audio clock, never advance highlights using an estimated reading speed.
                let range = player.isPlaying ? SpeechWordTiming.activeRange(at: player.currentTime, in: timings) : nil
                let highlight = range.map { SpokenWordHighlight(sentenceId: sentenceId, sourceText: text, range: $0) }
                if self.currentWord != highlight { self.currentWord = highlight }
                do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
            }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }

    private func voiceName(for type: SentenceAudioType) -> String {
        switch type {
        case .original:
            return "en-US-EmmaMultilingualNeural"
        case .translation:
            return "zh-CN-XiaoxiaoNeural"
        }
    }

    private func rateValue(for type: SentenceAudioType, style: SpeechPlaybackStyle) -> String {
        switch (type, style) {
        case (.original, .focusedSentence):
            return "-12%"
        case (.original, .continuousReading):
            return "-5%"
        case (.original, .followAlong):
            return "-18%"
        case (.translation, .focusedSentence):
            return "-6%"
        case (.translation, .continuousReading), (.translation, .followAlong):
            return "0%"
        }
    }

    private func pitchValue(for type: SentenceAudioType) -> String {
        switch type {
        case .original:
            return "+0Hz"
        case .translation:
            return "+0Hz"
        }
    }

    private func volumeValue(for type: SentenceAudioType) -> String {
        switch type {
        case .original:
            return "+0%"
        case .translation:
            return "+0%"
        }
    }

    private func makeSSML(text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) -> String {
        let escapedText = xmlEscaped(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'><voice name='\(voiceName(for: type))'><prosody pitch='\(pitchValue(for: type))' rate='\(rateValue(for: type, style: style))' volume='\(volumeValue(for: type))'>\(escapedText)</prosody></voice></speak>"
    }

    private func edgeDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return formatter.string(from: Date())
    }

    private func randomHexID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func xmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

extension ArticleAudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Cached files make sentence transitions effectively immediate. A finish
        // callback from the previous player can therefore arrive after the next
        // player has already been installed; ignore callbacks from stale players.
        guard audioPlayer === player else {
            playbackLog("ignored stale finish callback success=\(flag)")
            return
        }
        guard playbackContinuation != nil else {
            playbackLog("finish callback missing continuation activeAttempt=\(activePlaybackAttempt.map(String.init) ?? "nil")")
            return
        }
        playbackLog("player finished attempt=\(activePlaybackAttempt.map(String.init) ?? "nil") success=\(flag) currentTime=\(player.currentTime) duration=\(player.duration)")
        finishPlayback(player, result: flag ? .success(()) : .failure(ArticleAudioError.playbackInterrupted))
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard audioPlayer === player else {
            playbackLog("ignored stale decode error error=\(String(describing: error))")
            return
        }
        guard playbackContinuation != nil else {
            playbackLog("decode error missing continuation error=\(String(describing: error))")
            return
        }
        playbackLog("player decode error attempt=\(activePlaybackAttempt.map(String.init) ?? "nil") error=\(String(describing: error))")
        finishPlayback(player, result: .failure(error ?? ArticleAudioError.playbackInterrupted))
    }
}
