import XCTest
@testable import FocusRead

@MainActor
final class LibraryScalePerformanceTests: XCTestCase {
    func testLibraryHydration100ReadsPerformance() throws {
        try measureLibraryHydration(readCount: 100)
    }

    func testLibraryHydration500ReadsPerformance() throws {
        try measureLibraryHydration(readCount: 500)
    }

    func testLibraryHydration1000ReadsPerformance() throws {
        try measureLibraryHydration(readCount: 1_000)
    }

    func testLibrarySearchAndSort1000ReadsPerformance() throws {
        let reads = PerformanceBenchmarkFixtures.seededSavedReads(count: 1_000)
        let storageDirectory = try PerformanceBenchmarkFixtures.writeSavedReads(reads)
        let store = LocalReadingHistoryStore(storageDirectory: storageDirectory)
        let viewModel = LibraryViewModel(store: store)
        waitForLibrary(viewModel, expectedCount: reads.count)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            viewModel.searchText = "benchmark read 09"
            XCTAssertFalse(viewModel.reads.isEmpty)
            viewModel.sortMode = .title
            viewModel.searchText = "author 12"
            viewModel.sortMode = .author
            viewModel.searchText = ""
            viewModel.sortMode = .manual
            XCTAssertEqual(viewModel.reads.count, reads.count)
        }
    }

    private func measureLibraryHydration(readCount: Int) throws {
        let reads = PerformanceBenchmarkFixtures.seededSavedReads(count: readCount)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()]) {
            let storageDirectory = try! PerformanceBenchmarkFixtures.writeSavedReads(reads)
            let store = LocalReadingHistoryStore(storageDirectory: storageDirectory)
            let viewModel = LibraryViewModel(store: store)
            waitForLibrary(viewModel, expectedCount: readCount)
            XCTAssertEqual(viewModel.reads.count, readCount)
        }
    }

    private func waitForLibrary(_ viewModel: LibraryViewModel, expectedCount: Int) {
        let deadline = Date().addingTimeInterval(5)
        while viewModel.reads.count != expectedCount && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}
