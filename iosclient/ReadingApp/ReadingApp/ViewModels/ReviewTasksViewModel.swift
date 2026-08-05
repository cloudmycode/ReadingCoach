import Foundation
import Combine

@MainActor
final class ReviewTasksViewModel: ObservableObject {
    @Published var summary: WordReviewTodaySummary = WordReviewTodaySummary(
        dueCount: 0,
        completedCount: 0,
        dailyLimit: 20,
        streakDays: 0
    )
    @Published var pendingTasks: [WordReviewTaskItem] = []
    @Published var completedTasks: [WordReviewTaskItem] = []
    @Published var sessionQueue: [WordReviewTaskItem] = []
    @Published var sessionIndex: Int = 0
    @Published var isRevealed = false
    @Published var isSessionPresented = false
    @Published var isSessionFinished = false
    @Published var masteredInSession = 0
    @Published var againInSession = 0
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var toastMessage: String?
    private var reviewDurationTracker: StudyDurationTracker?

    var currentSessionTask: WordReviewTaskItem? {
        guard sessionIndex >= 0, sessionIndex < sessionQueue.count else { return nil }
        return sessionQueue[sessionIndex]
    }

    var sessionProgressText: String {
        guard !sessionQueue.isEmpty else { return "0 / 0" }
        let current = min(sessionIndex + 1, sessionQueue.count)
        return "\(current) / \(sessionQueue.count)"
    }

    /// 是否有待完成的复习任务（用于任务 Tab 红点）。
    var hasPendingTasks: Bool {
        !pendingTasks.isEmpty
    }

    /// 已完成任务按本地日历日分组（新→旧）。
    var completedTaskGroups: [CompletedWordReviewDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: completedTasks) { task -> Date in
            let date = task.reviewedDate ?? .distantPast
            return calendar.startOfDay(for: date)
        }
        return grouped.keys.sorted(by: >).map { day in
            let tasks = (grouped[day] ?? []).sorted {
                ($0.reviewedDate ?? .distantPast) > ($1.reviewedDate ?? .distantPast)
            }
            return CompletedWordReviewDayGroup(day: day, tasks: tasks)
        }
    }

    func loadTasks() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let summaryResponse = ReviewAPI.shared.todaySummary()
            async let pendingResponse = ReviewAPI.shared.listTasks(status: "pending")
            async let completedResponse = ReviewAPI.shared.listTasks(status: "completed")
            let (today, pending, completed) = try await (summaryResponse, pendingResponse, completedResponse)
            summary = today
            pendingTasks = pending.items
            completedTasks = completed.items
            toastMessage = nil
            await AppIconBadgeManager.refresh(pendingCount: pendingTasks.count)
        } catch {
            if isCancellationError(error) {
                return
            }
            toastMessage = error.localizedDescription
        }
    }

    func reloadForCurrentUser() {
        summary = WordReviewTodaySummary(
            dueCount: 0,
            completedCount: 0,
            dailyLimit: 20,
            streakDays: 0
        )
        pendingTasks = []
        completedTasks = []
        closeSession()
        toastMessage = nil
        Task {
            await AppIconBadgeManager.clear()
        }
    }

    func startSession() {
        guard !pendingTasks.isEmpty else { return }
        sessionQueue = pendingTasks
        sessionIndex = 0
        isRevealed = false
        isSessionFinished = false
        masteredInSession = 0
        againInSession = 0
        isSessionPresented = true
        startReviewDurationTracking()
    }

    func revealMeaning() {
        isRevealed = true
        reviewDurationTracker?.noteInteraction()
    }

    func noteReviewInteraction() {
        reviewDurationTracker?.noteInteraction()
    }

    func setReviewAppActive(_ active: Bool) {
        reviewDurationTracker?.setAppActive(active)
    }

    func submitCurrent(result: String) async {
        guard let task = currentSessionTask, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            _ = try await ReviewAPI.shared.submitResult(entryId: task.entryId, result: result)
            if result == "mastered" {
                masteredInSession += 1
            } else {
                againInSession += 1
            }
            advanceAfterSubmit()
            await loadTasks()
        } catch {
            if isCancellationError(error) {
                return
            }
            toastMessage = error.localizedDescription
        }
    }

    func closeSession() {
        stopReviewDurationTracking()
        isSessionPresented = false
        isSessionFinished = false
        isRevealed = false
        sessionQueue = []
        sessionIndex = 0
        Task {
            await loadTasks()
        }
    }

    private func advanceAfterSubmit() {
        reviewDurationTracker?.noteInteraction()
        let next = sessionIndex + 1
        if next >= sessionQueue.count {
            isSessionFinished = true
            isRevealed = false
            return
        }
        sessionIndex = next
        isRevealed = false
    }

    private func startReviewDurationTracking() {
        stopReviewDurationTracking()
        reviewDurationTracker = StudyDurationTracker { seconds in
            try? await StatsAPI.shared.reportReviewDuration(seconds: seconds)
        }
        reviewDurationTracker?.start()
    }

    private func stopReviewDurationTracking() {
        reviewDurationTracker?.stop()
        reviewDurationTracker = nil
    }
}

struct CompletedWordReviewDayGroup: Identifiable, Hashable {
    let day: Date
    let tasks: [WordReviewTaskItem]

    var id: Date { day }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return "今天"
        }
        if calendar.isDateInYesterday(day) {
            return "昨天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: day)
    }

    var subtitle: String {
        "\(tasks.count) 个单词"
    }
}
