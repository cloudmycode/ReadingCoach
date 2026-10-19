import Foundation

// Standalone app dependencies; the production HTTP client and ReadingAPI remain under test.
enum UserScopedStorage { static var currentUserId: String? = "child-a" }
final class UserManager {
    static let shared = UserManager()
    var loggedOut = false
    func currentToken() -> String? { "test-token" }
    func logoutCurrentUser() { loggedOut = true }
}
struct APIResponse<T: Decodable>: Decodable { let success: Bool; let message: String; let data: T? }
enum APIError: LocalizedError {
    case invalidURL, decoding, network(Error), server(message: String), http(status: Int, message: String)
    var errorDescription: String? { "测试请求失败" }
}
func decoded<T: Decodable>(_ object: Any, as type: T.Type = T.self) -> T {
    try! JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
}
let testSource = [ReadingSource(id: 11, text: "Emma helped him."), ReadingSource(id: 12, text: "He thanked her.")]
let testQuestions: [[String: Any]] = (1...5).map { ["id": $0, "type": "comprehension", "prompt": "Question \($0)?", "source_quote": "Emma helped him."] }
func paperObject(hash: String = ReadingSource.hash(testSource), completed: [Int] = [], status: String = "ready") -> [String: Any] {
    ["id": 7, "article_id": "article-A", "content_hash": hash, "status": status,
     "questions": status == "ready" ? testQuestions : [], "completed_sentence_ids": completed, "total_sentences": 2, "unlocked": completed.count == 2]
}
func attemptObject(id: Int = 1, status: String = "queued", answers: [ReadingAnswer] = []) -> [String: Any] {
    ["id": id, "paper_id": 7, "status": status, "answers": answers.map { ["question_id": $0.questionID, "answer": $0.answer] },
     "results": status == "review_required" ? [["question_id": 1, "verdict": "needs_review", "feedback": "请补充说明"]] : NSNull(),
     "score": status == "graded" ? 80 : NSNull(), "passed": status == "graded", "submitted_on": "2026-09-22"]
}
let cycleObject: [String: Any] = ["id": 1, "today": "2026-09-22", "starts_on": "2026-09-20", "ends_on": "2026-10-19",
    "timezone": "Asia/Shanghai", "status": "active", "completed_dates": ["2026-09-20", "2026-09-22"], "pending_attempts": 0,
    "tier": ["days": 0, "stars": 0, "amount_fen": 0], "tiers": [["days": 5, "stars": 1, "amount_fen": 500]]]
func voucherObject(redeemed: Bool = false) -> [String: Any] {
    ["id": 9, "stars": 7, "completed_days": 30, "amount_fen": 5000, "issued_at": 1770000000,
     "redeemed_at": redeemed ? 1770000500 : NSNull()]
}

