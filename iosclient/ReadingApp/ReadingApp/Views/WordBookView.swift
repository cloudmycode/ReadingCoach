import SwiftUI

struct WordBookPlaybackOptions {
    var playWord: Bool
    var playWordTranslation: Bool
    var playSentence: Bool
    var playSentenceTranslation: Bool

    var hasAnyEnabled: Bool {
        playWord || playWordTranslation || playSentence || playSentenceTranslation
    }
}

struct WordBookSettingsMenu: View {
    @AppStorage("wordBookAutoPlayWord") private var autoPlayWord = true
    @AppStorage("wordBookAutoPlayWordTranslation") private var autoPlayWordTranslation = false
    @AppStorage("wordBookAutoPlaySentence") private var autoPlaySentence = false
    @AppStorage("wordBookAutoPlaySentenceTranslation") private var autoPlaySentenceTranslation = false

    var body: some View {
        Menu {
            Toggle("读单词", isOn: $autoPlayWord)
            Toggle("读单词翻译", isOn: $autoPlayWordTranslation)
            Toggle("读句子", isOn: $autoPlaySentence)
            Toggle("读句子翻译", isOn: $autoPlaySentenceTranslation)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.4, green: 0.48, blue: 0.62))
                .frame(width: 36, height: 36)
                .background(Color(red: 0.95, green: 0.97, blue: 1.0))
                .clipShape(Circle())
        }
        .accessibilityLabel("生词本设置")
    }
}

struct WordBookView: View {
    @ObservedObject var viewModel: WordBookViewModel
    var articleId: String? = nil
    var articleTitle: String? = nil
    var showsOpenArticleButton: Bool = true
    let onOpenArticle: (String) -> Void

    @AppStorage("wordBookAutoPlayWord") private var autoPlayWord = true
    @AppStorage("wordBookAutoPlayWordTranslation") private var autoPlayWordTranslation = false
    @AppStorage("wordBookAutoPlaySentence") private var autoPlaySentence = false
    @AppStorage("wordBookAutoPlaySentenceTranslation") private var autoPlaySentenceTranslation = false

    private var playbackOptions: WordBookPlaybackOptions {
        WordBookPlaybackOptions(
            playWord: autoPlayWord,
            playWordTranslation: autoPlayWordTranslation,
            playSentence: autoPlaySentence,
            playSentenceTranslation: autoPlaySentenceTranslation
        )
    }

