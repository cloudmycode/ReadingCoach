import Foundation
import CryptoKit

struct ReadingQuizQuestion: Decodable, Identifiable {
    let id: Int
    let type: String
    let prompt: String
    let quote: String
    enum CodingKeys: String, CodingKey { case id, type, prompt; case quote = "source_quote" }
    var index: Int { id - 1 }
    var kind: String {
        ["translation": "原句翻译", "vocabulary": "语境词义", "sentence_meaning": "句意理解",
         "comprehension": "内容理解", "summary": "主旨概括"][type] ?? "阅读理解"
    }
}

struct ReadingPreparation: Decodable {
    let attempts: Int
    let maxAttempts: Int
    let startedAt: TimeInterval
    enum CodingKeys: String, CodingKey {
        case attempts, maxAttempts = "max_attempts", startedAt = "started_at"
    }
}

struct ReadingPaper: Decodable {
    let id: Int
    let articleID: String
    let contentHash: String
    let status: String
    let preparation: ReadingPreparation?
    private let items: [ReadingQuizQuestion]?
    let completedSentenceIDs: [Int]
    let totalSentences: Int
    let unlocked: Bool
    var questions: [ReadingQuizQuestion] { (items ?? []).sorted { $0.id < $1.id } }
    var isReady: Bool { status == "ready" && questions.map(\.id) == Array(1...5) }
    enum CodingKeys: String, CodingKey {
        case id, status, unlocked, preparation
        case articleID = "article_id", contentHash = "content_hash", items = "questions"
        case completedSentenceIDs = "completed_sentence_ids", totalSentences = "total_sentences"
    }
}

struct ReadingAnswer: Codable, Equatable {
    let questionID: Int
    let answer: String
    enum CodingKeys: String, CodingKey { case questionID = "question_id", answer }
}
struct ReadingVerdict: Decodable {
    let questionID: Int
    let verdict: String
    let feedback: String
    enum CodingKeys: String, CodingKey { case questionID = "question_id", verdict, feedback }
}
struct ReadingAttempt: Decodable, Identifiable {
    let id: Int
    let paperID: Int
    let status: String
    let answers: [ReadingAnswer]
    private let verdicts: [ReadingVerdict]?
    let score: Int?
    let passed: Bool
    let submittedOn: String
    var results: [ReadingVerdict] { verdicts ?? [] }
    var isPending: Bool { status == "queued" || status == "running" }
    var isResult: Bool { status == "graded" || status == "review_required" }
    enum CodingKeys: String, CodingKey {
        case id, status, answers, score, passed
        case paperID = "paper_id", verdicts = "results", submittedOn = "submitted_on"
    }
}

struct ReadingRewardTier: Decodable, Equatable {
    let days: Int
    let stars: Int
    let amountFen: Int
    var amount: Int { amountFen / 100 }
    var title: String { stars == 0 ? "尚未获得星级" : "\(["", "一", "二", "三", "四", "五", "六", "七"][min(7, max(0, stars))])星奖励" }
    enum CodingKeys: String, CodingKey { case days, stars; case amountFen = "amount_fen" }
    static let zero = ReadingRewardTier(days: 0, stars: 0, amountFen: 0)
}
struct ReadingCycle: Decodable, Identifiable {
    let id: Int
    let today: String
    let startsOn: String
    let endsOn: String
    let timezone: String
    let status: String
    let completedDates: [String]
    let pendingAttempts: Int
    let tier: ReadingRewardTier
    let tiers: [ReadingRewardTier]
    enum CodingKeys: String, CodingKey {
        case id, today, timezone, status, tier, tiers
        case startsOn = "starts_on", endsOn = "ends_on", completedDates = "completed_dates", pendingAttempts = "pending_attempts"
    }
    func date(on day: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        guard let start = formatter.date(from: startsOn),
              let date = calendar.date(byAdding: .day, value: day - 1, to: start) else { return "" }
        return formatter.string(from: date)
    }
    func completed(on day: Int) -> Bool { completedDates.contains(date(on: day)) }
}
struct ReadingVoucher: Decodable, Identifiable {
    let id: Int
    let stars: Int
    let days: Int
    let amountFen: Int
    private let issuedTimestamp: TimeInterval
    private let redeemedTimestamp: TimeInterval?
    var amount: Int { amountFen / 100 }
    var issuedAt: Date { Date(timeIntervalSince1970: issuedTimestamp) }
    var redeemedAt: Date? { redeemedTimestamp.map(Date.init(timeIntervalSince1970:)) }
    var tier: ReadingRewardTier { .init(days: days, stars: stars, amountFen: amountFen) }
    enum CodingKeys: String, CodingKey {
        case id, stars
        case days = "completed_days", amountFen = "amount_fen", issuedTimestamp = "issued_at", redeemedTimestamp = "redeemed_at"
    }
}

struct ReadingVoucherListState {
    private(set) var showRedeemed = false
    private(set) var recentlyRedeemedIDs: Set<Int> = []
    func displayed(from vouchers: [ReadingVoucher]) -> [ReadingVoucher] {
        vouchers.filter { showRedeemed ? $0.redeemedAt != nil : ($0.redeemedAt == nil || recentlyRedeemedIDs.contains($0.id)) }
    }
    mutating func didRedeem(_ id: Int) { recentlyRedeemedIDs.insert(id) }
    mutating func select(redeemed: Bool) {
        guard redeemed != showRedeemed else { return }
        recentlyRedeemedIDs.removeAll()
        showRedeemed = redeemed
    }
    mutating func clearFeedback() { recentlyRedeemedIDs.removeAll() }
}

struct ReadingSource: Equatable {
    let id: Int
    let text: String
    // Match Go's encoding/json exactly, including HTML escaping, to reject stale cached audio.
    static func hash(_ source: [ReadingSource]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let rows = source.map { sentence -> String in
            let encoded = String(data: try! encoder.encode(sentence.text), encoding: .utf8)!
                .replacingOccurrences(of: "<", with: "\\u003c")
                .replacingOccurrences(of: ">", with: "\\u003e")
                .replacingOccurrences(of: "&", with: "\\u0026")
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            return "{\"id\":\(sentence.id),\"text\":\(encoded)}"
        }
        return SHA256.hash(data: Data(("[" + rows.joined(separator: ",") + "]").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
