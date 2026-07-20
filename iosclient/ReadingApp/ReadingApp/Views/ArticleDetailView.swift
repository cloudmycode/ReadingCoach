//
//  ArticleDetailView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import SwiftUI

struct ArticleDetailView: View {
    @StateObject private var viewModel: ArticleDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appNavigationPath) private var appNavigationPath
    @State private var isNavigatingBack = false
    @State private var selectedSentenceIndex: Int?
    @State private var questionDraft = ""
    @State private var selectedWordNormalized: String?
    @State private var selectedWordExplanation: WordExplanation?
    @State private var chatMessages: [DetailChatMessage] = []
    @State private var isLoadingWordExplanation = false
    @State private var isSubmittingQuestion = false
    @State private var hasActivatedChatScroll = false
    @State private var pendingScrollSentenceIndex: Int?
    @State private var articleScrollOffset: CGFloat = 0
    @State private var articleContentHeight: CGFloat = 1
    @State private var articleViewportHeight: CGFloat = 1

    init(articleId: String, articleTitle: String) {
        _viewModel = StateObject(wrappedValue: ArticleDetailViewModel(articleId: articleId, initialTitle: articleTitle))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                articleBody
            }

            if let activeSentence {
                bottomSheet(for: activeSentence)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.loadArticleIfNeeded()
        }
        .onChange(of: viewModel.currentSentenceIndex) { _, newValue in
            if let newValue {
                selectedSentenceIndex = newValue
                pendingScrollSentenceIndex = newValue
            }
        }
        .onChange(of: activeSentence?.id ?? "") { _, _ in
            refreshInteractivePanel()
        }
        .onDisappear {
            isNavigatingBack = false
            viewModel.stopVoiceReading()
        }
        .alert(viewModel.toastMessage ?? "", isPresented: Binding(
            get: { viewModel.toastMessage != nil },
            set: { _ in viewModel.toastMessage = nil }
        )) {
            Button("确定", role: .cancel) { viewModel.toastMessage = nil }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.92), value: isPanelVisible)
    }

    private var topBar: some View {
        HStack {
            Button {
                guard !isNavigatingBack else { return }
                if let path = appNavigationPath, !path.wrappedValue.isEmpty {
                    isNavigatingBack = true
                    path.wrappedValue.removeLast()
                } else {
                    isNavigatingBack = true
                    dismiss()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                    Text("Library")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.0, green: 0.4, blue: 1.0))
            }
            .buttonStyle(.plain)
            .disabled(isNavigatingBack)

            Spacer()

            Text(viewModel.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                .lineLimit(1)

            Spacer()

            Button {
                viewModel.toggleVoiceReading()
                if viewModel.currentSentenceIndex == nil && !viewModel.sentences.isEmpty {
                    selectedSentenceIndex = 0
                    pendingScrollSentenceIndex = 0
                }
            } label: {
                Image(systemName: viewModel.isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(viewModel.isPlaying ? Color(red: 0.0, green: 0.4, blue: 1.0) : Color(red: 0.57, green: 0.64, blue: 0.75))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.91, green: 0.94, blue: 0.98))
                .frame(height: 1)
        }
    }

    private var articleBody: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if viewModel.sentences.isEmpty && !viewModel.isLoading {
                            Text("文章内容还没准备好")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                                .padding(.top, 80)
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(paragraphGroups.indices, id: \.self) { paragraphIndex in
                                VStack(alignment: .leading, spacing: 28) {
                                    ForEach(paragraphGroups[paragraphIndex], id: \.self) { sentenceIndex in
                                        sentenceLine(for: sentenceIndex)
                                            .id(sentenceIndex)
                                    }
                                }
                            }
                        }
                    }
                    .background(
                        GeometryReader { contentGeometry in
                            Color.clear
                                .preference(key: ArticleContentHeightKey.self, value: contentGeometry.size.height)
                                .preference(
                                    key: ArticleScrollOffsetKey.self,
                                    value: -contentGeometry.frame(in: .named("ArticleScrollView")).minY
                                )
                        }
                    )
                    .padding(.trailing, 16)
                    .padding(.horizontal, 38)
                    .padding(.top, 24)
                    .padding(.bottom, isPanelVisible ? 450 : 120)
                }
                .coordinateSpace(name: "ArticleScrollView")
                .scrollIndicators(.hidden)
                .overlay(alignment: .trailing) {
                    articleScrollIndicator
                        .padding(.trailing, 8)
                        .padding(.top, 20)
                        .padding(.bottom, isPanelVisible ? 466 : 28)
                }
                .onAppear {
                    articleViewportHeight = geometry.size.height
                }
                .onChange(of: geometry.size.height) { _, newValue in
                    articleViewportHeight = newValue
                }
                .onPreferenceChange(ArticleScrollOffsetKey.self) { value in
                    articleScrollOffset = max(0, value)
                }
                .onPreferenceChange(ArticleContentHeightKey.self) { value in
                    articleContentHeight = max(1, value)
                }
                .onChange(of: pendingScrollSentenceIndex) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(newValue, anchor: sentenceScrollAnchor)
                    }
                    pendingScrollSentenceIndex = nil
                }
            }
        }
    }

    private func sentenceLine(for index: Int) -> some View {
        let sentence = viewModel.sentences[index]
        let isSelected = activeSentenceIndex == index

        return Button {
            selectedSentenceIndex = index
            pendingScrollSentenceIndex = index
            viewModel.playSentence(at: index)
        } label: {
            Text(sentence.original)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(isSelected ? Color(red: 0.0, green: 0.4, blue: 1.0) : Color(red: 0.14, green: 0.18, blue: 0.27))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, isSelected ? 6 : 0)
                .padding(.vertical, isSelected ? 4 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color(red: 0.91, green: 0.96, blue: 1.0) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var paragraphGroups: [[Int]] {
        let indices = Array(viewModel.sentences.indices)
        guard !indices.isEmpty else { return [] }
        return stride(from: 0, to: indices.count, by: 3).map { start in
            Array(indices[start..<min(start + 3, indices.count)])
        }
    }

    private var activeSentenceIndex: Int? {
        selectedSentenceIndex ?? viewModel.currentSentenceIndex
    }

    private var activeSentence: ArticleSentence? {
        guard let activeSentenceIndex, viewModel.sentences.indices.contains(activeSentenceIndex) else { return nil }
        return viewModel.sentences[activeSentenceIndex]
    }

    private var sentenceScrollAnchor: UnitPoint {
        isPanelVisible ? .top : .center
    }

    private var articleScrollIndicator: some View {
        let visibleHeight = max(articleViewportHeight - (isPanelVisible ? 466 : 28), 120)
        let totalHeight = max(articleContentHeight, visibleHeight)
        let trackHeight = max(visibleHeight - 24, 120)
        let thumbHeight = max(trackHeight * (visibleHeight / totalHeight), 44)
        let maxOffset = max(totalHeight - visibleHeight, 1)
        let progress = min(max(articleScrollOffset / maxOffset, 0), 1)
        let travel = max(trackHeight - thumbHeight, 0)

        return ZStack(alignment: .top) {
            Capsule()
                .fill(Color(red: 0.88, green: 0.91, blue: 0.96))
            Capsule()
                .fill(Color(red: 0.36, green: 0.5, blue: 0.78))
                .frame(height: thumbHeight)
                .offset(y: progress * travel)
        }
        .frame(width: 5, height: trackHeight)
        .opacity(totalHeight > visibleHeight + 8 ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var isPanelVisible: Bool {
        activeSentence != nil
    }

    private func bottomSheet(for sentence: ArticleSentence) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button {
                    closePanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 12) {
                        sentenceWordBar(sentence.original)

                        if isLoadingWordExplanation {
                            ProgressView("正在生成单词解释…")
                                .font(.system(size: 13))
                                .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                        } else if let selectedWordExplanation {
                            wordDefinitionCard(for: selectedWordExplanation)
                        }

                        ForEach(chatMessages) { message in
                            chatMessageView(message)
                                .id(message.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("chat-bottom")
                    }
                    .padding(.bottom, 8)
                    .onAppear {
                        if hasActivatedChatScroll {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: chatMessages.last?.id) { _, _ in
                        guard hasActivatedChatScroll else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                }
            }

            askBar
        }
        .padding(.horizontal, 36)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .frame(height: 430)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white)
        )
        .background(alignment: .bottom) {
            Color.white
                .frame(height: 80)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.86, green: 0.89, blue: 0.94))
                .frame(width: 38, height: 5)
                .padding(.top, 8)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 30, x: 0, y: -6)
        .padding(.bottom, -10)
        .ignoresSafeArea(edges: .bottom)
    }

    private func sentenceWordBar(_ sentence: String) -> some View {
        let tokens = WordToken.tokenize(sentence)
        return FlowLayout(spacing: 4, lineSpacing: 8) {
            ForEach(tokens) { token in
                if token.isWord {
                    Button {
                        selectedWordNormalized = token.normalized
                        isLoadingWordExplanation = true
                        Task {
                            selectedWordNormalized = token.normalized
                            async let speakTask: Void = ArticleAudioManager.shared.speak(
                                sentenceId: nil,
                                text: token.text,
                                type: .original,
                                style: .focusedSentence
                            )
                            async let explainTask: Void = selectWord(token.normalized)
                            _ = try? await speakTask
                            await explainTask
                        }
                    } label: {
                        Text(token.text)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(selectedWordNormalized == token.normalized ? Color(red: 0.0, green: 0.4, blue: 1.0) : Color(red: 0.2, green: 0.25, blue: 0.34))
                            .padding(.horizontal, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(selectedWordNormalized == token.normalized ? Color(red: 0.91, green: 0.96, blue: 1.0) : Color.clear)
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

    private func wordDefinitionCard(for explanation: WordExplanation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(explanation.word)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.0, green: 0.4, blue: 1.0))
                    Text(explanation.partOfSpeech)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                }
                Text(explanation.meaning)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                Text(explanation.tip)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.35, green: 0.4, blue: 0.5))
                    .lineSpacing(4)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 0.89, green: 0.93, blue: 0.97), lineWidth: 1)
        )
    }

    private var askBar: some View {
        HStack(spacing: 10) {
            TextField("Ask AI Teacher...", text: $questionDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(red: 0.97, green: 0.98, blue: 1.0))
                .clipShape(Capsule())
                .onSubmit {
                    Task {
                        await submitQuestion()
                    }
                }

            Button {
                viewModel.toastMessage = "语音提问功能稍后补齐"
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
                        .frame(width: 42, height: 42)

                    Image(systemName: "mic")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(red: 0.55, green: 0.62, blue: 0.74))
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func chatMessageView(_ message: DetailChatMessage) -> some View {
        switch message.role {
        case .interpretation:
            VStack(alignment: .leading, spacing: 10) {
                Text("“ \(message.text) ”")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                    .lineSpacing(5)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
            )

        case .assistant:
            HStack(alignment: .top, spacing: 12) {
                if message.showsBulb {
                    Text("💡")
                        .font(.system(size: 22))
                }

                Text(message.text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                    .lineSpacing(6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
            )

        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineSpacing(5)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.0, green: 0.4, blue: 1.0))
                    )
            }
        }
    }

    private func closePanel() {
        selectedSentenceIndex = nil
        selectedWordNormalized = nil
        selectedWordExplanation = nil
    }

    private func playTranslationAsync(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        Task {
            try? await ArticleAudioManager.shared.speak(
                sentenceId: nil,
                text: normalized,
                type: .translation,
                style: .focusedSentence
            )
        }
    }

    private func hasPlayedWordTranslationBefore(_ word: String) -> Bool {
        let normalized = word
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return UserDefaults.standard.bool(forKey: "word-translation-played-\(normalized)")
    }

    private func markWordTranslationPlayed(_ word: String) {
        let normalized = word
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: "word-translation-played-\(normalized)")
    }

    private func selectWord(_ word: String) async {
        await selectWord(word, shouldPlayTranslation: !hasPlayedWordTranslationBefore(word))
    }

    private func selectWord(_ word: String, shouldPlayTranslation: Bool) async {
        guard let activeSentence, let sentenceId = activeSentence.sentenceId else { return }
        isLoadingWordExplanation = true
        defer { isLoadingWordExplanation = false }

        do {
            let response = try await viewModel.explainWord(sentenceId: sentenceId, word: word)
            selectedWordNormalized = response.word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            selectedWordExplanation = WordExplanation(
                word: response.word,
                partOfSpeech: response.partOfSpeech,
                meaning: response.meaning,
                tip: response.tip
            )

            let spokenExplanation = [response.meaning, response.tip]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "，")

            if shouldPlayTranslation,
               !ArticleAudioManager.shared.hasCachedAudio(text: spokenExplanation, type: .translation) {
                markWordTranslationPlayed(word)
                playTranslationAsync(spokenExplanation)
            } else if shouldPlayTranslation {
                markWordTranslationPlayed(word)
            }
        } catch {
            selectedWordExplanation = nil
            viewModel.toastMessage = error.localizedDescription
        }
    }

    private func refreshInteractivePanel() {
        guard let activeSentence else {
            chatMessages = []
            selectedWordNormalized = nil
            selectedWordExplanation = nil
            questionDraft = ""
            return
        }

        selectedWordNormalized = nil
        selectedWordExplanation = nil
        questionDraft = ""
        hasActivatedChatScroll = false
        chatMessages = [
            DetailChatMessage(
                role: .interpretation,
                text: activeSentence.translation.isEmpty ? "这句话暂时还没有翻译。" : activeSentence.translation,
                highlights: [],
                showsBulb: false
            ),
            DetailChatMessage(
                role: .assistant,
                text: "对这句话还有疑问吗？我都可以解答。",
                highlights: [],
                showsBulb: false
            )
        ]

        if let sentenceId = activeSentence.sentenceId {
            chatMessages.append(contentsOf: SentenceChatCacheStore.shared.messages(for: sentenceId))
        }
    }

    private func submitQuestion() async {
        let question = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let activeSentence, let sentenceId = activeSentence.sentenceId else { return }

        chatMessages.append(
            DetailChatMessage(
                role: .user,
                text: question,
                highlights: [],
                showsBulb: false
            )
        )
        hasActivatedChatScroll = true
        persistChatHistory(for: sentenceId)
        questionDraft = ""
        isSubmittingQuestion = true
        defer { isSubmittingQuestion = false }

        do {
            let response = try await viewModel.askQuestion(sentenceId: sentenceId, question: question)
            chatMessages.append(
                DetailChatMessage(
                    role: .assistant,
                    text: response.answer,
                    highlights: response.highlights,
                    showsBulb: false
                )
            )
            persistChatHistory(for: sentenceId)
        } catch {
            chatMessages.append(
                DetailChatMessage(
                    role: .assistant,
                    text: "这次回答没有成功拿到，我们换个问法再试一次。",
                    highlights: [],
                    showsBulb: false
                )
            )
            persistChatHistory(for: sentenceId)
            viewModel.toastMessage = error.localizedDescription
        }
    }

    private func persistChatHistory(for sentenceId: Int) {
        SentenceChatCacheStore.shared.save(messages: persistedChatMessages, for: sentenceId)
    }

    private var persistedChatMessages: [DetailChatMessage] {
        chatMessages.filter { message in
            message.role != .interpretation && !message.showsBulb
        }
    }
}

