import Foundation

struct ReadingSession: Equatable, Sendable {
    var tokens: [ReadingToken]
    var currentIndex: Int
    var wordsPerMinute: Int

    static let minimumWPM = 100
    static let maximumWPM = 1_200
    static let defaultWPM = 350

    init(tokens: [ReadingToken], currentIndex: Int = 0, wordsPerMinute: Int = Self.defaultWPM) {
        self.tokens = tokens
        self.currentIndex = min(max(currentIndex, 0), max(tokens.count - 1, 0))
        self.wordsPerMinute = Self.clampWPM(wordsPerMinute)
    }

    var currentToken: ReadingToken? {
        guard tokens.indices.contains(currentIndex) else { return nil }
        return tokens[currentIndex]
    }

    var progress: Double {
        guard !tokens.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(tokens.count)
    }

    var isAtEnd: Bool {
        currentIndex >= max(tokens.count - 1, 0)
    }

    mutating func advance() {
        guard !tokens.isEmpty else { return }
        currentIndex = min(currentIndex + 1, tokens.count - 1)
    }

    mutating func rewindWord() {
        currentIndex = max(currentIndex - 1, 0)
    }

    mutating func skipWord() {
        advance()
    }

    mutating func rewindSentence() {
        guard let current = currentToken else { return }
        if currentIndex > 0, tokens[currentIndex - 1].sentenceIndex == current.sentenceIndex {
            while currentIndex > 0, tokens[currentIndex - 1].sentenceIndex == current.sentenceIndex {
                currentIndex -= 1
            }
        } else {
            let targetSentence = max(current.sentenceIndex - 1, 0)
            while currentIndex > 0, tokens[currentIndex - 1].sentenceIndex >= targetSentence {
                currentIndex -= 1
                if tokens[currentIndex].sentenceIndex == targetSentence,
                   currentIndex == 0 || tokens[currentIndex - 1].sentenceIndex < targetSentence {
                    break
                }
            }
        }
    }

    mutating func setWPM(_ value: Int) {
        wordsPerMinute = Self.clampWPM(value)
    }

    static func clampWPM(_ value: Int) -> Int {
        min(max(value, minimumWPM), maximumWPM)
    }
}
