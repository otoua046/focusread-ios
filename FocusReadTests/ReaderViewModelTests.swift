import XCTest
@testable import FocusRead

final class ReaderViewModelTests: XCTestCase {
    @MainActor
    func testLookupCurrentWordUsesSanitizedVisibleWord() {
        let probe = DefinitionProbe(definedTerms: ["that"])
        let viewModel = ReaderViewModel(
            session: ReadingSession(tokens: [Self.token("that.")]),
            wordLookupService: probe.service()
        )
        
        viewModel.lookupCurrentWord()
        
        XCTAssertEqual(probe.requestedTerms, ["that"])
        XCTAssertEqual(viewModel.lookupRequest?.term, "that")
        XCTAssertFalse(viewModel.noDefinitionFound)
    }

    @MainActor
    func testLookupCurrentWordPassesCommonVisibleWord() {
        let probe = DefinitionProbe(definedTerms: ["expected"])
        let viewModel = ReaderViewModel(
            session: ReadingSession(tokens: [Self.token("expected")]),
            wordLookupService: probe.service()
        )

        viewModel.lookupCurrentWord()

        XCTAssertEqual(probe.requestedTerms, ["expected"])
        XCTAssertEqual(viewModel.lookupRequest?.term, "expected")
    }

    @MainActor
    func testLookupCurrentWordDoesNotMutateCurrentIndex() {
        let probe = DefinitionProbe(definedTerms: ["time"])
        let tokens = [
            Self.token("before", id: 0),
            Self.token("time,", id: 1),
            Self.token("after", id: 2)
        ]
        let viewModel = ReaderViewModel(
            session: ReadingSession(tokens: tokens, currentIndex: 1),
            wordLookupService: probe.service()
        )
        viewModel.isPlaying = true

        viewModel.lookupCurrentWord()

        XCTAssertEqual(viewModel.session.currentIndex, 1)
        XCTAssertEqual(viewModel.currentWord, "time,")
        XCTAssertEqual(probe.requestedTerms, ["time"])
        XCTAssertEqual(viewModel.lookupRequest?.term, "time")
    }
    
    @MainActor
    func testLookupCurrentWordPausesReader() {
        let probe = DefinitionProbe(definedTerms: ["word"])
        let session = ReadingSession(tokens: [Self.token("word")])
        let viewModel = ReaderViewModel(session: session, wordLookupService: probe.service())
        viewModel.isPlaying = true
        
        viewModel.lookupCurrentWord()
        
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertTrue(viewModel.controlsVisible)
    }

    @MainActor
    func testLookupCurrentWordShowsNoDefinitionForUnknownWord() {
        let probe = DefinitionProbe(definedTerms: [])
        let viewModel = ReaderViewModel(
            session: ReadingSession(tokens: [Self.token("notarealword")]),
            wordLookupService: probe.service()
        )

        viewModel.lookupCurrentWord()

        XCTAssertEqual(probe.requestedTerms, ["notarealword"])
        XCTAssertNil(viewModel.lookupRequest)
        XCTAssertTrue(viewModel.noDefinitionFound)
    }

    @MainActor
    func testCurrentWordForTranslationStripsEdgeCommasDotsAndDashes() {
        XCTAssertEqual(
            ReaderViewModel(session: ReadingSession(tokens: [Self.token("word,")])).currentWordForTranslation,
            "word"
        )
        XCTAssertEqual(
            ReaderViewModel(session: ReadingSession(tokens: [Self.token("word.")])).currentWordForTranslation,
            "word"
        )
        XCTAssertEqual(
            ReaderViewModel(session: ReadingSession(tokens: [Self.token("-word")])).currentWordForTranslation,
            "word"
        )
        XCTAssertEqual(
            ReaderViewModel(session: ReadingSession(tokens: [Self.token("word-")])).currentWordForTranslation,
            "word"
        )
        XCTAssertEqual(
            ReaderViewModel(session: ReadingSession(tokens: [Self.token("—word—")])).currentWordForTranslation,
            "word"
        )
    }

    @MainActor
    func testCurrentWordForTranslationPreservesNormalWordsAndInternalPunctuation() {
        XCTAssertEqual(
            ReaderViewModel(session: ReadingSession(tokens: [Self.token("word")])).currentWordForTranslation,
            "word"
        )
        XCTAssertEqual(
            ReaderViewModel(session: ReadingSession(tokens: [Self.token("well-being")])).currentWordForTranslation,
            "well-being"
        )
    }

    @MainActor
    func testCurrentWordForTranslationDoesNotMutateReaderDisplayText() {
        let viewModel = ReaderViewModel(session: ReadingSession(tokens: [Self.token("-word,")]))

        XCTAssertEqual(viewModel.currentWordForTranslation, "word")
        XCTAssertEqual(viewModel.currentWord, "-word,")
    }

