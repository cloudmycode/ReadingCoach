import SwiftUI

private enum SplitSidebarTab: String {
    case list
    case tasks
}

struct ArticleSplitView: View {
    @StateObject private var viewModel = ArticleListViewModel()
    @StateObject private var reviewTasksViewModel = ReviewTasksViewModel()
    @State private var selectedArticleId: String?
    @State private var isSidebarCollapsed = false
    @State private var isDraftPresented = false
    @State private var isStatsPresented = false
    @State private var selectedSidebarTab: SplitSidebarTab = .list

    private let sidebarWidth: CGFloat = 350

    var body: some View {
        ZStack(alignment: .leading) {
            Color(red: 0.97, green: 0.98, blue: 1.0)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                if !isSidebarCollapsed {
                    sidebar
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                detailPane
            }
        }
        .task {
            await viewModel.loadArticles()
            ensureSelectedArticle()
            await reviewTasksViewModel.loadTasks()
        }
        .onChange(of: viewModel.articles) { _, _ in
            ensureSelectedArticle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewTasksDidChange)) { _ in
            Task {
                await reviewTasksViewModel.loadTasks()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isSidebarCollapsed)
        .fullScreenCover(isPresented: $isDraftPresented) {
            ArticleTextDraftView(
                onSubmitted: { articleId in
                    selectedArticleId = articleId
                    Task {
                        await viewModel.loadArticles()
                    }
                },
                startByCapturing: true
            )
        }
        .sheet(isPresented: $isStatsPresented) {
            NavigationStack {
                StatsView()
            }
        }
        .alert("确认删除", isPresented: $viewModel.showDeleteConfirmation) {
            Button("取消", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("删除", role: .destructive) {
                Task {
                    let deletingId = viewModel.articleToDelete?.id
                    let deleted = await viewModel.confirmDelete()
                    if deleted, selectedArticleId == deletingId {
                        selectedArticleId = viewModel.articles.first?.id
                    }
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
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("Library")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))

                Spacer()

                Button {
                    isStatsPresented = true
                } label: {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.45, green: 0.54, blue: 0.68))
                        .frame(width: 38, height: 38)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    isDraftPresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 0.0, green: 0.4, blue: 1.0))
                        .frame(width: 38, height: 38)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                sidebarTabButton(title: "列表", isActive: selectedSidebarTab == .list) {
                    selectedSidebarTab = .list
                }
                sidebarTabButton(title: "任务", isActive: selectedSidebarTab == .tasks) {
                    selectedSidebarTab = .tasks
                    Task {
                        await reviewTasksViewModel.loadTasks()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Group {
                if selectedSidebarTab == .tasks {
                    ReviewTasksView(
                        viewModel: reviewTasksViewModel,
                        onOpenArticle: { articleId, _ in
                            selectedArticleId = articleId
                            selectedSidebarTab = .list
                        },
                        onAddArticle: {
                            isDraftPresented = true
                        }
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(groupedArticles) { group in
                                VStack(spacing: 0) {
                                    HStack {
                                        Text(group.title)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                                            .tracking(1.0)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(Color(red: 0.96, green: 0.97, blue: 0.99))

                                    ForEach(Array(group.articles.enumerated()), id: \.element.id) { index, article in
                                        HStack(spacing: 0) {
                                            Button {
                                                selectedArticleId = article.id
                                            } label: {
                                                SplitArticleRow(
                                                    article: article,
                                                    stripeColor: stripeColor(for: index),
                                                    isSelected: selectedArticleId == article.id
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
                                        .background(selectedArticleId == article.id ? Color(red: 0.95, green: 0.98, blue: 1.0) : Color.white)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 24)
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
        .background(Color.white)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(red: 0.91, green: 0.94, blue: 0.98))
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selectedArticle {
            ZStack(alignment: .topLeading) {
                ArticleDetailView(
                    articleId: selectedArticle.id,
                    articleTitle: selectedArticle.title,
                    showsBackButton: false
                )
                .id("\(selectedArticle.id)-\(selectedArticle.title)")

                if isSidebarCollapsed {
                    expandButton
                        .padding(.leading, 22)
                        .padding(.top, 18)
                } else {
                    collapseButtonOverlay
                }
            }
        } else {
            VStack(spacing: 18) {
                Text("还没有文章")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                Text("先在左侧新增一篇文章，随后会在这里显示完整阅读内容。")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                Button("新增文章") {
                    isDraftPresented = true
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(red: 0.0, green: 0.4, blue: 1.0))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
    }

    private var collapseButtonOverlay: some View {
        Button {
            isSidebarCollapsed = true
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(red: 0.45, green: 0.54, blue: 0.68))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.leading, 22)
        .padding(.top, 18)
    }

    private var expandButton: some View {
        Button {
            isSidebarCollapsed = false
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.45, green: 0.54, blue: 0.68))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var selectedArticle: ArticleItem? {
        guard let selectedArticleId else { return viewModel.articles.first }
        return viewModel.articles.first(where: { $0.id == selectedArticleId }) ?? viewModel.articles.first
    }

    private var groupedArticles: [SplitArticleSectionGroup] {
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
            return SplitArticleSectionGroup(id: key, title: key, articles: articles)
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        let message = selectedSidebarTab == .tasks ? reviewTasksViewModel.toastMessage : viewModel.toastMessage
        if let message {
            ToastBanner(message: message)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func ensureSelectedArticle() {
        guard !viewModel.articles.isEmpty else {
            selectedArticleId = nil
            return
        }
        if selectedArticleId == nil || !viewModel.articles.contains(where: { $0.id == selectedArticleId }) {
            selectedArticleId = viewModel.articles.first?.id
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

    private func sidebarTabButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isActive ? .white : Color(red: 0.4, green: 0.48, blue: 0.62))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? Color(red: 0.0, green: 0.4, blue: 1.0) : Color(red: 0.95, green: 0.97, blue: 1.0))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SplitArticleSectionGroup: Identifiable {
    let id: String
    let title: String
    let articles: [ArticleItem]
}

private struct SplitArticleRow: View {
    let article: ArticleItem
    let stripeColor: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            stripeColor
                .frame(width: 4)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text("\(article.addedDisplay)  •  \(article.wordCount) words")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.6, green: 0.67, blue: 0.78))
                }

                Spacer(minLength: 8)
            }
            .padding(.leading, 22)
            .padding(.trailing, 10)
            .padding(.vertical, 16)
        }
        .background(isSelected ? Color(red: 0.95, green: 0.98, blue: 1.0) : Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.93, green: 0.95, blue: 0.98))
                .frame(height: 1)
        }
    }
}

private extension ArticleItem {
    var lastReadDate: Date? {
        Self.parseSplitViewISODate(lastReadAt)
    }

    var createdDate: Date? {
        Self.parseSplitViewISODate(createdAt)
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

    static func parseSplitViewISODate(_ string: String?) -> Date? {
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
