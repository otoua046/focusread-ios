import XCTest
@testable import FocusRead

final class AIRecapStoreTests: XCTestCase {
    @MainActor
    func testSavingRecapPersistsAndReloads() {
        let directory = temporaryDirectory()
        let readID = UUID()
        let sessionID = UUID()
        let recap = makeRecap(
            readID: readID,
            sessionID: sessionID,
            sessionEndedAt: date("2026-05-02T10:10:00Z"),
            text: "AI-generated recap text."
        )

        let store = LocalAIRecapStore(storageDirectory: directory)
        store.save(recap)

        let reloaded = LocalAIRecapStore(storageDirectory: directory)
        XCTAssertEqual(reloaded.recaps(for: readID), [recap])
    }

    @MainActor
    func testSavingSameSessionReplacesExistingRecap() {
        let directory = temporaryDirectory()
        let readID = UUID()
        let sessionID = UUID()
        let first = makeRecap(
            readID: readID,
            sessionID: sessionID,
            sessionEndedAt: date("2026-05-02T10:10:00Z"),
            text: "First recap."
        )
        let replacement = makeRecap(
            readID: readID,
            sessionID: sessionID,
            sessionEndedAt: date("2026-05-02T10:10:00Z"),
            text: "Replacement recap."
        )

        let store = LocalAIRecapStore(storageDirectory: directory)
        store.save(first)
        store.save(replacement)

        XCTAssertEqual(store.recaps(for: readID), [replacement])
    }

    @MainActor
    func testStoreKeepsOnlyThreeNewestRecapsPerBook() {
        let directory = temporaryDirectory()
        let readID = UUID()
        let store = LocalAIRecapStore(storageDirectory: directory)

        let recaps = [
            makeRecap(readID: readID, sessionEndedAt: date("2026-05-01T10:00:00Z"), text: "Oldest"),
            makeRecap(readID: readID, sessionEndedAt: date("2026-05-02T10:00:00Z"), text: "Second"),
            makeRecap(readID: readID, sessionEndedAt: date("2026-05-03T10:00:00Z"), text: "Third"),
            makeRecap(readID: readID, sessionEndedAt: date("2026-05-04T10:00:00Z"), text: "Newest")
        ]

        recaps.forEach(store.save)

        XCTAssertEqual(store.recaps(for: readID).map(\.generatedText), ["Newest", "Third", "Second"])
    }

    @MainActor
    func testDeletingBookRecapsRemovesPersistedFile() {
        let directory = temporaryDirectory()
        let readID = UUID()
        let store = LocalAIRecapStore(storageDirectory: directory)
        store.save(makeRecap(readID: readID, text: "Temporary recap."))

        store.deleteRecaps(for: readID)

        let reloaded = LocalAIRecapStore(storageDirectory: directory)
        XCTAssertEqual(reloaded.recaps(for: readID), [])
    }

    private func makeRecap(
        readID: UUID,
        sessionID: UUID = UUID(),
        sessionEndedAt: Date = Date(),
        text: String
    ) -> AIRecap {
        AIRecap(
            readID: readID,
            sessionID: sessionID,
            sessionStartedAt: sessionEndedAt.addingTimeInterval(-600),
            sessionEndedAt: sessionEndedAt,
            sourceStartWordIndex: 10,
            sourceEndWordIndex: 110,
            generatedText: text,
            createdAt: sessionEndedAt.addingTimeInterval(60),
            inputWordCount: 100,
            outputWordCount: text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
            modelName: "Apple Foundation Models",
            modelVersion: "test"
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusReadAIRecapStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
