import Foundation

extension Notification.Name {
    static let reviewTasksDidChange = Notification.Name("ReadingCoachReviewTasksDidChange")
}

struct ReviewAPI {
    static let shared = ReviewAPI()
    private let networkManager = NetworkManager.shared

    func listTasks(status: String) async throws -> ReviewTasksResponse {
        try await networkManager.request(
            endpoint: "review/tasks?status=\(status)",
            method: "GET",
            responseType: ReviewTasksResponse.self
        )
    }

    func completeTask(articleId: String) async throws -> ReviewTaskCompletionResponse {
        let response = try await networkManager.request(
            endpoint: "review/articles/\(articleId)/complete",
            method: "POST",
            responseType: ReviewTaskCompletionResponse.self
        )
        if response.completed {
            await MainActor.run {
                NotificationCenter.default.post(name: .reviewTasksDidChange, object: nil)
            }
        }
        return response
    }
}