    @MainActor
    func testCurrentWordPartsKeepsAnchorInsidePunctuation() {
        let viewModel = ReaderViewModel(session: ReadingSession(tokens: [Self.token("\"word,\"")]))
        viewModel.updateBehaviorSettings(.default)

        XCTAssertEqual(viewModel.currentWordParts?.prefix, "\"w")
        XCTAssertEqual(viewModel.currentWordParts?.anchor, "o")
        XCTAssertEqual(viewModel.currentWordParts?.suffix, "rd,\"")
    }

    @MainActor
    func testCurrentWordPartsUsesCharacterOffsetsForComposedText() {
        let viewModel = ReaderViewModel(session: ReadingSession(tokens: [Self.token("👩‍💻word")]))
        viewModel.updateBehaviorSettings(.default)

        XCTAssertEqual(viewModel.currentWordParts?.prefix, "👩‍💻w")
        XCTAssertEqual(viewModel.currentWordParts?.anchor, "o")
        XCTAssertEqual(viewModel.currentWordParts?.suffix, "rd")
    }

    @MainActor
    func testCurrentLocationPreviewBuildsTXTSnippetWithoutMutatingPosition() {
        let tokens = Self.tokens(count: 160)
        let session = ReadingSession(
            tokens: tokens,
            document: ReadingDocument(
                title: "Sample",
                fileName: "sample.txt",
                sourceType: .txt,
                sections: [
                    ReadingDocumentSection(index: 0, title: nil, pageNumber: nil, chapterNumber: nil, wordRange: nil)
                ]
            ),
            currentIndex: 75
        )
        let viewModel = ReaderViewModel(session: session)

        let preview = viewModel.currentLocationPreview

        XCTAssertEqual(preview.title, "Current Location")
        XCTAssertEqual(preview.subtitle, "Word 76 of 160")
        XCTAssertEqual(preview.parts.count, 131)
        XCTAssertEqual(preview.parts[0], CurrentLocationPreviewPart(text: "word15", role: .read))
        XCTAssertEqual(preview.parts[60], CurrentLocationPreviewPart(text: "word75", role: .current))
        XCTAssertEqual(preview.parts[130], CurrentLocationPreviewPart(text: "word145", role: .unread))
        XCTAssertEqual(viewModel.session.currentIndex, 75)
    }

    @MainActor
    func testCurrentLocationPreviewAdjustsAtFirstAndLastWord() {
        let tokens = Self.tokens(count: 10)

        let firstWordPreview = ReaderViewModel(
            session: ReadingSession(tokens: tokens, currentIndex: 0)
        ).currentLocationPreview
        XCTAssertEqual(firstWordPreview.subtitle, "Word 1 of 10")
        XCTAssertEqual(firstWordPreview.parts.count, 10)
        XCTAssertEqual(firstWordPreview.parts.first?.role, .current)
        XCTAssertEqual(firstWordPreview.parts.dropFirst().map(\.role), Array(repeating: .unread, count: 9))

        let lastWordPreview = ReaderViewModel(
            session: ReadingSession(tokens: tokens, currentIndex: 9)
        ).currentLocationPreview
        XCTAssertEqual(lastWordPreview.subtitle, "Word 10 of 10")
        XCTAssertEqual(lastWordPreview.parts.count, 10)
        XCTAssertEqual(lastWordPreview.parts.last?.role, .current)
        XCTAssertEqual(lastWordPreview.parts.dropLast().map(\.role), Array(repeating: .read, count: 9))
    }

    @MainActor
    func testCurrentLocationPreviewUsesPDFPageLocation() {
        let tokens = (0..<10).map { index in
            Self.token(
                "word\(index)",
                id: index,
                pageNumber: index < 3 ? 1 : 2,
                sourceSectionIndex: index < 3 ? 0 : 1
            )
        }
        let document = ReadingDocument(
            title: "PDF",
            fileName: "sample.pdf",
            sourceType: .pdf,
            sections: [
                ReadingDocumentSection(index: 0, title: nil, pageNumber: 1, chapterNumber: nil, wordRange: nil),
                ReadingDocumentSection(index: 1, title: nil, pageNumber: 2, chapterNumber: nil, wordRange: nil)
            ]
        )
        let viewModel = ReaderViewModel(session: ReadingSession(tokens: tokens, document: document, currentIndex: 3))

        XCTAssertEqual(viewModel.currentLocationPreview.subtitle, "Page 2 · Word 4 of 10")
    }

