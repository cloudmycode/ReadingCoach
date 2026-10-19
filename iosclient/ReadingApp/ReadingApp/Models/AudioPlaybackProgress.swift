import Foundation

/// Detect a frozen audio clock, including when the player claims it is still playing.
struct AudioPlaybackProgress {
    private var lastPosition: TimeInterval = 0
    private var lastProgressAt: TimeInterval

    init(now: TimeInterval) { lastProgressAt = now }

    mutating func isStalled(position: TimeInterval, now: TimeInterval) -> Bool {
        if position.isFinite, position > lastPosition + 0.001 {
            lastPosition = position
            lastProgressAt = now
        }
        return now - lastProgressAt >= 5
    }
}
