//
//  AuthAPI.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case server(message: String)
    case decoding
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "接口地址无效"
        case .server(let message):
            return message
        case .decoding:
            return "数据解析失败"
        case .network(let error):
            return error.localizedDescription
        }
    }
}

struct AuthAPI {
    static let shared = AuthAPI()
    private let networkManager = NetworkManager.shared

    func sendCode(phone: String) async throws -> SendCodeResponse {
        let payload = ["phone": phone]
        return try await networkManager.request(
            endpoint: "auth/code",
            method: "POST",
            body: payload,
            responseType: SendCodeResponse.self
        )
    }

    func login(phone: String, code: String, agreePolicy: Bool) async throws -> LoginResponse {
        let payload: [String: Any] = [
            "phone": phone,
            "code": code,
            "agreePolicy": agreePolicy
        ]
        return try await networkManager.request(
            endpoint: "auth/login",
            method: "POST",
            body: payload,
            responseType: LoginResponse.self
        )
    }
}

