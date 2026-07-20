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
    private lazy var cacheDirectoryURL: URL = {
        let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent("SentenceAudioCache", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }()

    func speak(sentenceId: Int?, text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ArticleAudioError.emptyText
        }

        stop()

        let cacheURL = cacheFileURL(sentenceId: sentenceId, text: trimmed, type: type, style: style)
        if !fileManager.fileExists(atPath: cacheURL.path) {
            let audioData = try await synthesizeAudio(text: trimmed, type: type, style: style)
            try audioData.write(to: cacheURL, options: .atomic)
        }

        try configureAudioSession()
        try await playAudioFile(at: cacheURL)
    }

    func stop() {
        activeWebSocketTask?.cancel(with: .goingAway, reason: nil)
        activeWebSocketTask = nil

        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil

        if let playbackContinuation {
            playbackContinuation.resume(throwing: CancellationError())
            self.playbackContinuation = nil
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func cacheFileURL(sentenceId: Int?, text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) -> URL {
        let idComponent = sentenceId.map(String.init) ?? "adhoc"
        let digest = sha256Hex("\(text)|\(type.rawValue)|\(voiceName(for: type))|\(rateValue(for: type, style: style))")
        let fileName = "sentence_\(idComponent)_\(type.rawValue)_\(digest).mp3"
        return cacheDirectoryURL.appendingPathComponent(fileName)
    }

    private func synthesizeAudio(text: String, type: SentenceAudioType, style: SpeechPlaybackStyle) async throws -> Data {
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
        activeWebSocketTask = webSocketTask
        webSocketTask.resume()

        do {
            try await sendSpeechConfig(to: webSocketTask)
            try await sendSSML(text: text, type: type, style: style, to: webSocketTask)
            let data = try await receiveAudioData(from: webSocketTask)
            activeWebSocketTask = nil
            webSocketTask.cancel(with: .normalClosure, reason: nil)
            return data
        } catch {
            activeWebSocketTask = nil
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

    private func playAudioFile(at fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let player = try AVAudioPlayer(contentsOf: fileURL)
                player.delegate = self
                player.prepareToPlay()
                guard player.play() else {
                    throw ArticleAudioError.playbackInterrupted
                }
                audioPlayer = player
                playbackContinuation = continuation
            } catch {
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
        guard let playbackContinuation else { return }
        self.playbackContinuation = nil
        audioPlayer = nil

        if flag {
            playbackContinuation.resume()
        } else {
            playbackContinuation.resume(throwing: ArticleAudioError.playbackInterrupted)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard let playbackContinuation else { return }
        self.playbackContinuation = nil
        audioPlayer = nil
        playbackContinuation.resume(throwing: error ?? ArticleAudioError.playbackInterrupted)
    }
}
