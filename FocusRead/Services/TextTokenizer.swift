import Foundation

struct TextTokenizer: Sendable {
    func tokenize(_ input: String) -> [ReadingToken] {
        var tokens: [ReadingToken] = []
        var sentenceIndex = 0
        tokenize(
            input,
            tokens: &tokens,
            startingSentenceIndex: &sentenceIndex,
            sourceSection: nil
        )
        return tokens
    }

    func tokenize(_ document: ImportedDocument) -> [ReadingToken] {
        var tokens: [ReadingToken] = []
        var sentenceIndex = 0

        for section in document.sections {
            if let last = tokens.last, last.pauseKind != .paragraphBreak {
                tokens[tokens.count - 1] = ReadingToken(
                    id: last.id,
                    text: last.text,
                    rawText: last.rawText,
                    globalWordIndex: last.globalWordIndex,
                    sourcePageNumber: last.sourcePageNumber,
                    sourceChapterNumber: last.sourceChapterNumber,
                    sourceChapterTitle: last.sourceChapterTitle,
                    sourceSectionIndex: last.sourceSectionIndex,
                    pauseKind: .paragraphBreak,
                    sentenceIndex: last.sentenceIndex,
                    containsNumber: last.containsNumber
                )
                if last.pauseKind != .sentenceEnd {
                    sentenceIndex += 1
                }
            }

            tokenize(
                section.text,
                tokens: &tokens,
                startingSentenceIndex: &sentenceIndex,
                sourceSection: section
            )
        }

        return tokens
    }

    private func tokenize(
        _ input: String,
        tokens: inout [ReadingToken],
        startingSentenceIndex: inout Int,
        sourceSection: ImportedDocumentSection?
    ) {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let scanner = Scanner(string: normalized)
        scanner.charactersToBeSkipped = nil

        while !scanner.isAtEnd {
            if let whitespace = scanner.scanCharacters(from: CharacterSet.whitespacesAndNewlines) {
                if whitespace.contains("\n\n") {
                    if let last = tokens.last, last.pauseKind != .paragraphBreak, last.sourceSectionIndex == sourceSection?.index {
                        tokens[tokens.count - 1] = ReadingToken(
                            id: last.id,
                            text: last.text,
                            rawText: last.rawText,
                            globalWordIndex: last.globalWordIndex,
                            sourcePageNumber: last.sourcePageNumber,
                            sourceChapterNumber: last.sourceChapterNumber,
                            sourceChapterTitle: last.sourceChapterTitle,
                            sourceSectionIndex: last.sourceSectionIndex,
                            pauseKind: .paragraphBreak,
                            sentenceIndex: last.sentenceIndex,
                            containsNumber: last.containsNumber
                        )
                        if last.pauseKind != .sentenceEnd {
                            startingSentenceIndex += 1
                        }
                    } else if let last = tokens.last, last.pauseKind != .paragraphBreak {
                        // For cross section whitespace or when no sourceSection provided
                        tokens[tokens.count - 1] = ReadingToken(
                            id: last.id,
                            text: last.text,
                            rawText: last.rawText,
                            globalWordIndex: last.globalWordIndex,
                            sourcePageNumber: last.sourcePageNumber,
                            sourceChapterNumber: last.sourceChapterNumber,
                            sourceChapterTitle: last.sourceChapterTitle,
                            sourceSectionIndex: last.sourceSectionIndex,
                            pauseKind: .paragraphBreak,
                            sentenceIndex: last.sentenceIndex,
                            containsNumber: last.containsNumber
                        )
                        if last.pauseKind != .sentenceEnd {
                            startingSentenceIndex += 1
                        }
                    }
                }
                continue
            }

            guard let rawWord = scanner.scanUpToCharacters(from: CharacterSet.whitespacesAndNewlines) else {
                break
            }

            let pause = pauseKind(for: rawWord)
            let display = displayText(for: rawWord)
            guard !display.isEmpty else {
                continue
            }

            let token = ReadingToken(
                id: tokens.count,
                text: display,
                rawText: rawWord,
                globalWordIndex: tokens.count,
                sourcePageNumber: sourceSection?.pageNumber,
                sourceChapterNumber: sourceSection?.chapterNumber,
                sourceChapterTitle: sourceSection?.chapterTitle,
                sourceSectionIndex: sourceSection?.index,
                pauseKind: pause,
                sentenceIndex: startingSentenceIndex,
                containsNumber: rawWord.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
            )
            tokens.append(token)

            if pause == .sentenceEnd {
                startingSentenceIndex += 1
            }
        }
    }

    private func displayText(for rawWord: String) -> String {
        rawWord.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”‘’()[]{}"))
    }

    private func pauseKind(for rawWord: String) -> ReadingToken.PauseKind {
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
