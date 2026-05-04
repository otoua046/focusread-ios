import Foundation

struct ReadingStatsSnapshot: Codable, Equatable, Sendable {
    var totalWordsRead: Int
    var totalReadingSeconds: TimeInterval
    var averageWPM: Int
    var booksCompleted: Int
    var currentStreakDays: Int
    var longestStreakDays: Int
    var dailyGoalWords: Int
    var todayWordsRead: Int
    var estimatedTimeSavedSeconds: TimeInterval
    var lastReadDate: Date?

    static let defaultDailyGoalWords = 1_000

    static let empty = ReadingStatsSnapshot(
        totalWordsRead: 0,
        totalReadingSeconds: 0,
        averageWPM: 0,
        booksCompleted: 0,
        currentStreakDays: 0,
        longestStreakDays: 0,
        dailyGoalWords: defaultDailyGoalWords,
        todayWordsRead: 0,
        estimatedTimeSavedSeconds: 0,
        lastReadDate: nil
    )
}

struct DailyReadingStats: Identifiable, Codable, Equatable, Sendable {
    var id: Date { date }

    var date: Date
    var wordsRead: Int
    var readingSeconds: TimeInterval
    var sessionsCount: Int
    var completedBooksCount: Int
}

struct ReadingDayActivity: Identifiable, Equatable, Sendable {
    var id: Date { date }

    var date: Date
    var wordsRead: Int
    var intensityLevel: Int

    init(date: Date, wordsRead: Int, dailyGoalWords: Int, calendar: Calendar = .autoupdatingCurrent) {
        self.date = calendar.startOfDay(for: date)
        self.wordsRead = max(wordsRead, 0)
        self.intensityLevel = Self.intensityLevel(wordsRead: wordsRead, dailyGoalWords: dailyGoalWords)
    }

    static func intensityLevel(wordsRead: Int, dailyGoalWords: Int) -> Int {
        guard wordsRead > 0 else { return 0 }

        let goal = max(dailyGoalWords, 1)
        let progress = Double(wordsRead) / Double(goal)

        if progress < 0.25 {
            return 1
        }
        if progress < 0.5 {
            return 2
        }
        if progress < 1 {
            return 3
        }
        return 4
    }

    static func recentDays(
        from dailyStats: [DailyReadingStats],
        dailyGoalWords: Int,
        dayCount: Int = 91,
        endingAt endDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ReadingDayActivity] {
        let safeDayCount = max(dayCount, 1)
        let normalizedEndDate = calendar.startOfDay(for: endDate)
        let statsByDay = Dictionary(
            dailyStats.map { (calendar.startOfDay(for: $0.date), max($0.wordsRead, 0)) },
            uniquingKeysWith: +
        )

        return (0..<safeDayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: normalizedEndDate) else {
                return nil
            }

            return ReadingDayActivity(
                date: date,
                wordsRead: statsByDay[date] ?? 0,
                dailyGoalWords: dailyGoalWords,
                calendar: calendar
            )
        }
    }
}

struct ReadingSessionEvent: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var readID: UUID
    var startedAt: Date
    var endedAt: Date
    var wordsRead: Int
    var averageWPM: Int

    init(
        id: UUID = UUID(),
        readID: UUID,
        startedAt: Date,
        endedAt: Date,
        wordsRead: Int,
        averageWPM: Int
    ) {
        self.id = id
        self.readID = readID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.wordsRead = max(wordsRead, 0)
        self.averageWPM = ReadingSession.clampWPM(averageWPM)
    }

    var readingSeconds: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
    }
}

enum ReadingStatsCalculator {
    static let normalReadingWPM = 238

    static func snapshot(
        dailyStats: [DailyReadingStats],
        sessionEvents: [ReadingSessionEvent],
        completedReadIDs: Set<UUID>,
        dailyGoalWords: Int,
        calendar: Calendar,
        now: Date
    ) -> ReadingStatsSnapshot {
        let normalizedDailyStats = dailyStats.map { stat in
            DailyReadingStats(
                date: calendar.startOfDay(for: stat.date),
                wordsRead: max(stat.wordsRead, 0),
                readingSeconds: max(stat.readingSeconds, 0),
                sessionsCount: max(stat.sessionsCount, 0),
                completedBooksCount: max(stat.completedBooksCount, 0)
            )
        }

        let totalWordsRead = normalizedDailyStats.reduce(0) { $0 + $1.wordsRead }
        let totalReadingSeconds = normalizedDailyStats.reduce(0) { $0 + $1.readingSeconds }
        let averageWPM = weightedAverageWPM(from: sessionEvents)
            ?? effectiveAverageWPM(totalWordsRead: totalWordsRead, totalReadingSeconds: totalReadingSeconds)
        let todayStart = calendar.startOfDay(for: now)
        let todayWordsRead = normalizedDailyStats.first { calendar.isDate($0.date, inSameDayAs: todayStart) }?.wordsRead ?? 0
        let activeReadingDays = Set(
            normalizedDailyStats
                .filter { $0.wordsRead > 0 }
                .map { calendar.startOfDay(for: $0.date) }
        )

        let normalReadingSeconds = Double(totalWordsRead) / Double(normalReadingWPM) * 60
        let lastReadDate = sessionEvents
            .filter { $0.wordsRead > 0 }
            .map(\.endedAt)
            .max()
            ?? normalizedDailyStats
                .filter { $0.wordsRead > 0 }
                .map(\.date)
                .max()

        return ReadingStatsSnapshot(
            totalWordsRead: totalWordsRead,
            totalReadingSeconds: totalReadingSeconds,
            averageWPM: averageWPM,
            booksCompleted: completedReadIDs.count,
            currentStreakDays: currentStreakDays(activeDays: activeReadingDays, now: now, calendar: calendar),
            longestStreakDays: longestStreakDays(activeDays: activeReadingDays, calendar: calendar),
            dailyGoalWords: max(dailyGoalWords, 1),
            todayWordsRead: todayWordsRead,
            estimatedTimeSavedSeconds: max(normalReadingSeconds - totalReadingSeconds, 0),
            lastReadDate: lastReadDate
        )
    }

    private static func weightedAverageWPM(from events: [ReadingSessionEvent]) -> Int? {
        let weighted = events.reduce((words: 0, weightedWPM: 0)) { result, event in
            let words = max(event.wordsRead, 0)
            return (
                words: result.words + words,
                weightedWPM: result.weightedWPM + words * event.averageWPM
            )
        }

        guard weighted.words > 0 else { return nil }
        return Int((Double(weighted.weightedWPM) / Double(weighted.words)).rounded())
    }

    private static func effectiveAverageWPM(totalWordsRead: Int, totalReadingSeconds: TimeInterval) -> Int {
        guard totalWordsRead > 0, totalReadingSeconds > 0 else { return 0 }
        return Int((Double(totalWordsRead) / totalReadingSeconds * 60).rounded())
    }

    private static func currentStreakDays(activeDays: Set<Date>, now: Date, calendar: Calendar) -> Int {
        guard !activeDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let streakEnd: Date
        if activeDays.contains(today) {
            streakEnd = today
        } else if activeDays.contains(yesterday) {
            streakEnd = yesterday
        } else {
            return 0
        }

        var count = 0
        var cursor = streakEnd
        while activeDays.contains(cursor) {
            count += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }
        return count
    }

    private static func longestStreakDays(activeDays: Set<Date>, calendar: Calendar) -> Int {
        let days = activeDays.sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for index in days.indices.dropFirst() {
            let previous = days[days.index(before: index)]
            let day = days[index]
            if let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(expected, inSameDayAs: day) {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
        }

        return longest
    }
}
