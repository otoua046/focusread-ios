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

struct TextTokenizerTests {
    @Test func paragraphBreakRetroactivelyAppliedToPreviousToken() {
        let text = "Hello world.\n\nNew paragraph starts here."
        let tokenizer = TextTokenizer()
        let tokens = tokenizer.tokenize(text)

        #expect(tokens.count == 6)
        
        let worldToken = tokens[1]
        #expect(worldToken.text == "world.")
        #expect(worldToken.pauseKind == ReadingToken.PauseKind.paragraphBreak)
        #expect(worldToken.sentenceIndex == 0)

        let newToken = tokens[2]
        #expect(newToken.text == "New")
        #expect(newToken.pauseKind == ReadingToken.PauseKind.none)
        #expect(newToken.sentenceIndex == 1)

        let paragraphToken = tokens[3]
        #expect(paragraphToken.text == "paragraph")
        #expect(paragraphToken.sentenceIndex == 1)
        
        let hereToken = tokens.last!
        #expect(hereToken.text == "here.")
        #expect(hereToken.pauseKind == ReadingToken.PauseKind.sentenceEnd)
        #expect(hereToken.sentenceIndex == 1)
    }

    @Test func paragraphBreakUpgradesMinorPunctuation() {
        let text = "Hello world,\n\nNew paragraph"
        let tokenizer = TextTokenizer()
        let tokens = tokenizer.tokenize(text)

        #expect(tokens.count == 4)
        let worldToken = tokens[1]
        #expect(worldToken.text == "world,")
        #expect(worldToken.pauseKind == ReadingToken.PauseKind.paragraphBreak)
        #expect(worldToken.sentenceIndex == 0)

        let newToken = tokens[2]
        #expect(newToken.text == "New")
        #expect(newToken.pauseKind == ReadingToken.PauseKind.none)
        #expect(newToken.sentenceIndex == 1)
    }

    @Test func sectionBoundaryAppliesParagraphBreakToLastToken() {
        let section1 = ImportedDocumentSection(index: 0, text: "End of chapter 1.", pageNumber: 1, chapterNumber: 1, chapterTitle: nil, wordRange: nil, epubNavigationLevel: nil, epubSectionRole: .chapter, epubStructureSource: nil, epubStructureConfidence: nil)
        let section2 = ImportedDocumentSection(index: 1, text: "Chapter 2 begins here.", pageNumber: 2, chapterNumber: 2, chapterTitle: nil, wordRange: nil, epubNavigationLevel: nil, epubSectionRole: .chapter, epubStructureSource: nil, epubStructureConfidence: nil)
        
        let document = ImportedDocument(fileName: "Test.txt", displayTitle: "Test", sourceType: .txt, sections: [section1, section2], cleanupMode: .off)
        let tokenizer = TextTokenizer()
        let tokens = tokenizer.tokenize(document)

        // "End", "of", "chapter", "1."
        let lastOfSection1 = tokens[3]
        #expect(lastOfSection1.text == "1.")
        #expect(lastOfSection1.pauseKind == ReadingToken.PauseKind.paragraphBreak)
        #expect(lastOfSection1.sentenceIndex == 0)

        // "Chapter", "2", "begins", "here."
        let firstOfSection2 = tokens[4]
        #expect(firstOfSection2.text == "Chapter")
        #expect(firstOfSection2.pauseKind == ReadingToken.PauseKind.none)
        #expect(firstOfSection2.sentenceIndex == 1)
    }
    
    @Test func rewindSentenceBehaviorDoesNotIsolateFirstWord() {
        let text = "Hello world.\n\nNew paragraph starts here."
        let tokenizer = TextTokenizer()
        let tokens = tokenizer.tokenize(text)
        
        var session = ReadingSession(tokens: tokens)
        session.currentIndex = 4 // "starts"
        session.rewindSentence() // Should rewind to "New" which is index 2
        #expect(session.currentIndex == 2)
    }
}

struct OnboardingSampleTests {
    @Test func wordsTokenizesLanguagesWithoutWhitespace() {
        let words = FocusReadOnboardingSample.words(in: "今日は図書館で静かに読みます")

        #expect(words.count > 1)
        #expect(words.joined() == "今日は図書館で静かに読みます")
    }
}

struct SavedReadSourceTypeTests {
    @Test func debugLogNameUsesStableRawValues() {
        #expect(SavedReadSourceType.pastedText.debugLogName == "pastedText")
        #expect(SavedReadSourceType.txt.debugLogName == "txt")
        #expect(SavedReadSourceType.pdf.debugLogName == "pdf")
        #expect(SavedReadSourceType.epub.debugLogName == "epub")
        #expect(SavedReadSourceType.image.debugLogName == "image")
    }
}
