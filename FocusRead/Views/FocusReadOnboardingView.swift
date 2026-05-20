import SwiftUI
import UIKit

struct FocusReadOnboardingView: View {
    let mode: FocusReadOnboardingMode
    let onComplete: (FocusReadOnboardingCompletionAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.focusReadTheme) private var theme
    @AppStorage(ReaderBehaviorSettingsKey.defaultWPM) private var savedDefaultWPM: Int = ReadingSession.defaultWPM
    @AppStorage(FocusReadOnboardingSettingsKey.selectedReadingGoal) private var selectedGoalRawValue = FocusReadReadingGoal.research.rawValue
    @AppStorage(FocusReadOnboardingSettingsKey.selectedReadingGoals) private var selectedGoalsRawValue = ""
    @AppStorage(FocusReadOnboardingSettingsKey.selectedReadingInterests) private var selectedInterestsRawValue = ""
    @State private var step: FocusReadOnboardingStep = .promise
    @State private var canContinueFromRSVP = false
    @State private var pendingDefaultWPM = ReadingSession.defaultWPM
    @State private var pendingReadingGoals: Set<FocusReadReadingGoal> = [.research]
    @State private var pendingReadingInterests: Set<FocusReadReadingInterest> = []

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                topBar

                ZStack {
                    currentStepView
                        .id(step.id)
                        .transition(stepTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.38), value: step)

