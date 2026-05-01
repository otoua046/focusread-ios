import Testing
@testable import FocusRead

struct ReaderSearchServiceTests {
    @Test func searchIsCaseInsensitiveAndIgnoresPunctuation() {
        let tokens = [
            token("Before,", index: 0),
            token("Focus-Read!", index: 1),
            token("after.", index: 2)
        ]
        let service = ReaderSearchService()

        let results = service.search("focus read", in: tokens)

        #expect(results.map(\.index) == [1])
        #expect(results.first?.snippet == "Before, Focus-Read! after.")
        #expect(results.first?.snippetParts == [
            ReaderSearchSnippetPart(text: "Before,", isMatch: false),
            ReaderSearchSnippetPart(text: "Focus-Read!", isMatch: true),
            ReaderSearchSnippetPart(text: "after.", isMatch: false)
        ])
    }

    @Test func snippetHighlightsAllMatchingWordsInContext() {
        let tokens = [
            token("focus", index: 0),
            token("middle", index: 1),
            token("Focus!", index: 2)
        ]
        let service = ReaderSearchService()

        let result = service.search("focus", in: tokens).first

        #expect(result?.snippetParts.map(\.isMatch) == [true, false, true])
    }

    @Test func emptySearchReturnsNoResults() {
        let service = ReaderSearchService()

        #expect(service.search("?!", in: [token("anything", index: 0)]).isEmpty)
    }

    private func token(_ text: String, index: Int) -> ReadingToken {
        ReadingToken(
            id: index,
            text: text,
            rawText: text,
            globalWordIndex: index,
            sourcePageNumber: nil,
            sourceChapterNumber: nil,
            sourceChapterTitle: nil,
            sourceSectionIndex: nil,
            pauseKind: .none,
            sentenceIndex: 0,
            containsNumber: false
        )
    }
}
