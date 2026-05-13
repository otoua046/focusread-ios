import SwiftUI

struct OnboardingGoalPickerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedGoals: Set<FocusReadReadingGoal>

    var body: some View {
        OnboardingStepShell(
            title: "Choose what you read most.",
            subtitle: nil
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 10)],
                spacing: 10
            ) {
                ForEach(FocusReadReadingGoal.allCases) { goal in
                    Button {
                        toggle(goal)
                    } label: {
                        let isSelected = selectedGoals.contains(goal)
                        VStack(spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                Image(systemName: goal.systemImageName)
                                    .font(.system(size: 24, weight: .semibold))
                                    .frame(width: 42, height: 42)
                                    .background(
                                        isSelected ? AppTheme.primaryButtonForeground.opacity(0.16) : AppTheme.iconBackground,
                                        in: Circle()
                                    )

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.primaryButtonForeground)
                                        .background(AppTheme.accent, in: Circle())
                                        .offset(x: 4, y: 4)
                                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                                }
                            }

                            Text(goal.title)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .foregroundStyle(isSelected ? AppTheme.primaryButtonForeground : AppTheme.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 118)
                        .background(
                            isSelected ? AppTheme.primaryButtonBackground : AppTheme.controlBackground,
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(isSelected ? AppTheme.accent.opacity(0.9) : AppTheme.border.opacity(0.68), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selectedGoals.contains(goal) ? "Selected" : "Not selected")
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.14) : .smooth(duration: 0.2), value: selectedGoals)
        .sensoryFeedback(.selection, trigger: selectedGoals)
    }

    private func toggle(_ goal: FocusReadReadingGoal) {
        if selectedGoals.contains(goal) {
            selectedGoals.remove(goal)
        } else {
            selectedGoals.insert(goal)
        }
    }
}
