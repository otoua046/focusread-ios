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

        guard let data = defaults?.data(forKey: FocusReadWidgetShared.statsSnapshotKey),
              let snapshot = try? JSONDecoder().decode(FocusReadStatsSnapshot.self, from: data) else {
            return FocusReadWidgetPayload(snapshot: .empty, activityDays: [], themeID: themeID)
        }

        return FocusReadWidgetPayload(
            snapshot: snapshot,
            activityDays: loadActivityDays(from: defaults),
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
