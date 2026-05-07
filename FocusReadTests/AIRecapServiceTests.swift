import XCTest
@testable import FocusRead

final class AIRecapServiceTests: XCTestCase {
    func testRecentEligibleSessionsUsesOnlyRangedSessionsForBook() {
        let readID = UUID()
        let otherReadID = UUID()
        let extractor = AIRecapSourceExtractor(minimumInputWordCount: 1)
        let events = [
            event(readID: readID, endedAt: date("2026-05-01T10:00:00Z"), range: 0..<100),
            event(readID: readID, endedAt: date("2026-05-04T10:00:00Z"), range: 100..<200),
            event(readID: readID, endedAt: date("2026-05-03T10:00:00Z"), range: nil),
            event(readID: otherReadID, endedAt: date("2026-05-05T10:00:00Z"), range: 0..<100),
            event(readID: readID, endedAt: date("2026-05-02T10:00:00Z"), range: 200..<300)
        ]

        let eligible = extractor.recentEligibleSessions(for: readID, from: events)

        XCTAssertEqual(eligible.map(\.endedAt), [
            date("2026-05-04T10:00:00Z"),
            date("2026-05-02T10:00:00Z"),
            date("2026-05-01T10:00:00Z")
        ])
    }

    func testRecentEligibleSessionsRecoversOnlyMostRecentRangeLessSessionForSavedRead() {
        var read = makeRead(wordCount: 200)
        read.currentWordIndex = 120
        let extractor = AIRecapSourceExtractor(minimumInputWordCount: 1)
        let olderMissingRange = event(readID: read.id, endedAt: date("2026-05-01T10:00:00Z"), range: nil)
        let ranged = event(readID: read.id, endedAt: date("2026-05-02T10:00:00Z"), range: 50..<80)
        let newestMissingRange = event(readID: read.id, endedAt: date("2026-05-03T10:00:00Z"), range: nil)

        let eligible = extractor.recentEligibleSessions(for: read, from: [
            olderMissingRange,
            ranged,
            newestMissingRange
        ])

        XCTAssertEqual(eligible.map(\.id), [
            newestMissingRange.id,
            ranged.id
        ])
    }

    func testSourceExtractionUsesSessionRangeAndCapsLongInput() throws {
        let read = makeRead(wordCount: 120)
        let extractor = AIRecapSourceExtractor(maximumInputWordCount: 20, minimumInputWordCount: 1)
        let session = event(readID: read.id, range: 10..<80)

        let source = try extractor.source(for: read, sessionEvent: session)

        XCTAssertEqual(source.sourceStartWordIndex, 60)
        XCTAssertEqual(source.sourceEndWordIndex, 80)
        XCTAssertEqual(source.wordCount, 20)
        XCTAssertTrue(source.isCapped)
        XCTAssertTrue(source.text.hasPrefix("word60 word61"))
        XCTAssertTrue(source.text.hasSuffix("word79"))
    }

    func testSourceExtractionRecoversRangeLessSessionFromSavedProgress() throws {
        var read = makeRead(wordCount: 200)
        read.currentWordIndex = 120
        let extractor = AIRecapSourceExtractor(maximumInputWordCount: 100, minimumInputWordCount: 1)
        let session = event(readID: read.id, range: nil)

        let source = try extractor.source(for: read, sessionEvent: session)

        XCTAssertEqual(source.sourceStartWordIndex, 70)
        XCTAssertEqual(source.sourceEndWordIndex, 120)
        XCTAssertEqual(source.wordCount, 50)
        XCTAssertTrue(source.text.hasPrefix("word70 word71"))
        XCTAssertTrue(source.text.hasSuffix("word119"))
    }

    func testSourceExtractionRejectsVeryShortSessionText() {
        let read = makeRead(wordCount: 10)
        let extractor = AIRecapSourceExtractor(maximumInputWordCount: 20, minimumInputWordCount: 8)
        let session = event(readID: read.id, range: 2..<5)

        XCTAssertThrowsError(try extractor.source(for: read, sessionEvent: session)) { error in
            XCTAssertEqual(error as? AIRecapGenerationError, .notEnoughText)
        }
    }

    func testServiceGeneratesRecapWithInjectedLocalModel() async throws {
        let read = makeRead(wordCount: 80)
        let generatedAt = date("2026-05-07T12:00:00Z")
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(maximumInputWordCount: 50, minimumInputWordCount: 1),
            model: FakeRecapModel(output: "A concise on-device recap."),
            dateProvider: { generatedAt }
        )
        let session = event(
            readID: read.id,
            endedAt: date("2026-05-07T10:10:00Z"),
            range: 5..<45
        )

        let recap = try await service.generateRecap(for: read, sessionEvent: session)

