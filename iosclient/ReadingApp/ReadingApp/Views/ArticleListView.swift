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

private struct ArticleSectionGroup: Identifiable {
    let id: String
    let title: String
    let articles: [ArticleItem]
}

struct ArticleListView: View {
    @StateObject private var viewModel = ArticleListViewModel()
    @StateObject private var reviewTasksViewModel = ReviewTasksViewModel()
    @State private var isDraftPresented = false
    @Environment(\.appNavigationPath) private var appNavigationPath

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                articleSections
                bottomTabBar
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.loadArticles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewTasksDidChange)) { _ in
            Task {
                await reviewTasksViewModel.loadTasks()
            }
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
                Text("确定要删除文章《\(article.title)》吗？")
            }
        }
        .alert("编辑标题", isPresented: $viewModel.showTitleEditor) {
            TextField("文章标题", text: $viewModel.titleDraft)
            Button("取消", role: .cancel) {
                viewModel.cancelTitleEdit()
            }
            Button("保存") {
                Task { await viewModel.confirmTitleEdit() }
            }
            .disabled(!viewModel.canSaveTitle)
        } message: {
            Text("标题不能为空，最多 60 个字符。")
        }
        .fullScreenCover(isPresented: $isDraftPresented) {
            ArticleTextDraftView(
                onSubmitted: { articleId in
                    appNavigationPath?.wrappedValue.append(AppNavigationRoute.articleRoute(.cameraResult(articleId)))
                    Task {
                        await viewModel.loadArticles()
                    }
                },
                startByCapturing: true
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text(viewModel.currentTab == "tasks" ? "任务" : "Library")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))

            Spacer()

            Button {
                isDraftPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 0.0, green: 0.4, blue: 1.0))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(red: 0.92, green: 0.95, blue: 0.98), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, 14)
        .background(Color.white)
    }

    private var articleSections: some View {
        Group {
            if viewModel.currentTab == "tasks" {
                ReviewTasksView(
                    viewModel: reviewTasksViewModel,
                    onOpenArticle: { articleId, articleTitle in
                        let article = viewModel.articles.first(where: { $0.id == articleId }) ?? ArticleItem(
                            id: articleId,
                            articleId: 0,
                            title: articleTitle,
                            sentenceCount: 0,
                            wordCount: 0,
                            readCount: 0,
                            createdAt: "",
                            lastReadAt: nil
                        )
                        appNavigationPath?.wrappedValue.append(
                            AppNavigationRoute.articleRoute(.article(article))
                        )
                    },
                    onAddArticle: {
                        isDraftPresented = true
                    }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        if groupedArticles.isEmpty && !viewModel.isLoading {
                            emptyState
                        } else {
                            ForEach(groupedArticles) { group in
                                sectionView(group)
                            }
                        }
                    }
                    .padding(.bottom, 110)
                }
                .refreshable {
                    await viewModel.refreshArticles()
                }
            }
        }
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        .animation(.easeInOut, value: viewModel.toastMessage)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        let message = viewModel.currentTab == "tasks" ? reviewTasksViewModel.toastMessage : viewModel.toastMessage
        if let message {
            ToastBanner(message: message)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func sectionView(_ group: ArticleSectionGroup) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(group.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                    .tracking(1.0)
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 10)
            .background(Color(red: 0.97, green: 0.98, blue: 1.0))

            ForEach(Array(group.articles.enumerated()), id: \.element.id) { index, article in
                HStack(spacing: 0) {
                    Button {
                        appNavigationPath?.wrappedValue.append(AppNavigationRoute.articleRoute(.article(article)))
                    } label: {
                        ArticleLibraryRow(
                            article: article,
                            stripeColor: stripeColor(for: index)
                        )
                    }
                    .buttonStyle(.plain)

                    ArticleActionsMenu(
                        article: article,
                        isDisabled: viewModel.isMutatingArticle,
                        isWorking: viewModel.deletingArticleId == article.id || viewModel.updatingTitleArticleId == article.id,
                        onEdit: { viewModel.requestTitleEdit(article: article) },
                        onDelete: { viewModel.requestDelete(article: article) }
                    )
                }
                .background(Color.white)
            }
        }
    }

    private var groupedArticles: [ArticleSectionGroup] {
        let calendar = Calendar.current
        let sorted = viewModel.filteredArticles.sorted {
            ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
        }
        let groups = Dictionary(grouping: sorted) { article -> String in
            let date = article.createdDate ?? .distantPast
            if calendar.isDateInToday(date) {
                return "TODAY"
            }
            if calendar.isDateInYesterday(date) {
                return "YESTERDAY"
            }
            return "EARLIER"
        }

        return ["TODAY", "YESTERDAY", "EARLIER"].compactMap { key in
            guard let articles = groups[key], !articles.isEmpty else { return nil }
            return ArticleSectionGroup(id: key, title: key, articles: articles)
        }
    }

    private func stripeColor(for index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.0, green: 0.4, blue: 1.0),
            Color(red: 0.96, green: 0.62, blue: 0.07),
            Color(red: 0.02, green: 0.75, blue: 0.58)
        ]
        return colors[index % colors.count]
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Text("还没有文章")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
            Text("点击右上角加号，拍照识别并创建第一篇文章。")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
            Button("新增文章") {
                isDraftPresented = true
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Color(red: 0.0, green: 0.4, blue: 1.0))
            .clipShape(Capsule())
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private var bottomTabBar: some View {
        HStack {
            tabItem(icon: "list.bullet", title: "列表", isActive: viewModel.currentTab == "list") {
                viewModel.switchTab("list")
            }
            Spacer()
            tabItem(icon: "checklist", title: "任务", isActive: viewModel.currentTab == "tasks") {
                viewModel.switchTab("tasks")
                Task {
                    await reviewTasksViewModel.loadTasks()
                }
            }
            Spacer()
            tabItem(icon: "gearshape", title: "设置", isActive: false) {
                appNavigationPath?.wrappedValue.append(AppNavigationRoute.stats)
            }
        }
        .padding(.horizontal, 54)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(
            Color.white
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(red: 0.92, green: 0.95, blue: 0.98))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabItem(icon: String, title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isActive ? Color(red: 0.0, green: 0.4, blue: 1.0) : Color(red: 0.68, green: 0.73, blue: 0.82))
            .frame(width: 70)
        }
        .buttonStyle(.plain)
    }
}

