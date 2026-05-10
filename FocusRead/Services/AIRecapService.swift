import Foundation
import NaturalLanguage
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIRecapSession: Identifiable, Equatable, Sendable {
    var id: UUID
    var readID: UUID
    var startedAt: Date
    var endedAt: Date
    var wordsRead: Int
    var averageWPM: Int
    var sourceStartWordIndex: Int
    var sourceEndWordIndex: Int
    var sourceEventIDs: [UUID]

    var sourceWordRange: Range<Int> {
        sourceStartWordIndex..<sourceEndWordIndex
    }
}

struct AIRecapDetectedLanguage: Equatable, Sendable {
    let code: String
    let name: String
    let source: Source

    enum Source: String, Equatable, Sendable {
        case metadata
        case text
    }
}

struct AIRecapSource: Equatable, Sendable {
    let readID: UUID
    let sessionID: UUID
    let sessionStartedAt: Date
    let sessionEndedAt: Date
    let documentSourceType: SavedReadSourceType
    let sourceStartWordIndex: Int
    let sourceEndWordIndex: Int
    let sourceWordCountBeforeCap: Int
    let rawTextLength: Int
    let cleanedTextLength: Int
    let text: String
    let wordCount: Int
    let isCapped: Bool
    let detectedLanguage: AIRecapDetectedLanguage?
}

enum AIRecapGenerationError: Error, Equatable {
    case localAIUnavailable
    case noEligibleSession
    case sourceUnavailable
    case notEnoughText
    case unsupportedLanguage
    case generationFailed
}

protocol AIRecapModelGenerating: Sendable {
    var isAvailable: Bool { get }
    var modelName: String { get }
    var modelVersion: String { get }
    var availabilityDebugDescription: String { get }

    func supportsLanguage(_ code: String) -> Bool?
    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String
}

extension AIRecapModelGenerating {
    var availabilityDebugDescription: String {
        isAvailable ? "available" : "unavailable"
    }

    func supportsLanguage(_ code: String) -> Bool? {
        nil
    }
}

struct AIRecapSourceExtractor: Sendable {
    static let logicalSessionMergeGap: TimeInterval = 30 * 60

    let tokenizer: TextTokenizer
    let maximumInputWordCount: Int
    let minimumInputWordCount: Int

