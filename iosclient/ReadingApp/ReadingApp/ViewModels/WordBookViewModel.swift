import Foundation
import Combine

@MainActor
final class WordBookViewModel: ObservableObject {
    @Published var entries: [WordBookEntry] = []
    @Published var filterArticleId: String?
    @Published var selectedEntryId: String?
    @Published var activeWord: String?
    @Published var activePartOfSpeech: String = ""
    @Published var activeMeaning: String = ""
    @Published var activeTip: String = ""
    @Published var isLoading = false
    @Published var isLoadingExplanation = false
    @Published var isPlayingSentence = false
    @Published var isPlayingAll = false
    @Published var toastMessage: String?

    private var playbackTask: Task<Void, Never>?
    private var playbackOptions = WordBookPlaybackOptions(
        playWord: false,
        playWordTranslation: false,
        playSentence: false,
        playSentenceTranslation: false
    )

    var displayedEntries: [WordBookEntry] {
        guard let filterArticleId, !filterArticleId.isEmpty else {
            return entries
        }
        return entries.filter { $0.articleId == filterArticleId }
    }

    var selectedEntry: WordBookEntry? {
        guard let selectedEntryId else { return nil }
        return displayedEntries.first(where: { $0.id == selectedEntryId })
            ?? entries.first(where: { $0.id == selectedEntryId })
    }

    func setFilterArticleId(_ articleId: String?) {
        let normalized = articleId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (normalized?.isEmpty == false) ? normalized : nil
        guard filterArticleId != next else { return }
        stopPlaybackAll()
        filterArticleId = next
        if let selectedEntryId, !displayedEntries.contains(where: { $0.id == selectedEntryId }) {
            clearSelection()
        }
    }

    func loadEntries() {
        Task {
            await refreshEntries()
        }
    }

