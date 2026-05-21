import XCTest
@testable import FocusRead

@MainActor
final class DiscoverPerformanceTests: XCTestCase {
    func testDiscoverViewModelFirstRenderSeedPerformance() {
        let store = LocalReadingHistoryStore(storageDirectory: temporaryStoreDirectory())

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            let viewModel = DiscoverViewModel(store: store)
            XCTAssertFalse(viewModel.sections.isEmpty)
            XCTAssertGreaterThan(viewModel.sections.flatMap(\.books).count, 20)
        }
    }

    func testDiscoverCuratedPresentationLargeFixturePerformance() {
        let books = PerformanceBenchmarkFixtures.discoverBooks(count: 1_000)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            let presented = DiscoverService.curatedPresentation(books, limit: 120)
            XCTAssertEqual(presented.count, 120)
        }
    }

    func testDiscoverRelatedBooksLargeFixturePerformance() {
        let store = LocalReadingHistoryStore(storageDirectory: temporaryStoreDirectory())
        let viewModel = DiscoverViewModel(store: store)
        let seedBook = viewModel.sections.flatMap(\.books).first!

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            let related = viewModel.relatedBooks(for: seedBook, limit: 10)
            XCTAssertFalse(related.isEmpty)
        }
    }

    func testDiscoverTrustedFastSearchPerformance() throws {
        let service = DiscoverService()

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            let results = try! runAsync {
                try await service.fastSearch("Pride and Prejudice", languageCodes: ["en"])
            }
            XCTAssertFalse(results.isEmpty)
        }
    }

    private func temporaryStoreDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusReadDiscoverBenchmarks-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
