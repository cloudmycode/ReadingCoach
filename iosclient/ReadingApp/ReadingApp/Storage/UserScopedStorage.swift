//
//  UserScopedStorage.swift
//  ReadingApp
//
//  按 user_id 隔离本地缓存目录与 UserDefaults key。
//

import Foundation

extension Notification.Name {
    static let userScopedStorageDidChange = Notification.Name("ReadingCoachUserScopedStorageDidChange")
    static let readingAppLogoutRequested = Notification.Name("ReadingAppLogoutRequested")
}

enum UserScopedStorage {
    private static let userDefaults = UserDefaults.standard
    private static let fileManager = FileManager.default
    private static let legacyMigrationFlagKey = "readingcoach.legacy.cache.migrated"

    static var currentUserId: String? {
        UserManager.shared.currentUser()?.id
    }

    // MARK: - Keys

    static func defaultsKey(_ base: String, userId: String? = currentUserId) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return "readingcoach.\(userId).\(base)"
    }

    static func wordTranslationPlayedKey(word: String, userId: String? = currentUserId) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        let normalized = word
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return "word-translation-played.\(userId).\(normalized)"
    }

    // MARK: - Directories

    static func applicationSupportRoot() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("ReadingCoach", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func applicationSupportUserDirectory(userId: String) -> URL {
        let directory = applicationSupportRoot()
            .appendingPathComponent("users", isDirectory: true)
            .appendingPathComponent(userId, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func audioCacheDirectory(userId: String) -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = caches
            .appendingPathComponent("ReadingCoach", isDirectory: true)
            .appendingPathComponent("users", isDirectory: true)
            .appendingPathComponent(userId, isDirectory: true)
            .appendingPathComponent("SentenceAudioCache", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func legacyAudioCacheDirectory() -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return caches.appendingPathComponent("SentenceAudioCache", isDirectory: true)
    }

    // MARK: - Scope activation

    /// 登录 / 切用户 / 登出 / 启动时调用：迁移（如需）并让各 Store 绑定当前用户。
    static func activateCurrentUserScope() {
        if let userId = currentUserId {
            migrateLegacyCacheIfNeeded(to: userId)
        }
        ArticleCacheStore.shared.reloadForCurrentUser()
        WordExplanationCacheStore.shared.reloadForCurrentUser()
        WordBookStore.shared.reloadForCurrentUser()
        NotificationCenter.default.post(name: .userScopedStorageDidChange, object: currentUserId)
    }

    // MARK: - Legacy migration (once per device)

    private static func migrateLegacyCacheIfNeeded(to userId: String) {
        guard !userDefaults.bool(forKey: legacyMigrationFlagKey) else { return }

        migrateDefaultsData(
            from: "readingcoach.article.list.cache",
            to: "readingcoach.\(userId).article.list.cache"
        )
        migrateDefaultsData(
            from: "readingcoach.article.detail.cache",
            to: "readingcoach.\(userId).article.detail.cache"
        )
        migrateDefaultsData(
            from: "readingcoach.sentence.chat.cache",
            to: "readingcoach.\(userId).sentence.chat.cache"
        )
        migrateWordTranslationPlayedKeys(to: userId)

        let legacyRoot = applicationSupportRoot()
        let userRoot = applicationSupportUserDirectory(userId: userId)
        moveSQLiteIfNeeded(
            from: legacyRoot.appendingPathComponent("word_explanations.sqlite"),
            to: userRoot.appendingPathComponent("word_explanations.sqlite")
        )
        moveSQLiteIfNeeded(
            from: legacyRoot.appendingPathComponent("word_book.sqlite"),
            to: userRoot.appendingPathComponent("word_book.sqlite")
        )

        migrateLegacyAudioCache(to: userId)

        userDefaults.set(true, forKey: legacyMigrationFlagKey)
    }

    private static func migrateDefaultsData(from oldKey: String, to newKey: String) {
        guard userDefaults.object(forKey: newKey) == nil,
              let value = userDefaults.object(forKey: oldKey) else {
            userDefaults.removeObject(forKey: oldKey)
            return
        }
        userDefaults.set(value, forKey: newKey)
        userDefaults.removeObject(forKey: oldKey)
    }

    private static func migrateWordTranslationPlayedKeys(to userId: String) {
        let prefix = "word-translation-played-"
        let legacyKeys = userDefaults.dictionaryRepresentation().keys.filter { key in
            key.hasPrefix(prefix) && !key.hasPrefix("word-translation-played.")
        }
        for key in legacyKeys {
            let word = String(key.dropFirst(prefix.count))
            let newKey = "word-translation-played.\(userId).\(word)"
            if userDefaults.object(forKey: newKey) == nil {
                userDefaults.set(userDefaults.bool(forKey: key), forKey: newKey)
            }
            userDefaults.removeObject(forKey: key)
        }
    }

    private static func moveSQLiteIfNeeded(from source: URL, to destination: URL) {
        guard fileManager.fileExists(atPath: source.path) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            removeSQLiteSidecars(at: source)
            try? fileManager.removeItem(at: source)
            return
        }
        try? fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.moveItem(at: source, to: destination)
        for suffix in ["-wal", "-shm"] {
            let legacySide = URL(fileURLWithPath: source.path + suffix)
            let destSide = URL(fileURLWithPath: destination.path + suffix)
            guard fileManager.fileExists(atPath: legacySide.path) else { continue }
            if fileManager.fileExists(atPath: destSide.path) {
                try? fileManager.removeItem(at: legacySide)
            } else {
                try? fileManager.moveItem(at: legacySide, to: destSide)
            }
        }
    }

    private static func removeSQLiteSidecars(at dbURL: URL) {
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: dbURL.path + suffix)
            try? fileManager.removeItem(at: side)
        }
    }

    private static func migrateLegacyAudioCache(to userId: String) {
        let legacy = legacyAudioCacheDirectory()
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        let destination = audioCacheDirectory(userId: userId)
        guard let items = try? fileManager.contentsOfDirectory(
            at: legacy,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            try? fileManager.removeItem(at: legacy)
            return
        }

        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try? fileManager.removeItem(at: item)
            } else {
                try? fileManager.moveItem(at: item, to: target)
            }
        }
        try? fileManager.removeItem(at: legacy)
    }
}
