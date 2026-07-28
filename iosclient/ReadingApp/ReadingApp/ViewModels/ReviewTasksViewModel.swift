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

    var currentSessionTask: WordReviewTaskItem? {
        guard sessionIndex >= 0, sessionIndex < sessionQueue.count else { return nil }
        return sessionQueue[sessionIndex]
    }

    var sessionProgressText: String {
        guard !sessionQueue.isEmpty else { return "0 / 0" }
        let current = min(sessionIndex + 1, sessionQueue.count)
        return "\(current) / \(sessionQueue.count)"
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
        } catch {
            if isCancellationError(error) {
                return
            }
            toastMessage = error.localizedDescription
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
    }

    func revealMeaning() {
        isRevealed = true
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
        let next = sessionIndex + 1
        if next >= sessionQueue.count {
            isSessionFinished = true
            isRevealed = false
            return
        }
        sessionIndex = next
        isRevealed = false
    }
}