    init(
        tokenizer: TextTokenizer = TextTokenizer(),
        maximumInputWordCount: Int = 5_000,
        minimumInputWordCount: Int = 250
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
    ) -> [AIRecapSession] {
        logicalSessions(for: read, from: events)
            .filter { $0.sourceWordRange.count >= minimumInputWordCount }
            .sorted { $0.endedAt > $1.endedAt }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    func source(for read: SavedRead, recapSession: AIRecapSession) throws -> AIRecapSource {
        let tokens = tokens(for: read)
        guard !tokens.isEmpty else {
            throw AIRecapGenerationError.sourceUnavailable
        }

        let lowerBound = min(max(recapSession.sourceWordRange.lowerBound, 0), tokens.count)
        let upperBound = min(max(recapSession.sourceWordRange.upperBound, lowerBound), tokens.count)
        guard upperBound > lowerBound else {
            throw AIRecapGenerationError.sourceUnavailable
        }

        let sourceWordCountBeforeCap = upperBound - lowerBound
        let cappedLowerBound = max(lowerBound, upperBound - maximumInputWordCount)
        let sourceTokens = tokens[cappedLowerBound..<upperBound]
        let rawSourceText = sourceTokens
            .map { $0.rawText.isEmpty ? $0.text : $0.rawText }
            .joined(separator: " ")
        let sourceText = AIRecapSourceTextCleaner.clean(rawSourceText)
        let wordCount = Self.wordCount(sourceText)
        guard wordCount >= minimumInputWordCount else {
            throw AIRecapGenerationError.notEnoughText
        }

        return AIRecapSource(
            readID: read.id,
            sessionID: recapSession.id,
            sessionStartedAt: recapSession.startedAt,
            sessionEndedAt: recapSession.endedAt,
            documentSourceType: read.sourceType,
            sourceStartWordIndex: cappedLowerBound,
            sourceEndWordIndex: upperBound,
            sourceWordCountBeforeCap: sourceWordCountBeforeCap,
            rawTextLength: rawSourceText.count,
            cleanedTextLength: sourceText.count,
            text: sourceText,
            wordCount: wordCount,
            isCapped: sourceWordCountBeforeCap > maximumInputWordCount,
            detectedLanguage: Self.detectedLanguage(metadataLanguageCode: read.languageCode, text: sourceText)
        )
    }

    func source(for read: SavedRead, sessionEvent: ReadingSessionEvent) throws -> AIRecapSource {
        guard let recapSession = logicalSessions(for: read, from: [sessionEvent]).first else {
            throw AIRecapGenerationError.noEligibleSession
        }

        return try source(for: read, recapSession: recapSession)
    }

    func logicalSessions(
        for read: SavedRead,
        from events: [ReadingSessionEvent]
    ) -> [AIRecapSession] {
        let readEvents = events
            .filter { $0.readID == read.id }
            .sorted {
                if $0.startedAt != $1.startedAt {
                    return $0.startedAt < $1.startedAt
                }
                return $0.endedAt < $1.endedAt
            }
        let newestRecoverableMissingRangeEventID = readEvents
            .filter { $0.sourceWordRange == nil }
            .sorted { $0.endedAt > $1.endedAt }
            .first { recoveredSourceWordRange(for: read, sessionEvent: $0) != nil }?
            .id

        let segments = readEvents.compactMap { event -> AIRecapSession? in
            let range: Range<Int>?
            if let sourceWordRange = event.sourceWordRange {
                range = sourceWordRange
            } else if event.id == newestRecoverableMissingRangeEventID {
                range = recoveredSourceWordRange(for: read, sessionEvent: event)
            } else {
                range = nil
            }

            guard let range, range.upperBound > range.lowerBound else {
                return nil
            }

            return AIRecapSession(
                id: event.id,
                readID: read.id,
                startedAt: event.startedAt,
                endedAt: event.endedAt,
                wordsRead: event.wordsRead,
                averageWPM: event.averageWPM,
                sourceStartWordIndex: range.lowerBound,
                sourceEndWordIndex: range.upperBound,
                sourceEventIDs: [event.id]
            )
        }

        return segments.reduce(into: [AIRecapSession]()) { sessions, segment in
            guard var current = sessions.popLast() else {
                sessions.append(segment)
                return
            }

            let gap = segment.startedAt.timeIntervalSince(current.endedAt)
            guard gap < Self.logicalSessionMergeGap,
                  Self.sourceRangesCanMerge(current.sourceWordRange, segment.sourceWordRange) else {
                sessions.append(current)
                sessions.append(segment)
                return
            }

            let totalWords = current.wordsRead + segment.wordsRead
            let weightedWPM = current.averageWPM * current.wordsRead + segment.averageWPM * segment.wordsRead
            current.endedAt = max(current.endedAt, segment.endedAt)
            current.wordsRead = totalWords
            current.averageWPM = totalWords > 0 ? Int((Double(weightedWPM) / Double(totalWords)).rounded()) : current.averageWPM
            current.sourceStartWordIndex = min(current.sourceStartWordIndex, segment.sourceStartWordIndex)
            current.sourceEndWordIndex = max(current.sourceEndWordIndex, segment.sourceEndWordIndex)
            current.sourceEventIDs.append(contentsOf: segment.sourceEventIDs)
            current.id = Self.logicalSessionID(for: current)
            sessions.append(current)
        }
    }

    private static func sourceRangesCanMerge(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        lhs.lowerBound <= rhs.upperBound && rhs.lowerBound <= lhs.upperBound
    }

    private static func logicalSessionID(for session: AIRecapSession) -> UUID {
        guard session.sourceEventIDs.count > 1 else {
            return session.id
        }

        var hasher = StableSessionHasher()
        hasher.update("ai-recap-logical-session-v1")
        hasher.update(session.readID.uuidString)
        hasher.update(session.sourceStartWordIndex)
        hasher.update(session.sourceEndWordIndex)
        session.sourceEventIDs.forEach { hasher.update($0.uuidString) }
        return hasher.uuid()
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

    private static func detectedLanguage(
        metadataLanguageCode: String?,
        text: String
    ) -> AIRecapDetectedLanguage? {
        if let metadataLanguage = language(fromMetadataCode: metadataLanguageCode) {
            return metadataLanguage
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(12_000)))
        guard let language = recognizer.dominantLanguage,
              language != .undetermined else {
            return nil
        }

        let code = language.rawValue.lowercased()
        return languageName(for: code).map {
            AIRecapDetectedLanguage(code: code, name: $0, source: .text)
        }
    }

    private static func language(fromMetadataCode code: String?) -> AIRecapDetectedLanguage? {
        guard let normalizedCode = normalizedLanguageCode(code),
              let name = languageName(for: normalizedCode) else {
            return nil
        }

        return AIRecapDetectedLanguage(code: normalizedCode, name: name, source: .metadata)
    }

    private static func normalizedLanguageCode(_ code: String?) -> String? {
        guard let code else { return nil }
        let normalized = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        guard !normalized.isEmpty,
              normalized != "und",
              normalized.range(of: #"^[a-z]{2,3}(-[a-z0-9]{2,8})*$"#, options: .regularExpression) != nil else {
            return nil
        }

        return normalized
    }

    private static func languageName(for code: String) -> String? {
        let baseCode = code.split(separator: "-").first.map(String.init) ?? code
        switch baseCode {
        case "en": return "English"
        case "fr": return "French"
        case "es": return "Spanish"
        case "de": return "German"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "nl": return "Dutch"
        case "sv": return "Swedish"
        case "da": return "Danish"
        case "no", "nb", "nn": return "Norwegian"
        case "fi": return "Finnish"
        case "pl": return "Polish"
        case "ru": return "Russian"
        case "uk": return "Ukrainian"
        case "zh": return "Chinese"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "ar": return "Arabic"
        case "tr": return "Turkish"
        default:
            return Locale(identifier: "en").localizedString(forLanguageCode: baseCode)
        }
    }
}

enum AIRecapSourceTextCleaner {
    static func clean(_ text: String) -> String {
        text
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .focusReadDecodedHTMLEntities
            .focusReadRemovingControlCharacters
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }
}

private struct StableSessionHasher {
    private var high: UInt64 = 0xcbf29ce484222325
    private var low: UInt64 = 0x84222325cbf29ce4

