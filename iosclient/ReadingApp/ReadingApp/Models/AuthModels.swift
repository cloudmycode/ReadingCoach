//
//  AuthModels.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation

struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let message: String
    let data: T?
}

struct SendCodeResponse: Decodable {
    let expiresIn: Int?
    let debugCode: String?
}

struct LoginResponse: Decodable {
    let token: String
    let userInfo: UserInfo
}

struct UserInfo: Codable {
    let id: Int?
    let phone: String?
    let nickname: String?
    let avatar: String?
}

struct StoredUser: Codable, Identifiable {
    let id: String
    let phone: String?
    let nickname: String?
    let avatar: String?
    let token: String
    let loginTime: Date
    var lastActiveTime: Date
}

