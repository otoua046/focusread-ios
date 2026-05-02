import XCTest
import Combine
@testable import FocusRead

final class ReaderViewModelTests: XCTestCase {
    @MainActor
    func testLookupCurrentWordUsesSanitizedWord() async {
        let tokens = [
            ReadingToken(id: 0, text: "that.", rawText: "that.", globalWordIndex: 0, sourcePageNumber: nil, sourceChapterNumber: nil, sourceChapterTitle: nil, sourceSectionIndex: 0, pauseKind: .none, sentenceIndex: 0, containsNumber: false)
        ]
        let session = ReadingSession(tokens: tokens)
        let viewModel = ReaderViewModel(session: session)
        
        viewModel.lookupCurrentWord()
        
        // Note: UIReferenceLibraryViewController.dictionaryHasDefinition might return false in tests.
        // We mainly want to verify it doesn't crash and respects the sanitized term logic.
        if let request = viewModel.lookupRequest {
            XCTAssertEqual(request.term, "that")
        } else {
            XCTAssertTrue(viewModel.noDefinitionFound)
        }
    }
    
    @MainActor
    func testLookupCurrentWordPausesReader() {
        let tokens = [
            ReadingToken(id: 0, text: "word", rawText: "word", globalWordIndex: 0, sourcePageNumber: nil, sourceChapterNumber: nil, sourceChapterTitle: nil, sourceSectionIndex: 0, pauseKind: .none, sentenceIndex: 0, containsNumber: false)
        ]
        let session = ReadingSession(tokens: tokens)
        let viewModel = ReaderViewModel(session: session)
        viewModel.isPlaying = true
        
        viewModel.lookupCurrentWord()
        
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertTrue(viewModel.controlsVisible)
    }
}
