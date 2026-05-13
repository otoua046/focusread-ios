import SwiftUI

struct OnboardingPromiseView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wordIndex = 0

    private var words: [String] {
        localizedPromiseWords()
    }

    private var currentWord: String? {
        guard !words.isEmpty else { return nil }
        return words[safeWordIndex]
    }

    private func localizedPromiseWords(localeIdentifier: String? = nil) -> [String] {
        let localizedWords = L10n.string(.onboardingPromiseWords, localeIdentifier: localeIdentifier)
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !localizedWords.isEmpty {
            return localizedWords
        }

        guard localeIdentifier != AppLanguage.english.rawValue else {
            return []
        }

        return localizedPromiseWords(localeIdentifier: AppLanguage.english.rawValue)
    }

    var body: some View {
        OnboardingCenteredStep {
            VStack(spacing: 26) {
                VStack(spacing: 16) {
                    (
                        Text(L10n.string(.onboardingPromisePrefix))
                        + Text(L10n.string(.onboardingPromiseHighlight))
                            .foregroundStyle(AppTheme.accent)
                        + Text(L10n.string(.onboardingPromiseSuffix))
                    )
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.74)
                    .lineLimit(4)

                    Text(.onboardingPromiseSubtitle)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 10)

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(AppTheme.cardBackground.opacity(0.86))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(AppTheme.border.opacity(0.66), lineWidth: 1)
                        }

                    OnboardingRSVPStageGuide()

                    if let currentWord {
                        OnboardingORPWordView(
                            word: currentWord,
                            fontSize: 46,
                            usesAnchorLetter: true
                        )
                        .id(wordIndex)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
                        .padding(.horizontal, 24)
                    }
                }
                .frame(height: 178)
                .frame(maxWidth: 430)
                .shadow(color: AppTheme.subtleShadow, radius: 18, x: 0, y: 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.string(.onboardingPromisePreviewAccessibility))
            }
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else {
                wordIndex = 0
                return
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(760))
                guard !Task.isCancelled else { return }
                let wordCount = words.count
                guard wordCount > 0 else {
                    wordIndex = 0
                    return
                }

                await MainActor.run {
                    withAnimation(.smooth(duration: 0.28)) {
                        wordIndex = (wordIndex + 1) % wordCount
                    }
                }
            }
        }
    }

    private var safeWordIndex: Int {
        guard !words.isEmpty else { return 0 }
        return min(max(wordIndex, 0), words.count - 1)
    }
}
