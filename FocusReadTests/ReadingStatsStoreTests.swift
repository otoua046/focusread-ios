import XCTest
@testable import FocusRead

final class ReadingStatsStoreTests: XCTestCase {
    func testReadingDayActivityIntensityUsesDailyGoalThresholds() {
        XCTAssertEqual(ReadingDayActivity.intensityLevel(wordsRead: 0, dailyGoalWords: 2_000), 0)
        XCTAssertEqual(ReadingDayActivity.intensityLevel(wordsRead: 1, dailyGoalWords: 2_000), 1)
        XCTAssertEqual(ReadingDayActivity.intensityLevel(wordsRead: 499, dailyGoalWords: 2_000), 1)
        XCTAssertEqual(ReadingDayActivity.intensityLevel(wordsRead: 500, dailyGoalWords: 2_000), 2)
        XCTAssertEqual(ReadingDayActivity.intensityLevel(wordsRead: 1_000, dailyGoalWords: 2_000), 3)
        XCTAssertEqual(ReadingDayActivity.intensityLevel(wordsRead: 2_000, dailyGoalWords: 2_000), 4)
        XCTAssertEqual(ReadingDayActivity.intensityLevel(wordsRead: 2_400, dailyGoalWords: 2_000), 4)
    }

    func testReadingDayActivityRecentDaysBackfillsEmptyDays() {
        let calendar = gregorianUTC()
        let today = date("2026-05-04T12:00:00Z")
        let yesterday = date("2026-05-03T12:00:00Z")

        let activities = ReadingDayActivity.recentDays(
            from: [
                DailyReadingStats(
                    date: yesterday,
                    wordsRead: 500,
                    readingSeconds: 60,
                    sessionsCount: 1,
                    completedBooksCount: 0
                )
            ],
            dailyGoalWords: 1_000,
            dayCount: 3,
            endingAt: today,
            calendar: calendar
        )

        XCTAssertEqual(activities.map(\.wordsRead), [0, 500, 0])
        XCTAssertEqual(activities.map(\.intensityLevel), [0, 3, 0])
        XCTAssertEqual(activities.first?.date, date("2026-05-02T00:00:00Z"))
        XCTAssertEqual(activities.last?.date, date("2026-05-04T00:00:00Z"))
    }

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
