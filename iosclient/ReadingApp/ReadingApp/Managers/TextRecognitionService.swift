//
//  TextRecognitionService.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2026/7/9.
//

import Foundation
import Vision
import UIKit

enum TextRecognitionError: LocalizedError {
    case invalidImage
    case noTextFound
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "图片无法识别"
        case .noTextFound:
            return "没有识别到英文正文，请尝试重新拍照或调整裁剪区域"
        }
    }
}

final class TextRecognitionService {
    static let shared = TextRecognitionService()
    
    func recognizeArticleText(from item: PhotoUploadItem) async throws -> String {
        let text = try await recognizeText(from: item.data)
        let normalized = normalizeRecognizedText(text)
        if normalized.isEmpty {
            throw TextRecognitionError.noTextFound
        }
        return normalized
    }
    
    private func recognizeText(from imageData: Data) async throws -> String {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            throw TextRecognitionError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "en-GB"]
            request.minimumTextHeight = 0.015
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func normalizeRecognizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
