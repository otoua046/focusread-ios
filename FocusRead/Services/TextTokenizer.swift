import Foundation

struct TextTokenizer: Sendable {
    func tokenize(_ input: String) -> [ReadingToken] {
        var sentenceIndex = 0
        return tokenize(
            input,
            startingGlobalWordIndex: 0,
            startingSentenceIndex: &sentenceIndex,
            sourceSection: nil
        )
    }

    func tokenize(_ document: ImportedDocument) -> [ReadingToken] {
        var tokens: [ReadingToken] = []
        var sentenceIndex = 0

        for section in document.sections {
            let sectionTokens = tokenize(
                section.text,
                startingGlobalWordIndex: tokens.count,
                startingSentenceIndex: &sentenceIndex,
                sourceSection: section,
                startsWithParagraphBreak: !tokens.isEmpty
            )
            tokens.append(contentsOf: sectionTokens)
        }

        return tokens
    }

    private func tokenize(
        _ input: String,
        startingGlobalWordIndex: Int,
        startingSentenceIndex: inout Int,
        sourceSection: ImportedDocumentSection?,
        startsWithParagraphBreak: Bool = false
    ) -> [ReadingToken] {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let scanner = Scanner(string: normalized)
        scanner.charactersToBeSkipped = nil

        var tokens: [ReadingToken] = []
        var pendingParagraphBreak = startsWithParagraphBreak

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
                id: startingGlobalWordIndex + tokens.count,
                text: display,
                rawText: rawWord,
                globalWordIndex: startingGlobalWordIndex + tokens.count,
                sourcePageNumber: sourceSection?.pageNumber,
                sourceChapterNumber: sourceSection?.chapterNumber,
                sourceChapterTitle: sourceSection?.chapterTitle,
                sourceSectionIndex: sourceSection?.index,
                pauseKind: pause,
                sentenceIndex: startingSentenceIndex,
                containsNumber: rawWord.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
            )
            tokens.append(token)

            if pause == .sentenceEnd || pause == .paragraphBreak {
                startingSentenceIndex += 1
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
