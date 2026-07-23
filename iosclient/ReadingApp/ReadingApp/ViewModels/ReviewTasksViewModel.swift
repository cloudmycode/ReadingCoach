import Foundation
import Combine

@MainActor
final class ReviewTasksViewModel: ObservableObject {
    @Published var currentTasks: [ReviewTaskItem] = []
    @Published var completedTasks: [ReviewTaskItem] = []
    @Published var isLoading = false
    @Published var toastMessage: String?

    func loadTasks() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let pendingResponse = ReviewAPI.shared.listTasks(status: "pending")
            async let completedResponse = ReviewAPI.shared.listTasks(status: "completed")
            let (pending, completed) = try await (pendingResponse, completedResponse)
            currentTasks = pending.items
            completedTasks = completed.items
            toastMessage = nil
        } catch is CancellationError {
            return
        } catch {
            toastMessage = error.localizedDescription
        }
    }
}
