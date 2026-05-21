import XCTest
@testable import FocusRead

final class OCRImportPerformanceTests: XCTestCase {
    func testScannedPDFOCRImportPerformance() throws {
        let file = try PerformanceBenchmarkFixtures.temporaryScannedPDF(pageCount: 1)
        let extractor = OCRTextExtractor()
        let options = XCTMeasureOptions()
        options.iterationCount = 1

        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()],
            options: options
        ) {
            let document = try! runAsync {
                try await extractor.extractText(from: file) { _ in }
            }
            XCTAssertTrue(document.text.localizedCaseInsensitiveContains("FocusRead"))
        }
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

final class LockedResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<T, Error>?

    var result: Result<T, Error> {
        lock.lock()
        defer { lock.unlock() }
        return storedResult!
    }

    func set(_ result: Result<T, Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }
}
