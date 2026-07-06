//
//  ArticleListView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import SwiftUI

enum ArticleRoute: Hashable {
    case article(ArticleItem)
    case cameraResult(String)
}

struct ArticleListView: View {
    @StateObject private var viewModel = ArticleListViewModel()
    @FocusState private var isSearchFocused: Bool
    @State private var isCameraPresented = false
    @State private var showFeatureMessage = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appNavigationPath) private var appNavigationPath
    
    var body: some View {
        content
            .navigationBarBackButtonHidden(true)
            .onAppear {
                print("🔵 [ArticleListView] onAppear - appNavigationPath count: \(appNavigationPath?.wrappedValue.count ?? -1)")
            }
            .onDisappear {
                print("🔵 [ArticleListView] onDisappear")
            }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCaptureView(
                onSubmit: { uploadItems in
                    // 调用分析文章图片的 API（使用统一接口）
                    let response = try await AIAPI.shared.analyzeArticleImages(uploadItems)
                    return response.id
                },
                onSuccess: { articleId in
                    if let path = appNavigationPath {
                        path.wrappedValue.append(AppNavigationRoute.articleRoute(.cameraResult(articleId)))
                    }
                    Task {
                        await viewModel.loadArticles()
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
                articleList
                bottomToolbar
            }
        }
        .onAppear {
            Task {
                await viewModel.loadArticles()
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
            if let article = viewModel.articleToDelete {
                Text("确定要删除文章《\(article.title)》吗？此操作不可恢复。")
            }
        }
        .alert("功能建设中", isPresented: $showFeatureMessage) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("收藏和日历会在后续版本继续补齐，当前原型已优先完成阅读主链路和学习统计。")
        }
    }
    
    private var topNavBar: some View {
        HStack {
            Button {
                if let path = appNavigationPath {
                    print("🔵 [ArticleListView] Back button tapped, appNavigationPath count: \(path.wrappedValue.count)")
                } else {
                    print("🔵 [ArticleListView] Back button tapped, appNavigationPath not available")
                }
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Text("阅读记录")
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
            
            TextField("试试搜索文章中的内容，如公司", text: $viewModel.searchKeyword)
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
    
    private var articleList: some View {
        Group {
            if viewModel.filteredArticles.isEmpty && !viewModel.isLoading {
                ScrollView {
                    emptyState
                        .padding(.vertical, 60)
                }
            } else {
                List {
                    ForEach(Array(viewModel.filteredArticles.enumerated()), id: \.element.id) { index, article in
                        Button {
                            print("🔵 [ArticleListView] Appending article to navigationPath: \(article.title)")
                            if let path = appNavigationPath {
                                print("🔵 [ArticleListView] Current navigationPath count: \(path.wrappedValue.count)")
                                withAnimation {
                                    path.wrappedValue.append(AppNavigationRoute.articleRoute(.article(article)))
                                }
                                print("🔵 [ArticleListView] NavigationPath count after append: \(path.wrappedValue.count)")
                            } else {
                                print("🔵 [ArticleListView] ERROR: appNavigationPath not available!")
                            }
                        } label: {
                            ArticleItemRow(article: article, index: index)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                viewModel.requestDelete(article: article)
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
                    await viewModel.loadArticles()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("📖")
                .font(.system(size: 60))
            Text("暂无阅读记录")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(viewModel.searchKeyword.isEmpty ? "点击底部拍照按钮添加文章" : "没有找到符合条件的文章")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            toolbarItem(icon: "doc.text", text: "文章", tab: "article")
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
            handleToolbarTap(tab)
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

    private func handleToolbarTap(_ tab: String) {
        switch tab {
        case "article":
            viewModel.switchTab(tab)
        case "mine":
            viewModel.switchTab(tab)
            appNavigationPath?.wrappedValue.append(AppNavigationRoute.stats)
        default:
            viewModel.switchTab(tab)
            showFeatureMessage = true
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

struct ArticleItemRow: View {
    let article: ArticleItem
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(index + 1).")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(article.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            
            HStack {
                Text("Duration \(article.durationDisplay)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if !article.lastReadDisplay.isEmpty {
                    Text("Read on \(article.lastReadDisplay)")
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
    ArticleListView()
}
