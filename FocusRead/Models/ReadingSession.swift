import Foundation

struct ReadingDocument: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let fileName: String?
    let sourceType: ReadingDocumentSourceType
    let sections: [ReadingDocumentSection]

    init(
        id: UUID = UUID(),
        title: String,
        fileName: String?,
        sourceType: ReadingDocumentSourceType,
        sections: [ReadingDocumentSection]
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.sourceType = sourceType
        self.sections = sections
    }

    init(importedDocument: ImportedDocument) {
        let sourceType: ReadingDocumentSourceType = switch importedDocument.sourceType {
        case .txt:
            .txt
        case .pdf:
            .pdf
        case .epub:
            .epub
        case .image:
            .image
        }

        self.init(
            title: importedDocument.displayTitle,
            fileName: importedDocument.displayTitle,
            sourceType: sourceType,
            sections: importedDocument.sections.map {
                ReadingDocumentSection(
                    index: $0.index,
                    title: $0.chapterTitle,
                    pageNumber: $0.pageNumber,
                    chapterNumber: $0.chapterNumber,
                    wordRange: $0.wordRange,
                    epubNavigationLevel: $0.epubNavigationLevel,
                    epubSectionRole: $0.epubSectionRole,
                    epubStructureSource: $0.epubStructureSource,
                    epubStructureConfidence: $0.epubStructureConfidence
                )
            }
        )
    }

    static func pastedText() -> ReadingDocument {
        ReadingDocument(
            title: "Pasted Text",
            fileName: nil,
            sourceType: .pastedText,
            sections: [
                ReadingDocumentSection(
                    index: 0,
                    title: nil,
                    pageNumber: nil,
                    chapterNumber: nil,
                    wordRange: nil
                )
            ]
        )
    }
}

enum ReadingDocumentSourceType: Equatable, Sendable {
    case pastedText
    case txt
    case pdf
    case epub
    case image
}

struct ReadingDocumentSection: Identifiable, Equatable, Sendable {
    var id: Int { index }

    let index: Int
    let title: String?
    let pageNumber: Int?
    let chapterNumber: Int?
    let wordRange: Range<Int>?
    let epubNavigationLevel: Int?
    let epubSectionRole: EPUBSectionRole
    let epubStructureSource: EPUBStructureSource?
    let epubStructureConfidence: Double?

    init(
        index: Int,
        title: String?,
        pageNumber: Int?,
        chapterNumber: Int?,
        wordRange: Range<Int>?,
        epubNavigationLevel: Int? = nil,
        epubSectionRole: EPUBSectionRole = .body,
        epubStructureSource: EPUBStructureSource? = nil,
        epubStructureConfidence: Double? = nil
    ) {
        self.index = index
        self.title = title
        self.pageNumber = pageNumber
        self.chapterNumber = chapterNumber
        self.wordRange = wordRange
        self.epubNavigationLevel = epubNavigationLevel
        self.epubSectionRole = epubSectionRole
        self.epubStructureSource = epubStructureSource
        self.epubStructureConfidence = epubStructureConfidence
    }
}

struct ReadingSession: Equatable, Sendable {
    var tokens: [ReadingToken]
    var document: ReadingDocument
    var currentIndex: Int
    var wordsPerMinute: Int
    var stepSize: Int

    static let minimumWPM = 100
    static let maximumWPM = 1_200
    static let defaultWPM = 350

    init(
        tokens: [ReadingToken],
        document: ReadingDocument = .pastedText(),
        currentIndex: Int = 0,
        wordsPerMinute: Int = Self.defaultWPM,
        stepSize: Int = 1
    ) {
        self.tokens = tokens
        self.document = document
        self.currentIndex = min(max(currentIndex, 0), max(tokens.count - 1, 0))
        self.wordsPerMinute = Self.clampWPM(wordsPerMinute)
        self.stepSize = max(1, stepSize)
    }

    var currentToken: ReadingToken? {
        guard tokens.indices.contains(currentIndex) else { return nil }
        return tokens[currentIndex]
    }

    var currentTokens: [ReadingToken] {
        guard !tokens.isEmpty, tokens.indices.contains(currentIndex) else { return [] }
        let endIndex = min(currentIndex + stepSize, tokens.count)
        return Array(tokens[currentIndex..<endIndex])
    }

    var progress: Double {
        guard !tokens.isEmpty else { return 0 }
        let readCount = min(currentIndex + stepSize, tokens.count)
        return Double(readCount) / Double(tokens.count)
    }

    var isAtEnd: Bool {
        guard !tokens.isEmpty else { return true }
        return currentIndex >= max(tokens.count - 1, 0)
    }

    mutating func advance() {
        guard !tokens.isEmpty else { return }
        currentIndex = min(currentIndex + stepSize, max(tokens.count - 1, 0))
    }

    mutating func rewindWord() {
        currentIndex = max(currentIndex - stepSize, 0)
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
