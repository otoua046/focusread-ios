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

        XCTAssertEqual(source.sourceStartWordIndex, 10)
        XCTAssertEqual(source.sourceEndWordIndex, 30)
        XCTAssertEqual(source.wordCount, 20)
        XCTAssertTrue(source.isCapped)
        XCTAssertTrue(source.text.hasPrefix("word10 word11"))
        XCTAssertTrue(source.text.hasSuffix("word29"))
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

    private func makeRead(wordCount: Int) -> SavedRead {
        let text = (0..<wordCount).map { "word\($0)" }.joined(separator: " ")
        let tokens = TextTokenizer().tokenize(text)
        return SavedReadMapper.makeSavedRead(from: text, tokens: tokens, now: date("2026-05-07T09:00:00Z"))
    }

    private func event(
        readID: UUID,
        endedAt: Date = Date(),
        range: Range<Int>?
    ) -> ReadingSessionEvent {
        ReadingSessionEvent(
            readID: readID,
            startedAt: endedAt.addingTimeInterval(-600),
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
