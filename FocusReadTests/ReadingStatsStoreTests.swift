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

    func testReadingSessionEventExposesSourceWordRangeWhenPresent() {
        let event = ReadingSessionEvent(
            readID: UUID(),
            startedAt: date("2026-05-02T10:00:00Z"),
            endedAt: date("2026-05-02T10:02:00Z"),
            wordsRead: 120,
            averageWPM: 300,
            sourceStartWordIndex: 42,
            sourceEndWordIndex: 162
        )

        XCTAssertEqual(event.sourceWordRange, 42..<162)
    }

    func testReadingSessionEventTreatsMissingSourceRangeAsIneligible() {
        let event = ReadingSessionEvent(
            readID: UUID(),
            startedAt: date("2026-05-02T10:00:00Z"),
            endedAt: date("2026-05-02T10:02:00Z"),
            wordsRead: 120,
            averageWPM: 300
        )

        XCTAssertNil(event.sourceWordRange)
    }

    func testContributionCalendarCrossesFebruaryInNonLeapYearWithoutMissingDays() {
        let calendar = gregorianUTC()
        let activities = contributionActivities(
            endingAt: date("2023-03-15T12:00:00Z"),
            dayCount: 90,
            calendar: calendar
        )
        let contributionCalendar = ReadingContributionCalendar(calendar: calendar)
        let weeks = contributionCalendar.weeks(
            activities: activities,
            visibleWeekCount: visibleWeekCount(for: activities, contributionCalendar: contributionCalendar),
            endingAt: activities.last?.date
        )

        assertConsecutiveDates(in: weeks, calendar: calendar)
        assertNoDuplicateDates(in: weeks)
        assertMonthMarkersAlign(
            contributionCalendar.monthMarkers(for: weeks),
            weeks: weeks,
            calendar: calendar
        )

        let dates = gridDates(in: weeks)
        XCTAssertTrue(dates.contains(day(2023, 2, 28, calendar: calendar)))
        XCTAssertFalse(dates.contains { calendar.component(.month, from: $0) == 2 && calendar.component(.day, from: $0) == 29 })
    }

    func testContributionCalendarCrossesFebruaryInLeapYearWithoutMissingDays() {
        let calendar = gregorianUTC()
        let activities = contributionActivities(
            endingAt: date("2024-03-15T12:00:00Z"),
            dayCount: 90,
            calendar: calendar
        )
        let contributionCalendar = ReadingContributionCalendar(calendar: calendar)
        let weeks = contributionCalendar.weeks(
            activities: activities,
            visibleWeekCount: visibleWeekCount(for: activities, contributionCalendar: contributionCalendar),
            endingAt: activities.last?.date
        )

        assertConsecutiveDates(in: weeks, calendar: calendar)
        assertNoDuplicateDates(in: weeks)
        assertMonthMarkersAlign(
            contributionCalendar.monthMarkers(for: weeks),
            weeks: weeks,
            calendar: calendar
        )

        XCTAssertTrue(gridDates(in: weeks).contains(day(2024, 2, 29, calendar: calendar)))
    }

    func testContributionCalendarCrossesYearBoundaryAndAlignsJanuaryLabel() {
        let calendar = gregorianUTC()
        let activities = contributionActivities(
            endingAt: date("2026-01-15T12:00:00Z"),
            dayCount: 90,
            calendar: calendar
        )
        let contributionCalendar = ReadingContributionCalendar(calendar: calendar)
        let weeks = contributionCalendar.weeks(
            activities: activities,
            visibleWeekCount: visibleWeekCount(for: activities, contributionCalendar: contributionCalendar),
            endingAt: activities.last?.date
        )
        let markers = contributionCalendar.monthMarkers(for: weeks)

        assertConsecutiveDates(in: weeks, calendar: calendar)
        assertNoDuplicateDates(in: weeks)
        assertMonthMarkersAlign(markers, weeks: weeks, calendar: calendar)

        let januaryFirst = day(2026, 1, 1, calendar: calendar)
        let januaryMarker = markers.first { $0.date == januaryFirst }
        XCTAssertNotNil(januaryMarker)
        if let januaryMarker {
            XCTAssertTrue(weeks[januaryMarker.columnIndex].days.map(\.date).contains(januaryFirst))
        }
    }

    func testContributionCalendarUsesFullCurrentWeekWhenTodayIsMidweek() {
        let calendar = gregorianUTC()
        let contributionCalendar = ReadingContributionCalendar(calendar: calendar)
        let weeks = contributionCalendar.weeks(
            activities: contributionActivities(
                endingAt: date("2026-05-06T12:00:00Z"),
                dayCount: 7,
                calendar: calendar
            ),
            visibleWeekCount: 1,
            endingAt: date("2026-05-06T12:00:00Z")
        )

        XCTAssertEqual(weeks.first?.days.map(\.date), [
            day(2026, 5, 3, calendar: calendar),
            day(2026, 5, 4, calendar: calendar),
            day(2026, 5, 5, calendar: calendar),
            day(2026, 5, 6, calendar: calendar),
            day(2026, 5, 7, calendar: calendar),
            day(2026, 5, 8, calendar: calendar),
            day(2026, 5, 9, calendar: calendar)
        ])
    }

    func testContributionCalendarKeepsSundayRowsWhenCalendarFirstWeekdayDiffers() {
        var calendar = gregorianUTC()
        calendar.firstWeekday = 2
        let contributionCalendar = ReadingContributionCalendar(calendar: calendar)

        XCTAssertEqual(
            contributionCalendar.weekStart(containing: date("2026-05-06T12:00:00Z")),
            day(2026, 5, 3, calendar: calendar)
        )
        XCTAssertEqual((0..<ReadingContributionCalendar.rowsPerWeek).map { contributionCalendar.weekdayLabel(for: $0) }, [
            "",
            "Mon",
            "",
            "Wed",
            "",
            "Fri",
            ""
        ])
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

    private func day(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))!
    }

    private func contributionActivities(
        endingAt endDate: Date,
        dayCount: Int,
        calendar: Calendar
    ) -> [ReadingDayActivity] {
        ReadingDayActivity.recentDays(
            from: [],
            dailyGoalWords: 1_000,
            dayCount: dayCount,
            endingAt: endDate,
            calendar: calendar
        )
    }

    private func visibleWeekCount(
        for activities: [ReadingDayActivity],
        contributionCalendar: ReadingContributionCalendar
    ) -> Int {
        guard let firstDate = activities.first?.date,
              let lastDate = activities.last?.date else {
            return 1
        }

        let firstWeekStart = contributionCalendar.weekStart(containing: firstDate)
        let lastWeekStart = contributionCalendar.weekStart(containing: lastDate)
        let daySpan = contributionCalendar.calendar.dateComponents(
            [.day],
            from: firstWeekStart,
            to: lastWeekStart
        ).day ?? 0
        return max(daySpan / ReadingContributionCalendar.rowsPerWeek + 1, 1)
    }

    private func gridDates(in weeks: [ReadingContributionGridWeek]) -> [Date] {
        weeks.flatMap { $0.days.map(\.date) }
    }

    private func assertConsecutiveDates(
        in weeks: [ReadingContributionGridWeek],
        calendar: Calendar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let dates = gridDates(in: weeks)
        for index in dates.indices.dropFirst() {
            let previous = dates[dates.index(before: index)]
            let expected = calendar.date(byAdding: .day, value: 1, to: previous)
            XCTAssertEqual(dates[index], expected, file: file, line: line)
        }
    }

    private func assertNoDuplicateDates(
        in weeks: [ReadingContributionGridWeek],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let dates = gridDates(in: weeks)
        XCTAssertEqual(Set(dates).count, dates.count, file: file, line: line)
    }

    private func assertMonthMarkersAlign(
        _ markers: [ReadingContributionMonthMarker],
        weeks: [ReadingContributionGridWeek],
        calendar: Calendar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let firstOfMonthDates = weeks
            .enumerated()
            .flatMap { columnIndex, week in
                week.days
                    .filter { calendar.component(.day, from: $0.date) == 1 }
                    .map { (date: $0.date, columnIndex: columnIndex) }
            }

        XCTAssertEqual(markers.count, firstOfMonthDates.count, file: file, line: line)
        for expected in firstOfMonthDates {
            XCTAssertTrue(
                markers.contains { $0.date == expected.date && $0.columnIndex == expected.columnIndex },
                "Missing month marker for \(expected.date) at column \(expected.columnIndex)",
                file: file,
                line: line
            )
        }
    }
}
