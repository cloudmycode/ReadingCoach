import Foundation

/// All reading requests use the app's existing host, JWT and error handling.
@MainActor
protocol ReadingServing {
    func paper(articleID: String) async throws -> ReadingPaper
    func completeListening(articleID: String, paper: ReadingPaper, sentenceID: Int) async throws
    func submit(articleID: String, paperID: Int, requestID: String, answers: [ReadingAnswer]) async throws -> ReadingAttempt
    func attempts(articleID: String) async throws -> [ReadingAttempt]
    func attempt(id: Int) async throws -> ReadingAttempt
    func retry(kind: String, id: Int) async throws
    func challenge() async throws -> ReadingCycle
    func cycles() async throws -> [ReadingCycle]
    func vouchers(offset: Int) async throws -> [ReadingVoucher]
    func redeem(id: Int) async throws -> ReadingVoucher
}

@MainActor
struct ReadingAPI: ReadingServing {
    static let shared = ReadingAPI()
    var network = NetworkManager.shared
    private struct Acknowledgement: Decodable {}
    private func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        try await network.request(endpoint: path, method: body == nil ? "GET" : "POST", body: body, timeout: 30, responseType: T.self)
    }
    func paper(articleID: String) async throws -> ReadingPaper { try await request("articles/\(articleID)/quiz") }
    func completeListening(articleID: String, paper: ReadingPaper, sentenceID: Int) async throws {
        let _: Acknowledgement = try await request("articles/\(articleID)/listening-completions", body: [
            "paper_id": paper.id, "content_hash": paper.contentHash, "sentence_id": sentenceID
        ])
    }
    func submit(articleID: String, paperID: Int, requestID: String, answers: [ReadingAnswer]) async throws -> ReadingAttempt {
        try await request("articles/\(articleID)/quiz/attempts", body: [
            "paper_id": paperID, "request_id": requestID,
            "answers": answers.map { ["question_id": $0.questionID, "answer": $0.answer] as [String: Any] }
        ])
    }
    func attempts(articleID: String) async throws -> [ReadingAttempt] { try await request("articles/\(articleID)/quiz/attempts") }
    func attempt(id: Int) async throws -> ReadingAttempt { try await request("reading/attempts/\(id)") }
    func retry(kind: String, id: Int) async throws {
        let _: Acknowledgement = try await request("reading/\(kind)/\(id)/retry", body: [:])
    }
    func challenge() async throws -> ReadingCycle { try await request("reading/challenge") }
    func cycles() async throws -> [ReadingCycle] { try await request("reading/cycles") }
    func vouchers(offset: Int) async throws -> [ReadingVoucher] { try await request("reading/vouchers?limit=100&offset=\(offset)") }
    func redeem(id: Int) async throws -> ReadingVoucher { try await request("reading/vouchers/\(id)/redeem", body: [:]) }
}
