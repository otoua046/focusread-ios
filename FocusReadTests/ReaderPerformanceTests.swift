import XCTest
@testable import FocusRead

@MainActor
final class ReaderPerformanceTests: XCTestCase {
    private let tokenizer = TextTokenizer()

    override func setUp() {
        super.setUp()
        setenv("FOCUSREAD_BENCHMARK_SIGNPOSTS", "1", 1)
    }

    func testLargeDocumentTokenizationPerformance() {
        let text = PerformanceBenchmarkFixtures.text(wordCount: 120_000)

        measure(metrics: [
            XCTClockMetric(),
            XCTMemoryMetric(),
            XCTCPUMetric(),
            XCTOSSignpostMetric(
                subsystem: FocusReadBenchmarkSignposts.subsystem,
                category: FocusReadBenchmarkSignposts.category,
                name: "TextTokenization"
            )
        ]) {
            let tokens = tokenizer.tokenize(text)
            XCTAssertGreaterThan(tokens.count, 100_000)
        }
    }

    func testReaderOpenFromImportedDocumentPerformance() {
        let document = ImportedDocument(
            fileName: "reader-open-benchmark.txt",
            text: PerformanceBenchmarkFixtures.text(wordCount: 80_000),
            sourceType: .txt
        )

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            let tokens = tokenizer.tokenize(document)
            let session = ReadingSession(
                tokens: tokens,
                document: ReadingDocument(importedDocument: document),
                wordsPerMinute: 1_200
            )
            let viewModel = ReaderViewModel(session: session, importedDocument: document)
            XCTAssertFalse(viewModel.currentWord.isEmpty)
            XCTAssertEqual(viewModel.wordsPerMinute, 1_200)
        }
    }

    func testHighWPMPlaybackStateAdvancementPerformance() {
        let tokens = tokenizer.tokenize(PerformanceBenchmarkFixtures.text(wordCount: 60_000))

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            var session = ReadingSession(tokens: tokens, wordsPerMinute: 1_200)
            for _ in 0..<5_000 {
                session.advance()
            }
            XCTAssertEqual(session.currentIndex, 5_000)
        }
    }

    func testRapidPlaybackSpeedChangesPerformance() {
        let tokens = tokenizer.tokenize(PerformanceBenchmarkFixtures.text(wordCount: 5_000))
        let session = ReadingSession(tokens: tokens)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            let viewModel = ReaderViewModel(session: session)
            for speed in stride(from: 100, through: 1_200, by: 25) {
                viewModel.setWPM(speed, haptic: false)
            }
            XCTAssertEqual(viewModel.wordsPerMinute, 1_200)
        }
    }
}
