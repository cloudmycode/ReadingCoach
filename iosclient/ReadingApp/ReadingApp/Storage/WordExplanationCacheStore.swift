//
//  WordExplanationCacheStore.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2026/7/19.
//

import Foundation
import SQLite3

struct CachedWordExplanation {
    let sentenceId: Int
    let normalizedWord: String
    let word: String
    let partOfSpeech: String
    let meaning: String
    let tip: String
}

final class WordExplanationCacheStore {
    static let shared = WordExplanationCacheStore()

    private var database: OpaquePointer?
    private let queue = DispatchQueue(label: "readingcoach.word-cache.db")

    private init() {
        openDatabase()
        createTableIfNeeded()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func cachedExplanation(sentenceId: Int, word: String) -> CachedWordExplanation? {
        let normalizedWord = normalize(word)
        guard sentenceId > 0, !normalizedWord.isEmpty else { return nil }

        return queue.sync {
            guard let database else { return nil }
            let sql = """
            SELECT sentence_id, normalized_word, word, part_of_speech, meaning, tip
            FROM word_explanations
            WHERE sentence_id = ? AND normalized_word = ?
            LIMIT 1;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }

            sqlite3_bind_int(statement, 1, Int32(sentenceId))
            sqlite3_bind_text(statement, 2, normalizedWord, -1, transientDestructor)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            return CachedWordExplanation(
                sentenceId: Int(sqlite3_column_int(statement, 0)),
                normalizedWord: Self.string(from: statement, index: 1),
                word: Self.string(from: statement, index: 2),
                partOfSpeech: Self.string(from: statement, index: 3),
                meaning: Self.string(from: statement, index: 4),
                tip: Self.string(from: statement, index: 5)
            )
        }
    }

    func save(sentenceId: Int, word: String, partOfSpeech: String, meaning: String, tip: String) {
        let normalizedWord = normalize(word)
        guard sentenceId > 0, !normalizedWord.isEmpty else { return }

        queue.sync {
            guard let database else { return }
            let sql = """
            INSERT INTO word_explanations (sentence_id, normalized_word, word, part_of_speech, meaning, tip, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(sentence_id, normalized_word) DO UPDATE SET
                word = excluded.word,
                part_of_speech = excluded.part_of_speech,
                meaning = excluded.meaning,
                tip = excluded.tip,
                updated_at = CURRENT_TIMESTAMP;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return
            }

            sqlite3_bind_int(statement, 1, Int32(sentenceId))
            sqlite3_bind_text(statement, 2, normalizedWord, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, word, -1, transientDestructor)
            sqlite3_bind_text(statement, 4, partOfSpeech, -1, transientDestructor)
            sqlite3_bind_text(statement, 5, meaning, -1, transientDestructor)
            sqlite3_bind_text(statement, 6, tip, -1, transientDestructor)

            sqlite3_step(statement)
        }
    }

    func removeExplanations(sentenceId: Int) {
        guard sentenceId > 0 else { return }
        queue.sync {
            guard let database else { return }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, "DELETE FROM word_explanations WHERE sentence_id = ?", -1, &statement, nil) == SQLITE_OK else { return }
            sqlite3_bind_int(statement, 1, Int32(sentenceId))
            sqlite3_step(statement)
        }
    }

    private func openDatabase() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("ReadingCoach", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("word_explanations.sqlite")

        if sqlite3_open(dbURL.path, &database) != SQLITE_OK {
            database = nil
        }
    }

    private func createTableIfNeeded() {
        queue.sync {
            guard let database else { return }
            if hasLegacySchema(database: database) {
                sqlite3_exec(database, "DROP TABLE IF EXISTS word_explanations;", nil, nil, nil)
            }
            let sql = """
            CREATE TABLE IF NOT EXISTS word_explanations (
                sentence_id INTEGER NOT NULL,
                normalized_word TEXT NOT NULL,
                word TEXT NOT NULL,
                part_of_speech TEXT NOT NULL,
                meaning TEXT NOT NULL,
                tip TEXT NOT NULL,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (sentence_id, normalized_word)
            );
            """
            sqlite3_exec(database, sql, nil, nil, nil)
        }
    }

    private func hasLegacySchema(database: OpaquePointer) -> Bool {
        let sql = "PRAGMA table_info(word_explanations);"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        var columnNames = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            columnNames.insert(Self.string(from: statement, index: 1))
        }
        return !columnNames.isEmpty && !columnNames.contains("sentence_id")
    }

    private func normalize(_ word: String) -> String {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]{}<>"))
    }

    private static func string(from statement: OpaquePointer?, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
