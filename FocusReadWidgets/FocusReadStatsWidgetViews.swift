import SwiftUI
import WidgetKit

enum FocusReadStatsMetric: CaseIterable, Identifiable {
    case dailyProgress
    case dailyStreak
    case averageWPM
    case readingTime
    case booksCompleted
    case timeSaved

    var id: String { kind }

    var kind: String {
        switch self {
        case .dailyProgress:
            return "FocusReadDailyProgressWidget"
        case .dailyStreak:
            return "FocusReadDailyStreakWidget"
        case .averageWPM:
            return "FocusReadAverageWPMWidget"
        case .readingTime:
            return "FocusReadReadingTimeWidget"
        case .booksCompleted:
            return "FocusReadBooksCompletedWidget"
        case .timeSaved:
            return "FocusReadTimeSavedWidget"
        }
    }

    var title: String {
        switch self {
        case .dailyProgress:
            return "Daily Progress"
        case .dailyStreak:
            return "Daily Streak"
        case .averageWPM:
            return "Average WPM"
        case .readingTime:
            return "Reading Time"
        case .booksCompleted:
            return "Books Completed"
        case .timeSaved:
            return "Time Saved"
        }
    }

    var widgetDescription: String {
        "Show your FocusRead \(title.lowercased()) stat."
    }

    var symbolName: String? {
        switch self {
        case .dailyProgress:
            return nil
        case .dailyStreak:
            return "flame.fill"
        case .averageWPM:
            return "speedometer"
        case .readingTime:
            return "clock.fill"
        case .booksCompleted:
            return "checkmark.circle.fill"
        case .timeSaved:
            return "forward.end.fill"
        }
    }

    var companion: FocusReadStatsMetric {
        switch self {
        case .dailyProgress:
            return .dailyStreak
        case .dailyStreak:
            return .dailyProgress
        case .averageWPM:
            return .readingTime
        case .readingTime:
            return .averageWPM
        case .booksCompleted:
            return .timeSaved
        case .timeSaved:
            return .booksCompleted
        }
    }

    var isProgress: Bool {
        self == .dailyProgress
    }
}

struct FocusReadStatsWidgetView: View {
    let entry: FocusReadStatsEntry
    let primaryMetric: FocusReadStatsMetric
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme

    private var theme: FocusReadWidgetTheme {
        FocusReadWidgetTheme(themeID: entry.themeID, colorScheme: colorScheme)
    }

