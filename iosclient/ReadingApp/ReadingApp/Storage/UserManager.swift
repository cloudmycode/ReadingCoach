//
//  UserManager.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation

enum UserStorageError: Error {
    case encodingFailed
    case decodingFailed
}

final class UserManager {
    static let shared = UserManager()
    private let usersKey = "multiUsers"
    private let currentUserKey = "currentUserId"
    private let phoneHistoryKey = "phoneHistory"
    private let userDefaults: UserDefaults

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Users
    private func loadUsers() -> [String: StoredUser] {
        guard let data = userDefaults.data(forKey: usersKey) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: StoredUser].self, from: data) {
            return decoded
        }
        return [:]
    }

    private func save(users: [String: StoredUser]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(users) else {
            throw UserStorageError.encodingFailed
        }
        userDefaults.set(data, forKey: usersKey)
    }

    func saveUser(info: UserInfo, token: String, phone: String) throws {
        var users = loadUsers()
        let identifier = info.id.map { String($0) } ?? info.phone ?? phone
        let now = Date()
        let stored = StoredUser(
            id: identifier,
            phone: phone,
            nickname: info.nickname,
            avatar: info.avatar,
            token: token,
            loginTime: now,
            lastActiveTime: now
        )
        users[identifier] = stored
        try save(users: users)
        setCurrentUser(id: identifier)
    }

    func currentUser() -> StoredUser? {
        guard let id = userDefaults.string(forKey: currentUserKey) else { return nil }
        let users = loadUsers()
        return users[id]
    }

    func currentToken() -> String? {
        // 检查令牌是否过期
        if let user = currentUser(), isTokenExpired(user: user) {
            // 令牌已过期，清除当前用户
            clearCurrentUser()
            return nil
        }
        return currentUser()?.token
    }
    
    /// 检查令牌是否过期（JWT 默认 7 天有效期）
    /// 这里我们检查登录时间，如果超过 6.5 天就认为可能过期
    func isTokenExpired(user: StoredUser) -> Bool {
        let tokenLifetime: TimeInterval = 7 * 24 * 3600 // 7 天
        let safetyMargin: TimeInterval = 12 * 3600 // 12 小时安全边距
        let expirationTime = user.loginTime.addingTimeInterval(tokenLifetime - safetyMargin)
        return Date() > expirationTime
    }
    
    /// 检查当前用户的令牌是否过期
    func isCurrentTokenExpired() -> Bool {
        guard let user = currentUser() else { return true }
        return isTokenExpired(user: user)
    }
    
    /// 清除当前用户（用于令牌过期或登出）
    func clearCurrentUser() {
        userDefaults.removeObject(forKey: currentUserKey)
    }

    func setCurrentUser(id: String) {
        userDefaults.set(id, forKey: currentUserKey)
    }

    // MARK: - Phone History
    func phoneHistory() -> [String] {
        userDefaults.stringArray(forKey: phoneHistoryKey) ?? []
    }

    func addPhoneToHistory(_ phone: String) {
        guard !phone.isEmpty else { return }
        var history = phoneHistory().filter { $0 != phone }
        history.insert(phone, at: 0)
        if history.count > 10 {
            history = Array(history.prefix(10))
        }
        userDefaults.set(history, forKey: phoneHistoryKey)
    }

    func removePhoneFromHistory(_ phone: String) {
        var history = phoneHistory()
        history.removeAll { $0 == phone }
        userDefaults.set(history, forKey: phoneHistoryKey)
    }
}

