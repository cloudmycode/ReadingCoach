import Foundation

/// Times are supplied by the synthesizer, in seconds on the generated audio timeline.
struct SpeechWordBoundary: Codable, Equatable {
    let text: String
    let start: Double
    let duration: Double

    static func parse(metadata: Data) -> [SpeechWordBoundary] {
        guard let root = try? JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              let entries = root["Metadata"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard entry["Type"] as? String == "WordBoundary",
                  let data = entry["Data"] as? [String: Any],
                  let offset = data["Offset"] as? Double,
                  let duration = data["Duration"] as? Double,
                  offset.isFinite, duration.isFinite, offset >= 0, duration > 0,
                  let text = data["text"] as? [String: Any],
                  let value = text["Text"] as? String, !value.isEmpty else { return nil }
            let decoded = value.replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&")
            return SpeechWordBoundary(text: decoded, start: offset / 10_000_000, duration: duration / 10_000_000)
        }
    }
}

/// Audio and its timing metadata are cached atomically, so preloading cannot mix two syntheses.
struct TimedSpeechAudio: Codable {
    let audio: Data
    let boundaries: [SpeechWordBoundary]
}

struct SpeechWordTiming: Equatable {
    let range: NSRange
    let start: Double
    let end: Double

    static func align(_ boundaries: [SpeechWordBoundary], to text: String) -> [SpeechWordTiming] {
        // These replacements retain UTF-16 lengths, including offsets after emoji.
        func normalized(_ value: String) -> String {
            value.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
        }
        let source = normalized(text)
        let length = (source as NSString).length
        var cursor = 0
        var result: [SpeechWordTiming] = []
        for boundary in boundaries.sorted(by: { $0.start < $1.start }) {
            guard boundary.start.isFinite, boundary.duration.isFinite,
                  boundary.start >= 0, boundary.duration > 0 else { continue }
            let word = normalized(boundary.text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: source, range: NSRange(location: cursor, length: length - cursor)),
                  Range(match.range, in: text) != nil else { continue }
            let gap = (source as NSString).substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            // Do not jump over unmatched spoken content (e.g. "1 one" synthesized as
            // "one one") and incorrectly highlight a later occurrence of the word.
            guard gap.rangeOfCharacter(from: .alphanumerics) == nil else { break }
            result.append(SpeechWordTiming(range: match.range, start: boundary.start, end: boundary.start + boundary.duration))
            cursor = NSMaxRange(match.range)
        }
        return result
    }

    static func activeRange(at time: Double, in timings: [SpeechWordTiming]) -> NSRange? {
        timings.last(where: { $0.start <= time && time < $0.end })?.range
    }
}

struct SpokenWordHighlight: Equatable {
    let sentenceId: Int?
    let sourceText: String
    let range: NSRange
}
