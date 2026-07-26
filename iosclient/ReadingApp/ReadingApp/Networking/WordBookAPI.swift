import Foundation

struct WordBookAPI {
    static let shared = WordBookAPI()
    private let networkManager = NetworkManager.shared

    func listEntries() async throws -> WordBookListResponse {
        try await networkManager.request(
            endpoint: "word-book",
            method: "GET",
            responseType: WordBookListResponse.self
        )
    }

    func deleteEntry(entryId: Int64) async throws {
        let _: WordBookDeleteResponse = try await networkManager.request(
            endpoint: "word-book/\(entryId)",
            method: "DELETE",
            responseType: WordBookDeleteResponse.self
        )
    }
}

private struct WordBookDeleteResponse: Decodable {
    let entryId: Int64?

    enum CodingKeys: String, CodingKey {
        case entryId = "entry_id"
    }
}
