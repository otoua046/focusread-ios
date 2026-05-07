import Foundation
import Combine
import UIKit

struct WordLookupRequest: Identifiable, Equatable {
    let term: String

    var id: String { term }
}

struct WordParts: Equatable {
    let prefix: String
    let anchor: String
    let suffix: String
    let isAnchorEnabled: Bool
    let fullWord: String
}

struct CurrentLocationPreview: Equatable, Sendable {
    let title: String
    let subtitle: String
    let parts: [CurrentLocationPreviewPart]

    init(session: ReadingSession, currentSection: ReadingDocumentSection?) {
        title = "Current Location"

        let totalWordCount = session.tokens.count
        let wordNumber = totalWordCount == 0 ? 0 : min(session.currentIndex + 1, totalWordCount)
        let wordLocation = "Word \(wordNumber) of \(totalWordCount)"
        subtitle = Self.subtitle(
            for: session,
            currentSection: currentSection,
            wordLocation: wordLocation
        )
        parts = Self.previewParts(for: session)
    }

    private static func subtitle(
        for session: ReadingSession,
        currentSection: ReadingDocumentSection?,
        wordLocation: String
    ) -> String {
        let currentToken = session.currentToken

        switch session.document.sourceType {
        case .pdf, .image:
            guard let pageNumber = currentSection?.pageNumber ?? currentToken?.sourcePageNumber else {
                return wordLocation
            }
            return "Page \(pageNumber) · \(wordLocation)"
        case .epub:
            let chapterNumber = currentSection?.chapterNumber ?? currentToken?.sourceChapterNumber
            let chapterTitle = Self.trimmedNonEmpty(currentSection?.title)
                ?? Self.trimmedNonEmpty(currentToken?.sourceChapterTitle)
            let chapterLocation: String?

            if let chapterNumber, let chapterTitle {
                chapterLocation = "Chapter \(chapterNumber): \(chapterTitle)"
            } else if let chapterNumber {
                chapterLocation = "Chapter \(chapterNumber)"
            } else {
                chapterLocation = chapterTitle
            }

            guard let chapterLocation else {
                return wordLocation
            }
            return "\(chapterLocation) · \(wordLocation)"
        case .pastedText, .txt:
            return wordLocation
        }
    }

    private static func previewParts(for session: ReadingSession) -> [CurrentLocationPreviewPart] {
        guard !session.tokens.isEmpty,
              session.tokens.indices.contains(session.currentIndex) else {
            return []
        }

        let wordsBefore = 60
        let wordsAfter = 70
        let targetWordCount = wordsBefore + wordsAfter + 1
        let currentIndex = session.currentIndex

        var lowerBound = max(session.tokens.startIndex, currentIndex - wordsBefore)
        var upperBound = min(session.tokens.endIndex, currentIndex + wordsAfter + 1)

        let missingBefore = wordsBefore - (currentIndex - lowerBound)
        if missingBefore > 0 {
            upperBound = min(session.tokens.endIndex, upperBound + missingBefore)
        }

        let visibleWordCount = upperBound - lowerBound
        if visibleWordCount < targetWordCount {
            lowerBound = max(session.tokens.startIndex, lowerBound - (targetWordCount - visibleWordCount))
        }

        return session.tokens[lowerBound..<upperBound].enumerated().map { offset, token in
            let index = lowerBound + offset
            let role: CurrentLocationPreviewPart.Role
            if index < currentIndex {
                role = .read
            } else if index == currentIndex {
                role = .current
            } else {
                role = .unread
            }

            return CurrentLocationPreviewPart(
                text: token.rawText.isEmpty ? token.text : token.rawText,
                role: role
            )
        }
    }

