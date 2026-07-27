import SwiftUI

private enum ReviewTaskTab: String, CaseIterable, Identifiable {
    case current
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current:
            return "当前任务"
        case .completed:
            return "已完成"
        }
    }
}

struct ReviewTasksView: View {
    @ObservedObject var viewModel: ReviewTasksViewModel
    let onOpenArticle: (String, String) -> Void
    let onAddArticle: () -> Void

    @State private var selectedTab: ReviewTaskTab = .current

    var body: some View {
        VStack(spacing: 0) {
            tabHeader
            ScrollView {
                VStack(spacing: 14) {
                    if selectedTab == .current {
                        currentTaskContent
                    } else {
                        completedTaskContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 120)
            }
        }
        .task {
            await viewModel.loadTasks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewTasksDidChange)) { _ in
            Task {
                await viewModel.loadTasks()
            }
        }
        .fullScreenCover(isPresented: $viewModel.isSessionPresented) {
            WordReviewSessionView(
                viewModel: viewModel,
                onOpenArticle: { articleId, title in
                    viewModel.closeSession()
                    onOpenArticle(articleId, title)
                }
            )
        }
    }

    private var tabHeader: some View {
        HStack(spacing: 12) {
            ForEach(ReviewTaskTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .white : Color(red: 0.4, green: 0.48, blue: 0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedTab == tab ? Color(red: 0.0, green: 0.4, blue: 1.0) : Color(red: 0.95, green: 0.97, blue: 1.0))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.white)
    }

    @ViewBuilder
    private var currentTaskContent: some View {
        summaryCard

        if viewModel.pendingTasks.isEmpty && !viewModel.isLoading {
            ReviewTaskEmptyState(
                title: viewModel.summary.completedCount > 0 ? "今天的复习都完成了" : "今天没有新的复习任务",
                message: viewModel.summary.completedCount > 0
                    ? "明天会继续安排新的生词。也可以去单词本看看积累。"
                    : "继续阅读并查词，生词会在第二天出现在这里。",
                buttonTitle: viewModel.summary.completedCount > 0 ? "查看已完成" : "新增文章",
                action: {
                    if viewModel.summary.completedCount > 0 {
                        selectedTab = .completed
                    } else {
                        onAddArticle()
                    }
                }
            )
        } else {
            ForEach(viewModel.pendingTasks) { task in
                WordReviewPreviewCard(
                    word: task.word,
                    articleTitle: task.articleTitle,
                    accentColor: Color(red: 0.0, green: 0.4, blue: 1.0)
                )
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今日复习 \(viewModel.summary.completedCount) / \(viewModel.summary.dueCount + viewModel.summary.completedCount)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))

            Text("复习你查过的生词，巩固阅读中的薄弱点。每天最多 \(viewModel.summary.dailyLimit) 个。")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 0.47, green: 0.55, blue: 0.68))

            ProgressView(
                value: Double(viewModel.summary.completedCount),
                total: Double(max(viewModel.summary.dueCount + viewModel.summary.completedCount, 1))
            )
            .tint(Color(red: 0.0, green: 0.4, blue: 1.0))

            if !viewModel.pendingTasks.isEmpty {
                Button {
                    viewModel.startSession()
                } label: {
                    Text("开始复习")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.0, green: 0.4, blue: 1.0))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(red: 0.92, green: 0.95, blue: 0.98), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var completedTaskContent: some View {
        if viewModel.completedTasks.isEmpty && !viewModel.isLoading {
            ReviewTaskEmptyState(
                title: "还没有完成的任务",
                message: "完成词卡复习后，这里会记录你今天复习过的生词。",
                buttonTitle: "查看当前任务",
                action: {
                    selectedTab = .current
                }
            )
        } else {
            ForEach(viewModel.completedTasks) { task in
                WordReviewCompletedCard(
                    word: task.word,
                    meaning: task.meaning,
                    articleTitle: task.articleTitle,
                    onOpenArticle: {
                        onOpenArticle(task.articleId, task.articleTitle)
                    }
                )
            }
        }
    }
}

private struct WordReviewPreviewCard: View {
    let word: String
    let articleTitle: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accentColor)
                .frame(width: 6, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(word)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                Text(articleTitle.isEmpty ? "来自阅读文章" : "来自 \(articleTitle)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.6, green: 0.67, blue: 0.78))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.92, green: 0.95, blue: 0.98), lineWidth: 1)
        )
    }
}

