import Foundation

@main struct FollowAlongResultChecks {
    static func main() {
        func score(_ expected: String, _ actual: String) -> Int? {
            FollowAlongResult(reference: expected, transcript: actual).score
        }
        precondition(score("Hello, world!", "hello world") == 10)
        precondition(score("Don't stop.", "don’t stop") == 10)
        precondition(score("one two three four", "one two") == 5)
        precondition(score("one two", "one two three four") == 5)
        precondition(score("one two", "red blue") == 1)
        precondition(score("one two", "two one")! < 10)
        precondition(score("hello", " \n ") == nil)
        precondition(score("...", "hello") == nil)
        precondition(score("hello", "...") == nil)
        precondition(FollowAlongResult(reference: "hello", transcript: "hello", failureMessage: "failed").score == nil)
        print("PASS: follow-along matching, normalization, omissions/extras/order, 1–10 range, silence/error unscored")
    }
}