    mutating func update(_ value: String) {
        value.utf8.forEach { update($0) }
        update(UInt8.max)
    }

    mutating func update(_ value: Int) {
        withUnsafeBytes(of: Int64(value).bigEndian) { bytes in
            bytes.forEach { update($0) }
        }
        update(UInt8.max)
    }

    func uuid() -> UUID {
        var bytes = bytes(for: high) + bytes(for: low)
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private mutating func update(_ byte: UInt8) {
        high ^= UInt64(byte)
        high = high &* 0x00000100000001b3
        low ^= UInt64(byte) &+ 0x9e3779b97f4a7c15
        low = low &* 0x00000100000001b3
    }

    private func bytes(for value: UInt64) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }
}

struct AIRecapService: Sendable {
    static let maximumOutputWordCount = 500
    private static let logger = Logger(subsystem: "FocusRead", category: "AIRecap")

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

    func generateRecap(for read: SavedRead, recapSession: AIRecapSession) async throws -> AIRecap {
        Self.logger.debug("AI recap generation requested. localAIAvailable=\(model.isAvailable, privacy: .public) availability=\(model.availabilityDebugDescription, privacy: .public) documentType=\(read.sourceType.debugLogName, privacy: .public)")
        guard model.isAvailable else {
            Self.logger.error("AI recap generation blocked. reason=localAIUnavailable availability=\(model.availabilityDebugDescription, privacy: .public) documentType=\(read.sourceType.debugLogName, privacy: .public)")
            throw AIRecapGenerationError.localAIUnavailable
        }

        let source: AIRecapSource
        do {
            source = try extractor.source(for: read, recapSession: recapSession)
        } catch {
            Self.logger.error("AI recap source extraction failed. reason=\(String(describing: error), privacy: .public) documentType=\(read.sourceType.debugLogName, privacy: .public)")
            throw error
        }

        if let languageCode = source.detectedLanguage?.code,
           model.supportsLanguage(languageCode) == false {
            Self.logger.error("AI recap generation blocked. reason=unsupportedLanguage documentType=\(source.documentSourceType.debugLogName, privacy: .public) detectedLanguage=\(source.detectedLanguage?.name ?? "unknown", privacy: .public) detectedLanguageCode=\(languageCode, privacy: .public) availability=\(model.availabilityDebugDescription, privacy: .public)")
            throw AIRecapGenerationError.unsupportedLanguage
        }

        let prompt = AIRecapPromptBuilder.makePrompt(for: source, outputWordLimit: Self.maximumOutputWordCount)
        Self.logger.debug("AI recap generation starting. documentType=\(source.documentSourceType.debugLogName, privacy: .public) rawTextLength=\(source.rawTextLength, privacy: .public) cleanedTextLength=\(source.cleanedTextLength, privacy: .public) sourceWordsBeforeCap=\(source.sourceWordCountBeforeCap, privacy: .public) sourceWordsAfterCap=\(source.wordCount, privacy: .public) detectedLanguage=\(source.detectedLanguage?.name ?? "unknown", privacy: .public) detectedLanguageCode=\(source.detectedLanguage?.code ?? "unknown", privacy: .public) isCapped=\(source.isCapped, privacy: .public) cleanedSourcePreview=\(Self.loggableSnippet(source.text, limit: 500), privacy: .private) promptPreview=\(prompt.logDescription, privacy: .private)")

        let generationStartedAt = Date()
        do {
            let generatedText = try await model.generateRecap(
                from: source,
                outputWordLimit: Self.maximumOutputWordCount
            )
            let sanitizedText = Self.sanitizedSummary(generatedText, wordLimit: Self.maximumOutputWordCount)
            guard !sanitizedText.isEmpty else {
                let duration = Date().timeIntervalSince(generationStartedAt)
                Self.logger.error("AI recap generation failed. reason=emptyOutput documentType=\(source.documentSourceType.debugLogName, privacy: .public) detectedLanguage=\(source.detectedLanguage?.name ?? "unknown", privacy: .public) durationSeconds=\(duration, privacy: .public)")
                throw AIRecapGenerationError.generationFailed
            }

            let duration = Date().timeIntervalSince(generationStartedAt)
            Self.logger.debug("AI recap generation finished. documentType=\(source.documentSourceType.debugLogName, privacy: .public) outputWords=\(Self.wordCount(sanitizedText), privacy: .public) detectedLanguage=\(source.detectedLanguage?.name ?? "unknown", privacy: .public) durationSeconds=\(duration, privacy: .public)")

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
                sourceLanguageCode: source.detectedLanguage?.code,
                sourceLanguageName: source.detectedLanguage?.name,
                modelName: model.modelName,
                modelVersion: model.modelVersion
            )
        } catch {
            let mappedError = Self.mappedGenerationError(error)
            let duration = Date().timeIntervalSince(generationStartedAt)
            Self.logger.error("AI recap generation failed. reason=\(Self.debugDescription(for: error), privacy: .public) mappedReason=\(String(describing: mappedError), privacy: .public) documentType=\(source.documentSourceType.debugLogName, privacy: .public) rawTextLength=\(source.rawTextLength, privacy: .public) cleanedTextLength=\(source.cleanedTextLength, privacy: .public) sourceWordsAfterCap=\(source.wordCount, privacy: .public) detectedLanguage=\(source.detectedLanguage?.name ?? "unknown", privacy: .public) durationSeconds=\(duration, privacy: .public)")
            if mappedError == .unsupportedLanguage {
                throw mappedError
            }
            throw error
        }
    }

