import SwiftUI

struct StatsView: View {
    @ObservedObject var statsStore: LocalReadingStatsStore
    @ObservedObject var readingHistoryStore: LocalReadingHistoryStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.focusReadTheme) private var theme
    @AppStorage(AppLanguageStorageKey.selectedLanguage) private var selectedLanguageRawValue: String = AppLanguage.systemDefault.rawValue

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
                FocusReadPageHeader(titleKey: .statsTitle)

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
                        title: L10n.string(.statsDailyStreak),
                        value: "\(statsStore.snapshot.currentStreakDays)",
                        detail: longestStreakText,
                        symbolName: "flame.fill"
                    )

                    StatsMetricWidget(
                        title: L10n.string(.statsAverageWPM),
                        value: statsStore.snapshot.averageWPM > 0 ? "\(statsStore.snapshot.averageWPM)" : "--",
                        symbolName: "speedometer"
                    )

                    StatsMetricWidget(
                        title: L10n.string(.statsReadingTime),
                        value: formattedDuration(statsStore.snapshot.totalReadingSeconds),
                        symbolName: "clock.fill"
                    )

                    StatsMetricWidget(
                        title: L10n.string(.statsBooksCompleted),
                        value: "\(statsStore.snapshot.booksCompleted)",
                        symbolName: "checkmark.circle.fill"
                    )

                    StatsMetricWidget(
                        title: L10n.string(.statsTimeSaved),
                        value: formattedDuration(statsStore.snapshot.estimatedTimeSavedSeconds),
                        detail: L10n.string(.statsTimeSavedDetail),
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
        .focusReadLocalizationRefresh()
        .onAppear {
            statsStore.reconcileCompletedReads(from: readingHistoryStore.savedReads)
        }
        .onChange(of: readingHistoryStore.savedReads.map(\.id)) {
            statsStore.reconcileCompletedReads(from: readingHistoryStore.savedReads)
        }
    }

    private var recentDaysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.statsRecentDays)
                .font(.headline)
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 2)

            if recentDailyStats.isEmpty {
                Text(.statsEmptyRecentDays)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
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
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        return statsStore.dailyStats.filter { stat in
            let day = calendar.startOfDay(for: stat.date)
            return day >= sevenDayStart && day <= today
        }
    }

    private var maxRecentWords: Int {
        max(recentDailyStats.map(\.wordsRead).max() ?? 0, statsStore.snapshot.dailyGoalWords)
    }

    private var readingActivityDays: [ReadingDayActivity] {
        ReadingDayActivity.recentDays(
            from: statsStore.dailyStats,
            dailyGoalWords: statsStore.snapshot.dailyGoalWords,
            dayCount: 366
        )
    }

    private var dailyGoalProgress: Double {
        guard statsStore.snapshot.dailyGoalWords > 0 else { return 0 }
        return min(Double(statsStore.snapshot.todayWordsRead) / Double(statsStore.snapshot.dailyGoalWords), 1)
    }

    private var selectedLocale: Locale {
        (AppLanguage(rawValue: selectedLanguageRawValue) ?? .systemDefault).locale
    }

    private var longestStreakText: String? {
        guard statsStore.snapshot.longestStreakDays > 0 else { return nil }
        return L10n.format(.statsBestStreakFormat, statsStore.snapshot.longestStreakDays)
    }

    private func formattedInteger(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(selectedLocale))
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let seconds = Int(seconds.rounded())
        guard seconds > 0 else { return L10n.string(.statsDurationZero) }

        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0, minutes > 0 {
            return L10n.format(.statsDurationHoursMinutesFormat, hours, minutes)
        }
        if hours > 0 {
            return L10n.format(.statsDurationHoursFormat, hours)
        }
        return L10n.format(.statsDurationMinutesFormat, max(minutes, 1))
    }

    private func formattedDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(selectedLocale))
    }
}

private struct ReadingActivityWidget: View {
    let activities: [ReadingDayActivity]
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(.statsReadingActivity)
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 8)

                ContributionLegend()
            }

            ReadingContributionGrid(
                activities: activities,
                compactMode: true,
                showsMonthLabels: true,
                showsWeekdayLabels: true
            )
                .frame(maxWidth: .infinity)
                .frame(height: 106)
        }
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .padding(14)
        .widgetSurface(cornerRadius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string(.statsReadingActivityAccessibility))
    }
}

private struct ContributionLegend: View {
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        HStack(spacing: 3) {
            Text(.statsLess)

            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.contributionColor(for: level))
                    .frame(width: 7, height: 7)
            }

            Text(.statsMore)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(theme.tertiaryText)
        .lineLimit(1)
    }
}

