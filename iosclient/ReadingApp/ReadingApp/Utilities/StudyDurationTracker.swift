import Foundation

/// 前台有效学习时长追踪：活跃时累计秒数，定期/退出时通过回调上报。
@MainActor
final class StudyDurationTracker {
    private let idleTimeout: TimeInterval
    private let flushInterval: TimeInterval
    private let report: (Int) async -> Void

    private var accumulatedSeconds = 0
    private var segmentStartedAt: Date?
    private var lastInteractionAt = Date()
    private var isTracking = false
    private var isAppActive = true
    private var flushTask: Task<Void, Never>?

    init(
        idleTimeout: TimeInterval = 60,
        flushInterval: TimeInterval = 15,
        report: @escaping (Int) async -> Void
    ) {
        self.idleTimeout = idleTimeout
        self.flushInterval = flushInterval
        self.report = report
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true
        lastInteractionAt = Date()
        if isAppActive {
            beginSegment()
        }
        startFlushLoop()
    }

    func stop() {
        guard isTracking else { return }
        isTracking = false
        flushTask?.cancel()
        flushTask = nil
        endSegment()
        Task {
            await flushNow()
        }
    }

    func noteInteraction() {
        lastInteractionAt = Date()
        guard isTracking, isAppActive else { return }
        if segmentStartedAt == nil {
            beginSegment()
        }
    }

    func setAppActive(_ active: Bool) {
        isAppActive = active
        guard isTracking else { return }
        if active {
            lastInteractionAt = Date()
            beginSegment()
        } else {
            endSegment()
            Task { await flushNow() }
        }
    }

    private func beginSegment() {
        if segmentStartedAt == nil {
            segmentStartedAt = Date()
        }
    }

    private func endSegment() {
        guard let started = segmentStartedAt else { return }
        let now = Date()
        let idleCut = lastInteractionAt.addingTimeInterval(idleTimeout)
        let effectiveEnd = min(now, idleCut)
        let seconds = max(0, Int(effectiveEnd.timeIntervalSince(started)))
        if seconds > 0 {
            accumulatedSeconds += seconds
        }
        segmentStartedAt = nil
    }

    private func startFlushLoop() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.flushInterval ?? 15) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.tickAndFlush()
            }
        }
    }

    private func tickAndFlush() async {
        guard isTracking else { return }
        if isAppActive {
            let idleDeadline = lastInteractionAt.addingTimeInterval(idleTimeout)
            if Date() > idleDeadline {
                endSegment()
            } else if segmentStartedAt == nil {
                beginSegment()
            } else {
                // 周期性截断当前片段，避免长时间会话只在退出时上报。
                endSegment()
                beginSegment()
            }
        }
        await flushNow()
    }

    private func flushNow() async {
        let seconds = accumulatedSeconds
        guard seconds > 0 else { return }
        accumulatedSeconds = 0
        await report(seconds)
    }
}