private struct DetailChatMessage: Identifiable {
    enum Role: String, Codable {
        case interpretation
        case assistant
        case user
    }

    let id = UUID()
    let role: Role
    let text: String
    let highlights: [String]
    let showsBulb: Bool
}

private final class SentenceChatCacheStore {
    static let shared = SentenceChatCacheStore()

    private let userDefaults = UserDefaults.standard
    private let storageKey = "readingcoach.sentence.chat.cache"

    func messages(for sentenceId: Int) -> [DetailChatMessage] {
        loadCache()[sentenceId] ?? []
    }

    func save(messages: [DetailChatMessage], for sentenceId: Int) {
        var cache = loadCache()
        cache[sentenceId] = messages
        saveCache(cache)
    }

    private func loadCache() -> [Int: [DetailChatMessage]] {
        guard let data = userDefaults.data(forKey: storageKey),
              let cache = try? JSONDecoder().decode([Int: [StoredDetailChatMessage]].self, from: data) else {
            return [:]
        }

        return cache.mapValues { items in
            items.map {
                DetailChatMessage(
                    role: $0.role,
                    text: $0.text,
                    highlights: $0.highlights,
                    showsBulb: $0.showsBulb
                )
            }
        }
    }

    private func saveCache(_ cache: [Int: [DetailChatMessage]]) {
        let stored = cache.mapValues { items in
            items.map {
                StoredDetailChatMessage(
                    role: $0.role,
                    text: $0.text,
                    highlights: $0.highlights,
                    showsBulb: $0.showsBulb
                )
            }
        }

        guard let data = try? JSONEncoder().encode(stored) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

private struct StoredDetailChatMessage: Codable {
    let role: DetailChatMessage.Role
    let text: String
    let highlights: [String]
    let showsBulb: Bool
}

private struct WordExplanation {
    let word: String
    let partOfSpeech: String
    let meaning: String
    let tip: String
}

private struct ArticleScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ArticleContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct WordToken: Identifiable {
    let id = UUID()
    let text: String
    let normalized: String
    let isWord: Bool

    static func tokenize(_ text: String) -> [WordToken] {
        let pattern = #"[A-Za-z']+|[^A-Za-z'\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [WordToken(text: text, normalized: text.lowercased(), isWord: true)]
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            let token = nsText.substring(with: match.range)
            let normalized = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]{}")).lowercased()
            return WordToken(
                text: token,
                normalized: normalized,
                isWord: normalized.range(of: #"^[a-z']+$"#, options: .regularExpression) != nil
            )
        }
    }
}

private struct FlowLayout: Layout {
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

#Preview {
    ArticleDetailView(articleId: "demo", articleTitle: "Last Week on Mars")
}