struct ReadingContributionGrid: View {
    let activities: [ReadingDayActivity]
    var compactMode = false
    var showsMonthLabels = false
    var showsWeekdayLabels = false
    @Environment(\.focusReadTheme) private var theme
    @AppStorage(AppLanguageStorageKey.selectedLanguage) private var selectedLanguageRawValue: String = AppLanguage.systemDefault.rawValue

    private let rows = 7

    private var selectedLocale: Locale {
        (AppLanguage(rawValue: selectedLanguageRawValue) ?? .systemDefault).locale
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = contributionLayout(
                availableSize: proxy.size
            )

            VStack(alignment: .leading, spacing: layout.labelGap) {
                if showsMonthLabels {
                    monthLabels(layout: layout)
                }

                HStack(alignment: .top, spacing: layout.weekdayLabelGap) {
                    if showsWeekdayLabels {
                        weekdayLabels(cellSize: layout.cellSize, spacing: layout.cellSpacing)
                    }

                    HStack(alignment: .top, spacing: layout.cellSpacing) {
                        ForEach(layout.columns) { column in
                            VStack(spacing: layout.cellSpacing) {
                                ForEach(column.days) { cell in
                                    RoundedRectangle(
                                        cornerRadius: max(layout.cellSize * 0.24, 1.75),
                                        style: .continuous
                                    )
                                    .fill(theme.contributionColor(for: cell.activity?.intensityLevel ?? 0))
                                    .frame(width: layout.cellSize, height: layout.cellSize)
                                    .accessibilityLabel(accessibilityLabel(for: cell))
                                }
                            }
                        }
                    }
                }
            }
            .frame(
                width: layout.totalWidth,
                height: layout.totalHeight,
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func monthLabels(layout: ContributionGridLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.monthLabels) { label in
                Text(label.text)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize()
                    .offset(x: label.xOffset)
            }
        }
        .frame(
            width: layout.gridWidth,
            height: layout.monthLabelHeight,
            alignment: .topLeading
        )
        .padding(.leading, showsWeekdayLabels ? layout.weekdayLabelWidth + layout.weekdayLabelGap : 0)
    }

    private func weekdayLabels(cellSize: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                Text(weekdayLabel(for: row))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                    .frame(width: 22, height: cellSize, alignment: .trailing)
            }
        }
    }

    private func contributionLayout(availableSize: CGSize) -> ContributionGridLayout {
        let calendar = Calendar.autoupdatingCurrent
        let contributionCalendar = ReadingContributionCalendar(calendar: calendar)
        let cellSpacing: CGFloat = compactMode ? (availableSize.width < 340 ? 2.5 : 3.0) : 4.0
        let maximumCellSize: CGFloat = compactMode ? 11.0 : 14.0
        let minimumCellSize: CGFloat = compactMode ? 7.0 : 6.0
        let weekdayLabelWidth: CGFloat = showsWeekdayLabels ? 24.0 : 0.0
        let weekdayLabelGap: CGFloat = showsWeekdayLabels ? 5.0 : 0.0
        let monthLabelHeight: CGFloat = showsMonthLabels ? 11.0 : 0.0
        let labelGap: CGFloat = showsMonthLabels ? 3.0 : 0.0
        let gridWidth = max(availableSize.width - weekdayLabelWidth - weekdayLabelGap, 1)
        let gridHeight = max(availableSize.height - monthLabelHeight - labelGap, 1)
        let endDate = activities.last?.date ?? Date()
        let latestWeekStart = contributionCalendar.weekStart(containing: endDate)
        let earliestDate = activities.first?.date ?? endDate
        let earliestWeekStart = contributionCalendar.weekStart(containing: earliestDate)
        let availableDaySpan = max(calendar.dateComponents([.day], from: earliestWeekStart, to: latestWeekStart).day ?? 0, 0)
        let availableWeekCount = availableDaySpan / rows + 1
        let heightDrivenCellSize = normalizedCellSize(
            (gridHeight - CGFloat(rows - 1) * cellSpacing) / CGFloat(rows),
            maximumCellSize: maximumCellSize,
            minimumCellSize: minimumCellSize
        )
        let widthDrivenWeekCount = Int((gridWidth + cellSpacing) / (heightDrivenCellSize + cellSpacing))
        let maximumVisibleWeeks = max(widthDrivenWeekCount, 1)
        var visibleWeeks = min(availableWeekCount, maximumVisibleWeeks)

        func resolvedCellSize(weekCount: Int) -> CGFloat {
            let widthDrivenSize = (gridWidth - CGFloat(weekCount - 1) * cellSpacing) / CGFloat(weekCount)
            let heightDrivenSize = (gridHeight - CGFloat(rows - 1) * cellSpacing) / CGFloat(rows)
            return normalizedCellSize(
                min(widthDrivenSize, heightDrivenSize),
                maximumCellSize: maximumCellSize,
                minimumCellSize: minimumCellSize
            )
        }

        var cellSize = resolvedCellSize(weekCount: visibleWeeks)
        while cellSize < minimumCellSize, visibleWeeks > 1 {
            visibleWeeks -= 1
            cellSize = resolvedCellSize(weekCount: visibleWeeks)
        }
        cellSize = max(minimumCellSize, cellSize)

        let columns = contributionCalendar.weeks(
            activities: activities,
            visibleWeekCount: visibleWeeks,
            endingAt: endDate
        )

        let monthLabels = contributionCalendar.monthMarkers(for: columns).map { marker in
                ContributionMonthLayoutLabel(
                    id: marker.date,
                    text: marker.date.formatted(.dateTime.month(.abbreviated).locale(selectedLocale)),
                    xOffset: CGFloat(marker.columnIndex) * (cellSize + cellSpacing)
                )
            }

        let resolvedGridWidth = CGFloat(visibleWeeks) * cellSize + CGFloat(visibleWeeks - 1) * cellSpacing
        let resolvedGridHeight = CGFloat(rows) * cellSize + CGFloat(rows - 1) * cellSpacing
        let totalWidth = resolvedGridWidth + weekdayLabelWidth + weekdayLabelGap
        let totalHeight = resolvedGridHeight + monthLabelHeight + labelGap

        return ContributionGridLayout(
            columns: columns,
            monthLabels: monthLabels,
            cellSize: cellSize,
            cellSpacing: cellSpacing,
            weekdayLabelWidth: weekdayLabelWidth,
            weekdayLabelGap: weekdayLabelGap,
            monthLabelHeight: monthLabelHeight,
            labelGap: labelGap,
            gridWidth: resolvedGridWidth,
            totalWidth: totalWidth,
            totalHeight: totalHeight
        )
    }

    private func weekdayLabel(for row: Int) -> String {
        ReadingContributionCalendar().weekdayLabel(for: row)
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

    private func accessibilityLabel(for cell: ReadingContributionGridDay) -> String {
        let formattedDate = cell.date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(selectedLocale))
        let wordsRead = cell.activity?.wordsRead ?? 0
        return L10n.format(.statsContributionDayAccessibilityFormat, formattedDate, wordsRead)
    }
}