    private var showsInlineTitle: Bool {
        articleTitle?.isEmpty == false
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsInlineTitle {
                topBar
            }

            if viewModel.displayedEntries.isEmpty {
                emptyState
            } else {
                playbackBar

                List {
                    ForEach(viewModel.displayedEntries) { entry in
                        WordBookEntryCard(
                            entry: entry,
                            isSelected: viewModel.selectedEntryId == entry.id,
                            showsOpenArticleButton: showsOpenArticleButton,
                            onTapWord: {
                                Task {
                                    await viewModel.explainWord(
                                        in: entry,
                                        word: entry.word,
                                        options: playbackOptions
                                    )
                                }
                            },
                            onTapSentence: {
                                Task {
                                    await viewModel.playSentence(entry, options: playbackOptions)
                                }
                            },
                            onOpenArticle: {
                                onOpenArticle(entry.articleId)
                            },
                            onDelete: {
                                Task {
                                    await viewModel.deleteEntry(entry)
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteEntry(entry)
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                if let entry = viewModel.selectedEntry {
                    interactionPanel(for: entry)
                }
            }
        }
        .task(id: articleId) {
            viewModel.setFilterArticleId(articleId)
            await viewModel.refreshEntries()
        }
        .onChange(of: articleId) { _, newValue in
            viewModel.setFilterArticleId(newValue)
        }
        .onDisappear {
            viewModel.stopPlaybackAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wordBookDidChange)) { _ in
            guard !viewModel.isPlayingAll else { return }
            Task {
                await viewModel.refreshEntries()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .onTapGesture { viewModel.toastMessage = nil }
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        if viewModel.toastMessage == toast {
                            viewModel.toastMessage = nil
                        }
                    }
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(articleTitle ?? "")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 60)
            Text(articleId == nil ? "单词本还是空的" : "这篇文章还没有生词")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
            Text(
                articleId == nil
                ? "在文章里点查单词后，会自动出现在这里，并记住当时的句子。"
                : "在文章阅读页点查单词后，生词会出现在这里。"
            )
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.togglePlaybackAll(options: playbackOptions)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isPlayingAll ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(viewModel.isPlayingAll ? "停止朗读" : "连续朗读")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.0, green: 0.4, blue: 1.0))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!playbackOptions.hasAnyEnabled && !viewModel.isPlayingAll)

            Text(
                viewModel.isPlayingAll
                ? "按设置顺序朗读"
                : (playbackOptions.hasAnyEnabled ? "按设置项依次朗读" : "请先在设置中勾选朗读项")
            )
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func interactionPanel(for entry: WordBookEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("查词与朗读")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.4, green: 0.48, blue: 0.62))
                Spacer()
                Button("关闭") {
                    viewModel.clearSelection()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 0.0, green: 0.4, blue: 1.0))
                .buttonStyle(.plain)
            }

            sentenceWordBar(entry)

            if let word = viewModel.activeWord, !word.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(word)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.0, green: 0.4, blue: 1.0))
                        if !viewModel.activePartOfSpeech.isEmpty {
                            Text(viewModel.activePartOfSpeech)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                        }
                    }
                    if viewModel.isLoadingExplanation {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("翻译中")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.45, green: 0.52, blue: 0.62))
                        }
                        .padding(.top, 2)
                    } else {
                        if !viewModel.activeMeaning.isEmpty {
                            Text(viewModel.activeMeaning)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                        }
                        if !viewModel.activeTip.isEmpty {
                            Text(viewModel.activeTip)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 0.35, green: 0.4, blue: 0.5))
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
                )
            }

            if !entry.sentenceTranslation.isEmpty {
                Text(entry.sentenceTranslation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.45, green: 0.52, blue: 0.62))
            }
        }
        .padding(16)
        .background(
            Color.white
                .shadow(color: Color.black.opacity(0.08), radius: 16, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func sentenceWordBar(_ entry: WordBookEntry) -> some View {
        let tokens = WordBookToken.tokenize(entry.sentenceOriginal)
        return WordBookFlowLayout(spacing: 4, lineSpacing: 8) {
            ForEach(tokens) { token in
                if token.isWord {
                    Button {
                        Task {
                            await viewModel.explainWord(
                                in: entry,
                                word: token.normalized,
                                options: playbackOptions
                            )
                        }
                    } label: {
                        Text(token.text)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(
                                viewModel.activeWord?.lowercased() == token.normalized
                                ? Color(red: 0.0, green: 0.4, blue: 1.0)
                                : Color(red: 0.2, green: 0.25, blue: 0.34)
                            )
                            .padding(.horizontal, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(
                                        viewModel.activeWord?.lowercased() == token.normalized
                                        ? Color(red: 0.91, green: 0.96, blue: 1.0)
                                        : Color.clear
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(token.text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(red: 0.2, green: 0.25, blue: 0.34))
                }
            }
        }
    }
}

private struct WordBookEntryCard: View {
    let entry: WordBookEntry
    let isSelected: Bool
    var showsOpenArticleButton: Bool = true
    let onTapWord: () -> Void
    let onTapSentence: () -> Void
    let onOpenArticle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Button(action: onTapWord) {
                    Text(entry.word)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 0.0, green: 0.4, blue: 1.0))
                }
                .buttonStyle(.plain)

                if !entry.partOfSpeech.isEmpty {
                    Text(entry.partOfSpeech)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                }

                Text(entry.reviewBadgeText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.0, green: 0.4, blue: 1.0))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.91, green: 0.96, blue: 1.0))
                    .clipShape(Capsule())

                Spacer()

                if showsOpenArticleButton {
                    Button(action: onOpenArticle) {
                        Image(systemName: "book")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                            .frame(width: 30, height: 30)
                            .background(Color(red: 0.95, green: 0.97, blue: 1.0))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.86, green: 0.28, blue: 0.28))
                        .frame(width: 30, height: 30)
                        .background(Color(red: 1.0, green: 0.95, blue: 0.95))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if !entry.meaning.isEmpty {
                Text(entry.meaning)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.35, green: 0.4, blue: 0.5))
                    .lineLimit(2)
            }

            Button(action: onTapSentence) {
                Text(entry.sentenceOriginal)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(red: 0.97, green: 0.98, blue: 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isSelected ? Color(red: 0.0, green: 0.4, blue: 1.0).opacity(0.35) : Color(red: 0.92, green: 0.95, blue: 0.98),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
    }
}

private struct WordBookToken: Identifiable {
    let id = UUID()
    let text: String
    let normalized: String
    let isWord: Bool

    static func tokenize(_ text: String) -> [WordBookToken] {
        let pattern = #"[A-Za-z']+|[^A-Za-z'\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [WordBookToken(text: text, normalized: text.lowercased(), isWord: true)]
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            let token = nsText.substring(with: match.range)
            let normalized = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]{}")).lowercased()
            return WordBookToken(
                text: token,
                normalized: normalized,
                isWord: normalized.range(of: #"^[a-z']+$"#, options: .regularExpression) != nil
            )
        }
    }
}

private struct WordBookFlowLayout: Layout {
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