    var body: some View {
        Group {
            switch widgetFamily {
            case .systemSmall:
                FocusReadWidgetStatCard(
                    metric: primaryMetric,
                    snapshot: entry.snapshot,
                    theme: theme,
                    layout: .small
                )
            case .systemMedium:
                HStack(spacing: 8) {
                    FocusReadWidgetStatCard(
                        metric: primaryMetric,
                        snapshot: entry.snapshot,
                        theme: theme,
                        layout: .medium
                    )

                    FocusReadWidgetStatCard(
                        metric: primaryMetric.companion,
                        snapshot: entry.snapshot,
                        theme: theme,
                        layout: .medium
                    )
                }
            case .systemLarge:
                FocusReadWidgetDashboard(snapshot: entry.snapshot, theme: theme)
            default:
                FocusReadWidgetStatCard(
                    metric: primaryMetric,
                    snapshot: entry.snapshot,
                    theme: theme,
                    layout: .small
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(contentPadding)
        .containerBackground(for: .widget) {
            theme.background
        }
    }

    private var contentPadding: CGFloat {
        switch widgetFamily {
        case .systemSmall:
            return 6
        case .systemMedium:
            return 8
        case .systemLarge:
            return 10
        default:
            return 6
        }
    }
}

struct FocusReadReadingActivityWidgetView: View {
    let entry: FocusReadStatsEntry
    @Environment(\.colorScheme) private var colorScheme

    private var theme: FocusReadWidgetTheme {
        FocusReadWidgetTheme(themeID: entry.themeID, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Reading Activity")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 8)

                FocusReadWidgetContributionLegend(theme: theme)
            }

            FocusReadWidgetContributionGrid(activityDays: entry.activityDays, theme: theme)
                .frame(maxWidth: .infinity)
                .frame(height: 76)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.border.opacity(theme.isDark ? 0.22 : 0.42), lineWidth: 0.75)
        }
        .shadow(color: theme.shadow, radius: 6, x: 0, y: 3)
        .padding(6)
        .containerBackground(for: .widget) {
            theme.background
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading Activity, daily words read contribution grid")
    }
}

private struct FocusReadWidgetContributionLegend: View {
    let theme: FocusReadWidgetTheme

    var body: some View {
        HStack(spacing: 3) {
            Text("Less")

            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.contributionColor(for: level))
                    .frame(width: 7, height: 7)
            }

            Text("More")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(theme.tertiaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct FocusReadWidgetContributionGrid: View {
    let activityDays: [FocusReadWidgetActivityDay]
    let theme: FocusReadWidgetTheme

    private let rows = 7

    var body: some View {
        GeometryReader { proxy in
            let layout = contributionLayout(availableSize: proxy.size)

            HStack(alignment: .top, spacing: layout.cellSpacing) {
                ForEach(layout.columns.indices, id: \.self) { columnIndex in
                    VStack(spacing: layout.cellSpacing) {
                        ForEach(layout.columns[columnIndex].indices, id: \.self) { rowIndex in
                            RoundedRectangle(
                                cornerRadius: max(layout.cellSize * 0.24, 1.75),
                                style: .continuous
                            )
                            .fill(theme.contributionColor(for: layout.columns[columnIndex][rowIndex].intensityLevel))
                            .frame(width: layout.cellSize, height: layout.cellSize)
                        }
                    }
                }
            }
            .frame(width: layout.totalWidth, height: layout.totalHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func contributionLayout(availableSize: CGSize) -> FocusReadWidgetContributionLayout {
        let cellSpacing: CGFloat = availableSize.width < 300 ? 2.5 : 3
        let maximumCellSize: CGFloat = 10.5
        let minimumCellSize: CGFloat = 6.5
        let gridWidth = max(availableSize.width, 1)
        let gridHeight = max(availableSize.height, 1)
        let heightDrivenCellSize = normalizedCellSize(
            (gridHeight - CGFloat(rows - 1) * cellSpacing) / CGFloat(rows),
            maximumCellSize: maximumCellSize,
            minimumCellSize: minimumCellSize
        )
        let visibleWeeks = max(Int((gridWidth + cellSpacing) / (heightDrivenCellSize + cellSpacing)), 1)
        let visibleDayCount = visibleWeeks * rows
        let visibleDays = normalizedVisibleDays(count: visibleDayCount)
        let columns = stride(from: 0, to: visibleDays.count, by: rows).map { startIndex in
            Array(visibleDays[startIndex..<min(startIndex + rows, visibleDays.count)])
        }
        let totalWidth = CGFloat(columns.count) * heightDrivenCellSize + CGFloat(max(columns.count - 1, 0)) * cellSpacing
        let totalHeight = CGFloat(rows) * heightDrivenCellSize + CGFloat(rows - 1) * cellSpacing

        return FocusReadWidgetContributionLayout(
            columns: columns,
            cellSize: heightDrivenCellSize,
            cellSpacing: cellSpacing,
            totalWidth: totalWidth,
            totalHeight: totalHeight
        )
    }

    private func normalizedVisibleDays(count: Int) -> [FocusReadWidgetActivityDay] {
        let calendar = Calendar.autoupdatingCurrent
        let endDate = calendar.startOfDay(for: Date())
        let daysByDate = Dictionary(
            activityDays.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        return (0..<max(count, rows)).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: endDate) else {
                return nil
            }

            return daysByDate[date] ?? FocusReadWidgetActivityDay(
                date: date,
                wordsRead: 0,
                dailyGoalWords: 1_000,
                calendar: calendar
            )
        }
    }

    private func normalizedCellSize(
        _ value: CGFloat,
        maximumCellSize: CGFloat,
        minimumCellSize: CGFloat
    ) -> CGFloat {
        let clampedValue = min(maximumCellSize, value)
        let halfPointValue = floor(clampedValue * 2) / 2
        return max(minimumCellSize, halfPointValue)
    }
}

private struct FocusReadWidgetContributionLayout {
    let columns: [[FocusReadWidgetActivityDay]]
    let cellSize: CGFloat
    let cellSpacing: CGFloat
    let totalWidth: CGFloat
    let totalHeight: CGFloat
}

private struct FocusReadWidgetDashboard: View {
    let snapshot: FocusReadStatsSnapshot
    let theme: FocusReadWidgetTheme

    private let rows: [[FocusReadStatsMetric]] = [
        [.dailyProgress, .dailyStreak],
        [.averageWPM, .readingTime],
        [.booksCompleted, .timeSaved]
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 10) {
                    ForEach(rows[rowIndex]) { metric in
                        FocusReadWidgetStatCard(
                            metric: metric,
                            snapshot: snapshot,
                            theme: theme,
                            layout: .large
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FocusReadWidgetStatCard: View {
    let metric: FocusReadStatsMetric
    let snapshot: FocusReadStatsSnapshot
    let theme: FocusReadWidgetTheme
    let layout: FocusReadWidgetCardLayout

    var body: some View {
        Group {
            if metric.isProgress {
                FocusReadWidgetProgressCard(
                    snapshot: snapshot,
                    theme: theme,
                    layout: layout
                )
            } else {
                FocusReadWidgetValueCard(
                    metric: metric,
                    snapshot: snapshot,
                    theme: theme,
                    layout: layout
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: layout.cardHeight, maxHeight: layout.cardHeight ?? .infinity)
        .padding(layout.cardPadding)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .strokeBorder(theme.border.opacity(colorSchemeBorderOpacity), lineWidth: 0.75)
        }
        .shadow(color: theme.shadow, radius: 6, x: 0, y: 3)
    }

    private var colorSchemeBorderOpacity: Double {
        theme.isDark ? 0.22 : 0.42
    }
}

private struct FocusReadWidgetProgressCard: View {
    let snapshot: FocusReadStatsSnapshot
    let theme: FocusReadWidgetTheme
    let layout: FocusReadWidgetCardLayout

    private var progress: Double {
        guard snapshot.dailyGoalWords > 0 else { return 0 }
        return min(Double(snapshot.todayWordsRead) / Double(snapshot.dailyGoalWords), 1)
    }

    var body: some View {
        VStack(spacing: layout.progressSpacing) {
            ZStack {
                Circle()
                    .stroke(theme.ringTrack, lineWidth: layout.ringLineWidth)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        theme.progressIndicator,
                        style: StrokeStyle(lineWidth: layout.ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(Int((progress * 100).rounded()))%")
                    .font(layout.progressPercentFont)
                    .foregroundStyle(theme.primaryText)
                    .monospacedDigit()
                    .minimumScaleFactor(0.78)
            }
            .frame(width: layout.ringSize, height: layout.ringSize)
            .accessibilityHidden(true)

            Text("\(snapshot.todayWordsRead.formattedInteger) / \(snapshot.dailyGoalWords.formattedInteger)")
                .font(layout.secondaryValueFont)
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .monospacedDigit()

            Text(FocusReadStatsMetric.dailyProgress.title)
                .font(layout.labelFont)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily Progress, \(snapshot.todayWordsRead) of \(snapshot.dailyGoalWords) words")
    }
}

private struct FocusReadWidgetValueCard: View {
    let metric: FocusReadStatsMetric
    let snapshot: FocusReadStatsSnapshot
    let theme: FocusReadWidgetTheme
    let layout: FocusReadWidgetCardLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let symbolName = metric.symbolName {
                Image(systemName: symbolName)
                    .font(layout.iconFont)
                    .foregroundStyle(theme.progressIndicator)
                    .frame(width: layout.iconSize, height: layout.iconSize)
                    .background(theme.iconBackground, in: Circle())
                    .accessibilityHidden(true)
            }

            Spacer(minLength: layout.valueTopSpacing)

            Text(value)
                .font(layout.valueFont)
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .monospacedDigit()

            Text(metric.title)
                .font(layout.labelFont)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.64)

            Text(detail ?? " ")
                .font(layout.detailFont)
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var value: String {
        switch metric {
        case .dailyProgress:
            return ""
        case .dailyStreak:
            return "\(snapshot.currentStreakDays)"
        case .averageWPM:
            return snapshot.averageWPM > 0 ? "\(snapshot.averageWPM)" : "--"
        case .readingTime:
            return snapshot.totalReadingSeconds.formattedDuration
        case .booksCompleted:
            return "\(snapshot.booksCompleted)"
        case .timeSaved:
            return snapshot.estimatedTimeSavedSeconds.formattedDuration
        }
    }

    private var detail: String? {
        switch metric {
        case .dailyProgress:
            return nil
        case .dailyStreak:
            guard snapshot.longestStreakDays > 0 else { return nil }
            return "Best \(snapshot.longestStreakDays)"
        case .timeSaved:
            return "vs. normal reading"
        default:
            return nil
        }
    }

    private var accessibilityLabel: String {
        if let detail {
            return "\(metric.title), \(value), \(detail)"
        }
        return "\(metric.title), \(value)"
    }
}

private struct FocusReadWidgetCardLayout {
    let cardHeight: CGFloat?
    let cardPadding: CGFloat
    let cornerRadius: CGFloat
    let iconSize: CGFloat
    let ringSize: CGFloat
    let ringLineWidth: CGFloat
    let progressSpacing: CGFloat
    let valueTopSpacing: CGFloat
    let iconFont: Font
    let valueFont: Font
    let secondaryValueFont: Font
    let progressPercentFont: Font
    let labelFont: Font
    let detailFont: Font

    static let small = FocusReadWidgetCardLayout(
        cardHeight: nil,
        cardPadding: 14,
        cornerRadius: 22,
        iconSize: 30,
        ringSize: 44,
        ringLineWidth: 7,
        progressSpacing: 5,
        valueTopSpacing: 8,
        iconFont: .subheadline.weight(.semibold),
        valueFont: .title2.weight(.semibold),
        secondaryValueFont: .caption.weight(.semibold),
        progressPercentFont: .subheadline.weight(.semibold),
        labelFont: .caption.weight(.semibold),
        detailFont: .caption2.weight(.medium)
    )

    static let medium = FocusReadWidgetCardLayout(
        cardHeight: nil,
        cardPadding: 14,
        cornerRadius: 22,
        iconSize: 30,
        ringSize: 42,
        ringLineWidth: 7,
        progressSpacing: 5,
        valueTopSpacing: 8,
        iconFont: .subheadline.weight(.semibold),
        valueFont: .title2.weight(.semibold),
        secondaryValueFont: .caption.weight(.semibold),
        progressPercentFont: .subheadline.weight(.semibold),
        labelFont: .caption.weight(.semibold),
        detailFont: .caption2.weight(.medium)
    )

    static let large = FocusReadWidgetCardLayout(
        cardHeight: nil,
        cardPadding: 12,
        cornerRadius: 20,
        iconSize: 24,
        ringSize: 34,
        ringLineWidth: 6,
        progressSpacing: 3,
        valueTopSpacing: 5,
        iconFont: .caption.weight(.semibold),
        valueFont: .title3.weight(.semibold),
        secondaryValueFont: .caption2.weight(.semibold),
        progressPercentFont: .caption.weight(.semibold),
        labelFont: .caption.weight(.semibold),
        detailFont: .caption2.weight(.medium)
    )
}

private extension Int {
    var formattedInteger: String {
        formatted(.number.grouping(.automatic))
    }
}

private extension Array where Element == FocusReadWidgetActivityDay {
    static var previewActivityDays: [FocusReadWidgetActivityDay] {
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

private extension TimeInterval {
    var formattedDuration: String {
        let seconds = Int(rounded())
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
}