    func generateRecap(for read: SavedRead, sessionEvent: ReadingSessionEvent) async throws -> AIRecap {
        guard let recapSession = extractor.logicalSessions(for: read, from: [sessionEvent]).first else {
            throw AIRecapGenerationError.noEligibleSession
        }

        return try await generateRecap(for: read, recapSession: recapSession)
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

    private static func loggableSnippet(_ text: String, limit: Int) -> String {
        let snippet = String(text.prefix(max(limit, 0)))
        return snippet.replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func mappedGenerationError(_ error: Error) -> AIRecapGenerationError {
        if let recapError = error as? AIRecapGenerationError {
            return recapError
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let generationError = error as? LanguageModelSession.GenerationError {
            if case .unsupportedLanguageOrLocale = generationError {
                return .unsupportedLanguage
            }
        }
        #endif

        return .generationFailed
    }

    private static func debugDescription(for error: Error) -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let generationError = error as? LanguageModelSession.GenerationError {
            return [
                String(describing: generationError),
                generationError.failureReason.map { "failureReason=\($0)" },
                generationError.recoverySuggestion.map { "recoverySuggestion=\($0)" }
            ]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        #endif

        return String(describing: error)
    }
}

struct AIRecapPromptPayload: Equatable, Sendable {
    let instructions: String
    let prompt: String
    let logDescription: String
}

enum AIRecapPromptBuilder {
    static func makePrompt(for source: AIRecapSource, outputWordLimit: Int) -> AIRecapPromptPayload {
        let languageName = source.detectedLanguage?.name
        let targetLanguage = languageName.map { "in \($0)" } ?? "in the same language as the source text"
        let instructions = """
        Summarize the following reading session \(targetLanguage). Keep the recap clear, concise, and useful for remembering what was read.
        Return plain prose only. Do not include a title, markdown, bullets, or labels.
        """

        let prompt = """
        Source word count: \(source.wordCount)
        Output word limit: \(outputWordLimit)

        Reading session text:
        \(source.text)
        """

        let logDescription = """
        Instructions:
        \(instructions)

        Prompt:
        Source word count: \(source.wordCount)
        Output word limit: \(outputWordLimit)
        Reading session text: [omitted \(source.cleanedTextLength) characters]
        """
            .replacingOccurrences(of: "\n", with: "\\n")

        return AIRecapPromptPayload(
            instructions: instructions,
            prompt: prompt,
            logDescription: logDescription
        )
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

    var availabilityDebugDescription: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            return [
                "availability=\(String(describing: model.availability))",
                "supportedLanguages=\(model.supportedLanguages.map(\.minimalIdentifier).sorted().joined(separator: ","))"
            ].joined(separator: " ")
        }
        #endif

        return "FoundationModelsUnavailable"
    }

    func supportsLanguage(_ code: String) -> Bool? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.supportsLocale(Locale(identifier: code))
        }
        #endif

        return nil
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
        let promptPayload = AIRecapPromptBuilder.makePrompt(for: source, outputWordLimit: outputWordLimit)
        let session = LanguageModelSession(instructions: promptPayload.instructions)
        let options = GenerationOptions(
            sampling: .greedy,
            temperature: nil,
            maximumResponseTokens: max(outputWordLimit * 2, 300)
        )
        let response = try await session.respond(to: promptPayload.prompt, options: options)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
