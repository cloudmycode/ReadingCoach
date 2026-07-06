//
//  StatsViewModel.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2026/7/6.
//

import Foundation
import Combine

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var toastMessage: String?
    @Published var stats: StudyStatsResponse = .empty
    
    private var hasLoaded = false
    
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
        hasLoaded = true
    }
    
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            stats = try await StatsAPI.shared.getOverview(days: 7)
        } catch {
            toastMessage = error.localizedDescription
        }
    }
}
