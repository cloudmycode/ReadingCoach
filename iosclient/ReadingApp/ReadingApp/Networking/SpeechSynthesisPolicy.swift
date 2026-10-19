import Foundation

enum SpeechSynthesisTimeoutError: LocalizedError {
    case exhausted
    var errorDescription: String? { "语音生成超时，重新连接后仍未成功，请稍后重试" }
}

@MainActor
enum SpeechSynthesisPolicy {
    nonisolated static let inactivityTimeout: TimeInterval = 5

    /// Only retry timeouts. A manual cancellation or a server rejection must not reconnect.
    static func retryOnce<Value>(_ operation: (Int) async throws -> Value) async throws -> Value {
        for attempt in 1...2 {
            try Task.checkCancellation()
            do {
                return try await operation(attempt)
            } catch {
                try Task.checkCancellation()
                let failure = error as NSError
                guard failure.domain == NSURLErrorDomain, failure.code == URLError.timedOut.rawValue else {
                    throw error
                }
                if attempt == 2 { throw SpeechSynthesisTimeoutError.exhausted }
            }
        }
        throw SpeechSynthesisTimeoutError.exhausted
    }
}

/// Cancels the socket when no audio arrives. Each attempt owns its own watchdog.
@MainActor
final class SpeechInactivityTimeout {
    private let interval: TimeInterval
    private let onTimeout: () -> Void
    private var timer: Task<Void, Never>?
    private(set) var didTimeOut = false

    init(interval: TimeInterval = SpeechSynthesisPolicy.inactivityTimeout, onTimeout: @escaping () -> Void) {
        self.interval = interval
        self.onTimeout = onTimeout
        receivedAudio()
    }

    func receivedAudio() {
        guard !didTimeOut else { return }
        timer?.cancel()
        let nanoseconds = UInt64(interval * 1_000_000_000)
        timer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: nanoseconds) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.didTimeOut = true
            self.onTimeout()
        }
    }

    func cancel() {
        timer?.cancel()
        timer = nil
    }

    deinit { timer?.cancel() }
}
