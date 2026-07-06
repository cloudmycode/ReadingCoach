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
    let currentStreakDays: Int
    let totalReadCount: Int
    let totalSentenceCount: Int
    let recentDays: [DailyStudyStat]
    
    enum CodingKeys: String, CodingKey {
        case totalArticles = "total_articles"
        case todayNewArticles = "today_new_articles"
        case todayReviewCount = "today_review_count"
        case currentStreakDays = "current_streak_days"
        case totalReadCount = "total_read_count"
        case totalSentenceCount = "total_sentence_count"
        case recentDays = "recent_days"
    }
    
    static let empty = StudyStatsResponse(
        totalArticles: 0,
        todayNewArticles: 0,
        todayReviewCount: 0,
        currentStreakDays: 0,
        totalReadCount: 0,
        totalSentenceCount: 0,
        recentDays: []
    )
}

struct DailyStudyStat: Decodable, Identifiable {
    let date: String
    let newArticles: Int
    let reviewCount: Int
    let active: Bool
    
    enum CodingKeys: String, CodingKey {
        case date
        case newArticles = "new_articles"
        case reviewCount = "review_count"
        case active
    }
    
    var id: String { date }
}
