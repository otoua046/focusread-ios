import XCTest
@testable import FocusRead

final class ImportPipelinePerformanceTests: XCTestCase {
    private let importService = DocumentImportService()
    private let tokenizer = TextTokenizer()

    override func setUp() {
        super.setUp()
        setenv("FOCUSREAD_BENCHMARK_SIGNPOSTS", "1", 1)
    }

    func testTXTImportToReadableWordsPerformance() throws {
        let file = try PerformanceBenchmarkFixtures.temporaryTextFile(wordCount: 25_000)
        let service = importService

        measure(metrics: importMetrics(named: "DocumentImport")) {
            let document = try! runAsync {
                try await service.extractText(from: file, smartCleanupMode: .off) { _ in }
            }
            let tokens = tokenizer.tokenize(document)
            XCTAssertGreaterThan(tokens.count, 20_000)
        }
    }

    func testEPUBImportToReadableWordsPerformance() throws {
        let file = try PerformanceBenchmarkFixtures.epubFixture("jane-austen_pride-and-prejudice", testCase: self)
        let service = importService

        measure(metrics: importMetrics(named: "DocumentImport")) {
            let document = try! runAsync {
                try await service.extractText(from: file, smartCleanupMode: .off) { _ in }
            }
            let tokens = tokenizer.tokenize(document)
            XCTAssertGreaterThan(document.sections.count, 50)
            XCTAssertGreaterThan(tokens.count, 100_000)
        }
    }

    func testPDFImportToReadableWordsPerformance() throws {
        let file = try PerformanceBenchmarkFixtures.temporaryPDF(pageCount: 18, wordsPerPage: 550)
        let service = importService

        measure(metrics: importMetrics(named: "DocumentImport")) {
            let document = try! runAsync {
                try await service.extractText(from: file, smartCleanupMode: .off) { _ in }
            }
            let tokens = tokenizer.tokenize(document)
            XCTAssertEqual(document.sections.count, 18)
            XCTAssertGreaterThan(tokens.count, 4_000)
        }
    }

    private func importMetrics(named signpostName: String) -> [any XCTMetric] {
        [
            XCTClockMetric(),
            XCTMemoryMetric(),
            XCTCPUMetric(),
            XCTOSSignpostMetric(
                subsystem: FocusReadBenchmarkSignposts.subsystem,
                category: FocusReadBenchmarkSignposts.category,
                name: signpostName
            )
        ]
    }

    private func runAsync<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LockedResultBox<T>()

        Task.detached {
            do {
                resultBox.set(.success(try await operation()))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try resultBox.result.get()
    }
}
