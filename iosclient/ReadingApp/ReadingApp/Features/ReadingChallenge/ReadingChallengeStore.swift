import Foundation
import Combine

@MainActor
final class ReadingChallengeStore: ObservableObject {
    @Published private(set) var cycle: ReadingCycle?
    @Published private(set) var cycles: [ReadingCycle] = []
    @Published private(set) var vouchers: [ReadingVoucher] = []
    @Published private(set) var isLoading = false
    @Published private(set) var redeemingIDs: Set<Int> = []
    @Published var errorMessage: String?
    private let api: ReadingServing
    private let userID: String?
    private let currentUser: @MainActor () -> String?

    init(api: ReadingServing? = nil, currentUser: @escaping @MainActor () -> String? = { UserScopedStorage.currentUserId }) {
        self.api = api ?? ReadingAPI.shared
        self.currentUser = currentUser
        userID = currentUser()
    }
    var completedDays: Int { cycle?.completedDates.count ?? 0 }
    var todayCompleted: Bool { cycle.map { $0.completedDates.contains($0.today) } ?? false }
    var tier: ReadingRewardTier { cycle?.tier ?? .zero }
    var tiers: [ReadingRewardTier] { cycle?.tiers ?? [] }
    var pendingMessage: String? {
        let pending = cycles.filter { $0.id != cycle?.id && $0.pendingAttempts > 0 }.count
        return pending > 0 ? "有 \(pending) 个历史周期等待批改完成后结算。" : nil
    }
    func refresh() async {
        guard !isLoading, userID != nil, currentUser() == userID else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let latest = try await api.challenge()
            guard currentUser() == userID else { return }
            cycle = latest
            let history = try await api.cycles()
            guard currentUser() == userID else { return }
            cycles = history
            var all: [ReadingVoucher] = []
            while true {
                try Task.checkCancellation()
                guard currentUser() == userID else { return }
                let page = try await api.vouchers(offset: all.count)
                all += page
                if page.count < 100 { break }
            }
            guard currentUser() == userID else { return }
            // Preserve a successful concurrent redemption if an older list response arrives later.
            vouchers = all.map { incoming in
                vouchers.first(where: { $0.id == incoming.id && $0.redeemedAt != nil }) ?? incoming
            }
        } catch is CancellationError { }
        catch { if currentUser() == userID { errorMessage = error.localizedDescription } }
    }
    func redeem(_ id: Int) async -> Bool {
        guard currentUser() == userID, userID != nil, !redeemingIDs.contains(id) else { return false }
        redeemingIDs.insert(id)
        defer { redeemingIDs.remove(id) }
        do {
            let voucher = try await api.redeem(id: id)
            guard currentUser() == userID else { return false }
            if let index = vouchers.firstIndex(where: { $0.id == id }) { vouchers[index] = voucher }
            errorMessage = nil
            return voucher.redeemedAt != nil
        } catch { if currentUser() == userID { errorMessage = error.localizedDescription }; return false }
    }
}
