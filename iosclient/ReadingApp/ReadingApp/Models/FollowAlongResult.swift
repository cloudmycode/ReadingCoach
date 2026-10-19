import Foundation

/// A transcript-matching practice score, not a phonetic/pronunciation assessment.
struct FollowAlongResult: Codable, Equatable {
    let transcript: String
    let score: Int?
    let failureMessage: String?

    init(reference: String, transcript: String, failureMessage: String? = nil) {
        self.transcript = transcript
        self.failureMessage = failureMessage
        let expected = Self.words(reference)
        let actual = Self.words(transcript)
        guard failureMessage == nil, !expected.isEmpty, !actual.isEmpty else {
            score = nil
            return
        }
        // Word edit distance penalizes omissions, substitutions and extra words.
        var previous = Array(0...actual.count)
        for (i, word) in expected.enumerated() {
            var row = [i + 1]
            for (j, spoken) in actual.enumerated() {
                row.append(min(previous[j + 1] + 1, row[j] + 1,
                               previous[j] + (word == spoken ? 0 : 1)))
            }
            previous = row
        }
        let similarity = max(0, 1 - Double(previous[actual.count]) / Double(max(expected.count, actual.count)))
        score = max(1, min(10, Int((similarity * 10).rounded())))
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
