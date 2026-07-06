//
//  WordListViewModel.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation
import Combine

// 单词单元数据模型
struct WordUnitItem: Identifiable, Hashable {
    let id: String
    let title: String
    let wordCount: Int
    let lastStudyAt: String?
    
    var lastStudyDisplay: String {
        guard let lastStudyAt = lastStudyAt, !lastStudyAt.isEmpty else {
            return ""
        }
        // TODO: 格式化日期显示
        return lastStudyAt
    }
}

@MainActor
final class WordListViewModel: ObservableObject {
    @Published var units: [WordUnitItem] = []
    @Published var isLoading: Bool = false
    @Published var toastMessage: String?
    @Published var showDeleteConfirmation: Bool = false
    @Published var unitToDelete: WordUnitItem?
    @Published var searchKeyword: String = ""
    @Published var currentTab: String = "word"
    
    private var hasLoaded = false
    
    var filteredUnits: [WordUnitItem] {
        if searchKeyword.isEmpty {
            return units
        }
        return units.filter { unit in
            unit.title.localizedCaseInsensitiveContains(searchKeyword)
        }
    }
    
    func loadWordUnitsIfNeeded() async {
        guard !hasLoaded else { return }
        await loadWordUnits()
        hasLoaded = true
    }
    
    func loadWordUnits() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        
        // TODO: 调用实际的 API 获取单词单元列表
        // 目前使用模拟数据
        do {
            // 模拟 API 调用延迟
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            
            // 模拟数据
            units = [
                WordUnitItem(id: "1", title: "Unit 1: 基础词汇", wordCount: 50, lastStudyAt: "2025-11-26"),
                WordUnitItem(id: "2", title: "Unit 2: 日常用语", wordCount: 45, lastStudyAt: "2025-11-25"),
                WordUnitItem(id: "3", title: "Unit 3: 商务英语", wordCount: 60, lastStudyAt: nil),
            ]
        } catch {
            toastMessage = error.localizedDescription
        }
    }
    
    func requestDelete(unit: WordUnitItem) {
        unitToDelete = unit
        showDeleteConfirmation = true
    }
    
    func confirmDelete() async {
        guard let unit = unitToDelete else { return }
        
        // 立即从列表中移除
        units.removeAll { $0.id == unit.id }
        showDeleteConfirmation = false
        unitToDelete = nil
        
        // TODO: 异步调用云接口删除，不等待结果，不处理错误
        // Task {
        //     try? await WordAPI.shared.deleteUnit(unitId: unit.id)
        // }
    }
    
    func cancelDelete() {
        showDeleteConfirmation = false
        unitToDelete = nil
    }
    
    func onSearchInput(_ keyword: String) {
        searchKeyword = keyword
    }
    
    func switchTab(_ tab: String) {
        currentTab = tab
    }
}

