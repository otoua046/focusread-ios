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

                    Text("You're ready to read.")
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
                        Label("Try Sample Text", systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnboardingPrimaryActionButtonStyle())

                    Button {
                        onComplete(.importBook)
                    } label: {
                        Label("Import a Book", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnboardingSecondaryActionButtonStyle())

                    Button(mode == .replay ? "Back to Settings" : "Go to Library") {
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

private struct OnboardingPrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.primaryButtonForeground)
            .padding(.vertical, 15)
            .background(AppTheme.primaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct OnboardingSecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.primaryText)
            .padding(.vertical, 15)
            .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.border.opacity(0.76), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
