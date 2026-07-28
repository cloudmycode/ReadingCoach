//
//  WordBookStore.swift
//  ReadingApp
//
//  本地单词本缓存：与服务端 user_word_book 同步，离线时可兜底展示。
//

import Foundation
import SQLite3

extension Notification.Name {
    static let wordBookDidChange = Notification.Name("ReadingCoachWordBookDidChange")
}

struct WordBookEntry: Identifiable, Equatable {
    let entryId: Int64
    let articleId: String
    let sentenceId: Int
    let word: String
    let normalizedWord: String
    let sentenceOriginal: String
    let sentenceTranslation: String
    let partOfSpeech: String
    let meaning: String
    let tip: String
    let reviewStep: Int
    let nextReviewAt: String?
    let masteryStatus: String
    let lastReviewedAt: String?
    let lookedUpAt: Date

    var id: String { "\(entryId)" }

    var reviewBadgeText: String {
        if masteryStatus == "mastered" {
            return "已掌握"
        }
        if masteryStatus == "paused" {
            return "已暂停"
        }
        guard let nextReviewAt, !nextReviewAt.isEmpty else {
            return "待安排"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: nextReviewAt) else {
            return "学习中"
        }
        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        if target <= today {
            return "今日任务"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "明天复习"
        }
        let output = DateFormatter()
        output.dateFormat = "M/d"
        return "第 \(max(reviewStep, 1)) 轮 · \(output.string(from: date))"
    }
}

final class WordBookStore {
    static let shared = WordBookStore()

    private var database: OpaquePointer?
    private let queue = DispatchQueue(label: "readingcoach.word-book.db")
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {
        reloadForCurrentUser()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func reloadForCurrentUser() {
        queue.sync {
            closeDatabaseLocked()
            guard let userId = UserScopedStorage.currentUserId else { return }
            openDatabaseLocked(userId: userId)
            createTableIfNeededLocked()
        }
    }

    func allEntries() -> [WordBookEntry] {
        queue.sync {
            guard let database else { return [] }
            let sql = """
            SELECT entry_id, article_id, sentence_id, word, normalized_word, sentence_original, sentence_translation,
                   part_of_speech, meaning, tip, looked_up_at
            FROM word_book_entries
            ORDER BY datetime(looked_up_at) DESC, entry_id DESC;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            var entries: [WordBookEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let lookedUpRaw = Self.string(from: statement, index: 10)
                entries.append(
                    WordBookEntry(
                        entryId: Int64(sqlite3_column_int64(statement, 0)),
                        articleId: Self.string(from: statement, index: 1),
                        sentenceId: Int(sqlite3_column_int(statement, 2)),
                        word: Self.string(from: statement, index: 3),
                        normalizedWord: Self.string(from: statement, index: 4),
                        sentenceOriginal: Self.string(from: statement, index: 5),
                        sentenceTranslation: Self.string(from: statement, index: 6),
                        partOfSpeech: Self.string(from: statement, index: 7),
                        meaning: Self.string(from: statement, index: 8),
                        tip: Self.string(from: statement, index: 9),
                        reviewStep: 0,
                        nextReviewAt: nil,
                        masteryStatus: "learning",
                        lastReviewedAt: nil,
                        lookedUpAt: parseDate(lookedUpRaw) ?? Date()
                    )
                )
            }
            return entries
        }
    }

    /// 用服务端列表整体替换本地缓存（离线兜底）。
    func replaceAll(_ entries: [WordBookEntry]) {
        queue.sync {
            guard let database else { return }
            sqlite3_exec(database, "DELETE FROM word_book_entries;", nil, nil, nil)

            let sql = """
            INSERT INTO word_book_entries (
                entry_id, article_id, sentence_id, normalized_word, word,
                sentence_original, sentence_translation,
                part_of_speech, meaning, tip, looked_up_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

            for entry in entries {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { continue }
                let lookedUpAt = isoFormatter.string(from: entry.lookedUpAt)
                sqlite3_bind_int64(statement, 1, entry.entryId)
                sqlite3_bind_text(statement, 2, entry.articleId, -1, transientDestructor)
                sqlite3_bind_int(statement, 3, Int32(entry.sentenceId))
                sqlite3_bind_text(statement, 4, entry.normalizedWord, -1, transientDestructor)
                sqlite3_bind_text(statement, 5, entry.word, -1, transientDestructor)
                sqlite3_bind_text(statement, 6, entry.sentenceOriginal, -1, transientDestructor)
                sqlite3_bind_text(statement, 7, entry.sentenceTranslation, -1, transientDestructor)
                sqlite3_bind_text(statement, 8, entry.partOfSpeech, -1, transientDestructor)
                sqlite3_bind_text(statement, 9, entry.meaning, -1, transientDestructor)
                sqlite3_bind_text(statement, 10, entry.tip, -1, transientDestructor)
                sqlite3_bind_text(statement, 11, lookedUpAt, -1, transientDestructor)
                sqlite3_step(statement)
            }
        }
    }

    private func closeDatabaseLocked() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
    }

    private func openDatabaseLocked(userId: String) {
        let dbURL = UserScopedStorage.applicationSupportUserDirectory(userId: userId)
            .appendingPathComponent("word_book.sqlite")
        if sqlite3_open(dbURL.path, &database) != SQLITE_OK {
            database = nil
        }
    }

    private func createTableIfNeededLocked() {
        guard let database else { return }
        if !hasEntryIdColumn(database: database) {
            sqlite3_exec(database, "DROP TABLE IF EXISTS word_book_entries;", nil, nil, nil)
        }
        let sql = """
        CREATE TABLE IF NOT EXISTS word_book_entries (
            entry_id INTEGER NOT NULL,
            article_id TEXT NOT NULL,
            sentence_id INTEGER NOT NULL,
            normalized_word TEXT NOT NULL,
            word TEXT NOT NULL,
            sentence_original TEXT NOT NULL,
            sentence_translation TEXT NOT NULL DEFAULT '',
            part_of_speech TEXT NOT NULL DEFAULT '',
            meaning TEXT NOT NULL DEFAULT '',
            tip TEXT NOT NULL DEFAULT '',
            looked_up_at TEXT NOT NULL,
            PRIMARY KEY (entry_id)
        );
        """
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func hasEntryIdColumn(database: OpaquePointer) -> Bool {
        let sql = "PRAGMA table_info(word_book_entries);"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            if Self.string(from: statement, index: 1) == "entry_id" {
                return true
            }
        }
        return false
    }

    private func parseDate(_ raw: String) -> Date? {
        if let date = isoFormatter.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        return plain.date(from: raw)
    }

    private static func string(from statement: OpaquePointer?, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