@MainActor
final class FakeReadingAPI: ReadingServing {
    var hash = ReadingSource.hash(testSource)
    var completed: [Int] = []
    var records: [Int] = []
    var savedAttempts: [ReadingAttempt] = []
    var submissions: [(String, [ReadingAnswer])] = []
    var failListening = false
    var loseSubmitResponse = false
    var rejectSubmit = false
    var failRedeem = false
    var redeemed = false
    var switchAccountOnPaper = false
    var paperStatus = "ready"
    var preparation: [String: Any]?
    func paper(articleID: String) async throws -> ReadingPaper {
        if switchAccountOnPaper { UserScopedStorage.currentUserId = "child-b" }
        var object = paperObject(hash: hash, completed: completed, status: paperStatus)
        object["preparation"] = preparation
        return decoded(object)
    }
    func completeListening(articleID: String, paper: ReadingPaper, sentenceID: Int) async throws {
        if failListening { throw URLError(.notConnectedToInternet) }
        records.append(sentenceID)
        if !completed.contains(sentenceID) { completed.append(sentenceID) }
    }
    func submit(articleID: String, paperID: Int, requestID: String, answers: [ReadingAnswer]) async throws -> ReadingAttempt {
        submissions.append((requestID, answers))
        if rejectSubmit { throw APIError.http(status: 409, message: "conflict") }
        if loseSubmitResponse { throw URLError(.timedOut) }
        let attempt: ReadingAttempt = decoded(attemptObject(answers: answers))
        savedAttempts = [attempt]
        return attempt
    }
    func attempts(articleID: String) async throws -> [ReadingAttempt] { savedAttempts }
    func attempt(id: Int) async throws -> ReadingAttempt { savedAttempts.first! }
    func retry(kind: String, id: Int) async throws {
        if kind == "attempts", let previous = savedAttempts.first {
            savedAttempts = [decoded(attemptObject(id: id, answers: previous.answers))]
        }
    }
    func challenge() async throws -> ReadingCycle { decoded(cycleObject) }
    func cycles() async throws -> [ReadingCycle] { [decoded(cycleObject)] }
    func vouchers(offset: Int) async throws -> [ReadingVoucher] { [decoded(voucherObject(redeemed: redeemed))] }
    func redeem(id: Int) async throws -> ReadingVoucher {
        if failRedeem { throw URLError(.timedOut) }
        redeemed = true
        return decoded(voucherObject(redeemed: true))
    }
}
final class ReadingHTTPStub: URLProtocol {
    static var captured: [URLRequest] = []
    static var status = 200
    static var payload: Any = paperObject()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.captured.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let bytes = try! JSONSerialization.data(withJSONObject: ["success": Self.status < 400, "message": "test", "data": Self.payload])
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main
struct ReadingClientTests {
    @MainActor static func main() async throws {
        let suite = "ReadingClientTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try SpeechWordTimingChecks.run()
        let hashVector = [ReadingSource(id: 11, text: "A & <b> / 🥳.\n\"He\u{2028}said\u{2029}\""), ReadingSource(id: 12, text: "He thanked her.")]
        precondition(ReadingSource.hash(hashVector) == "478346ae78b0d27190e8b5f49d729c4be5d81295b7784999917fa1abfb01e930", "Hash must match Go encoding/json")
        let api = FakeReadingAPI()
        func store(_ articleID: String = "article-A") -> ReadingQuizStore {
            let store = ReadingQuizStore(articleID: articleID, api: api, defaults: defaults)
            store.prepare(title: "Article", source: testSource)
            return store
        }
        let preparing = store("preparing")
        for sentence in testSource { preparing.recordListened(sentenceID: sentence.id) }
        precondition(preparing.statusText.contains("获取小测状态"))
        api.paperStatus = "queued"
        api.preparation = ["attempts": 0, "max_attempts": 5, "started_at": Date().timeIntervalSince1970]
        await preparing.refresh()
        precondition(!preparing.canOpen && preparing.isPreparing && preparing.statusText.contains("排队"))
        api.paperStatus = "running"
        api.preparation?["attempts"] = 1
        await preparing.refresh()
        precondition(preparing.statusText.contains("检查题目"))
        api.preparation?["started_at"] = Date().timeIntervalSince1970 - 120
        await preparing.refresh()
        precondition(preparing.statusText.contains("时间较长"))
        api.preparation?["attempts"] = 3
        await preparing.refresh()
        precondition(preparing.statusText.contains("第 3 / 5 次") && !preparing.canOpen)
        api.paperStatus = "failed"
        await preparing.refresh()
        precondition(preparing.statusText.contains("请重试") && !preparing.isPreparing)
        let preparingResumed = store("preparing")
        api.paperStatus = "ready"; api.preparation = nil
        await preparingResumed.refresh()
        precondition(preparingResumed.canOpen && preparingResumed.listenedCount == 2 && api.records == [11, 12])
        api.completed = []; api.records = []
        let lastOnly = store("last-only")
        lastOnly.recordListened(sentenceID: 12)
        lastOnly.recordListened(sentenceID: 12)
        lastOnly.recordListened(sentenceID: -1)
        await lastOnly.refresh()
        precondition(!lastOnly.canOpen && lastOnly.listenedCount == 1)
        api.completed = []; api.records = []
        let edited = store("edited")
        edited.recordListened(sentenceID: 11)
        edited.prepare(title: "New", source: [ReadingSource(id: 11, text: "Changed.")])
        precondition(edited.listenedCount == 0 && !edited.canOpen)
        let first = store()
        await first.refresh()
        precondition(!first.canOpen)
        first.recordListened(sentenceID: 11)
        api.failListening = true
        await first.refresh()
        precondition(first.errorMessage != nil && !first.canOpen)
        let resumed = store()
        precondition(resumed.listenedCount == 1)
        api.failListening = false
        await resumed.refresh()
        precondition(api.completed == [11] && !resumed.canOpen)
        resumed.recordListened(sentenceID: 12)
        await resumed.refresh()
        precondition(resumed.canOpen && api.records == [11,12])
        await resumed.refresh()
        precondition(api.records == [11,12])
        resumed.answer("my answer", at: 0)
        api.loseSubmitResponse = true
        await resumed.submit()
        precondition(resumed.answersLocked && resumed.attempt == nil)
        resumed.answer("must not replace frozen answer", at: 0)
        let restarted = store()
        await restarted.refresh()
        api.loseSubmitResponse = false
        await restarted.submit()
        precondition(api.submissions.count == 2 && api.submissions[0].0 == api.submissions[1].0 && api.submissions[0].1 == api.submissions[1].1)
        precondition(restarted.attempt?.isPending == true)
        api.savedAttempts = [decoded(attemptObject(status: "failed", answers: api.submissions[1].1))]
        await restarted.pollAttempt()
        await restarted.retrySystemTask()
        precondition(restarted.attempt?.isPending == true)
        api.savedAttempts = [decoded(attemptObject(status: "review_required", answers: api.submissions[1].1))]
        await restarted.pollAttempt()
        precondition(restarted.attempt?.score == nil && restarted.attempt?.isResult == true)
        restarted.retry()
        await restarted.refresh()
        precondition(restarted.attempt == nil && restarted.answeredCount == 0)
        api.rejectSubmit = true
        restarted.answer("another try", at: 0)
        await restarted.submit()
        precondition(!restarted.answersLocked && restarted.answers[0] == "another try")
        api.rejectSubmit = false
        await restarted.submit()
        precondition(api.submissions.last!.0 != api.submissions[0].0)
        let changed = store("changed")
        changed.recordListened(sentenceID: 11)
        api.hash = "new server version"
        let previousRecords = api.records.count
        await changed.refresh()
        precondition(changed.paper == nil && changed.errorMessage != nil && api.records.count == previousRecords)
        api.hash = ReadingSource.hash(testSource)
        api.switchAccountOnPaper = true
        let scoped = store("scoped")
        scoped.recordListened(sentenceID: 11)
        await scoped.refresh()
        precondition(scoped.paper == nil && api.records.count == previousRecords)
        precondition(store().answeredCount == 0)
        UserScopedStorage.currentUserId = "child-a"
        api.switchAccountOnPaper = false
        let rewards = ReadingChallengeStore(api: api)
        await rewards.refresh()
        precondition(rewards.completedDays == 2 && rewards.todayCompleted)
        precondition(rewards.cycle!.completed(on: 1) && !rewards.cycle!.completed(on: 2) && rewards.cycle!.completed(on: 3))
        precondition(rewards.cycle!.date(on: 30) == "2026-10-19")
        precondition(rewards.vouchers[0].amount == 50 && rewards.vouchers[0].issuedAt.timeIntervalSince1970 == 1770000000)
        api.failRedeem = true
        let failed = await rewards.redeem(9)
        precondition(!failed && rewards.vouchers[0].redeemedAt == nil)
        api.failRedeem = false
        var list = ReadingVoucherListState()
        if await rewards.redeem(9) { list.didRedeem(9) }
        precondition(!list.showRedeemed && list.displayed(from: rewards.vouchers).count == 1)
        list.select(redeemed: true)
        list.select(redeemed: false)
        precondition(list.displayed(from: rewards.vouchers).isEmpty)
        // Wire format: existing JWT and URL, 202 envelopes, request body, 409 details and 401 logout.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReadingHTTPStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let http = ReadingAPI(network: NetworkManager(session: session))
        let paper = try await http.paper(articleID: "encrypted-id")
        precondition(paper.questions.map(\.id) == [1,2,3,4,5])
        precondition(ReadingHTTPStub.captured.last!.url!.path == "/api/articles/encrypted-id/quiz")
        precondition(ReadingHTTPStub.captured.last!.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        ReadingHTTPStub.status = 202
        ReadingHTTPStub.payload = attemptObject()
        let accepted = try await http.submit(articleID: "encrypted-id", paperID: 7, requestID: "request-123", answers: [.init(questionID: 1, answer: "Hello")])
        precondition(accepted.score == nil && accepted.results.isEmpty)
        let request = ReadingHTTPStub.captured.last!
        let body: Data
        if let data = request.httpBody { body = data } else {
            let stream = request.httpBodyStream!
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            body = data
        }
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        precondition(request.httpMethod == "POST" && json["request_id"] as? String == "request-123" && json["paper_id"] as? Int == 7)
        ReadingHTTPStub.status = 409
        do { _ = try await http.paper(articleID: "a"); preconditionFailure("409 should fail") }
        catch APIError.http(let status, _) { precondition(status == 409) }
        ReadingHTTPStub.status = 401
        do { _ = try await http.challenge(); preconditionFailure("401 should fail") } catch { precondition(UserManager.shared.loggedOut) }
        print("PASS: listening outbox/restart, server gate, version/account isolation, lost submission response, frozen idempotent retry, nullable results, retry practice, definitive rejection, real calendar dates, voucher failure/in-place success, production HTTP routes/JWT/202/409/401.")
    }
}