private struct ContributionGridLayout {
    var columns: [ReadingContributionGridWeek]
    var monthLabels: [ContributionMonthLayoutLabel]
    var cellSize: CGFloat
    var cellSpacing: CGFloat
    var weekdayLabelWidth: CGFloat
    var weekdayLabelGap: CGFloat
    var monthLabelHeight: CGFloat
    var labelGap: CGFloat
    var gridWidth: CGFloat
    var totalWidth: CGFloat
    var totalHeight: CGFloat
}

private struct ContributionMonthLayoutLabel: Identifiable {
    var id: Date
    var text: String
    var xOffset: CGFloat
}

private struct DailyProgressMetricWidget: View {
    let wordsRead: Int
    let goalWords: Int
    let progress: Double
    let formattedWords: String
    let formattedGoal: String
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(theme.ringTrack, lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        theme.progressIndicator,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(Int((progress * 100).rounded()))%")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            Text("\(formattedWords) / \(formattedGoal)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .monospacedDigit()

            Text(.statsDailyProgress)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .center)
        .padding(14)
        .widgetSurface(cornerRadius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format(.statsDailyProgressAccessibilityFormat, wordsRead, goalWords))
    }
}

private struct StatsMetricWidget: View {
    let title: String
    let value: String
    var detail: String? = nil
    let symbolName: String
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.progressIndicator)
                .frame(width: 30, height: 30)
                .background(theme.iconBackground, in: Circle())

            Spacer(minLength: 12)

            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .monospacedDigit()

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail ?? " ")
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.tertiaryText)
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
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedDate)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(L10n.format(.statsWordsReadFormat, formattedWords))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .monospacedDigit()
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(theme.ringTrack)

                        Capsule()
                            .fill(theme.progressIndicator)
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
                .foregroundStyle(theme.tertiaryText)
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

private struct StatsWidgetSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.focusReadTheme) private var theme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(theme.cardBackground, in: shape)
            .overlay {
                shape.strokeBorder(
                    theme.border.opacity(colorScheme == .light ? 0.42 : 0.22),
                    lineWidth: 0.75
                )
            }
            .shadow(
                color: theme.subtleShadow.opacity(colorScheme == .light ? 1 : 0),
                radius: 6,
                x: 0,
                y: 3
            )
    }
}

#if DEBUG
private extension ReadingDayActivity {
    static func previewActivities(dayCount: Int = 366, dailyGoalWords: Int = 2_200) -> [ReadingDayActivity] {
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

#Preview("Reading Activity - Calendar Grid") {
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
