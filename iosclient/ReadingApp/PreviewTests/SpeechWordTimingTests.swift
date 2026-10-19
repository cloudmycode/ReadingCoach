import Foundation

enum SpeechWordTimingChecks {
    static func run() throws {
        let metadata = Data(#"{"Metadata":[{"Type":"WordBoundary","Data":{"Offset":1000000,"Duration":2000000,"text":{"Text":"Go"}}},{"Type":"WordBoundary","Data":{"Offset":4000000,"Duration":2000000,"text":{"Text":"go"}}},{"Type":"SentenceBoundary","Data":{"Offset":0,"Duration":10000000,"text":{"Text":"Go go"}}},{"Type":"WordBoundary","Data":{"Offset":-1,"Duration":4,"text":{"Text":"invalid"}}}]}"#.utf8)
        let boundaries = SpeechWordBoundary.parse(metadata: metadata)
        precondition(boundaries.count == 2 && boundaries[0].start == 0.1 && boundaries[0].duration == 0.2)
        let text = "🙂 Go, go!"
        let aligned = SpeechWordTiming.align(boundaries, to: text)
        precondition(aligned.map(\.range) == [NSRange(location: 3, length: 2), NSRange(location: 7, length: 2)])
        precondition(SpeechWordTiming.activeRange(at: 0.09, in: aligned) == nil)
        precondition(SpeechWordTiming.activeRange(at: 0.1, in: aligned) == aligned[0].range)
        precondition(SpeechWordTiming.activeRange(at: 0.35, in: aligned) == nil)
        precondition(SpeechWordTiming.activeRange(at: 0.5, in: aligned) == aligned[1].range)
        precondition(SpeechWordTiming.activeRange(at: 1, in: aligned) == nil)
        let words = ["The", "hero", "said", "he", "can't", "catch", "a", "cat"].enumerated().map { SpeechWordBoundary(text: $0.element, start: Double($0.offset), duration: 0.5) }
        let tricky = "The hero said he can’t catch a cat."
        let mapped = SpeechWordTiming.align(words, to: tricky)
        precondition(mapped.map { (tricky as NSString).substring(with: $0.range) } == ["The", "hero", "said", "he", "can’t", "catch", "a", "cat"])
        precondition(SpeechWordTiming.align([SpeechWordBoundary(text: "two", start: 0, duration: 1)], to: "2").isEmpty)
        precondition(SpeechWordTiming.align([SpeechWordBoundary(text: "one", start: 0, duration: 1)], to: "1 one").isEmpty)
        precondition(SpeechWordTiming.align([SpeechWordBoundary(text: "he", start: 0, duration: 1)], to: "The hero").isEmpty)
        precondition(SpeechWordBoundary.parse(metadata: Data("invalid".utf8)).isEmpty)
        let escaped = Data(#"{"Metadata":[{"Type":"WordBoundary","Data":{"Offset":0,"Duration":1000000,"text":{"Text":"Tom&apos;s"}}}]}"#.utf8)
        precondition(SpeechWordBoundary.parse(metadata: escaped).first?.text == "Tom's")
        let speech = TimedSpeechAudio(audio: Data([1, 2, 3]), boundaries: boundaries)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let restored = try PropertyListDecoder().decode(TimedSpeechAudio.self, from: encoder.encode(speech))
        precondition(restored.audio == speech.audio && restored.boundaries == speech.boundaries)
        print("PASS: word metadata ticks, invalid metadata, repeated words, UTF-16 emoji offsets, punctuation, apostrophes, whole-word matching, missing timings, silence/end clearing, atomic audio/timing cache round trip.")
    }
}
