import Foundation

extension Notification.Name {
    static let reviewTasksDidChange = Notification.Name("ReadingCoachReviewTasksDidChange")
}

struct ReviewAPI {
    static let shared = ReviewAPI()
    private let networkManager = NetworkManager.shared

    func todaySummary() async throws -> WordReviewTodaySummary {
        try await networkManager.request(
            endpoint: "review/today",
            method: "GET",
            responseType: WordReviewTodaySummary.self
        )
    }

    func listTasks(status: String) async throws -> WordReviewTasksResponse {
        try await networkManager.request(
            endpoint: "review/tasks?status=\(status)",
            method: "GET",
            responseType: WordReviewTasksResponse.self
        )
    }

    func submitResult(entryId: Int64, result: String) async throws -> WordReviewResultResponse {
        let response = try await networkManager.request(
            endpoint: "review/tasks/\(entryId)/result",
            method: "POST",
            body: ["result": result],
            responseType: WordReviewResultResponse.self
        )
        await MainActor.run {
            NotificationCenter.default.post(name: .reviewTasksDidChange, object: nil)
            NotificationCenter.default.post(name: .wordBookDidChange, object: nil)
        }
        return response
    }
}
