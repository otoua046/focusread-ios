import SwiftUI
import WidgetKit

struct FocusReadStatsEntry: TimelineEntry {
    let date: Date
    let snapshot: FocusReadStatsSnapshot
    let activityDays: [FocusReadWidgetActivityDay]
    let themeID: String
}

struct FocusReadStatsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusReadStatsEntry {
        FocusReadStatsEntry(
            date: Date(),
            snapshot: .preview,
            activityDays: .preview,
            themeID: FocusReadWidgetShared.defaultThemeID
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusReadStatsEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(entry(from: FocusReadWidgetStatsStore.loadPayload()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusReadStatsEntry>) -> Void) {
        let entry = entry(from: FocusReadWidgetStatsStore.loadPayload())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func entry(from payload: FocusReadWidgetPayload) -> FocusReadStatsEntry {
        FocusReadStatsEntry(
            date: Date(),
            snapshot: payload.snapshot,
            activityDays: payload.activityDays,
            themeID: payload.themeID
        )
    }
}

struct FocusReadMetricWidget: Widget {
    let metric: FocusReadStatsMetric

    init() {
        metric = .dailyProgress
    }

    init(metric: FocusReadStatsMetric) {
        self.metric = metric
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: metric.kind, provider: FocusReadStatsTimelineProvider()) { entry in
            FocusReadStatsWidgetView(entry: entry, primaryMetric: metric)
        }
        .configurationDisplayName(metric.title)
        .description(metric.widgetDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct FocusReadReadingActivityWidget: Widget {
    private let kind = "FocusReadReadingActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FocusReadStatsTimelineProvider()) { entry in
            FocusReadReadingActivityWidgetView(entry: entry)
        }
        .configurationDisplayName("Reading Activity")
        .description("Show your FocusRead reading activity grid.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private extension FocusReadStatsSnapshot {
    static let preview = FocusReadStatsSnapshot(
        totalWordsRead: 18_420,
        totalReadingSeconds: 5_820,
        averageWPM: 420,
        booksCompleted: 7,
        currentStreakDays: 9,
        longestStreakDays: 21,
        dailyGoalWords: 2_400,
        todayWordsRead: 790,
        estimatedTimeSavedSeconds: 2_460,
        lastUpdatedAt: Date()
    )
}

private extension Array where Element == FocusReadWidgetActivityDay {
    static var preview: [FocusReadWidgetActivityDay] {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()

        return (0..<120).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }

            let wordsRead: Int
            switch offset % 11 {
            case 0:
                wordsRead = 2_500
            case 1, 5:
                wordsRead = 1_500
            case 2, 6, 9:
                wordsRead = 760
            case 3, 8:
                wordsRead = 240
            default:
                wordsRead = 0
            }

            return FocusReadWidgetActivityDay(
                date: date,
                wordsRead: wordsRead,
                dailyGoalWords: 2_400,
                calendar: calendar
            )
        }
    }
}

#if DEBUG
#Preview("Daily Progress", as: .systemSmall) {
    FocusReadMetricWidget(metric: .dailyProgress)
} timeline: {
    FocusReadStatsEntry(date: Date(), snapshot: .preview, activityDays: .preview, themeID: FocusReadWidgetShared.defaultThemeID)
}

#Preview("Daily Streak", as: .systemSmall) {
    FocusReadMetricWidget(metric: .dailyStreak)
} timeline: {
    FocusReadStatsEntry(date: Date(), snapshot: .preview, activityDays: .preview, themeID: FocusReadWidgetShared.defaultThemeID)
}

#Preview("Average WPM", as: .systemSmall) {
    FocusReadMetricWidget(metric: .averageWPM)
} timeline: {
    FocusReadStatsEntry(date: Date(), snapshot: .preview, activityDays: .preview, themeID: FocusReadWidgetShared.defaultThemeID)
}

#Preview("Reading Time", as: .systemSmall) {
    FocusReadMetricWidget(metric: .readingTime)
} timeline: {
    FocusReadStatsEntry(date: Date(), snapshot: .preview, activityDays: .preview, themeID: FocusReadWidgetShared.defaultThemeID)
}

#Preview("Books Completed", as: .systemSmall) {
    FocusReadMetricWidget(metric: .booksCompleted)
} timeline: {
    FocusReadStatsEntry(date: Date(), snapshot: .preview, activityDays: .preview, themeID: FocusReadWidgetShared.defaultThemeID)
}

#Preview("Time Saved", as: .systemSmall) {
    FocusReadMetricWidget(metric: .timeSaved)
} timeline: {
    FocusReadStatsEntry(date: Date(), snapshot: .preview, activityDays: .preview, themeID: FocusReadWidgetShared.defaultThemeID)
}

#Preview("Stats Pair", as: .systemMedium) {
    FocusReadMetricWidget(metric: .dailyProgress)
} timeline: {
    FocusReadStatsEntry(date: Date(), snapshot: .preview, activityDays: .preview, themeID: FocusReadWidgetShared.defaultThemeID)
}

#Preview("Stats Dashboard", as: .systemLarge) {
    FocusReadMetricWidget(metric: .dailyProgress)
} timeline: {
    FocusReadStatsEntry(date: Date(), snapshot: .preview, activityDays: .preview, themeID: FocusReadWidgetShared.defaultThemeID)
}

#Preview("Reading Activity", as: .systemMedium) {
    FocusReadReadingActivityWidget()
} timeline: {
    FocusReadStatsEntry(date: Date(), snapshot: .preview, activityDays: .preview, themeID: FocusReadWidgetShared.defaultThemeID)
}
#endif
