import SwiftUI

struct StatsView: View {
    @ObservedObject var statsStore: LocalReadingStatsStore
    @ObservedObject var readingHistoryStore: LocalReadingHistoryStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var widgetColumns: [GridItem] {
        if horizontalSizeClass == .compact {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }

        return [
            GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FocusReadPageHeader(title: "My Stats")

                ReadingActivityWidget(
                    activities: readingActivityDays
                )

                LazyVGrid(columns: widgetColumns, spacing: 12) {
                    DailyProgressMetricWidget(
                        wordsRead: statsStore.snapshot.todayWordsRead,
                        goalWords: statsStore.snapshot.dailyGoalWords,
                        progress: dailyGoalProgress,
                        formattedWords: formattedInteger(statsStore.snapshot.todayWordsRead),
                        formattedGoal: formattedInteger(statsStore.snapshot.dailyGoalWords)
                    )

                    StatsMetricWidget(
                        title: "Daily Streak",
                        value: "\(statsStore.snapshot.currentStreakDays)",
                        detail: longestStreakText,
                        symbolName: "flame.fill"
                    )

                    StatsMetricWidget(
                        title: "Average WPM",
                        value: statsStore.snapshot.averageWPM > 0 ? "\(statsStore.snapshot.averageWPM)" : "--",
                        symbolName: "speedometer"
                    )

                    StatsMetricWidget(
                        title: "Reading Time",
                        value: formattedDuration(statsStore.snapshot.totalReadingSeconds),
                        symbolName: "clock.fill"
                    )

                    StatsMetricWidget(
                        title: "Books Completed",
                        value: "\(statsStore.snapshot.booksCompleted)",
                        symbolName: "checkmark.circle.fill"
                    )

                    StatsMetricWidget(
                        title: "Time Saved",
                        value: formattedDuration(statsStore.snapshot.estimatedTimeSavedSeconds),
                        detail: "vs. normal reading",
                        symbolName: "forward.end.fill"
                    )
                }

                recentDaysSection
            }
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .background(FocusReadBackground())
        .onAppear {
            statsStore.reconcileCompletedReads(from: readingHistoryStore.savedReads)
        }
        .onChange(of: readingHistoryStore.savedReads.map(\.id)) {
            statsStore.reconcileCompletedReads(from: readingHistoryStore.savedReads)
        }
    }

    private var recentDaysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Days")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 2)

            if recentDailyStats.isEmpty {
                Text("Start a reading session to fill in your progress.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 82)
                    .padding(16)
                    .widgetSurface(cornerRadius: 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentDailyStats.enumerated()), id: \.element.id) { index, stat in
                        DailyStatsRow(
                            stat: stat,
                            maxWords: maxRecentWords,
                            formattedWords: formattedInteger(stat.wordsRead),
                            formattedDuration: formattedDuration(stat.readingSeconds),
                            formattedDate: formattedDay(stat.date)
                        )

                        if index < recentDailyStats.count - 1 {
                            Divider()
                                .padding(.leading, 2)
                                .opacity(0.45)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .widgetSurface(cornerRadius: 22)
            }
        }
        .padding(.top, 2)
    }

    private var recentDailyStats: [DailyReadingStats] {
        Array(statsStore.dailyStats.prefix(7))
    }

    private var maxRecentWords: Int {
        max(recentDailyStats.map(\.wordsRead).max() ?? 0, statsStore.snapshot.dailyGoalWords)
    }

    private var readingActivityDays: [ReadingDayActivity] {
        ReadingDayActivity.recentDays(
            from: statsStore.dailyStats,
            dailyGoalWords: statsStore.snapshot.dailyGoalWords
        )
    }

    private var dailyGoalProgress: Double {
        guard statsStore.snapshot.dailyGoalWords > 0 else { return 0 }
        return min(Double(statsStore.snapshot.todayWordsRead) / Double(statsStore.snapshot.dailyGoalWords), 1)
    }

    private var longestStreakText: String? {
        guard statsStore.snapshot.longestStreakDays > 0 else { return nil }
        return "Best \(statsStore.snapshot.longestStreakDays)"
    }

    private func formattedInteger(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let seconds = Int(seconds.rounded())
        guard seconds > 0 else { return "0m" }

        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }

    private func formattedDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

private struct ReadingActivityWidget: View {
    let activities: [ReadingDayActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Reading Activity")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)

                Text("Daily words read")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            ReadingContributionGrid(activities: activities)
                .frame(maxWidth: .infinity)
                .frame(height: 124)

            HStack(spacing: 6) {
                Text("Less")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.tertiaryText)

                ForEach(0...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(StatsWidgetStyle.contributionColor(for: level))
                        .frame(width: 11, height: 11)
                }

                Text("More")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 218)
        .widgetSurface(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading Activity, daily words read contribution grid")
    }
}

struct ReadingContributionGrid: View {
    let activities: [ReadingDayActivity]

    private let rows = 7
    private let spacing: CGFloat = 4
    private let maximumSquareSize: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let columns = activityColumns
            let squareSize = squareSize(
                availableWidth: proxy.size.width,
                availableHeight: proxy.size.height,
                columnCount: columns.count
            )
            let gridHeight = CGFloat(rows) * squareSize + CGFloat(rows - 1) * spacing

