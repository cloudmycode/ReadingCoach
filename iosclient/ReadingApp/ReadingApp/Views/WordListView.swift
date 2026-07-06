//
//  WordListView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import SwiftUI

enum WordRoute: Hashable {
    case wordUnit(WordUnitItem)
}

struct WordListView: View {
    @StateObject private var viewModel = WordListViewModel()
    @FocusState private var isSearchFocused: Bool
    @State private var navigationPath = NavigationPath()
    @State private var isCameraPresented = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationBarHidden(true)
                .navigationDestination(for: WordRoute.self) { route in
                    switch route {
                    case .wordUnit(let unit):
                        // TODO: 创建单词单元详情页面
                        Text("单词单元: \(unit.title)")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCaptureView(
                onSubmit: { uploadItems in
                    // TODO: 调用分析单词图片的 API
                    // let response = try await WordAPI.shared.analyzeWordImages(uploadItems)
                    // return response.unitId
                    // 暂时返回模拟数据
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 模拟延迟
                    return "unit_1"
                },
                onSuccess: { unitId in
                    // TODO: 处理成功后的逻辑，比如导航到单词单元详情
                    Task {
                        await viewModel.loadWordUnits()
                    }
                }
            )
        }
    }
    
    private var content: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                topNavBar
                searchBar
                wordUnitList
                bottomToolbar
            }
            
            if viewModel.isLoading {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                ProgressView("正在加载单词单元...")
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
            }
        }
        .onAppear {
            Task {
                await viewModel.loadWordUnits()
            }
        }
        .alert(viewModel.toastMessage ?? "", isPresented: Binding(
            get: { viewModel.toastMessage != nil },
            set: { _ in viewModel.toastMessage = nil }
        )) {
            Button("确定", role: .cancel) { viewModel.toastMessage = nil }
        }
        .alert("确认删除", isPresented: $viewModel.showDeleteConfirmation) {
            Button("取消", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("删除", role: .destructive) {
                Task {
                    await viewModel.confirmDelete()
                }
            }
        } message: {
            if let unit = viewModel.unitToDelete {
                Text("确定要删除单词单元《\(unit.title)》吗？此操作不可恢复。")
            }
        }
    }
    
    private var topNavBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Text("单词单元")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // 占位保持平衡
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .padding(.leading, 12)
            
            TextField("试试搜索单词单元，如 Unit 1", text: $viewModel.searchKeyword)
                .focused($isSearchFocused)
                .onChange(of: viewModel.searchKeyword) { oldValue, newValue in
                    viewModel.onSearchInput(newValue)
                }
                .padding(.vertical, 12)
        }
        .background(Color(red: 0.94, green: 0.94, blue: 0.94))
        .cornerRadius(25)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var wordUnitList: some View {
        Group {
            if viewModel.filteredUnits.isEmpty && !viewModel.isLoading {
                ScrollView {
                    emptyState
                        .padding(.vertical, 60)
                }
            } else {
                List {
                    ForEach(Array(viewModel.filteredUnits.enumerated()), id: \.element.id) { index, unit in
                        Button {
                            navigationPath.append(WordRoute.wordUnit(unit))
                        } label: {
                            WordUnitItemRow(unit: unit, index: index)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                viewModel.requestDelete(unit: unit)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(red: 0.97, green: 0.97, blue: 0.97))
                .refreshable {
                    await viewModel.loadWordUnits()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("📚")
                .font(.system(size: 60))
            Text("暂无单词单元")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(viewModel.searchKeyword.isEmpty ? "点击底部按钮添加单词单元" : "没有找到符合条件的单词单元")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            toolbarItem(icon: "book.fill", text: "单词集", tab: "word")
            toolbarItem(icon: "calendar", text: "日历", tab: "calendar")
            cameraButton
            toolbarItem(icon: "star", text: "收藏", tab: "favorite")
            toolbarItem(icon: "person", text: "我的", tab: "mine")
        }
        .frame(height: 60)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(red: 0.9, green: 0.9, blue: 0.9)),
            alignment: .top
        )
    }
    
    private func toolbarItem(icon: String, text: String, tab: String) -> some View {
        Button {
            viewModel.switchTab(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(viewModel.currentTab == tab ? Color(red: 0.03, green: 0.76, blue: 0.38) : .gray)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.currentTab == tab ? Color(red: 0.03, green: 0.76, blue: 0.38) : .gray)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private var cameraButton: some View {
        Button {
            isCameraPresented = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color(red: 0.03, green: 0.76, blue: 0.38))
                    .clipShape(Circle())
                    .shadow(color: Color(red: 0.03, green: 0.76, blue: 0.38).opacity(0.3), radius: 8, x: 0, y: 4)
                Text("相机")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.03, green: 0.76, blue: 0.38))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct WordUnitItemRow: View {
    let unit: WordUnitItem
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(index + 1).")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(unit.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            
            HStack {
                Text("单词数: \(unit.wordCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if !unit.lastStudyDisplay.isEmpty {
                    Text("学习于 \(unit.lastStudyDisplay)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
    }
}

#Preview {
    WordListView()
}