        XCTAssertEqual(recap.readID, read.id)
        XCTAssertEqual(recap.sessionID, session.id)
        XCTAssertEqual(recap.sourceStartWordIndex, 5)
        XCTAssertEqual(recap.sourceEndWordIndex, 45)
        XCTAssertEqual(recap.generatedText, "A concise on-device recap.")
        XCTAssertEqual(recap.createdAt, generatedAt)
        XCTAssertEqual(recap.inputWordCount, 40)
        XCTAssertEqual(recap.modelName, "Fake Local Model")
    }

    func testServiceRejectsUnavailableLocalModel() async {
        let read = makeRead(wordCount: 80)
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 1),
            model: FakeRecapModel(isAvailable: false, output: "")
        )

        do {
            _ = try await service.generateRecap(for: read, sessionEvent: event(readID: read.id, range: 0..<20))
            XCTFail("Expected localAIUnavailable")
        } catch {
            XCTAssertEqual(error as? AIRecapGenerationError, .localAIUnavailable)
        }
    }

    func testEnglishSourceGeneratesEnglishRecap() async throws {
        let read = makeRead(text: englishText(wordCount: 280))
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: LanguageAwareFakeRecapModel()
        )

        let recap = try await service.generateRecap(for: read, sessionEvent: event(readID: read.id, range: 0..<280))

        XCTAssertEqual(recap.generatedText, "This is an English recap.")
        XCTAssertEqual(recap.sourceLanguageCode, "en")
        XCTAssertEqual(recap.sourceLanguageName, "English")
    }

    func testFrenchSourceGeneratesFrenchRecap() async throws {
        let read = makeRead(text: frenchText(wordCount: 280))
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: LanguageAwareFakeRecapModel()
        )

        let recap = try await service.generateRecap(for: read, sessionEvent: event(readID: read.id, range: 0..<280))

        XCTAssertEqual(recap.generatedText, "Ceci est un résumé en français.")
        XCTAssertEqual(recap.sourceLanguageCode, "fr")
        XCTAssertEqual(recap.sourceLanguageName, "French")
    }

    func testShortFrenchSourceGeneratesFrenchRecapWhenAllowed() async throws {
        let read = makeRead(text: frenchText(wordCount: 100))
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 1),
            model: LanguageAwareFakeRecapModel()
        )

        let recap = try await service.generateRecap(for: read, sessionEvent: event(readID: read.id, range: 0..<100))

        XCTAssertEqual(recap.generatedText, "Ceci est un résumé en français.")
        XCTAssertEqual(recap.sourceLanguageCode, "fr")
    }

    func testMetadataLanguagePreferredWhenReliable() throws {
        var read = makeRead(text: englishText(wordCount: 280))
        read.languageCode = "fr"
        let extractor = AIRecapSourceExtractor(minimumInputWordCount: 250)

        let source = try extractor.source(for: read, sessionEvent: event(readID: read.id, range: 0..<280))

        XCTAssertEqual(source.detectedLanguage?.code, "fr")
        XCTAssertEqual(source.detectedLanguage?.source, .metadata)
    }

    func testPausePlayAfterTenSecondsMergesIntoSameLogicalRecapSession() {
        let read = makeRead(wordCount: 400)
        let first = event(readID: read.id, startedAt: date("2026-05-07T10:00:00Z"), endedAt: date("2026-05-07T10:02:00Z"), range: 0..<180)
        let second = event(readID: read.id, startedAt: date("2026-05-07T10:02:10Z"), endedAt: date("2026-05-07T10:04:00Z"), range: 180..<360)

        let sessions = AIRecapSourceExtractor(minimumInputWordCount: 250).recentEligibleSessions(for: read, from: [first, second])

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sourceWordRange, 0..<360)
    }

    func testPausePlayAfterFiveMinutesMergesIntoSameLogicalRecapSession() {
        let read = makeRead(wordCount: 500)
        let first = event(readID: read.id, startedAt: date("2026-05-07T10:00:00Z"), endedAt: date("2026-05-07T10:05:00Z"), range: 0..<200)
        let second = event(readID: read.id, startedAt: date("2026-05-07T10:10:00Z"), endedAt: date("2026-05-07T10:15:00Z"), range: 200..<420)

        let sessions = AIRecapSourceExtractor(minimumInputWordCount: 250).recentEligibleSessions(for: read, from: [first, second])

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sourceWordRange, 0..<420)
    }

    func testReturnAfterThirtyOneMinutesStartsNewLogicalRecapSession() {
        let read = makeRead(wordCount: 700)
        let first = event(readID: read.id, startedAt: date("2026-05-07T10:00:00Z"), endedAt: date("2026-05-07T10:10:00Z"), range: 0..<300)
        let second = event(readID: read.id, startedAt: date("2026-05-07T10:41:00Z"), endedAt: date("2026-05-07T10:50:00Z"), range: 300..<620)

        let sessions = AIRecapSourceExtractor(minimumInputWordCount: 250).recentEligibleSessions(for: read, from: [first, second])

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.sourceWordRange), [300..<620, 0..<300])
    }

    func testMultipleShortSegmentsWithinThirtyMinutesMergeIntoEligibleSession() {
        let read = makeRead(wordCount: 400)
        let segments = [
            event(readID: read.id, startedAt: date("2026-05-07T10:00:00Z"), endedAt: date("2026-05-07T10:01:00Z"), range: 0..<90),
            event(readID: read.id, startedAt: date("2026-05-07T10:06:00Z"), endedAt: date("2026-05-07T10:07:00Z"), range: 90..<180),
            event(readID: read.id, startedAt: date("2026-05-07T10:12:00Z"), endedAt: date("2026-05-07T10:13:00Z"), range: 180..<270)
        ]

        let sessions = AIRecapSourceExtractor(minimumInputWordCount: 250).recentEligibleSessions(for: read, from: segments)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sourceWordRange, 0..<270)
    }

    func testOneWordSessionIsNotRecapable() {
        let read = makeRead(wordCount: 300)
        let session = event(readID: read.id, range: 0..<1)

        let sessions = AIRecapSourceExtractor().recentEligibleSessions(for: read, from: [session])

        XCTAssertEqual(sessions, [])
    }

    func testOneHundredWordSessionIsNotRecapable() {
        let read = makeRead(wordCount: 300)
        let session = event(readID: read.id, range: 0..<100)

        let sessions = AIRecapSourceExtractor().recentEligibleSessions(for: read, from: [session])

        XCTAssertEqual(sessions, [])
    }

    func testTwoHundredFiftyWordSessionIsRecapable() {
        let read = makeRead(wordCount: 300)
        let session = event(readID: read.id, range: 0..<250)

        let sessions = AIRecapSourceExtractor().recentEligibleSessions(for: read, from: [session])

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sourceWordRange, 0..<250)
    }

    func testSixThousandWordSessionCapsToMostRecentFiveThousandWords() throws {
        let read = makeRead(wordCount: 6_200)
        let extractor = AIRecapSourceExtractor()

        let source = try extractor.source(for: read, sessionEvent: event(readID: read.id, range: 0..<6_000))

        XCTAssertEqual(source.sourceStartWordIndex, 1_000)
        XCTAssertEqual(source.sourceEndWordIndex, 6_000)
        XCTAssertEqual(source.sourceWordCountBeforeCap, 6_000)
        XCTAssertEqual(source.wordCount, 5_000)
        XCTAssertTrue(source.isCapped)
        XCTAssertTrue(source.text.hasPrefix("word1000 word1001"))
        XCTAssertTrue(source.text.hasSuffix("word5999"))
    }

    private func makeRead(wordCount: Int) -> SavedRead {
        let text = (0..<wordCount).map { "word\($0)" }.joined(separator: " ")
        return makeRead(text: text)
    }

    private func makeRead(text: String) -> SavedRead {
        let tokens = TextTokenizer().tokenize(text)
        return SavedReadMapper.makeSavedRead(from: text, tokens: tokens, now: date("2026-05-07T09:00:00Z"))
    }

    private func event(
        readID: UUID,
        endedAt: Date = Date(),
        range: Range<Int>?
    ) -> ReadingSessionEvent {
        event(
            readID: readID,
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            range: range
        )
    }

    private func event(
        readID: UUID,
        startedAt: Date,
        endedAt: Date,
        range: Range<Int>?
    ) -> ReadingSessionEvent {
        ReadingSessionEvent(
            readID: readID,
            startedAt: startedAt,
            endedAt: endedAt,
            wordsRead: range.map { $0.count } ?? 50,
            averageWPM: 300,
            sourceStartWordIndex: range?.lowerBound,
            sourceEndWordIndex: range?.upperBound
        )
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private func englishText(wordCount: Int) -> String {
        repeatedWords(["the", "reader", "follows", "a", "clear", "English", "chapter", "about", "memory", "and", "attention"], count: wordCount)
    }

    private func frenchText(wordCount: Int) -> String {
        repeatedWords(["le", "lecteur", "suit", "un", "chapitre", "français", "sur", "la", "mémoire", "et", "l’attention"], count: wordCount)
    }

    private func repeatedWords(_ words: [String], count: Int) -> String {
        (0..<count).map { words[$0 % words.count] }.joined(separator: " ")
    }
}

private struct FakeRecapModel: AIRecapModelGenerating {
    var isAvailable = true
    var output: String
    var modelName: String { "Fake Local Model" }
    var modelVersion: String { "test" }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        output
    }
}

private struct LanguageAwareFakeRecapModel: AIRecapModelGenerating {
    var isAvailable = true
    var modelName: String { "Fake Local Model" }
    var modelVersion: String { "test" }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        if source.detectedLanguage?.code == "fr" {
            return "Ceci est un résumé en français."
        }

        return "This is an English recap."
    }
}
