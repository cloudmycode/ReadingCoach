//
//  ArticleAudioManager.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/27.
//

import Foundation
import AVFoundation
import CryptoKit

enum SentenceAudioType: String, CaseIterable {
    case original = "original"
    case translation = "translation"
}

enum SpeechPlaybackStyle {
    case focusedSentence
    case continuousReading
}

enum ArticleAudioError: LocalizedError {
    case emptyText
    case synthesisFailed
    case playbackInterrupted

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "该句子暂时没有可朗读内容"
        case .synthesisFailed:
            return "语音生成失败，请稍后重试"
        case .playbackInterrupted:
            return "朗读已中断，请稍后重试"
        }
    }
}

@MainActor
final class ArticleAudioManager: NSObject {
    static let shared = ArticleAudioManager()

    private enum EdgeTTSConfig {
        static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
        static let websocketBaseURL = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
        static let chromiumMajor = "143"
        static let chromiumFullVersion = "143.0.3650.75"
        static let outputFormat = "audio-24khz-48kbitrate-mono-mp3"
        static let origin = "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold"
    }

    private let fileManager = FileManager.default
    private var audioPlayer: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Error>?
    private var activeWebSocketTask: URLSessionWebSocketTask?
    private var warmingCacheKeys: Set<String> = []
    private var playbackAttempt = 0
    private var activePlaybackAttempt: Int?
    private var isAudioSessionConfigured = false

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

        let cacheURL = try await ensureAudioCached(sentenceId: sentenceId, text: trimmed, type: type, style: style)

