//
//  StatsAPI.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2026/7/6.
//

import Foundation

struct StatsAPI {
    static let shared = StatsAPI()
    private let networkManager = NetworkManager.shared
    
    func getOverview(days: Int = 7) async throws -> StudyStatsResponse {
        let safeDays = min(max(days, 1), 30)
        return try await networkManager.request(
            endpoint: "stats/overview?days=\(safeDays)",
            method: "GET",
            responseType: StudyStatsResponse.self
        )
    }
}
