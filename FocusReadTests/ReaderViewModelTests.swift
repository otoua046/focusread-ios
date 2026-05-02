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

    private static func token(_ text: String, id: Int = 0) -> ReadingToken {
        ReadingToken(
            id: id,
            text: text,
            rawText: text,
            globalWordIndex: id,
            sourcePageNumber: nil,
            sourceChapterNumber: nil,
            sourceChapterTitle: nil,
            sourceSectionIndex: 0,
            pauseKind: .none,
            sentenceIndex: 0,
            containsNumber: false
        )
    }
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
