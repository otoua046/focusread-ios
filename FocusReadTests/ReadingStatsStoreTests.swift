import XCTest
@testable import FocusRead

final class ReadingStatsStoreTests: XCTestCase {
    @MainActor
    func testRecordingSessionUpdatesSnapshotAndDailyStats() {
        let directory = temporaryDirectory()
        let calendar = gregorianUTC()
        let readID = UUID()
        let now = date("2026-05-02T12:00:00Z")
        let store = LocalReadingStatsStore(
            storageDirectory: directory,
            calendar: calendar,
            now: { now }
        )

        store.record(ReadingSessionEvent(
            readID: readID,
            startedAt: date("2026-05-02T10:00:00Z"),
            endedAt: date("2026-05-02T10:02:00Z"),
            wordsRead: 1_000,
            averageWPM: 500
        ))

        XCTAssertEqual(store.snapshot.totalWordsRead, 1_000)
        XCTAssertEqual(store.snapshot.totalReadingSeconds, 120)
        XCTAssertEqual(store.snapshot.averageWPM, 500)
        XCTAssertEqual(store.snapshot.todayWordsRead, 1_000)
        XCTAssertEqual(store.snapshot.currentStreakDays, 1)
        XCTAssertEqual(store.dailyStats.first?.sessionsCount, 1)
        XCTAssertGreaterThan(store.snapshot.estimatedTimeSavedSeconds, 130)
    }

    @MainActor
    func testStreakAllowsYesterdayAsCurrentStreakEnd() {
        let directory = temporaryDirectory()
        let calendar = gregorianUTC()
        let readID = UUID()
        let store = LocalReadingStatsStore(
            storageDirectory: directory,
            calendar: calendar,
            now: { self.date("2026-05-03T09:00:00Z") }
        )

        store.record(ReadingSessionEvent(
            readID: readID,
            startedAt: date("2026-05-01T10:00:00Z"),
            endedAt: date("2026-05-01T10:01:00Z"),
            wordsRead: 300,
            averageWPM: 300
        ))
        store.record(ReadingSessionEvent(
            readID: readID,
            startedAt: date("2026-05-02T10:00:00Z"),
            endedAt: date("2026-05-02T10:01:00Z"),
            wordsRead: 300,
            averageWPM: 300
        ))

        XCTAssertEqual(store.snapshot.currentStreakDays, 2)
        XCTAssertEqual(store.snapshot.longestStreakDays, 2)
    }

    @MainActor
    func testDailyGoalAndCompletedReadsPersistLocally() {
        let directory = temporaryDirectory()
        let calendar = gregorianUTC()
        let now = date("2026-05-02T12:00:00Z")
        let readID = UUID()

        let store = LocalReadingStatsStore(
            storageDirectory: directory,
            calendar: calendar,
            now: { now }
        )
        store.updateDailyGoalWords(2_400)
        store.markReadCompleted(readID: readID, completedAt: now)
        store.markReadCompleted(readID: readID, completedAt: now)

        let reloaded = LocalReadingStatsStore(
            storageDirectory: directory,
            calendar: calendar,
            now: { now }
        )

        XCTAssertEqual(reloaded.snapshot.dailyGoalWords, 2_400)
        XCTAssertEqual(reloaded.snapshot.booksCompleted, 1)
        XCTAssertEqual(reloaded.dailyStats.first?.completedBooksCount, 1)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusReadTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
