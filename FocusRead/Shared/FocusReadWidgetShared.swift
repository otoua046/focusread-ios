import Foundation

enum FocusReadWidgetShared {
    static let appGroupIdentifier = "group.com.otoua046.app"
    static let statsSnapshotKey = "focusread.widgets.statsSnapshot"
    static let activityDaysKey = "focusread.widgets.activityDays"
    static let themeIDKey = "focusread.widgets.themeID"
    static let defaultThemeID = "classic-gold"
}

struct FocusReadStatsSnapshot: Codable, Equatable, Sendable {
    var totalWordsRead: Int
    var totalReadingSeconds: TimeInterval
    var averageWPM: Int
    var booksCompleted: Int
    var currentStreakDays: Int
    var longestStreakDays: Int
    var dailyGoalWords: Int
    var todayWordsRead: Int
    var estimatedTimeSavedSeconds: TimeInterval
    var lastUpdatedAt: Date

    static let empty = FocusReadStatsSnapshot(
        totalWordsRead: 0,
        totalReadingSeconds: 0,
        averageWPM: 0,
        booksCompleted: 0,
        currentStreakDays: 0,
        longestStreakDays: 0,
        dailyGoalWords: 1_000,
        todayWordsRead: 0,
        estimatedTimeSavedSeconds: 0,
        lastUpdatedAt: Date.distantPast
    )

    func normalizedForWidget(
        activityDays: [FocusReadWidgetActivityDay],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> FocusReadStatsSnapshot {
        let wordsByDay = Dictionary(
            activityDays.map { (calendar.startOfDay(for: $0.date), $0.wordsRead) },
            uniquingKeysWith: +
        )
        let activeDays = Set(
            wordsByDay
                .filter { $0.value > 0 }
                .map(\.key)
        )
        let today = calendar.startOfDay(for: now)

        var snapshot = self
        snapshot.todayWordsRead = wordsByDay[today] ?? 0
        snapshot.currentStreakDays = Self.currentStreakDays(activeDays: activeDays, now: now, calendar: calendar)
        return snapshot
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
}

struct FocusReadWidgetActivityDay: Codable, Equatable, Identifiable, Sendable {
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

        let progress = Double(wordsRead) / Double(max(dailyGoalWords, 1))
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
}

struct FocusReadWidgetPayload: Codable, Equatable, Sendable {
    var snapshot: FocusReadStatsSnapshot
    var activityDays: [FocusReadWidgetActivityDay]
    var themeID: String
}

enum FocusReadWidgetStatsStore {
    static func loadPayload() -> FocusReadWidgetPayload {
        let defaults = sharedDefaults
        let themeID = defaults?.string(forKey: FocusReadWidgetShared.themeIDKey)
            ?? FocusReadWidgetShared.defaultThemeID

        let activityDays = loadActivityDays(from: defaults)

        guard let data = defaults?.data(forKey: FocusReadWidgetShared.statsSnapshotKey),
              let snapshot = try? JSONDecoder().decode(FocusReadStatsSnapshot.self, from: data) else {
            return FocusReadWidgetPayload(snapshot: .empty, activityDays: [], themeID: themeID)
        }

        return FocusReadWidgetPayload(
            snapshot: snapshot.normalizedForWidget(activityDays: activityDays),
            activityDays: activityDays,
            themeID: themeID
        )
    }

    static func save(snapshot: FocusReadStatsSnapshot) {
        guard let defaults = sharedDefaults,
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: FocusReadWidgetShared.statsSnapshotKey)
    }

    static func saveActivityDays(_ activityDays: [FocusReadWidgetActivityDay]) {
        guard let defaults = sharedDefaults,
              let data = try? JSONEncoder().encode(activityDays) else {
            return
        }

        defaults.set(data, forKey: FocusReadWidgetShared.activityDaysKey)
    }

    static func saveThemeID(_ themeID: String) {
        sharedDefaults?.set(themeID, forKey: FocusReadWidgetShared.themeIDKey)
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: FocusReadWidgetShared.appGroupIdentifier)
    }

    private static func loadActivityDays(from defaults: UserDefaults?) -> [FocusReadWidgetActivityDay] {
        guard let data = defaults?.data(forKey: FocusReadWidgetShared.activityDaysKey),
              let activityDays = try? JSONDecoder().decode([FocusReadWidgetActivityDay].self, from: data) else {
            return []
        }

        return activityDays
    }
}
