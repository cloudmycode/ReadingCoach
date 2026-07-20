import Foundation
import CryptoKit

extension ArticleAudioManager {
    func hasCachedAudio(text: String, type: SentenceAudioType) -> Bool {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return false }
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }

        let cacheDirectory = cachesDirectory.appendingPathComponent("SentenceAudioCache", isDirectory: true)
        let digest = Insecure.MD5.hash(data: Data(normalizedText.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let fileURL = cacheDirectory.appendingPathComponent("\(type.rawValue)-\(hash).mp3")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
