import Foundation

/// A snapshot for immediate display; the server still determines today's tasks and results.
struct ReviewTaskCache: Codable {
    let summary: WordReviewTodaySummary
    let pending: [WordReviewTaskItem]
    let completed: [WordReviewTaskItem]

    static func load(userID: String?) -> ReviewTaskCache? {
        guard let url = fileURL(userID: userID),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save(userID: String?) {
        guard let url = Self.fileURL(userID: userID),
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func fileURL(userID: String?) -> URL? {
        guard let userID, !userID.isEmpty else { return nil }
        return UserScopedStorage.applicationSupportUserDirectory(userId: userID)
            .appendingPathComponent("review-tasks-v1.json")
    }
}
