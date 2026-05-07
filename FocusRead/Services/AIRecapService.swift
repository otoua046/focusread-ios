import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIRecapSource: Equatable, Sendable {
    let readID: UUID
    let sessionID: UUID
    let sessionStartedAt: Date
    let sessionEndedAt: Date
    let sourceStartWordIndex: Int
    let sourceEndWordIndex: Int
    let text: String
    let wordCount: Int
    let isCapped: Bool
}

enum AIRecapGenerationError: Error, Equatable {
    case localAIUnavailable
    case noEligibleSession
    case sourceUnavailable
    case notEnoughText
    case generationFailed
}

protocol AIRecapModelGenerating: Sendable {
    var isAvailable: Bool { get }
    var modelName: String { get }
    var modelVersion: String { get }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String
}

struct AIRecapSourceExtractor: Sendable {
    let tokenizer: TextTokenizer
    let maximumInputWordCount: Int
    let minimumInputWordCount: Int

    init(
        tokenizer: TextTokenizer = TextTokenizer(),
        maximumInputWordCount: Int = 3_000,
        minimumInputWordCount: Int = 40
    ) {
        self.tokenizer = tokenizer
        self.maximumInputWordCount = max(maximumInputWordCount, 1)
        self.minimumInputWordCount = max(minimumInputWordCount, 1)
    }

