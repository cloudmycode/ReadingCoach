import Foundation

@main struct AudioPlaybackProgressChecks {
    static func main() {
        var neverStarted = AudioPlaybackProgress(now: 10)
        precondition(!neverStarted.isStalled(position: 0, now: 14.99))
        precondition(neverStarted.isStalled(position: 0, now: 15))

        var longSentence = AudioPlaybackProgress(now: 0)
        for second in 1...120 {
            precondition(!longSentence.isStalled(position: Double(second), now: Double(second)))
        }
        precondition(!longSentence.isStalled(position: 120, now: 124.99))
        precondition(longSentence.isStalled(position: 120, now: 125))

        var intermittent = AudioPlaybackProgress(now: 0)
        precondition(!intermittent.isStalled(position: 1, now: 1))
        precondition(!intermittent.isStalled(position: 1, now: 5.9))
        precondition(!intermittent.isStalled(position: 1.1, now: 6))
        precondition(!intermittent.isStalled(position: 1.1, now: 10.9))
        precondition(intermittent.isStalled(position: 1.1, now: 11))

        var resetClock = AudioPlaybackProgress(now: 0)
        precondition(!resetClock.isStalled(position: 3, now: 3))
        precondition(!resetClock.isStalled(position: 0, now: 4))
        precondition(resetClock.isStalled(position: 0, now: 8))
        var invalidClock = AudioPlaybackProgress(now: 0)
        precondition(invalidClock.isStalled(position: .nan, now: 5))
        precondition(invalidClock.isStalled(position: .infinity, now: 6))
        print("PASS: never-started playback, frozen progress, normal long sentences, recovered progress, reset clock and invalid clock")
    }
}
