Onimport XCTest
@testable import FocusRead

final class WordLookupServiceTests: XCTestCase {
    func testSanitizedTermStripsPunctuationAroundWord() {
        XCTAssertEqual(WordLookupService.sanitizedTerm(from: "word,"), "word")
        XCTAssertEqual(WordLookupService.sanitizedTerm(from: "Socialism."), "Socialism")
        XCTAssertEqual(WordLookupService.sanitizedTerm(from: "“reader”"), "reader")
    }

    func testSanitizedTermPreservesInternalPunctuation() {
        XCTAssertEqual(WordLookupService.sanitizedTerm(from: "can't"), "can't")
        XCTAssertEqual(WordLookupService.sanitizedTerm(from: "well-being."), "well-being")
    }

    func testSanitizedTermReturnsNilWithoutLookupContent() {
        XCTAssertNil(WordLookupService.sanitizedTerm(from: "..."))
        XCTAssertNil(WordLookupService.sanitizedTerm(from: "   "))
    }
}
