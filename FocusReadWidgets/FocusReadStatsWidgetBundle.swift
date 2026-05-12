import SwiftUI
import WidgetKit

@main
struct FocusReadStatsWidgetBundle: WidgetBundle {
    var body: some Widget {
        FocusReadMetricWidget(metric: .dailyProgress)
        FocusReadMetricWidget(metric: .dailyStreak)
        FocusReadMetricWidget(metric: .averageWPM)
        FocusReadMetricWidget(metric: .readingTime)
        FocusReadMetricWidget(metric: .booksCompleted)
        FocusReadMetricWidget(metric: .timeSaved)
        FocusReadReadingActivityWidget()
    }
}
