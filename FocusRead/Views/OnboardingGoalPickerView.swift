import SwiftUI

struct OnboardingGoalPickerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedGoals: Set<FocusReadReadingGoal>
    @Binding var selectedInterests: Set<FocusReadReadingInterest>

    var body: some View {
        OnboardingStepShell(
            title: L10n.string(.onboardingGoalTitle),
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 24) {
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
                        .accessibilityValue(selectedGoals.contains(goal) ? L10n.string(.commonSelected) : L10n.string(.commonNotSelected))
                    }
                }

                interestPicker
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.14) : .smooth(duration: 0.2), value: selectedGoals)
        .animation(reduceMotion ? .easeInOut(duration: 0.14) : .smooth(duration: 0.2), value: selectedInterests)
        .sensoryFeedback(.selection, trigger: selectedGoals)
        .sensoryFeedback(.selection, trigger: selectedInterests)
    }

    private var interestPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading interests")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 126, maximum: 190), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(FocusReadReadingInterest.allCases) { interest in
                    Button {
                        toggle(interest)
                    } label: {
                        let isSelected = selectedInterests.contains(interest)
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark" : interest.systemImageName)
                                .font(.caption.weight(.bold))
                                .frame(width: 18, height: 18)

                            Text(interest.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                        }
                        .foregroundStyle(isSelected ? AppTheme.primaryButtonForeground : AppTheme.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.horizontal, 12)
                        .background(
                            isSelected ? AppTheme.primaryButtonBackground : AppTheme.controlBackground.opacity(0.86),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(isSelected ? AppTheme.accent.opacity(0.85) : AppTheme.border.opacity(0.6), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selectedInterests.contains(interest) ? L10n.string(.commonSelected) : L10n.string(.commonNotSelected))
                }
            }
        }
    }

    private func toggle(_ goal: FocusReadReadingGoal) {
        if selectedGoals.contains(goal) {
            selectedGoals.remove(goal)
        } else {
            selectedGoals.insert(goal)
        }
    }

    private func toggle(_ interest: FocusReadReadingInterest) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
        } else {
            selectedInterests.insert(interest)
        }
    }
}
