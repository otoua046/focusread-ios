import SwiftUI

struct OnboardingAIRecapDemoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealLevel = 0

    private let aiRecapCapabilityService = AIRecapService()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(.onboardingAIRecapTitle)
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.72)

                        Text(.onboardingAIRecapSubtitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 16) {
                        demoBlock(
                            title: L10n.string(.onboardingAIRecapYesterdaySession),
                            systemImage: "clock.arrow.circlepath",
                            isVisible: revealLevel >= 0
                        ) {
                            Text(FocusReadOnboardingSample.passage)
                                .font(.system(.body, design: .serif, weight: .medium))
                                .foregroundStyle(AppTheme.primaryText)
                                .lineSpacing(4)
                                .lineLimit(4)
                        }

                        if revealLevel >= 1 {
                            Image(systemName: "arrow.down")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.92)))
                        }

                        if revealLevel >= 1 {
                            demoBlock(
                                title: L10n.string(.onboardingAIRecapBeforeContinue),
                                systemImage: "sparkles",
                                isVisible: true
                            ) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(FocusReadOnboardingSample.recap)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(AppTheme.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Divider()
                                        .overlay(AppTheme.border.opacity(0.75))

                                    VStack(alignment: .leading, spacing: 10) {
                                        recapIdea(L10n.string(.onboardingAIRecapIdeaCoveredTitle), L10n.string(.onboardingAIRecapIdeaCoveredDetail))
                                        recapIdea(L10n.string(.onboardingAIRecapIdeaNextTitle), L10n.string(.onboardingAIRecapIdeaNextDetail))
                                        recapIdea(L10n.string(.onboardingAIRecapIdeaContinueTitle), L10n.string(.onboardingAIRecapIdeaContinueDetail))
                                    }
                                }
                            }
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                        }

                        if revealLevel >= 2 {
                            demoBlock(
                                title: L10n.string(.onboardingAIRecapContinuity),
                                systemImage: "bookmark",
                                isVisible: true
                            ) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 10) {
                                        Image(systemName: aiRecapCapabilityService.isAvailable ? "checkmark.seal.fill" : "sparkles.rectangle.stack")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.accent)

                                        Text(aiAvailabilityText)
                                            .font(.callout.weight(.medium))
                                            .foregroundStyle(AppTheme.primaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Text(.onboardingAIRecapUseful)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(.onboardingAIRecapPrivacy)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .id("reading-continuity")
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 1.8)) {
                        proxy.scrollTo("reading-continuity", anchor: .bottom)
                    }
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.32), value: revealLevel)
        .task {
            guard !reduceMotion else {
                revealLevel = 2
                return
            }

            for level in 1...2 {
                try? await Task.sleep(for: .milliseconds(820))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    revealLevel = level
                }
            }
        }
    }

    private var aiAvailabilityText: String {
        if aiRecapCapabilityService.isAvailable {
            return L10n.string(.onboardingAIRecapAvailable)
        } else {
            return L10n.string(.onboardingAIRecapSupported)
        }
    }

    private func demoBlock<Content: View>(
        title: String,
        systemImage: String,
        isVisible: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.iconBackground, in: Circle())

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.cardBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
        }
        .opacity(isVisible ? 1 : 0)
    }

    private func recapIdea(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(detail)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