                if step != .finish {
                    footer
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(FocusReadBackground().ignoresSafeArea())
        }
        .tint(theme.accent)
        .focusReadThemeRefresh()
        .onAppear {
            pendingDefaultWPM = savedDefaultWPM
            pendingReadingGoals = loadedReadingGoals()
            pendingReadingInterests = loadedReadingInterests()
        }
        .onChange(of: canContinueFromRSVP) { _, canContinue in
            guard canContinue else { return }
            UIAccessibility.post(notification: .announcement, argument: L10n.string(.onboardingDemoCompleteAnnouncement))
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            if step.previous != nil {
                Button {
                    moveBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.focusReadIconControl(tone: .regular, visualSize: 44, tapTargetSize: 44))
                .accessibilityLabel(L10n.string(.onboardingBack))
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }

            progressView

            Button(mode == .replay ? L10n.string(.onboardingClose) : L10n.string(.onboardingSkip)) {
                onComplete(.showLibrary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppTheme.secondaryText)
            .buttonStyle(.plain)
            .frame(width: 60, height: 44, alignment: .trailing)
            .contentShape(Rectangle())
            .accessibilityLabel(mode == .replay ? L10n.string(.onboardingCloseAccessibility) : L10n.string(.onboardingSkipAccessibility))
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var progressView: some View {
        HStack(spacing: 5) {
            ForEach(FocusReadOnboardingStep.allCases) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? AppTheme.accent : AppTheme.border.opacity(0.55))
                    .frame(height: 4)
                    .frame(maxWidth: item == step ? 34 : 14)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format(.onboardingStepProgressFormat, step.progressIndex, FocusReadOnboardingStep.allCases.count))
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch step {
        case .promise:
            OnboardingPromiseView()
        case .rsvpDemo:
            OnboardingRSVPDemoView(canContinue: $canContinueFromRSVP)
                .padding(.horizontal, 18)
        case .comparison:
            OnboardingComparisonView()
                .padding(.horizontal, 18)
        case .wpmSetup:
            OnboardingWPMSetupView(selectedWPM: $pendingDefaultWPM)
                .padding(.horizontal, 18)
        case .readingGoal:
            OnboardingGoalPickerView(
                selectedGoals: $pendingReadingGoals,
                selectedInterests: $pendingReadingInterests
            )
                .padding(.horizontal, 18)
        case .theme:
            OnboardingThemePickerView()
                .padding(.horizontal, 18)
        case .readAnything:
            OnboardingReadAnythingView()
                .padding(.horizontal, 18)
        case .aiRecap:
            OnboardingAIRecapDemoView()
                .padding(.horizontal, 18)
        case .finish:
            OnboardingFinishView(mode: mode, onComplete: onComplete)
                .padding(.horizontal, 18)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button(primaryButtonTitle) {
                moveForward()
            }
            .buttonStyle(.focusReadProminentAction())
            .disabled(!canContinueCurrentStep)
            .opacity(canContinueCurrentStep ? 1 : 0.45)
            .accessibilityHint(continueAccessibilityHint)

            VStack(spacing: 4) {
                if step == .rsvpDemo && !canContinueFromRSVP {
                    Text(.onboardingPlayWordsToContinue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background {
            Rectangle()
                .fill(AppTheme.background.opacity(0.82))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .promise:
            return L10n.string(.onboardingStartDemo)
        case .comparison:
            return L10n.string(.onboardingIGetIt)
        case .wpmSetup, .readingGoal, .theme, .readAnything, .aiRecap, .rsvpDemo:
            return L10n.string(.onboardingContinue)
        case .finish:
            return ""
        }
    }

    private var canContinueCurrentStep: Bool {
        switch step {
        case .rsvpDemo:
            return canContinueFromRSVP
        case .readingGoal:
            return !pendingReadingGoals.isEmpty
        default:
            return true
        }
    }

    private var continueAccessibilityHint: String {
        if step == .rsvpDemo && !canContinueFromRSVP {
            return L10n.string(.onboardingPlayDemoFirstHint)
        }
        if step == .readingGoal && pendingReadingGoals.isEmpty {
            return L10n.string(.onboardingChooseReadingTypeHint)
        }
        return ""
    }

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func moveForward() {
        commitCurrentStepIfNeeded()
        guard let next = step.next else { return }
        if next == .rsvpDemo {
            canContinueFromRSVP = false
        }
        step = next
    }

    private func moveBack() {
        guard let previous = step.previous else { return }
        step = previous
    }

    private func commitCurrentStepIfNeeded() {
        switch step {
        case .wpmSetup:
            savedDefaultWPM = ReadingSession.clampWPM(pendingDefaultWPM)
        case .readingGoal:
            let orderedGoals = FocusReadReadingGoal.allCases.filter { pendingReadingGoals.contains($0) }
            guard !orderedGoals.isEmpty else { return }
            selectedGoalsRawValue = orderedGoals.map(\.rawValue).joined(separator: ",")
            selectedGoalRawValue = orderedGoals.first?.rawValue ?? selectedGoalRawValue
            let orderedInterests = FocusReadReadingInterest.allCases.filter { pendingReadingInterests.contains($0) }
            selectedInterestsRawValue = orderedInterests.map(\.rawValue).joined(separator: ",")
        default:
            break
        }
    }

    private func loadedReadingGoals() -> Set<FocusReadReadingGoal> {
        let goals = selectedGoalsRawValue
            .split(separator: ",")
            .compactMap { FocusReadReadingGoal(rawValue: String($0)) }

        if !goals.isEmpty {
            return Set(goals)
        }

        return [FocusReadReadingGoal(savedRawValue: selectedGoalRawValue)]
    }

    private func loadedReadingInterests() -> Set<FocusReadReadingInterest> {
        let interests = selectedInterestsRawValue
            .split(separator: ",")
            .compactMap { FocusReadReadingInterest(rawValue: String($0)) }
        return Set(interests)
    }
}

struct OnboardingCenteredStep<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack {
                Spacer(minLength: 32)
                content()
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, count: 1, spacing: 0)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }
}

struct OnboardingStepShell<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)

                    if let subtitle {
                        Text(subtitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content()
                    .frame(maxWidth: 620)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }
}

struct OnboardingReadAnythingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedIndex = 0

    private var sources: [OnboardingReadSource] {
        [
            OnboardingReadSource(title: L10n.string(.onboardingReadSourceEPUBTitle), detail: L10n.string(.onboardingReadSourceEPUBDetail), systemImage: "book.closed"),
            OnboardingReadSource(title: L10n.string(.onboardingReadSourcePDFTitle), detail: L10n.string(.onboardingReadSourcePDFDetail), systemImage: "doc.richtext"),
            OnboardingReadSource(title: L10n.string(.onboardingReadSourcePhotoTitle), detail: L10n.string(.onboardingReadSourcePhotoDetail), systemImage: "camera.viewfinder"),
            OnboardingReadSource(title: L10n.string(.onboardingReadSourceBookPageTitle), detail: L10n.string(.onboardingReadSourceBookPageDetail), systemImage: "text.viewfinder"),
            OnboardingReadSource(title: L10n.string(.onboardingReadSourcePrintedNoteTitle), detail: L10n.string(.onboardingReadSourcePrintedNoteDetail), systemImage: "viewfinder.rectangular")
        ]
    }

    var body: some View {
        OnboardingStepShell(
            title: L10n.string(.onboardingReadAnythingTitle),
            subtitle: L10n.string(.onboardingReadAnythingSubtitle)
        ) {
            VStack(spacing: 18) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(sources.indices, id: \.self) { index in
                        OnboardingReadSourceCard(
                            source: sources[index],
                            isHighlighted: index == highlightedIndex
                        )
                    }
                }

                VStack(spacing: 10) {
                    OnboardingReadCapabilityRow(
                        systemImage: "wand.and.stars",
                        text: L10n.string(.onboardingReadCapabilityCleanup)
                    )
                    OnboardingReadCapabilityRow(
                        systemImage: "text.viewfinder",
                        text: L10n.string(.onboardingReadCapabilityOCR)
                    )
                    OnboardingReadCapabilityRow(
                        systemImage: "play.rectangle.on.rectangle",
                        text: L10n.string(.onboardingReadCapabilitySessions)
                    )
                }
                .padding(16)
                .background(AppTheme.cardBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
                }
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.smooth(duration: 0.24)) {
                        highlightedIndex = (highlightedIndex + 1) % sources.count
                    }
                }
            }
        }
    }
}

private struct OnboardingReadSource: Equatable {
    let title: String
    let detail: String
    let systemImage: String
}

private struct OnboardingReadSourceCard: View {
    let source: OnboardingReadSource
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: source.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isHighlighted ? AppTheme.primaryButtonForeground : AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(
                    isHighlighted ? AppTheme.primaryButtonForeground.opacity(0.16) : AppTheme.iconBackground,
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(source.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isHighlighted ? AppTheme.primaryButtonForeground : AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(source.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isHighlighted ? AppTheme.primaryButtonForeground.opacity(0.78) : AppTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(16)
        .background(
            isHighlighted ? AppTheme.primaryButtonBackground : AppTheme.controlBackground,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isHighlighted ? AppTheme.accent.opacity(0.9) : AppTheme.border.opacity(0.68), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.title), \(source.detail)")
    }
}

private struct OnboardingReadCapabilityRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 18)

            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