    func refreshEntries() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await WordBookAPI.shared.listEntries()
            entries = response.items.map { $0.asWordBookEntry() }
            WordBookStore.shared.replaceAll(entries)
            if let selectedEntryId, !entries.contains(where: { $0.id == selectedEntryId }) {
                clearSelection()
            }
        } catch {
            let local = WordBookStore.shared.allEntries()
            if !local.isEmpty {
                entries = local
                toastMessage = "生词本同步失败，已显示本地缓存"
            } else {
                toastMessage = error.localizedDescription
            }
        }
    }

    func selectEntry(_ entry: WordBookEntry) {
        selectedEntryId = entry.id
        activeWord = entry.word
        activePartOfSpeech = entry.partOfSpeech
        activeMeaning = entry.meaning
        activeTip = entry.tip
    }

    func clearSelection() {
        selectedEntryId = nil
        activeWord = nil
        activePartOfSpeech = ""
        activeMeaning = ""
        activeTip = ""
    }

    func deleteEntry(_ entry: WordBookEntry) async {
        stopPlaybackAll()
        do {
            try await WordBookAPI.shared.deleteEntry(entryId: entry.entryId)
            entries.removeAll { $0.entryId == entry.entryId }
            WordBookStore.shared.replaceAll(entries)
            if selectedEntryId == entry.id {
                clearSelection()
            }
            NotificationCenter.default.post(name: .wordBookDidChange, object: nil)
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    func togglePlaybackAll(options: WordBookPlaybackOptions) {
        if isPlayingAll {
            stopPlaybackAll()
        } else {
            startPlaybackAll(options: options)
        }
    }

    func stopPlaybackAll() {
        playbackTask?.cancel()
        playbackTask = nil
        ArticleAudioManager.shared.stop()
        isPlayingAll = false
        isPlayingSentence = false
    }

    private func startPlaybackAll(options: WordBookPlaybackOptions) {
        guard !displayedEntries.isEmpty, options.hasAnyEnabled else { return }
        stopPlaybackAll()
        playbackOptions = options
        isPlayingAll = true
        playbackTask = Task { [weak self] in
            await self?.playAllEntries()
        }
    }

    private func playAllEntries() async {
        defer {
            if !Task.isCancelled {
                isPlayingAll = false
            }
            playbackTask = nil
        }

        let playlist = displayedEntries
        let options = playbackOptions
        for entry in playlist {
            if Task.isCancelled { break }
            selectEntry(entry)
            await playEntry(entry, options: options)
        }
    }

    private func playEntry(_ entry: WordBookEntry, options: WordBookPlaybackOptions) async {
        if options.playWord {
            guard !Task.isCancelled else { return }
            await speakWord(entry.word)
        }
        if options.playWordTranslation {
            guard !Task.isCancelled else { return }
            await speakWordTranslation(for: entry)
        }
        if options.playSentence {
            guard !Task.isCancelled else { return }
            await speakSentence(entry)
        }
        if options.playSentenceTranslation {
            guard !Task.isCancelled else { return }
            await speakSentenceTranslation(for: entry)
        }
    }

    func playSentence(_ entry: WordBookEntry, options: WordBookPlaybackOptions) async {
        stopPlaybackAll()
        selectEntry(entry)
        await playEntry(entry, options: options)
    }

    private func speakWord(_ word: String) async {
        let text = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await ArticleAudioManager.shared.speak(
                sentenceId: nil,
                text: text,
                type: .original,
                style: .focusedSentence
            )
        } catch {
            if Task.isCancelled { return }
            toastMessage = error.localizedDescription
        }
    }

    private func speakWordTranslation(for entry: WordBookEntry) async {
        let spoken = wordTranslationText(for: entry)
        guard !spoken.isEmpty else { return }
        do {
            try await ArticleAudioManager.shared.speak(
                sentenceId: nil,
                text: spoken,
                type: .translation,
                style: .focusedSentence
            )
        } catch {
            if Task.isCancelled { return }
            toastMessage = error.localizedDescription
        }
    }

    private func speakSentence(_ entry: WordBookEntry) async {
        let text = entry.sentenceOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPlayingSentence = true
        defer { isPlayingSentence = false }
        do {
            try await ArticleAudioManager.shared.speak(
                sentenceId: entry.sentenceId,
                text: text,
                type: .original,
                style: .focusedSentence
            )
        } catch {
            if Task.isCancelled { return }
            toastMessage = error.localizedDescription
        }
    }

    private func speakSentenceTranslation(for entry: WordBookEntry) async {
        let text = entry.sentenceTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await ArticleAudioManager.shared.speak(
                sentenceId: entry.sentenceId,
                text: text,
                type: .translation,
                style: .focusedSentence
            )
        } catch {
            if Task.isCancelled { return }
            toastMessage = error.localizedDescription
        }
    }

    private func wordTranslationText(for entry: WordBookEntry) -> String {
        entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func wordTranslationText(meaning: String) -> String {
        meaning.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func explainWord(in entry: WordBookEntry, word: String, options: WordBookPlaybackOptions) async {
        stopPlaybackAll()
        let query = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        selectedEntryId = entry.id
        activeWord = query
        activePartOfSpeech = ""
        activeMeaning = ""
        activeTip = ""
        isLoadingExplanation = true

        do {
            if options.playWord {
                await speakWord(query)
            }

            let response = try await ArticleAPI.shared.explainWord(
                articleId: entry.articleId,
                sentenceId: entry.sentenceId,
                word: query
            )

            let displayWord = response.word.isEmpty ? query : response.word
            activeWord = displayWord
            activePartOfSpeech = response.partOfSpeech
            activeMeaning = response.meaning
            activeTip = response.tip
            isLoadingExplanation = false

            WordExplanationCacheStore.shared.save(
                sentenceId: entry.sentenceId,
                word: displayWord,
                partOfSpeech: response.partOfSpeech,
                meaning: response.meaning,
                tip: response.tip
            )

            await refreshEntries()
            if let refreshed = entries.first(where: {
                $0.articleId == entry.articleId
                    && $0.sentenceId == entry.sentenceId
                    && $0.normalizedWord == displayWord.lowercased()
                        .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]{}<>"))
            }) {
                selectedEntryId = refreshed.id
            }

            NotificationCenter.default.post(name: .wordBookDidChange, object: nil)

            if options.playWordTranslation {
                let spoken = wordTranslationText(meaning: response.meaning)
                if !spoken.isEmpty {
                    try? await ArticleAudioManager.shared.speak(
                        sentenceId: nil,
                        text: spoken,
                        type: .translation,
                        style: .focusedSentence
                    )
                }
            }
        } catch {
            isLoadingExplanation = false
            toastMessage = error.localizedDescription
        }
    }
}

private extension WordBookAPIItem {
    func asWordBookEntry() -> WordBookEntry {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lookedUp = formatter.date(from: lookedUpAt)
            ?? ISO8601DateFormatter().date(from: lookedUpAt)
            ?? Date()

        return WordBookEntry(
            entryId: entryId,
            articleId: articleId,
            sentenceId: sentenceId,
            word: word,
            normalizedWord: normalizedWord,
            sentenceOriginal: sentenceOriginal,
            sentenceTranslation: sentenceTranslation,
            partOfSpeech: partOfSpeech,
            meaning: meaning,
            tip: tip,
            reviewStep: reviewStep ?? 0,
            nextReviewAt: nextReviewAt,
            masteryStatus: masteryStatus ?? "learning",
            lastReviewedAt: lastReviewedAt,
            lookedUpAt: lookedUp
        )
    }
}
