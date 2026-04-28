import Foundation

struct TextTokenizer: Sendable {
    func tokenize(_ input: String) -> [ReadingToken] {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let scanner = Scanner(string: normalized)
        scanner.charactersToBeSkipped = nil

        var tokens: [ReadingToken] = []
        var sentenceIndex = 0
        var pendingParagraphBreak = false

        while !scanner.isAtEnd {
            if let whitespace = scanner.scanCharacters(from: CharacterSet.whitespacesAndNewlines) {
                if whitespace.contains("\n\n") {
                    pendingParagraphBreak = true
                }
                continue
            }

            guard let rawWord = scanner.scanUpToCharacters(from: CharacterSet.whitespacesAndNewlines) else {
                break
            }

            let pause = pauseKind(for: rawWord, paragraphBreak: pendingParagraphBreak)
            let display = displayText(for: rawWord)
            guard !display.isEmpty else {
                pendingParagraphBreak = false
                continue
            }

            let token = ReadingToken(
                id: tokens.count,
                text: display,
                rawText: rawWord,
                pauseKind: pause,
                sentenceIndex: sentenceIndex,
                containsNumber: rawWord.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
            )
            tokens.append(token)

            if pause == .sentenceEnd || pause == .paragraphBreak {
                sentenceIndex += 1
            }
            pendingParagraphBreak = false
        }

        return tokens
    }

    private func displayText(for rawWord: String) -> String {
        rawWord.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”‘’()[]{}"))
    }

    private func pauseKind(for rawWord: String, paragraphBreak: Bool) -> ReadingToken.PauseKind {
        if paragraphBreak {
            return .paragraphBreak
        }

        let trimmed = rawWord.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”‘’()[]{}"))
        guard let last = trimmed.last else { return .none }

        if ".?!".contains(last) {
            return .sentenceEnd
        }
        if ",;:".contains(last) {
            return .minorPunctuation
        }
        return .none
    }
}
