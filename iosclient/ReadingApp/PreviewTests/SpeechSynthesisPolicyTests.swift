import Foundation

@main struct SpeechSynthesisPolicyChecks {
    @MainActor static func main() async throws {
        precondition(SpeechSynthesisPolicy.inactivityTimeout == 5)
        var attempts: [Int] = []
        let value = try await SpeechSynthesisPolicy.retryOnce { attempt in
            attempts.append(attempt)
            if attempt == 1 { throw URLError(.timedOut) }
            return "audio"
        }
        precondition(value == "audio" && attempts == [1, 2])

        attempts = []
        do {
            let _: String = try await SpeechSynthesisPolicy.retryOnce { attempt in
                attempts.append(attempt)
                throw URLError(.timedOut)
            }
            preconditionFailure("Expected a final timeout")
        } catch is SpeechSynthesisTimeoutError {
            precondition(attempts == [1, 2])
        }

        for code in [URLError.cancelled, .badServerResponse, .notConnectedToInternet] {
            attempts = []
            do {
                let _: String = try await SpeechSynthesisPolicy.retryOnce { attempt in
                    attempts.append(attempt)
                    throw URLError(code)
                }
                preconditionFailure("Expected a non-retryable failure")
            } catch {
                precondition((error as? URLError)?.code == code && attempts == [1])
            }
        }

        var started = false
        var cancellationAttempts = 0
        let cancelled = Task {
            let _: String = try await SpeechSynthesisPolicy.retryOnce { _ in
                cancellationAttempts += 1
                started = true
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { throw URLError(.timedOut) } // A socket timeout races with user cancellation.
                return "audio"
            }
        }
        while !started { await Task.yield() }
        cancelled.cancel()
        do { try await cancelled.value; preconditionFailure("Expected cancellation") }
        catch is CancellationError { precondition(cancellationAttempts == 1) }

        var disconnects = 0
        let timer = SpeechInactivityTimeout(interval: 0.15) { disconnects += 1 }
        // Total synthesis exceeds the timeout, but regular audio must keep it alive.
        for _ in 0..<6 {
            try await Task.sleep(nanoseconds: 40_000_000)
            precondition(!timer.didTimeOut && disconnects == 0)
            timer.receivedAudio()
        }
        try await Task.sleep(nanoseconds: 220_000_000)
        precondition(timer.didTimeOut && disconnects == 1)
        timer.receivedAudio()
        try await Task.sleep(nanoseconds: 180_000_000)
        precondition(disconnects == 1, "A timed-out socket must not revive")
        timer.cancel()

        let completed = SpeechInactivityTimeout(interval: 0.05) { disconnects += 1 }
        completed.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(disconnects == 1 && !completed.didTimeOut, "Finished attempts must cancel their timer")
        print("PASS: timeout reconnects once, retry limit, user cancellation, non-timeout errors, streaming progress, stalled audio disconnect, timer cleanup")
    }
}
