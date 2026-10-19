import SwiftUI

private enum ChallengeDestination: Hashable { case rewards, wallet }

struct ReadingChallengeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: ReadingChallengeStore
    @State private var path: [ChallengeDestination] = []
    @State private var selectedArticle: ArticleItem?
    @State private var showArticlePicker = false
    @State private var articles: [ArticleItem] = []
    @State private var articleError: String?
    @State private var isLoadingArticles = false
    @State private var hasMoreArticles = true
    @Environment(\.scenePhase) private var scenePhase
    var initialScreen: String? = nil

    init(initialScreen: String? = nil) {
        self.initialScreen = initialScreen
        _store = StateObject(wrappedValue: ReadingChallengeStore())
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("READ & EARN REWARDS", systemImage: "bolt.fill")
                            .font(.caption.bold()).tracking(1)
                            .foregroundStyle(ReadingChallengeTheme.cyan)
                        Text("阅读有收获\n坚持有奖励").font(.largeTitle.bold())
                        Text("读 1 篇文章答 5 题，达到 80 分即点亮任务。")
                            .font(.subheadline).foregroundStyle(ReadingChallengeTheme.onHeroSecondary)
                        VStack(spacing: 10) {
                            HStack {
                                Label("30 天挑战赛", systemImage: "shield.fill")
                                Spacer(minLength: 4)
                                Text("已达标 \(store.completedDays)/30 天")
                                    .foregroundStyle(ReadingChallengeTheme.heroGold)
                            }.font(.caption.bold())
                            ProgressView(value: Double(store.completedDays), total: 30)
                                .tint(ReadingChallengeTheme.heroGold)
                                .accessibilityLabel("阅读挑战进度")
                        }.padding(14)
                            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.16)))
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white)
                    .background(ReadingChallengeTheme.heroGradient, in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: ReadingChallengeTheme.accent.opacity(0.14), radius: 16, y: 10)
                    HStack {
                        Label("今日阅读任务", systemImage: "target").font(.title3.bold())
                        Spacer()
                        Text(store.todayCompleted ? "1 / 1 篇" : "0 / 1 篇")
                            .font(.subheadline.bold()).foregroundStyle(ReadingChallengeTheme.accent)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(ReadingChallengeTheme.softBlue, in: Capsule())
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text(store.todayCompleted ? "今日已达标，继续阅读巩固理解" : "选择一篇文章开始阅读").font(.headline)
                        Text("听完全文音频后，在文章底部开始小测。").font(.subheadline).foregroundStyle(ReadingChallengeTheme.muted)
                        if let article = selectedArticle ?? articles.first {
                            Text(article.title).font(.title2.bold())
                            Text("\(article.wordCount) 词").font(.subheadline).foregroundStyle(.secondary)
                            NavigationLink {
                                ArticleDetailView(articleId: article.id, articleTitle: article.title)
                                    .environment(\.appNavigationPath, nil)
                            } label: {
                                Label("开始阅读闯关", systemImage: "book.fill")
                                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
                                    .foregroundStyle(.white)
                                    .background(ReadingChallengeTheme.heroGradient, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain)
                            Button("选择其他文章") { showArticlePicker = true }.frame(maxWidth: .infinity)
                        } else if !isLoadingArticles && articleError == nil {
                            Text("还没有文章，请回到文章列表添加。").foregroundStyle(.secondary)
                        }
                        if let articleError {
                            Text(articleError).foregroundStyle(.orange).font(.caption)
                            Button("重新加载文章") { Task { await loadArticles() } }.disabled(isLoadingArticles)
                        }
                        if isLoadingArticles { ProgressView() }
                    }.padding(20)
                        .background(ReadingChallengeTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    ReadingLoadStatus(store: store)
                    HStack(spacing: 12) {
                        navigationCard("七星挑战", subtitle: store.tier.stars == 0 ? "暂未获星" : store.tier.title, icon: "star.fill", destination: .rewards)
                        navigationCard("我的兑换券", subtitle: "\(store.vouchers.filter { $0.redeemedAt == nil }.count) 张可用", icon: "ticket.fill", destination: .wallet)
                    }
                }.padding(20).frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(ReadingChallengeTheme.ink)
            .background(ReadingChallengeTheme.canvas)
            .tint(ReadingChallengeTheme.accent)
            .navigationTitle("阅读闯关").navigationBarTitleDisplayMode(.inline)
            .readingRewardScrollAppearance()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("关闭", systemImage: "xmark").labelStyle(.titleAndIcon) }.tint(ReadingChallengeTheme.ink)
                }
            }
            .navigationDestination(for: ChallengeDestination.self) { destination in
                switch destination {
                case .rewards: ReadingRewardsView(store: store)
                case .wallet: ReadingVoucherWallet(store: store)
                }
            }
            .task { await store.refresh(); if articles.isEmpty { await loadArticles() } }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showArticlePicker) {
                NavigationStack {
                    List {
                        ForEach(articles) { article in
                            Button {
                                selectedArticle = article
                                showArticlePicker = false
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(article.title).foregroundStyle(.primary)
                                    Text("\(article.wordCount) 词").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let articleError { Text(articleError).font(.caption).foregroundStyle(.orange) }
                        if hasMoreArticles {
                            Button(isLoadingArticles ? "加载中…" : "加载更多") { Task { await loadArticles() } }.disabled(isLoadingArticles)
                        }
                    }.navigationTitle("选择文章").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭", systemImage: "xmark") { showArticlePicker = false } } }
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
            .onAppear {
                guard path.isEmpty else { return }
                switch initialScreen {
                case "rewards": path = [.rewards]
                case "wallet": path = [.wallet]
                default: break
                }
            }
        }.tint(.blue)
    }

    private func loadArticles() async {
        guard !isLoadingArticles else { return }
        let userID = UserScopedStorage.currentUserId
        isLoadingArticles = true
        defer { isLoadingArticles = false }
        do {
            let page = try await ArticleAPI.shared.listArticles(limit: 20, offset: articles.count)
            guard UserScopedStorage.currentUserId == userID else { return }
            let existing = Set(articles.map(\.id))
            articles += page.items.filter { !existing.contains($0.id) }
            hasMoreArticles = page.items.count == 20
            articleError = nil
        } catch { articleError = error.localizedDescription }
    }

    private func navigationCard(_ title: String, subtitle: String, icon: String, destination: ChallengeDestination) -> some View {
        let isRewards = destination == .rewards
        return Button { path.append(destination) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.title2)
                    .foregroundStyle(isRewards ? ReadingChallengeTheme.gold : ReadingChallengeTheme.pink)
                    .frame(width: 42, height: 46)
                    .background(isRewards ? ReadingChallengeTheme.softGold : ReadingChallengeTheme.softBlue, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(ReadingChallengeTheme.ink)
                    Text(subtitle).font(.caption).foregroundStyle(ReadingChallengeTheme.muted)
                }.fixedSize(horizontal: false, vertical: true)
            }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(ReadingChallengeTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(ReadingChallengeTheme.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

/// Article footer enters the quiz directly, without the challenge dashboard.
struct ReadingQuizEntry: View {
    @ObservedObject var store: ReadingQuizStore
    var onOpen: () -> Void = {}
    @State private var isPresented = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 10) {
            Button {
                guard store.canOpen else { return }
                onOpen()
                isPresented = true
            } label: {
                Label(store.attempt == nil ? "开始小测" : "查看小测", systemImage: "pencil.and.list.clipboard")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canOpen)
            .accessibilityIdentifier("startArticleQuiz")
            Text(store.statusText).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
            if store.paper?.status == "failed" || store.errorMessage != nil {
                Button("重试") { Task { await store.retrySystemTask() } }.disabled(store.isRefreshing || store.isSubmitting)
            } else if store.listeningComplete && store.isPreparing {
                Button("刷新题目") { Task { await store.refresh() } }.disabled(store.isRefreshing)
            }
        }
        .fullScreenCover(isPresented: $isPresented) {
            NavigationStack { ReadingQuizView(store: store) }
        }
        .task(id: "\(store.contextID)-\(store.listenedCount)-\(scenePhase == .active)-\(isPresented)") {
            if scenePhase == .active && !isPresented { await store.watch() }
        }
    }
}

struct ReadingChallengeEntry: View {
    var onOpen: () -> Void = {}
    @State private var isPresented = false
    var body: some View {
        Button { onOpen(); isPresented = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.closed.circle.fill").font(.largeTitle).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("阅读闯关与奖励").font(.headline)
                    Text("阅读小测 · 七星奖励 · 兑换券").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }.padding(16).background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("readingChallengeEntry")
            .fullScreenCover(isPresented: $isPresented) { ReadingChallengeView() }
    }
}

extension View {
    func challengeCard() -> some View {
        padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ReadingLoadStatus: View {
    @ObservedObject var store: ReadingChallengeStore
    var body: some View {
        VStack(spacing: 8) {
            if store.isLoading { ProgressView("正在同步…") }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
                Button("重新加载") { Task { await store.refresh() } }.disabled(store.isLoading)
            }
            if let message = store.pendingMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity)
    }
}
