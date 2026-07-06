//
//  AIAPI.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/27.
//

import Foundation

struct PhotoUploadItem {
    let data: Data
    let fileName: String
    let mimeType: String
}

struct AIAPI {
    static let shared = AIAPI()
    private let networkManager = NetworkManager.shared
    
    func analyzeArticleImages(_ photos: [PhotoUploadItem]) async throws -> AnalyzeImageResponse {
        guard !photos.isEmpty else {
            throw APIError.server(message: "没有可上传的图片")
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        let contentType = "multipart/form-data; boundary=\(boundary)"
        let body = makeMultipartBody(photos: photos, type: "article", boundary: boundary)
        
        let data = try await networkManager.requestMultipart(
            endpoint: "image/process",
            method: "POST",
            body: body,
            contentType: contentType
        )
        
        let decoder = JSONDecoder()
        if let apiResponse = try? decoder.decode(APIResponse<AnalyzeImageResponse>.self, from: data) {
            if let payload = apiResponse.data, apiResponse.success {
                return payload
            } else {
                throw APIError.server(message: apiResponse.message)
            }
        } else {
            throw APIError.decoding
        }
    }
    
    private func makeMultipartBody(photos: [PhotoUploadItem], type: String, boundary: String) -> Data {
        var body = Data()
        
        // 添加 type 参数
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"type\"\r\n\r\n")
        body.appendString("\(type)\r\n")
        
        // 添加图片文件
        for photo in photos {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"files[]\"; filename=\"\(photo.fileName)\"\r\n")
            body.appendString("Content-Type: \(photo.mimeType)\r\n\r\n")
            body.append(photo.data)
            body.appendString("\r\n")
        }
        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}