    private static func trimmedNonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct CurrentLocationPreviewPart: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case read
        case current
        case unread
    }

    let text: String
    let role: Role
}

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var session: ReadingSession
    @Published private(set) var cleanupProgress: AICleanupProgress?
    @Published private(set) var structureProgress: DocumentStructureProgress?
    private let engine: RSVPReadingEngine
    private let tokenizer: TextTokenizer
    private let wordLookupService: WordLookupService
    private let cleanupService: SmartCleanupService
    private let structureAnalyzerService: DocumentStructureAnalyzerService
    private let readingHistoryStore: ReadingHistoryStore?
    private let readingStatsStore: ReadingStatsStore?
    private let dateProvider: () -> Date
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private var behaviorSettings: ReaderBehaviorSettings
    private var importedDocument: ImportedDocument?
    private var savedReadID: UUID?
    private var lastPersistedWordIndex: Int
    private var cleanupChunks: [DocumentCleanupChunk]
    private var structureState: DocumentStructureState = .empty
    private var structureProcessedChunkCount = 0
    private var structureSummariesByChunkID: [UUID: ChunkStructureSummary] = [:]
    private var structureLabelBySectionIndex: [Int: String] = [:]
    private var cleanupTask: Task<Void, Never>?
    private var readingStatsSessionStartedAt: Date?
    private var readingStatsSessionWordsRead = 0
    private var readingStatsSessionWeightedWPM = 0
    private var readingStatsSessionStartWordIndex: Int?
    private var readingStatsSessionEndWordIndex: Int?
    private var hasMarkedCurrentReadCompleted = false

    @Published var isPlaying = false
    @Published var controlsVisible = true
    @Published var lookupRequest: WordLookupRequest?
    @Published var noDefinitionFound = false

    init(
        session: ReadingSession,
        importedDocument: ImportedDocument? = nil,
        engine: RSVPReadingEngine = RSVPReadingEngine(),
        tokenizer: TextTokenizer = TextTokenizer(),
        wordLookupService: WordLookupService = WordLookupService(),
        cleanupService: SmartCleanupService = SmartCleanupService(),
        structureAnalyzerService: DocumentStructureAnalyzerService = DocumentStructureAnalyzerService(),
        readingHistoryStore: ReadingHistoryStore? = nil,
        readingStatsStore: ReadingStatsStore? = nil,
        savedReadID: UUID? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.engine = engine
        self.tokenizer = tokenizer
        self.wordLookupService = wordLookupService
        self.cleanupService = cleanupService
        self.structureAnalyzerService = structureAnalyzerService
        self.readingHistoryStore = readingHistoryStore
        self.readingStatsStore = readingStatsStore
        self.dateProvider = dateProvider
        self.behaviorSettings = Self.storedBehaviorSettings()
        self.importedDocument = importedDocument
        self.savedReadID = savedReadID
        self.lastPersistedWordIndex = session.currentIndex
        self.cleanupChunks = importedDocument?.cleanupChunks ?? []
        haptics.prepare()
        startBackgroundAICleanupIfNeeded()
    }

    var isTranslationAvailable: Bool {
        if #available(iOS 17.4, *) {
            return true
        }
        return false
    }

    var isTwoWordMode: Bool {
        behaviorSettings.displayMode == .twoWords
    }

    var currentWord: String {
        session.currentTokens.map(\.text).joined(separator: " ")
    }

    var currentWordForTranslation: String {
        Self.cleanedTranslateWord(from: currentWord)
    }

    var currentWordParts: WordParts? {
        guard behaviorSettings.displayMode == .oneWord,
              behaviorSettings.anchorLetterEnabled,
              let token = session.currentToken else {
            return nil
        }
        
        return parts(for: token.text)
    }

    var currentAttributedWord: AttributedString {
        let tokens = session.currentTokens
        guard !tokens.isEmpty else { return AttributedString("") }
        
        if behaviorSettings.displayMode == .oneWord {
            return attributedString(for: tokens[0].text)
        } else {
            var result = AttributedString("")
            for (index, token) in tokens.enumerated() {
                if index > 0 {
                    result.append(AttributedString(" "))
                }
                result.append(attributedString(for: token.text))
            }
            return result
        }
    }

    private func attributedString(for text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard behaviorSettings.anchorLetterEnabled else { return attributed }
        
        if let offset = anchorGlobalOffset(for: text),
           let attrIndex = AttributedString.Index(text.index(text.startIndex, offsetBy: offset), within: attributed) {
            let nextIndex = attributed.index(afterCharacter: attrIndex)
            attributed[attrIndex..<nextIndex].foregroundColor = AppTheme.orpHighlight
        }
        return attributed
    }

    private func parts(for text: String) -> WordParts {
        let offset = anchorGlobalOffset(for: text) ?? 0
        let anchorIndex = text.index(text.startIndex, offsetBy: offset)
        let nextIndex = text.index(after: anchorIndex)
        
        return WordParts(
            prefix: String(text[..<anchorIndex]),
            anchor: String(text[anchorIndex..<nextIndex]),
            suffix: String(text[nextIndex...]),
            isAnchorEnabled: true,
            fullWord: text
        )
    }

    private func anchorGlobalOffset(for text: String) -> Int? {
        let characters = Array(text)
        guard let contentStartOffset = characters.firstIndex(where: Self.isAlphanumeric),
              let contentEndInclusiveOffset = characters.indices.reversed().first(where: { Self.isAlphanumeric(characters[$0]) }) else {
            return nil
        }

        let contentEndOffset = contentEndInclusiveOffset + 1
        let length = contentEndOffset - contentStartOffset
        let anchorOffset: Int
        switch length {
        case 0...2:
            anchorOffset = 0
        case 3...4:
            anchorOffset = 1
        case 5...6:
            anchorOffset = 1
        case 7...9:
            anchorOffset = 2
        default:
            anchorOffset = Int(floor(Double(length) * 0.35))
        }
        
        return contentStartOffset + anchorOffset
    }

    private static func isAlphanumeric(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func cleanedTranslateWord(from text: String) -> String {
        let edgeCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",.-–—"))
        return text.trimmingCharacters(in: edgeCharacters)
    }

    var sanitizedCurrentWordForLookup: String? {
        guard let firstToken = session.currentTokens.first else { return nil }
        return wordLookupService.sanitizedTerm(from: firstToken.text)
    }

    var wordsPerMinute: Int {
        get { session.wordsPerMinute }
        set { setWPM(newValue, haptic: false) }
    }

    var progress: Double {
        session.progress
    }

    var progressLabel: String {
        "Word \(currentWordNumber)/\(session.tokens.count)"
    }

    var currentLocationPreview: CurrentLocationPreview {
        CurrentLocationPreview(
            session: session,
            currentSection: currentSectionMetadata
        )
    }

    var searchableTokens: [ReadingToken] {
        session.tokens
    }

    var locationIndicatorTitle: String {
        switch session.document.sourceType {
        case .pastedText:
            return "Pasted Text"
        case .txt:
            if let structureTitle = currentStructureLocationTitle {
                return structureTitle
            }
            return session.document.fileName ?? session.document.title
        case .pdf:
            if let structureTitle = currentStructureLocationTitle {
                return "\(session.document.fileName ?? session.document.title): \(structureTitle)"
            }
            return "\(session.document.fileName ?? session.document.title): Page \(currentSectionNumber)"
        case .image:
            return "\(session.document.fileName ?? session.document.title): Page \(currentSectionNumber)"
        case .epub:
            let location = currentEPUBLocationTitle ?? "\(currentEPUBSectionKind) \(currentSectionNumber)"
            return "\(session.document.fileName ?? session.document.title): \(location)"
        }
    }

    var sectionNavigationAvailable: Bool {
        switch session.document.sourceType {
        case .pdf, .epub, .image:
            return session.document.sections.count > 1
        case .pastedText, .txt:
            return false
        }
    }

    var currentSectionMetadata: ReadingDocumentSection? {
        guard let index = session.currentToken?.sourceSectionIndex else {
            return nil
        }

        return session.document.sections.first { $0.index == index }
    }

    var canJumpToPreviousSection: Bool {
        guard sectionNavigationAvailable,
              let currentIndex = currentSectionMetadata?.index else {
            return false
        }

        return readableSectionIndex(before: currentIndex) != nil
    }

    var canJumpToNextSection: Bool {
        guard sectionNavigationAvailable,
              let currentIndex = currentSectionMetadata?.index else {
            return false
        }

        return readableSectionIndex(after: currentIndex) != nil
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !session.tokens.isEmpty else { return }
        guard !isPlaying else { return }
        if session.isAtEnd {
            session.currentIndex = 0
            hasMarkedCurrentReadCompleted = false
        }
        beginReadingStatsSessionIfNeeded()
        isPlaying = true
        controlsVisible = false
        triggerHaptic(intensity: 0.75)

        Task { [weak self, engine] in
            await engine.start(
                sessionProvider: { [weak self] in
                    self?.session ?? ReadingSession(tokens: [])
                },
                behaviorProvider: { [weak self] in
                    self?.behaviorSettings ?? .default
                },
                advance: { [weak self] in
                    guard let self else { return false }
                    return self.advanceFromEngine()
                }
            )
        }
    }

    func pause(showControls: Bool = true) {
        guard isPlaying else {
            controlsVisible = showControls
            return
        }
        finishReadingStatsSession()
        isPlaying = false
        controlsVisible = showControls
        triggerHaptic(intensity: 0.55)
        Task { [engine] in await engine.stop() }
    }

    func rewindWord() {
        pause(showControls: true)
        withAnimationStateChange {
            session.rewindWord()
        }
        persistProgress(force: true)
        triggerHaptic(intensity: 0.45)
    }

    func skipWord() {
        pause(showControls: true)
        withAnimationStateChange {
            session.skipWord()
        }
        persistProgress(force: true)
        triggerHaptic(intensity: 0.35)
    }

    func rewindSentence() {
        pause(showControls: true)
        withAnimationStateChange {
            session.rewindSentence()
        }
        persistProgress(force: true)
        triggerHaptic(intensity: 0.7)
    }

    func jumpToPreviousSection() {
        guard let currentIndex = currentSectionMetadata?.index,
              let targetIndex = readableSectionIndex(before: currentIndex) else {
            return
        }

        jumpToSection(index: targetIndex)
    }

    func jumpToNextSection() {
        guard let currentIndex = currentSectionMetadata?.index,
              let targetIndex = readableSectionIndex(after: currentIndex) else {
            return
        }

        jumpToSection(index: targetIndex)
    }

    func jumpToSection(index: Int) {
        guard let targetTokenIndex = firstReadableTokenIndex(in: index)
                ?? readableSectionIndex(after: index).flatMap({ firstReadableTokenIndex(in: $0) })
                ?? readableSectionIndex(before: index).flatMap({ firstReadableTokenIndex(in: $0) }) else {
            return
        }

        pause(showControls: true)
        withAnimationStateChange {
            session.currentIndex = targetTokenIndex
        }
        persistProgress(force: true)
        triggerHaptic(intensity: 0.6)
    }

    func canJumpToWordIndex(_ index: Int) -> Bool {
        session.tokens.indices.contains(index)
    }

    func jumpToWordIndex(_ index: Int) {
        guard canJumpToWordIndex(index) else {
            return
        }

        jumpToTokenIndex(index)
    }

    func adjustSpeed(by delta: Int) {
        setWPM(session.wordsPerMinute + delta, haptic: true)
    }

    func setWPM(_ value: Int, haptic: Bool = true) {
        let previous = session.wordsPerMinute
        session.setWPM(value)
        if haptic, previous != session.wordsPerMinute {
            triggerHaptic(intensity: 0.35)
        }
    }

    func revealControls() {
        controlsVisible = true
    }

    func prepareForSearchNavigation() {
        pause(showControls: true)
        triggerHaptic(intensity: 0.45)
    }

    func updateBehaviorSettings(_ settings: ReaderBehaviorSettings) {
        behaviorSettings = settings
        session.stepSize = settings.displayMode == .twoWords ? 2 : 1
    }

    func lookupCurrentWord() {
        pause(showControls: true)

        guard let term = sanitizedCurrentWordForLookup,
              wordLookupService.hasDefinition(for: term) else {
            lookupRequest = nil
            noDefinitionFound = true
            return
        }

        lookupRequest = WordLookupRequest(term: term)
    }

    func cleanup() {
        finishReadingStatsSession()
        isPlaying = false
        persistProgress(force: true, durability: .immediate)
        cleanupTask?.cancel()
        cleanupTask = nil
        Task { [engine] in await engine.stop() }
    }

    func prepareForInactiveScene() {
        if isPlaying {
            finishReadingStatsSession()
            isPlaying = false
            controlsVisible = true
            Task { [engine] in await engine.stop() }
        }
        persistProgress(force: true, durability: .immediate)
    }

    func persistProgress(
        force: Bool = false,
        durability: ReadingHistoryPersistenceDurability = .normal
    ) {
        guard let readingHistoryStore,
              let savedReadID,
              var read = readingHistoryStore.read(withID: savedReadID) else {
            return
        }

        let movedEnough = abs(session.currentIndex - lastPersistedWordIndex) >= 25
        guard force || movedEnough || session.isAtEnd else { return }

        read = SavedReadMapper.updating(read, from: session)
        if let importedDocument {
            read.sections = SavedReadMapper.savedSections(from: importedDocument)
        }
        readingHistoryStore.save(read, durability: durability)
        lastPersistedWordIndex = session.currentIndex

        if session.isAtEnd {
            markReadCompletedForStatsIfNeeded()
        }
    }

    private func startBackgroundAICleanupIfNeeded() {
        guard importedDocument?.cleanupMode == .ai,
              SmartCleanupAvailability.isAICleanupAvailable,
              !cleanupChunks.isEmpty else {
            return
        }

        cleanupProgress = AICleanupProgress(processedChunkCount: 0, totalChunkCount: cleanupChunks.count, isProcessing: true)
        let chunks = cleanupChunks

        cleanupTask = Task { [weak self, cleanupService, structureAnalyzerService] in
            for chunk in chunks {
                guard !Task.isCancelled else { return }

                let shouldContinue = await MainActor.run {
                    guard let self else { return false }
                    self.markCleanupChunk(chunk.id, status: .processing)
                    self.markStructureAnalysisStartedIfNeeded()
                    return true
                }
                guard shouldContinue else {
                    return
                }

                let modelText = await cleanupService.foundationModelTextCleanup(for: chunk.smartCleanedText)
                guard !Task.isCancelled else { return }

                let validatedText: String?
                if let modelText,
                   SmartCleanupService.isSafeTextCleanup(original: chunk.smartCleanedText, cleaned: modelText),
                   (chunk.sectionIndices.count == 1 || SmartCleanupService.pdfSectionTexts(from: modelText, sectionIndices: chunk.sectionIndices) != nil) {
                    validatedText = modelText
                } else {
                    validatedText = nil
                }

                await MainActor.run {
                    self?.finishCleanupChunk(chunk.id, aiCleanedText: validatedText)
                }

                let structureContext = await MainActor.run { () -> (DocumentStructureState, [String])? in
                    guard let self else { return nil }
                    return (
                        self.structureState,
                        structureAnalyzerService.deterministicHeadingCandidates(for: chunk, in: self.importedDocument)
                    )
                }
                guard !Task.isCancelled, let structureContext else { return }

                let structureSummary = await structureAnalyzerService.analyze(
                    chunk: chunk,
                    structureState: structureContext.0,
                    nearbyHeadingCandidates: structureContext.1
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self?.finishStructureAnalysis(for: chunk, summary: structureSummary)
                }
            }

            await MainActor.run {
                self?.cleanupProgress = self?.cleanupProgress?.finished()
                self?.structureProgress = self?.structureProgress?.finished()
                self?.cleanupTask = nil
            }
        }
    }

    private func markCleanupChunk(_ id: UUID, status: DocumentCleanupChunkStatus) {
        guard let index = cleanupChunks.firstIndex(where: { $0.id == id }) else { return }
        cleanupChunks[index].status = status
        updateCleanupProgress()
    }

    private func finishCleanupChunk(_ id: UUID, aiCleanedText: String?) {
        guard let index = cleanupChunks.firstIndex(where: { $0.id == id }) else { return }

        cleanupChunks[index].aiCleanedText = aiCleanedText
        cleanupChunks[index].status = aiCleanedText == nil ? .failed : .completed

        if aiCleanedText != nil {
            applyCompletedCleanupChunk(cleanupChunks[index])
        }

        updateCleanupProgress()
    }

    private func applyCompletedCleanupChunk(_ chunk: DocumentCleanupChunk) {
        guard let importedDocument else { return }

        let currentLocation = currentTokenLocation()
        var sections = importedDocument.sections

        if chunk.sectionIndices.count > 1 {
            guard let aiCleanedText = chunk.aiCleanedText,
                  let sectionTexts = SmartCleanupService.pdfSectionTexts(from: aiCleanedText, sectionIndices: chunk.sectionIndices) else {
                return
            }

            for (sectionIndex, text) in sectionTexts {
                guard let index = sections.firstIndex(where: { $0.index == sectionIndex }) else { continue }
                sections[index] = sections[index].withText(text)
            }
        } else {
            let sectionIndex = chunk.sectionIndex
            guard let index = sections.firstIndex(where: { $0.index == sectionIndex }) else { return }
            let sectionChunks = cleanupChunks
                .filter { $0.sectionIndices == [sectionIndex] }
                .sorted { $0.wordRange.lowerBound < $1.wordRange.lowerBound }

            let sectionText = sectionChunks
                .map { $0.effectiveText.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            sections[index] = sections[index].withText(sectionText)
        }

        let updatedDocument = ImportedDocument(
            fileName: importedDocument.fileName,
            displayTitle: importedDocument.displayTitle,
            author: importedDocument.author,
            sourceType: importedDocument.sourceType,
            sections: sections,
            cleanupMode: importedDocument.cleanupMode,
            cleanupChunks: cleanupChunks
        )
        self.importedDocument = updatedDocument

        let newTokens = tokenizer.tokenize(updatedDocument)
        guard !newTokens.isEmpty else { return }

        session.tokens = newTokens
        session.document = ReadingDocument(importedDocument: updatedDocument)
        session.currentIndex = tokenIndex(matching: currentLocation, in: newTokens)
    }

    private func updateCleanupProgress() {
        guard !cleanupChunks.isEmpty else {
            cleanupProgress = nil
            return
        }

        let processed = cleanupChunks.filter { $0.status == .completed || $0.status == .failed }.count
        cleanupProgress = AICleanupProgress(
            processedChunkCount: processed,
            totalChunkCount: cleanupChunks.count,
            isProcessing: processed < cleanupChunks.count
        )
    }

    private func markStructureAnalysisStartedIfNeeded() {
        guard importedDocument?.cleanupMode == .ai,
              SmartCleanupAvailability.isAICleanupAvailable,
              !cleanupChunks.isEmpty,
              structureProgress == nil else {
            return
        }

        structureProgress = DocumentStructureProgress(
            processedChunkCount: structureProcessedChunkCount,
            totalChunkCount: cleanupChunks.count,
            isProcessing: true
        )
    }

    private func finishStructureAnalysis(for chunk: DocumentCleanupChunk, summary: ChunkStructureSummary?) {
        structureProcessedChunkCount += 1

        if let summary {
            structureSummariesByChunkID[chunk.id] = summary
            structureState = structureAnalyzerService.updatedState(
                byApplying: summary,
                to: structureState,
                chunk: chunk
            )
            applyStructureLabel(from: summary, chunk: chunk)
        }

        updateStructureProgress()
    }

    private func updateStructureProgress() {
        guard !cleanupChunks.isEmpty else {
            structureProgress = nil
            return
        }

        structureProgress = DocumentStructureProgress(
            processedChunkCount: min(structureProcessedChunkCount, cleanupChunks.count),
            totalChunkCount: cleanupChunks.count,
            isProcessing: structureProcessedChunkCount < cleanupChunks.count
        )
    }

    private func applyStructureLabel(from summary: ChunkStructureSummary, chunk: DocumentCleanupChunk) {
        guard let label = structureAnalyzerService.acceptedLabel(from: summary) else {
            return
        }

        for sectionIndex in chunk.sectionIndices {
            structureLabelBySectionIndex[sectionIndex] = label
        }
    }

    private func advanceFromEngine() -> Bool {
        guard isPlaying else { return false }
        recordCurrentWordReadForStats()

        let willBeAtEnd = session.currentIndex + session.stepSize >= session.tokens.count

        if session.isAtEnd {
            isPlaying = false
            controlsVisible = true
            persistProgress(force: true)
            finishReadingStatsSession()
            return false
        }

        session.advance()
        persistProgress()

        if willBeAtEnd {
            isPlaying = false
            controlsVisible = true
            persistProgress(force: true)
            finishReadingStatsSession()
            return false
        }

        return true
    }
    private func withAnimationStateChange(_ change: () -> Void) {
        change()
    }

    private func jumpToTokenIndex(_ index: Int) {
        pause(showControls: true)
        withAnimationStateChange {
            session.currentIndex = index
        }
        persistProgress(force: true)
        triggerHaptic(intensity: 0.6)
    }

    private var currentWordNumber: Int {
        guard !session.tokens.isEmpty else { return 0 }
        return min(session.currentIndex + session.stepSize, session.tokens.count)
    }

    private func currentTokenLocation() -> TokenLocation? {
        guard session.tokens.indices.contains(session.currentIndex) else {
            return nil
        }

        let token = session.tokens[session.currentIndex]
        guard let sectionIndex = token.sourceSectionIndex else {
            return nil
        }

        let sectionOffset = session.tokens[..<session.currentIndex]
            .filter { $0.sourceSectionIndex == sectionIndex }
            .count

        return TokenLocation(sectionIndex: sectionIndex, wordOffsetInSection: sectionOffset)
    }

    private func tokenIndex(matching location: TokenLocation?, in tokens: [ReadingToken]) -> Int {
        guard let location else {
            return min(session.currentIndex, max(tokens.count - 1, 0))
        }

        let sectionTokenIndices = tokens.indices.filter { tokens[$0].sourceSectionIndex == location.sectionIndex }
        guard !sectionTokenIndices.isEmpty else {
            return min(session.currentIndex, max(tokens.count - 1, 0))
        }

        let offset = min(location.wordOffsetInSection, sectionTokenIndices.count - 1)
        return sectionTokenIndices[offset]
    }

    private var currentSectionNumber: Int {
        switch session.document.sourceType {
        case .pdf, .image:
            currentSectionMetadata?.pageNumber ?? session.currentToken?.sourcePageNumber ?? 1
        case .epub:
            currentSectionMetadata?.chapterNumber ?? session.currentToken?.sourceChapterNumber ?? 1
        case .pastedText, .txt:
            1
        }
    }

    private var currentEPUBLocationTitle: String? {
        guard let title = currentSectionMetadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              title.count <= 80 else {
            if let structureTitle = currentStructureLocationTitle {
                return structureTitle
            }
            return nil
        }

        return title
    }

    private var currentEPUBSectionKind: String {
        switch currentSectionMetadata?.epubSectionRole {
        case .chapter:
            return "Chapter"
        case .part:
            return "Part"
        case .frontMatter, .backMatter, .appendix, .reference, .body, nil:
            return "Section"
        }
    }

    private var currentStructureLocationTitle: String? {
        guard let chunk = currentCleanupChunk,
              let summary = structureSummariesByChunkID[chunk.id],
              let label = structureAnalyzerService.acceptedLabel(from: summary) else {
            if let sectionIndex = currentSectionMetadata?.index {
                return structureLabelBySectionIndex[sectionIndex]
            }
            return nil
        }

        if let chapterNumber = chunk.chapterNumber {
            return "Chapter \(chapterNumber): \(label)"
        }

        if let pageRange = chunk.sourcePageRange {
            if pageRange.lowerBound == pageRange.upperBound {
                return "Page \(pageRange.lowerBound): \(label)"
            }
            return "Pages \(pageRange.lowerBound)-\(pageRange.upperBound): \(label)"
        }

        return label
    }

    private var currentCleanupChunk: DocumentCleanupChunk? {
        guard let token = session.currentToken else {
            return nil
        }

        if let chunk = cleanupChunks.first(where: { $0.wordRange.contains(token.globalWordIndex) }) {
            return chunk
        }

        guard let sectionIndex = token.sourceSectionIndex else {
            return nil
        }

        return cleanupChunks.first { $0.sectionIndices.contains(sectionIndex) }
    }

    private func firstReadableTokenIndex(in sectionIndex: Int) -> Int? {
        session.tokens.firstIndex { $0.sourceSectionIndex == sectionIndex }
    }

    private func sectionHasReadableTokens(_ sectionIndex: Int) -> Bool {
        firstReadableTokenIndex(in: sectionIndex) != nil
    }

    private func readableSectionIndex(before sectionIndex: Int) -> Int? {
        session.document.sections
            .map(\.index)
            .filter { $0 < sectionIndex }
            .reversed()
            .first { sectionHasReadableTokens($0) }
    }

    private func readableSectionIndex(after sectionIndex: Int) -> Int? {
        session.document.sections
            .map(\.index)
            .filter { $0 > sectionIndex }
            .first { sectionHasReadableTokens($0) }
    }

    private func triggerHaptic(intensity: CGFloat) {
        guard UserDefaults.standard.object(forKey: ReaderBehaviorSettingsKey.hapticsEnabled) as? Bool ?? true else {
            return
        }
        haptics.impactOccurred(intensity: intensity)
        haptics.prepare()
    }

    private func beginReadingStatsSessionIfNeeded() {
        guard savedReadID != nil else { return }
        guard readingStatsSessionStartedAt == nil else { return }

        readingStatsSessionStartedAt = dateProvider()
        readingStatsSessionWordsRead = 0
        readingStatsSessionWeightedWPM = 0
        readingStatsSessionStartWordIndex = nil
        readingStatsSessionEndWordIndex = nil
    }

    private func recordCurrentWordReadForStats() {
        guard readingStatsSessionStartedAt != nil else { return }

        let wordsInStep = session.currentTokens.count
        guard wordsInStep > 0 else { return }

        let sourceStart = session.currentIndex
        let sourceEnd = min(session.currentIndex + wordsInStep, session.tokens.count)
        readingStatsSessionStartWordIndex = min(readingStatsSessionStartWordIndex ?? sourceStart, sourceStart)
        readingStatsSessionEndWordIndex = max(readingStatsSessionEndWordIndex ?? sourceEnd, sourceEnd)

        readingStatsSessionWordsRead += wordsInStep
        readingStatsSessionWeightedWPM += session.wordsPerMinute * wordsInStep
    }

    private func finishReadingStatsSession() {
        guard let readID = savedReadID,
              let startedAt = readingStatsSessionStartedAt else {
            resetReadingStatsSession()
            return
        }

        let endedAt = max(dateProvider(), startedAt)
        let wordsRead = readingStatsSessionWordsRead
        let averageWPM = wordsRead > 0
            ? Int((Double(readingStatsSessionWeightedWPM) / Double(wordsRead)).rounded())
            : session.wordsPerMinute
        resetReadingStatsSession()

        guard wordsRead > 0 else { return }

        let event = ReadingSessionEvent(
            readID: readID,
            startedAt: startedAt,
            endedAt: endedAt,
            wordsRead: wordsRead,
            averageWPM: averageWPM,
            sourceStartWordIndex: readingStatsSessionStartWordIndex,
            sourceEndWordIndex: readingStatsSessionEndWordIndex
        )
        readingStatsStore?.record(event)
        addReadingTimeToSavedRead(event.readingSeconds)
    }

    private func resetReadingStatsSession() {
        readingStatsSessionStartedAt = nil
        readingStatsSessionWordsRead = 0
        readingStatsSessionWeightedWPM = 0
        readingStatsSessionStartWordIndex = nil
        readingStatsSessionEndWordIndex = nil
    }

    private func addReadingTimeToSavedRead(_ seconds: TimeInterval) {
        guard seconds > 0,
              let readingHistoryStore,
              let savedReadID,
              var read = readingHistoryStore.read(withID: savedReadID) else {
            return
        }

        read.readingStats.totalTimeRead += seconds
        read.updatedAt = dateProvider()
        readingHistoryStore.save(read)
    }

    private func markReadCompletedForStatsIfNeeded() {
        guard !hasMarkedCurrentReadCompleted,
              let savedReadID else {
            return
        }

        hasMarkedCurrentReadCompleted = true
        readingStatsStore?.markReadCompleted(readID: savedReadID, completedAt: dateProvider())
    }

    private static func storedBehaviorSettings() -> ReaderBehaviorSettings {
        let defaults = UserDefaults.standard
        let punctuationPauses = defaults.object(forKey: ReaderBehaviorSettingsKey.punctuationPausesEnabled) as? Bool ?? true
        let rawLongWordMode = defaults.string(forKey: ReaderBehaviorSettingsKey.longWordDelayMode) ?? LongWordDelayMode.moderate.rawValue
        let anchorLetterEnabled = defaults.object(forKey: ReaderBehaviorSettingsKey.anchorLetterEnabled) as? Bool ?? true
        let rawDisplayMode = defaults.string(forKey: ReaderBehaviorSettingsKey.displayMode) ?? ReaderDisplayMode.oneWord.rawValue

        return ReaderBehaviorSettings(
            punctuationPausesEnabled: punctuationPauses,
            longWordDelayMode: LongWordDelayMode(rawValue: rawLongWordMode) ?? .moderate,
            anchorLetterEnabled: anchorLetterEnabled,
            displayMode: ReaderDisplayMode(rawValue: rawDisplayMode) ?? .oneWord
        )
    }
}

struct AICleanupProgress: Equatable, Sendable {
    let processedChunkCount: Int
    let totalChunkCount: Int
    let isProcessing: Bool

    func finished() -> AICleanupProgress {
        AICleanupProgress(
            processedChunkCount: totalChunkCount,
            totalChunkCount: totalChunkCount,
            isProcessing: false
        )
    }
}

struct DocumentStructureProgress: Equatable, Sendable {
    let processedChunkCount: Int
    let totalChunkCount: Int
    let isProcessing: Bool

    func finished() -> DocumentStructureProgress {
        DocumentStructureProgress(
            processedChunkCount: totalChunkCount,
            totalChunkCount: totalChunkCount,
            isProcessing: false
        )
    }
}

private struct TokenLocation {
    let sectionIndex: Int
    let wordOffsetInSection: Int
}

private extension ImportedDocumentSection {
    func withText(_ text: String) -> ImportedDocumentSection {
        ImportedDocumentSection(
            index: index,
            text: text,
            pageNumber: pageNumber,
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            wordRange: wordRange,
            epubNavigationLevel: epubNavigationLevel,
            epubSectionRole: epubSectionRole,
            epubStructureSource: epubStructureSource,
            epubStructureConfidence: epubStructureConfidence
        )
    }
}
