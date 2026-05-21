import SwiftUI

struct OnboardingFinishView: View {
    let mode: FocusReadOnboardingMode
    let onComplete: (FocusReadOnboardingCompletionAction) -> Void

    var body: some View {
        OnboardingCenteredStep {
            VStack(spacing: 28) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.14))
                            .frame(width: 104, height: 104)

                        Image(systemName: "checkmark")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }

                    Text(.onboardingFinishTitle)
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }

                VStack(spacing: 12) {
                    Button {
                        onComplete(.trySampleText)
                    } label: {
                        Label(.onboardingTrySampleText, systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.focusReadProminentAction())

                    Button {
                        onComplete(.importBook)
                    } label: {
                        Label(.onboardingImportBook, systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.focusReadSecondaryAction())

                    Button(mode == .replay ? L10n.string(.onboardingBackToSettings) : L10n.string(.onboardingGoToLibrary)) {
                        onComplete(.showLibrary)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: 420)
            }
        }
    }
}