        if !isAudioSessionConfigured {
            try configureAudioSession()
            isAudioSessionConfigured = true
            playbackLog("audio session activated attempt=\(attempt)")
        } else {
            playbackLog("audio session reused attempt=\(attempt)")
        }
        activePlaybackAttempt = attempt
        do {
            try await playAudioFile(at: cacheURL, attempt: attempt)
            playbackLog("speak completed attempt=\(attempt) sentenceId=\(sentenceId.map(String.init) ?? "nil")")
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

    func stop(reason: String = "external") {
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

        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isAudioSessionConfigured = false
    }

    private func cacheFileURL(sentenceId: Int?, text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) -> URL? {
        guard let cacheDirectoryURL else { return nil }
        let idComponent = sentenceId.map(String.init) ?? "adhoc"
        let digest = sha256Hex("\(text)|\(type.rawValue)|\(voiceName(for: type))|\(rateValue(for: type, style: style))")
        let fileName = "sentence_\(idComponent)_\(type.rawValue)_\(digest).mp3"
        return cacheDirectoryURL.appendingPathComponent(fileName)
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
    ) async throws -> URL {
        guard let cacheURL = cacheFileURL(sentenceId: sentenceId, text: text, type: type, style: style) else {
            throw ArticleAudioError.synthesisFailed
        }
        if fileManager.fileExists(atPath: cacheURL.path) {
            playbackLog("cache hit sentenceId=\(sentenceId.map(String.init) ?? "nil") file=\(cacheURL.lastPathComponent)")
            return cacheURL
        }

        playbackLog("cache miss sentenceId=\(sentenceId.map(String.init) ?? "nil") file=\(cacheURL.lastPathComponent)")

        let audioData = try await synthesizeAudio(
            text: text,
            type: type,
            style: style,
            tracksActiveTask: tracksActiveTask
        )
        try audioData.write(to: cacheURL, options: .atomic)
        return cacheURL
    }

    private func synthesizeAudio(
        text: String,
        type: SentenceAudioType,
        style: SpeechPlaybackStyle,
        tracksActiveTask: Bool
    ) async throws -> Data {
        guard let url = edgeWebSocketURL() else {
            throw ArticleAudioError.synthesisFailed
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(EdgeTTSConfig.chromiumMajor).0.0.0 Safari/537.36 Edg/\(EdgeTTSConfig.chromiumMajor).0.0.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("gzip, deflate, br, zstd", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(EdgeTTSConfig.origin, forHTTPHeaderField: "Origin")

        let webSocketTask = URLSession.shared.webSocketTask(with: request)
        if tracksActiveTask {
            activeWebSocketTask = webSocketTask
        }
        webSocketTask.resume()

        do {
            try await sendSpeechConfig(to: webSocketTask)
            try await sendSSML(text: text, type: type, style: style, to: webSocketTask)
            let data = try await receiveAudioData(from: webSocketTask)
            if tracksActiveTask, activeWebSocketTask === webSocketTask {
                activeWebSocketTask = nil
            }
            webSocketTask.cancel(with: .normalClosure, reason: nil)
            return data
        } catch {
            if tracksActiveTask, activeWebSocketTask === webSocketTask {
                activeWebSocketTask = nil
            }
            webSocketTask.cancel(with: .goingAway, reason: nil)
            throw error
        }
    }

    private func sendSpeechConfig(to task: URLSessionWebSocketTask) async throws {
        let configMessage = """
        X-Timestamp:\(edgeDateString())
        Content-Type:application/json; charset=utf-8
        Path:speech.config

        {"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"\(EdgeTTSConfig.outputFormat)"}}}}
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

    private func receiveAudioData(from task: URLSessionWebSocketTask) async throws -> Data {
        var audioData = Data()

        while true {
            try Task.checkCancellation()
            let message = try await task.receive()

            switch message {
            case .string(let string):
                if string.contains("Path:turn.end") {
                    guard !audioData.isEmpty else {
                        throw ArticleAudioError.synthesisFailed
                    }
                    return audioData
                }
            case .data(let data):
                guard data.count >= 2 else { continue }
                let headerLength = Int(data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
                guard 2 + headerLength <= data.count else { continue }
                audioData.append(data[(2 + headerLength)...])
            @unknown default:
                continue
            }
        }
    }

    private func playAudioFile(at fileURL: URL, attempt: Int) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let player = try AVAudioPlayer(contentsOf: fileURL)
                player.delegate = self
                player.prepareToPlay()
                playbackLog("player prepared attempt=\(attempt) duration=\(player.duration) file=\(fileURL.lastPathComponent)")
                // Install all shared state before play(). Cached files can begin
                // and finish very quickly, so delegate callbacks must always see
                // the player and continuation that belong to this attempt.
                audioPlayer = player
                playbackContinuation = continuation
                guard player.play() else {
                    player.delegate = nil
                    audioPlayer = nil
                    playbackContinuation = nil
                    activePlaybackAttempt = nil
                    playbackLog("player refused start attempt=\(attempt)")
                    continuation.resume(throwing: ArticleAudioError.playbackInterrupted)
                    return
                }
                playbackLog("player started attempt=\(attempt) isPlaying=\(player.isPlaying)")
            } catch {
                activePlaybackAttempt = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }

    private func edgeWebSocketURL() -> URL? {
        var components = URLComponents(string: EdgeTTSConfig.websocketBaseURL)
        components?.queryItems = [
            URLQueryItem(name: "TrustedClientToken", value: EdgeTTSConfig.trustedClientToken),
            URLQueryItem(name: "Sec-MS-GEC", value: secMSGEC()),
            URLQueryItem(name: "Sec-MS-GEC-Version", value: "1-\(EdgeTTSConfig.chromiumFullVersion)"),
            URLQueryItem(name: "ConnectionId", value: randomHexID())
        ]
        return components?.url
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
        case (.translation, .focusedSentence):
            return "-6%"
        case (.translation, .continuousReading):
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

    private func secMSGEC() -> String {
        let windowsEpochOffset: Double = 11_644_473_600
        var ticks = Double(Date().timeIntervalSince1970) + windowsEpochOffset
        ticks -= ticks.truncatingRemainder(dividingBy: 300)
        ticks *= 10_000_000
        let source = String(format: "%.0f%@", ticks, EdgeTTSConfig.trustedClientToken)
        return sha256Hex(source).uppercased()
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
        guard let playbackContinuation else {
            playbackLog("finish callback missing continuation activeAttempt=\(activePlaybackAttempt.map(String.init) ?? "nil")")
            return
        }
        playbackLog("player finished attempt=\(activePlaybackAttempt.map(String.init) ?? "nil") success=\(flag) currentTime=\(player.currentTime) duration=\(player.duration)")
        self.playbackContinuation = nil
        player.delegate = nil
        audioPlayer = nil
        activePlaybackAttempt = nil

        if flag {
            playbackContinuation.resume()
        } else {
            playbackContinuation.resume(throwing: ArticleAudioError.playbackInterrupted)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard audioPlayer === player else {
            playbackLog("ignored stale decode error error=\(String(describing: error))")
            return
        }
        guard let playbackContinuation else {
            playbackLog("decode error missing continuation error=\(String(describing: error))")
            return
        }
        playbackLog("player decode error attempt=\(activePlaybackAttempt.map(String.init) ?? "nil") error=\(String(describing: error))")
        self.playbackContinuation = nil
        player.delegate = nil
        audioPlayer = nil
        activePlaybackAttempt = nil
        playbackContinuation.resume(throwing: error ?? ArticleAudioError.playbackInterrupted)
    }
}