    @MainActor
    func testCurrentLocationPreviewUsesEPUBChapterLocation() {
        let tokens = [
            Self.token("before", id: 0, chapterNumber: 1, chapterTitle: "Opening", sourceSectionIndex: 0),
            Self.token("current", id: 1, chapterNumber: 2, chapterTitle: "A Clean Door", sourceSectionIndex: 1),
            Self.token("after", id: 2, chapterNumber: 2, chapterTitle: "A Clean Door", sourceSectionIndex: 1)
        ]
        let document = ReadingDocument(
            title: "Book",
            fileName: "book.epub",
            sourceType: .epub,
            sections: [
                ReadingDocumentSection(index: 0, title: "Opening", pageNumber: nil, chapterNumber: 1, wordRange: nil, epubSectionRole: .chapter),
                ReadingDocumentSection(index: 1, title: "A Clean Door", pageNumber: nil, chapterNumber: 2, wordRange: nil, epubSectionRole: .chapter)
            ]
        )
        let viewModel = ReaderViewModel(session: ReadingSession(tokens: tokens, document: document, currentIndex: 1))

        XCTAssertEqual(viewModel.currentLocationPreview.subtitle, "Chapter 2: A Clean Door · Word 2 of 3")
    }

    @MainActor
    func testCurrentLocationPreviewPreservesRawPunctuation() {
        let tokens = [
            Self.token("Hello,", rawText: "\"Hello,\"", id: 0),
            Self.token("word.", rawText: "(word.)", id: 1),
            Self.token("next", id: 2)
        ]
        let viewModel = ReaderViewModel(session: ReadingSession(tokens: tokens, currentIndex: 1))

        let preview = viewModel.currentLocationPreview

        XCTAssertEqual(preview.parts.map(\.text), ["\"Hello,\"", "(word.)", "next"])
        XCTAssertEqual(preview.parts[1].role, .current)
    }

    @MainActor
    func testCurrentLocationPreviewLimitsLargeBooksToVisibleSnippet() {
        let tokens = Self.tokens(count: 20_000)
        let viewModel = ReaderViewModel(session: ReadingSession(tokens: tokens, currentIndex: 10_000))

        let preview = viewModel.currentLocationPreview

        XCTAssertEqual(preview.parts.count, 131)
        XCTAssertEqual(preview.parts.first?.text, "word9940")
        XCTAssertEqual(preview.parts[60], CurrentLocationPreviewPart(text: "word10000", role: .current))
        XCTAssertEqual(preview.parts.last?.text, "word10070")
    }

    @MainActor
    func testCleanupRecordsSourceWordRangeForPlaybackSession() async throws {
        let readID = UUID()
        let statsStore = ReadingStatsStoreProbe()
        let viewModel = ReaderViewModel(
            session: ReadingSession(tokens: Self.tokens(count: 20), currentIndex: 4, wordsPerMinute: 1_200),
            readingStatsStore: statsStore,
            savedReadID: readID
        )

        viewModel.play()
        try await Task.sleep(for: .milliseconds(220))
        viewModel.cleanup()

        let event = try XCTUnwrap(statsStore.sessionEvents.first)
        XCTAssertEqual(event.readID, readID)
        XCTAssertEqual(event.sourceWordRange?.lowerBound, 4)
        XCTAssertGreaterThan(event.sourceWordRange?.upperBound ?? 0, 4)
    }

    private static func tokens(count: Int) -> [ReadingToken] {
        (0..<count).map { index in
            Self.token("word\(index)", id: index)
        }
    }

    private static func token(
        _ text: String,
        rawText: String? = nil,
        id: Int = 0,
        pageNumber: Int? = nil,
        chapterNumber: Int? = nil,
        chapterTitle: String? = nil,
        sourceSectionIndex: Int? = 0
    ) -> ReadingToken {
        ReadingToken(
            id: id,
            text: text,
            rawText: rawText ?? text,
            globalWordIndex: id,
            sourcePageNumber: pageNumber,
            sourceChapterNumber: chapterNumber,
            sourceChapterTitle: chapterTitle,
            sourceSectionIndex: sourceSectionIndex,
            pauseKind: .none,
            sentenceIndex: 0,
            containsNumber: false
        )
    }
}

@MainActor
private final class ReadingStatsStoreProbe: ReadingStatsStore {
    var snapshot: ReadingStatsSnapshot = .empty
    var dailyStats: [DailyReadingStats] = []
    var sessionEvents: [ReadingSessionEvent] = []

    func record(_ event: ReadingSessionEvent) {
        sessionEvents.append(event)
    }

    func markReadCompleted(readID: UUID, completedAt: Date) {}

    func updateDailyGoalWords(_ words: Int) {}
}

@MainActor
private final class DefinitionProbe: @unchecked Sendable {
    private let definedTerms: Set<String>
    private(set) var requestedTerms: [String] = []

    init(definedTerms: Set<String>) {
        self.definedTerms = definedTerms
    }

    func service() -> WordLookupService {
        WordLookupService { [self] term in
            requestedTerms.append(term)
            return definedTerms.contains(term)
        }
    }
}
