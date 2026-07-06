//
//  ArticleAudioManager.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/27.
//

import Foundation

enum SentenceAudioType: String, CaseIterable {
    case original = "original"
    case translation = "translation"
}

enum ArticleAudioError: LocalizedError {
    case missingSentenceID
    case invalidResponse
    case downloadFailed
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .missingSentenceID:
            return "该句子暂不支持语音播放"
        case .invalidResponse:
            return "音频下载失败，请稍后重试"
        case .downloadFailed:
            return "无法下载音频文件"
        case .playbackFailed:
            return "音频播放失败"
        }
    }
}

final class ArticleAudioManager {
    static let shared = ArticleAudioManager()
    
    private let fileManager: FileManager
    private let cacheDirectory: URL
    
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let directory = caches.appendingPathComponent("ArticleAudioCache", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        cacheDirectory = directory
    }
    
    func fetchAudioURL(sentenceId: Int, type: SentenceAudioType) async throws -> URL {
        let localURL = cacheDirectory.appendingPathComponent("sentence_\(sentenceId)_\(type.rawValue).mp3")
        if fileManager.fileExists(atPath: localURL.path) {
            return localURL
        }
        
        let remoteURL = AppConfig.API.serverBaseURL
            .appendingPathComponent("attachments/articleaudio/audio_\(sentenceId)_\(type.rawValue).mp3")
        
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                throw ArticleAudioError.invalidResponse
            }
            
            if fileManager.fileExists(atPath: localURL.path) {
                try? fileManager.removeItem(at: localURL)
            }
            try fileManager.moveItem(at: tempURL, to: localURL)
            return localURL
        } catch {
            throw ArticleAudioError.downloadFailed
        }
    }
    
    func clearCache() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for url in contents {
                try? fileManager.removeItem(at: url)
            }
        } catch {
            // ignore
        }
    }
}