private struct ArticleLibraryRow: View {
    let article: ArticleItem
    let stripeColor: Color

    var body: some View {
        HStack(spacing: 0) {
            stripeColor
                .frame(width: 5)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text("\(article.addedDisplay)  •  \(article.wordCount) words")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.6, green: 0.67, blue: 0.78))
                }

                Spacer(minLength: 12)
            }
            .padding(.leading, 34)
            .padding(.trailing, 12)
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.93, green: 0.95, blue: 0.98))
                .frame(height: 1)
        }
    }
}

struct ArticleActionsMenu: View {
    let article: ArticleItem
    let isDisabled: Bool
    let isWorking: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button(action: onEdit) {
                Label("编辑标题", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("删除文章", systemImage: "trash")
            }
        } label: {
            Group {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(red: 0.45, green: 0.54, blue: 0.68))
                }
            }
            .frame(width: 46, height: 46)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .accessibilityLabel("文章操作 \(article.title)")
    }
}

private extension ArticleItem {
    var lastReadDate: Date? {
        Self.parseISODate(lastReadAt)
    }

    var createdDate: Date? {
        Self.parseISODate(createdAt)
    }

    var addedDisplay: String {
        guard let createdDate else { return "Added" }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if calendar.isDateInToday(createdDate) {
            return "Added \(formatter.string(from: createdDate))"
        }
        if calendar.isDateInYesterday(createdDate) {
            return "Yesterday"
        }
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: createdDate)
    }

    static func parseISODate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: string) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: string)
    }
}

#Preview {
    ArticleListView()
}