private struct WordReviewCompletedCard: View {
    let word: String
    let meaning: String
    let articleTitle: String
    let onOpenArticle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(word)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(red: 0.02, green: 0.7, blue: 0.44))
                Spacer()
                Button("打开原文", action: onOpenArticle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 0.02, green: 0.7, blue: 0.44))
            }
            if !meaning.isEmpty {
                Text(meaning)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.35, green: 0.4, blue: 0.5))
            }
            Text(articleTitle.isEmpty ? "来自阅读文章" : "来自 \(articleTitle)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(red: 0.6, green: 0.67, blue: 0.78))
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.92, green: 0.95, blue: 0.98), lineWidth: 1)
        )
    }
}

private struct ReviewTaskEmptyState: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button(buttonTitle, action: action)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Color(red: 0.0, green: 0.4, blue: 1.0))
                .clipShape(Capsule())
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WordReviewSessionView: View {
    @ObservedObject var viewModel: ReviewTasksViewModel
    let onOpenArticle: (String, String) -> Void

    @AppStorage("reviewAutoPlayWord") private var autoPlayWord = false
    @AppStorage("reviewAutoPlayWordTranslation") private var autoPlayWordTranslation = false
    @AppStorage("reviewAutoPlaySentence") private var autoPlaySentence = false
    @AppStorage("reviewAutoPlaySentenceTranslation") private var autoPlaySentenceTranslation = false
    @State private var autoPlayTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.98, blue: 1.0).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if viewModel.isSessionFinished {
                    finishedContent
                } else if let task = viewModel.currentSessionTask {
                    cardContent(task)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            scheduleAutoPlay()
        }
        .onChange(of: viewModel.sessionIndex) { _, _ in
            scheduleAutoPlay()
        }
        .onChange(of: viewModel.isSessionFinished) { _, finished in
            if finished {
                cancelAutoPlay()
            }
        }
        .onDisappear {
            cancelAutoPlay()
        }
    }

    private var header: some View {
        HStack {
            Button("关闭") {
                cancelAutoPlay()
                viewModel.closeSession()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Color(red: 0.4, green: 0.48, blue: 0.62))

            Spacer()

            Text(viewModel.isSessionFinished ? "今日完成" : viewModel.sessionProgressText)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))

            Spacer()

            Menu {
                Toggle("读单词", isOn: $autoPlayWord)
                Toggle("读单词翻译", isOn: $autoPlayWordTranslation)
                Toggle("读句子", isOn: $autoPlaySentence)
                Toggle("读句子翻译", isOn: $autoPlaySentenceTranslation)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.4, green: 0.48, blue: 0.62))
                    .frame(width: 40, height: 20)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("复习设置")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func cardContent(_ task: WordReviewTaskItem) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Text(task.word)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                    .multilineTextAlignment(.center)

                Button {
                    cancelAutoPlay()
                    Task { await playWord(task) }
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.4, blue: 1.0))
                        .padding(6)
                        .background(Color(red: 0.91, green: 0.96, blue: 1.0))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放单词")
            }

            Button {
                cancelAutoPlay()
                Task { await playSentence(task) }
            } label: {
                highlightedSentence(task)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .accessibilityLabel("播放句子")

            Text(task.articleTitle.isEmpty ? "来自阅读文章" : "来自 \(task.articleTitle)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 0.6, green: 0.67, blue: 0.78))

            if viewModel.isRevealed {
                VStack(alignment: .leading, spacing: 8) {
                    if !task.partOfSpeech.isEmpty {
                        Text(task.partOfSpeech)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                    }
                    if !task.meaning.isEmpty {
                        Text(task.meaning)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                    }
                    if !task.tip.isEmpty {
                        Text(task.tip)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 0.35, green: 0.4, blue: 0.5))
                    }
                    if !task.sentenceTranslation.isEmpty {
                        Text(task.sentenceTranslation)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 0.45, green: 0.52, blue: 0.62))
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Spacer()

            if viewModel.isRevealed {
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.submitCurrent(result: "again") }
                    } label: {
                        Text("还不熟")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 0.86, green: 0.35, blue: 0.28))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 1.0, green: 0.94, blue: 0.93))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSubmitting)

                    Button {
                        Task { await viewModel.submitCurrent(result: "mastered") }
                    } label: {
                        Text("认识了")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 0.02, green: 0.7, blue: 0.44))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSubmitting)
                }

                Button {
                    cancelAutoPlay()
                    onOpenArticle(task.articleId, task.articleTitle)
                } label: {
                    Text("打开原文")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.4, green: 0.48, blue: 0.62))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                Button {
                    viewModel.revealMeaning()
                } label: {
                    Text("显示释义")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.0, green: 0.4, blue: 1.0))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }

    private var finishedContent: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("今日复习完成")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
            Text("\(viewModel.sessionQueue.count) 个生词已复习")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(red: 0.47, green: 0.55, blue: 0.68))
            Text("认识了 \(viewModel.masteredInSession) 个 · 还不熟 \(viewModel.againInSession) 个")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
            Button("返回任务") {
                cancelAutoPlay()
                viewModel.closeSession()
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Color(red: 0.0, green: 0.4, blue: 1.0))
            .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func highlightedSentence(_ task: WordReviewTaskItem) -> some View {
        let tokens = WordReviewToken.tokenize(task.sentenceOriginal)
        let target = task.normalizedWord.lowercased()
        return WordReviewFlowLayout(spacing: 4, lineSpacing: 8) {
            ForEach(tokens) { token in
                Text(token.text)
                    .font(.system(size: 17, weight: token.isWord && token.normalized == target ? .bold : .medium))
                    .foregroundColor(
                        token.isWord && token.normalized == target
                        ? Color(red: 0.0, green: 0.4, blue: 1.0)
                        : Color(red: 0.2, green: 0.25, blue: 0.34)
                    )
                    .padding(.horizontal, token.isWord && token.normalized == target ? 2 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                token.isWord && token.normalized == target
                                ? Color(red: 0.91, green: 0.96, blue: 1.0)
                                : Color.clear
                            )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func scheduleAutoPlay() {
        guard !viewModel.isSessionFinished,
              let task = viewModel.currentSessionTask,
              autoPlayWord || autoPlayWordTranslation || autoPlaySentence || autoPlaySentenceTranslation else {
            cancelAutoPlay()
            return
        }

        cancelAutoPlay()
        let shouldPlayWord = autoPlayWord
        let shouldPlayWordTranslation = autoPlayWordTranslation
        let shouldPlaySentence = autoPlaySentence
        let shouldPlaySentenceTranslation = autoPlaySentenceTranslation
        autoPlayTask = Task {
            if shouldPlayWord {
                guard !Task.isCancelled else { return }
                await playWord(task)
            }
            if shouldPlayWordTranslation {
                guard !Task.isCancelled else { return }
                await playWordTranslation(task)
            }
            if shouldPlaySentence {
                guard !Task.isCancelled else { return }
                await playSentence(task)
            }
            if shouldPlaySentenceTranslation {
                guard !Task.isCancelled else { return }
                await playSentenceTranslation(task)
            }
        }
    }

    private func cancelAutoPlay() {
        autoPlayTask?.cancel()
        autoPlayTask = nil
        ArticleAudioManager.shared.stop()
    }

    private func playWord(_ task: WordReviewTaskItem) async {
        try? await ArticleAudioManager.shared.speak(
            sentenceId: nil,
            text: task.word,
            type: .original,
            style: .focusedSentence
        )
    }

    private func playWordTranslation(_ task: WordReviewTaskItem) async {
        let spoken = [task.meaning, task.tip]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "，")
        guard !spoken.isEmpty else { return }
        try? await ArticleAudioManager.shared.speak(
            sentenceId: nil,
            text: spoken,
            type: .translation,
            style: .focusedSentence
        )
    }

    private func playSentence(_ task: WordReviewTaskItem) async {
        try? await ArticleAudioManager.shared.speak(
            sentenceId: task.sentenceId,
            text: task.sentenceOriginal,
            type: .original,
            style: .focusedSentence
        )
    }

    private func playSentenceTranslation(_ task: WordReviewTaskItem) async {
        let text = task.sentenceTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? await ArticleAudioManager.shared.speak(
            sentenceId: task.sentenceId,
            text: text,
            type: .translation,
            style: .focusedSentence
        )
    }
}

private struct WordReviewToken: Identifiable {
    let id = UUID()
    let text: String
    let normalized: String
    let isWord: Bool

    static func tokenize(_ text: String) -> [WordReviewToken] {
        let pattern = #"[A-Za-z']+|[^A-Za-z'\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [WordReviewToken(text: text, normalized: text.lowercased(), isWord: true)]
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            let token = nsText.substring(with: match.range)
            let normalized = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]{}")).lowercased()
            return WordReviewToken(
                text: token,
                normalized: normalized,
                isWord: normalized.range(of: #"^[a-z']+$"#, options: .regularExpression) != nil
            )
        }
    }
}

private struct WordReviewFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