    func recentEligibleSessions(
        for readID: UUID,
        from events: [ReadingSessionEvent],
        limit: Int = 3
    ) -> [ReadingSessionEvent] {
        events
            .filter { $0.readID == readID && $0.sourceWordRange != nil }
            .sorted { $0.endedAt > $1.endedAt }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    func recentEligibleSessions(
        for read: SavedRead,
        from events: [ReadingSessionEvent],
        limit: Int = 3
    ) -> [ReadingSessionEvent] {
        var hasIncludedRecoveredRange = false
        let sortedEvents = events
            .filter { $0.readID == read.id }
            .sorted { $0.endedAt > $1.endedAt }

        return sortedEvents.compactMap { event in
            if event.sourceWordRange != nil {
                return event
            }

            guard !hasIncludedRecoveredRange,
                  recoveredSourceWordRange(for: read, sessionEvent: event) != nil else {
                return nil
            }

            hasIncludedRecoveredRange = true
            return event
        }
        .prefix(max(limit, 0))
        .map { $0 }
    }

    func source(for read: SavedRead, sessionEvent: ReadingSessionEvent) throws -> AIRecapSource {
        let tokens = tokens(for: read)
        guard !tokens.isEmpty else {
            throw AIRecapGenerationError.sourceUnavailable
        }

        guard let sessionRange = sessionEvent.sourceWordRange
                ?? recoveredSourceWordRange(for: read, sessionEvent: sessionEvent, tokenCount: tokens.count) else {
            throw AIRecapGenerationError.noEligibleSession
        }

        let lowerBound = min(max(sessionRange.lowerBound, 0), tokens.count)
        let upperBound = min(max(sessionRange.upperBound, lowerBound), tokens.count)
        guard upperBound > lowerBound else {
            throw AIRecapGenerationError.sourceUnavailable
        }

        let cappedUpperBound = min(upperBound, lowerBound + maximumInputWordCount)
        let sourceTokens = tokens[lowerBound..<cappedUpperBound]
        let sourceText = sourceTokens
            .map { $0.rawText.isEmpty ? $0.text : $0.rawText }
            .joined(separator: " ")
            .focusReadNormalizedDocumentText
        let wordCount = Self.wordCount(sourceText)
        guard wordCount >= minimumInputWordCount else {
            throw AIRecapGenerationError.notEnoughText
        }

        return AIRecapSource(
            readID: read.id,
            sessionID: sessionEvent.id,
            sessionStartedAt: sessionEvent.startedAt,
            sessionEndedAt: sessionEvent.endedAt,
            sourceStartWordIndex: lowerBound,
            sourceEndWordIndex: cappedUpperBound,
            text: sourceText,
            wordCount: wordCount,
            isCapped: cappedUpperBound < upperBound
        )
    }

    private func tokens(for read: SavedRead) -> [ReadingToken] {
        if let importedDocument = SavedReadMapper.importedDocument(from: read) {
            return tokenizer.tokenize(importedDocument)
        }

        return tokenizer.tokenize(SavedReadMapper.text(from: read))
    }

    private func recoveredSourceWordRange(
        for read: SavedRead,
        sessionEvent: ReadingSessionEvent,
        tokenCount: Int? = nil
    ) -> Range<Int>? {
        guard sessionEvent.readID == read.id,
              sessionEvent.wordsRead > 0 else {
            return nil
        }

        let totalWordCount = max(tokenCount ?? read.totalWordCount, read.totalWordCount, 0)
        let rawUpperBound = read.progressPercent >= 100 ? totalWordCount : read.currentWordIndex
        let upperBound = min(max(rawUpperBound, 0), totalWordCount)
        let lowerBound = max(upperBound - sessionEvent.wordsRead, 0)
        guard upperBound > lowerBound else {
            return nil
        }

        return lowerBound..<upperBound
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

struct AIRecapService: Sendable {
    static let maximumOutputWordCount = 500

    let extractor: AIRecapSourceExtractor
    private let model: any AIRecapModelGenerating
    private let dateProvider: @Sendable () -> Date

    init(
        extractor: AIRecapSourceExtractor = AIRecapSourceExtractor(),
        model: any AIRecapModelGenerating = FoundationModelAIRecapModel(),
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.extractor = extractor
        self.model = model
        self.dateProvider = dateProvider
    }

    var isAvailable: Bool {
        model.isAvailable
    }

    func generateRecap(for read: SavedRead, sessionEvent: ReadingSessionEvent) async throws -> AIRecap {
        guard model.isAvailable else {
            throw AIRecapGenerationError.localAIUnavailable
        }

        let source = try extractor.source(for: read, sessionEvent: sessionEvent)
        let generatedText = try await model.generateRecap(
            from: source,
            outputWordLimit: Self.maximumOutputWordCount
        )
        let sanitizedText = Self.sanitizedSummary(generatedText, wordLimit: Self.maximumOutputWordCount)
        guard !sanitizedText.isEmpty else {
            throw AIRecapGenerationError.generationFailed
        }

        return AIRecap(
            readID: read.id,
            sessionID: source.sessionID,
            sessionStartedAt: source.sessionStartedAt,
            sessionEndedAt: source.sessionEndedAt,
            sourceStartWordIndex: source.sourceStartWordIndex,
            sourceEndWordIndex: source.sourceEndWordIndex,
            generatedText: sanitizedText,
            createdAt: dateProvider(),
            inputWordCount: source.wordCount,
            outputWordCount: Self.wordCount(sanitizedText),
            modelName: model.modelName,
            modelVersion: model.modelVersion
        )
    }

    static func sanitizedSummary(_ text: String, wordLimit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        let words = normalized.split { $0.isWhitespace || $0.isNewline }
        guard words.count > wordLimit else {
            return normalized
        }

        return words.prefix(max(wordLimit, 1)).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

private struct FoundationModelAIRecapModel: AIRecapModelGenerating {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif

        return false
    }

    var modelName: String {
        "Apple Foundation Models"
    }

    var modelVersion: String {
        "foundation-models-ios26"
    }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return try await FoundationModelAIRecapGenerator.generateRecap(
                from: source,
                outputWordLimit: outputWordLimit
            )
        }
        #endif

        throw AIRecapGenerationError.localAIUnavailable
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private enum FoundationModelAIRecapGenerator {
    static func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        let instructions = """
        You create concise reading-session recaps on this device.
        Use only the supplied excerpt. Do not add facts, guesses, spoilers from outside the excerpt, citations, or chatbot-style commentary.
        Return plain prose only, around 250-500 words, with short paragraphs.
        Make the recap useful for quickly remembering what happened or what ideas were covered.
        Do not include a title, markdown, bullets, or labels such as "AI Recap".
        """

        let prompt = """
        Book/session excerpt word count: \(source.wordCount)
        Output word limit: \(outputWordLimit)
        Excerpt:
        \(source.text)
        """

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
