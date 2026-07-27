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

    func togglePlaybackAll() {
        if isPlayingAll {
            stopPlaybackAll()
        } else {
            startPlaybackAll()
        }
    }

    func stopPlaybackAll() {
        playbackTask?.cancel()
        playbackTask = nil
        ArticleAudioManager.shared.stop()
        isPlayingAll = false
        isPlayingSentence = false
    }

    private func startPlaybackAll() {
        guard !displayedEntries.isEmpty else { return }
        stopPlaybackAll()
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
        for entry in playlist {
            if Task.isCancelled { break }

            selectEntry(entry)

            let word = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty {
                do {
                    try await ArticleAudioManager.shared.speak(
                        sentenceId: nil,
                        text: word,
                        type: .original,
                        style: .focusedSentence
                    )
                } catch {
                    if Task.isCancelled { break }
                    toastMessage = error.localizedDescription
                    break
                }
            }

            if Task.isCancelled { break }

            let sentence = entry.sentenceOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                isPlayingSentence = true
                do {
                    try await ArticleAudioManager.shared.speak(
                        sentenceId: entry.sentenceId,
                        text: sentence,
                        type: .original,
                        style: .focusedSentence
                    )
                } catch {
                    isPlayingSentence = false
                    if Task.isCancelled { break }
                    toastMessage = error.localizedDescription
                    break
                }
                isPlayingSentence = false
            }
        }
    }

    func playSentence(_ entry: WordBookEntry) async {
        stopPlaybackAll()
        let text = entry.sentenceOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPlayingSentence = true
        defer { isPlayingSentence = false }
        selectEntry(entry)
        do {
            try await ArticleAudioManager.shared.speak(
                sentenceId: entry.sentenceId,
                text: text,
                type: .original,
                style: .focusedSentence
            )
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    func explainWord(in entry: WordBookEntry, word: String, playTranslation: Bool) async {
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
            try await ArticleAudioManager.shared.speak(
                sentenceId: nil,
                text: query,
                type: .original,
                style: .focusedSentence
            )

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

            if playTranslation {
                let spoken = [response.meaning, response.tip]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "，")
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
