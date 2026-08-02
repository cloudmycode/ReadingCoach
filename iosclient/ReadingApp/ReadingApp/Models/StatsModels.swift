//
//  StatsModels.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2026/7/6.
//

import Foundation

struct StudyStatsResponse: Decodable {
    let totalArticles: Int
    let todayNewArticles: Int
    let todayReviewCount: Int
    let todayReadSeconds: Int
    let todayReviewSeconds: Int
    let currentStreakDays: Int
    let totalReadCount: Int
    let totalSentenceCount: Int
    let totalReadSeconds: Int
    let averageReadingSpeedWpm: Int?
    let recentDays: [DailyStudyStat]

    enum CodingKeys: String, CodingKey {
        case totalArticles = "total_articles"
        case todayNewArticles = "today_new_articles"
        case todayReviewCount = "today_review_count"
        case todayReadSeconds = "today_read_seconds"
        case todayReviewSeconds = "today_review_seconds"
        case currentStreakDays = "current_streak_days"
        case totalReadCount = "total_read_count"
        case totalSentenceCount = "total_sentence_count"
        case totalReadSeconds = "total_read_seconds"
        case averageReadingSpeedWpm = "average_reading_speed_wpm"
        case recentDays = "recent_days"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalArticles = try container.decodeIfPresent(Int.self, forKey: .totalArticles) ?? 0
        todayNewArticles = try container.decodeIfPresent(Int.self, forKey: .todayNewArticles) ?? 0
        todayReviewCount = try container.decodeIfPresent(Int.self, forKey: .todayReviewCount) ?? 0
        todayReadSeconds = try container.decodeIfPresent(Int.self, forKey: .todayReadSeconds) ?? 0
        todayReviewSeconds = try container.decodeIfPresent(Int.self, forKey: .todayReviewSeconds) ?? 0
        currentStreakDays = try container.decodeIfPresent(Int.self, forKey: .currentStreakDays) ?? 0
        totalReadCount = try container.decodeIfPresent(Int.self, forKey: .totalReadCount) ?? 0
        totalSentenceCount = try container.decodeIfPresent(Int.self, forKey: .totalSentenceCount) ?? 0
        totalReadSeconds = try container.decodeIfPresent(Int.self, forKey: .totalReadSeconds) ?? 0
        averageReadingSpeedWpm = try container.decodeIfPresent(Int.self, forKey: .averageReadingSpeedWpm)
        recentDays = try container.decodeIfPresent([DailyStudyStat].self, forKey: .recentDays) ?? []
    }

    static let empty = StudyStatsResponse(
        totalArticles: 0,
        todayNewArticles: 0,
        todayReviewCount: 0,
        todayReadSeconds: 0,
        todayReviewSeconds: 0,
        currentStreakDays: 0,
        totalReadCount: 0,
        totalSentenceCount: 0,
        totalReadSeconds: 0,
        averageReadingSpeedWpm: nil,
        recentDays: []
    )

    init(
        totalArticles: Int,
        todayNewArticles: Int,
        todayReviewCount: Int,
        todayReadSeconds: Int,
        todayReviewSeconds: Int,
        currentStreakDays: Int,
        totalReadCount: Int,
        totalSentenceCount: Int,
        totalReadSeconds: Int,
        averageReadingSpeedWpm: Int?,
        recentDays: [DailyStudyStat]
    ) {
        self.totalArticles = totalArticles
        self.todayNewArticles = todayNewArticles
        self.todayReviewCount = todayReviewCount
        self.todayReadSeconds = todayReadSeconds
        self.todayReviewSeconds = todayReviewSeconds
        self.currentStreakDays = currentStreakDays
        self.totalReadCount = totalReadCount
        self.totalSentenceCount = totalSentenceCount
        self.totalReadSeconds = totalReadSeconds
        self.averageReadingSpeedWpm = averageReadingSpeedWpm
        self.recentDays = recentDays
    }
}

struct DailyStudyStat: Decodable, Identifiable {
    let date: String
    let newArticles: Int
    let reviewCount: Int
    let readSeconds: Int
    let reviewSeconds: Int
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case date
        case newArticles = "new_articles"
        case reviewCount = "review_count"
        case readSeconds = "read_seconds"
        case reviewSeconds = "review_seconds"
        case active
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        newArticles = try container.decodeIfPresent(Int.self, forKey: .newArticles) ?? 0
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        readSeconds = try container.decodeIfPresent(Int.self, forKey: .readSeconds) ?? 0
        reviewSeconds = try container.decodeIfPresent(Int.self, forKey: .reviewSeconds) ?? 0
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? false
    }

    var id: String { date }
}

enum StudyDurationFormat {
    static func minutesText(_ seconds: Int) -> String {
        if seconds <= 0 { return "0分钟" }
        if seconds < 60 { return "<1分钟" }
        let minutes = seconds / 60
        let hours = minutes / 60
        let remain = minutes % 60
        if hours > 0 {
            return remain > 0 ? "\(hours)小时\(remain)分" : "\(hours)小时"
        }
        return "\(minutes)分钟"
    }
}