            HStack(alignment: .top, spacing: spacing) {
                ForEach(columns.indices, id: \.self) { columnIndex in
                    VStack(spacing: spacing) {
                        ForEach(columns[columnIndex]) { activity in
                            RoundedRectangle(cornerRadius: max(squareSize * 0.26, 2), style: .continuous)
                                .fill(StatsWidgetStyle.contributionColor(for: activity.intensityLevel))
                                .frame(width: squareSize, height: squareSize)
                                .accessibilityLabel(accessibilityLabel(for: activity))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: gridHeight, alignment: .center)
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private var activityColumns: [[ReadingDayActivity]] {
        stride(from: 0, to: activities.count, by: rows).map { startIndex in
            let endIndex = min(startIndex + rows, activities.count)
            return Array(activities[startIndex..<endIndex])
        }
    }

    private func squareSize(availableWidth: CGFloat, availableHeight: CGFloat, columnCount: Int) -> CGFloat {
        let safeColumnCount = max(columnCount, 1)
        let widthDrivenSize = (availableWidth - CGFloat(safeColumnCount - 1) * spacing) / CGFloat(safeColumnCount)
        let heightDrivenSize = (availableHeight - CGFloat(rows - 1) * spacing) / CGFloat(rows)
        return max(6, min(maximumSquareSize, floor(min(widthDrivenSize, heightDrivenSize))))
    }

    private func accessibilityLabel(for activity: ReadingDayActivity) -> String {
        let formattedDate = activity.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return "\(formattedDate), \(activity.wordsRead) words read"
    }
}

private struct DailyProgressMetricWidget: View {
    let wordsRead: Int
    let goalWords: Int
    let progress: Double
    let formattedWords: String
    let formattedGoal: String

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(StatsWidgetStyle.ringTrack, lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        StatsWidgetStyle.accent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(Int((progress * 100).rounded()))%")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            Text("\(formattedWords) / \(formattedGoal)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .monospacedDigit()

            Text("Daily Progress")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .center)
        .padding(14)
        .widgetSurface(cornerRadius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily Progress, \(wordsRead) of \(goalWords) words")
    }
}

private struct StatsMetricWidget: View {
    let title: String
    let value: String
    var detail: String? = nil
    let symbolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StatsWidgetStyle.accent)
                .frame(width: 30, height: 30)
                .background(StatsWidgetStyle.iconBackground, in: Circle())

            Spacer(minLength: 12)

            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .monospacedDigit()

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail ?? " ")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .leading)
        .padding(14)
        .widgetSurface(cornerRadius: 22)
    }
}

private struct DailyStatsRow: View {
    let stat: DailyReadingStats
    let maxWords: Int
    let formattedWords: String
    let formattedDuration: String
    let formattedDate: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedDate)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("\(formattedWords) words")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .monospacedDigit()
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(StatsWidgetStyle.ringTrack)

                        Capsule()
                            .fill(StatsWidgetStyle.accent)
                            .frame(width: proxy.size.width * barProgress)
                    }
                }
                .frame(height: 6)

                HStack(spacing: 10) {
                    Label(formattedDuration, systemImage: "clock")
                    Label("\(stat.sessionsCount)", systemImage: "play.circle")
                    if stat.completedBooksCount > 0 {
                        Label("\(stat.completedBooksCount)", systemImage: "checkmark.circle")
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.tertiaryText)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 9)
    }

    private var barProgress: Double {
        guard maxWords > 0 else { return 0 }
        return min(Double(stat.wordsRead) / Double(maxWords), 1)
    }
}

private extension View {
    func widgetSurface(cornerRadius: CGFloat) -> some View {
        modifier(StatsWidgetSurface(cornerRadius: cornerRadius))
    }
}

private enum StatsWidgetStyle {
    static let accent = AppTheme.accent
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let iconBackground = Color(uiColor: .systemGray5)
    static let ringTrack = Color(uiColor: .systemGray5)
    static let stroke = Color(uiColor: .separator)

    static func contributionColor(for level: Int) -> Color {
        switch level {
        case 1:
            return accent.opacity(0.28)
        case 2:
            return accent.opacity(0.46)
        case 3:
            return accent.opacity(0.68)
        case 4:
            return accent
        default:
            return Color(uiColor: .systemGray5)
        }
    }
}

private struct StatsWidgetSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(StatsWidgetStyle.surface, in: shape)
            .overlay {
                shape.strokeBorder(
                    StatsWidgetStyle.stroke.opacity(colorScheme == .light ? 0.42 : 0.22),
                    lineWidth: 0.75
                )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .light ? 0.07 : 0),
                radius: 6,
                x: 0,
                y: 3
            )
    }
}

#if DEBUG
private extension ReadingDayActivity {
    static func previewActivities(dayCount: Int = 91, dailyGoalWords: Int = 2_200) -> [ReadingDayActivity] {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()

        return (0..<dayCount).reversed().compactMap { offset in
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

            return ReadingDayActivity(
                date: date,
                wordsRead: wordsRead,
                dailyGoalWords: dailyGoalWords,
                calendar: calendar
            )
        }
    }
}

#Preview("Reading Activity - No Data") {
    ReadingActivityWidget(
        activities: ReadingDayActivity.previewActivities().map {
            ReadingDayActivity(date: $0.date, wordsRead: 0, dailyGoalWords: 2_200)
        }
    )
    .padding(20)
    .background(FocusReadBackground())
}

#Preview("Reading Activity - 90 Days") {
    ReadingActivityWidget(
        activities: ReadingDayActivity.previewActivities()
    )
    .padding(20)
    .background(FocusReadBackground())
}

#Preview("Daily Progress Card") {
    DailyProgressMetricWidget(
        wordsRead: 400,
        goalWords: 2_200,
        progress: 400.0 / 2_200.0,
        formattedWords: "400",
        formattedGoal: "2,200"
    )
    .frame(width: 160)
    .padding(20)
    .background(FocusReadBackground())
}
#endif
