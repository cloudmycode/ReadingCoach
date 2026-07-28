import Foundation
import CryptoKit

extension ArticleAudioManager {
    /// 探测当前用户目录下是否已有对应音频（与主写入路径同一套 SHA256 命名）。
    func hasCachedAudio(
        sentenceId: Int?,
        text: String,
        type: SentenceAudioType,
        style: SpeechPlaybackStyle = .focusedSentence
    ) -> Bool {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return false }
        guard let userId = UserScopedStorage.currentUserId else { return false }

        let directory = UserScopedStorage.audioCacheDirectory(userId: userId)
        let idComponent = sentenceId.map(String.init) ?? "adhoc"
        let voice: String = {
            switch type {
            case .original: return "en-US-EmmaMultilingualNeural"
            case .translation: return "zh-CN-XiaoxiaoNeural"
            }
        }()
        let rate: String = {
            switch (type, style) {
            case (.original, .focusedSentence): return "-12%"
            case (.original, .continuousReading): return "-5%"
            case (.translation, .focusedSentence): return "-6%"
            case (.translation, .continuousReading): return "0%"
            }
        }()
        let digest = SHA256.hash(data: Data("\(normalizedText)|\(type.rawValue)|\(voice)|\(rate)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let fileName = "sentence_\(idComponent)_\(type.rawValue)_\(digest).mp3"
        let fileURL = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
