import SwiftUI

struct OnboardingRSVPDemoView: View {
    @Binding var canContinue: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ReaderBehaviorSettingsKey.anchorLetterEnabled) private var anchorLetterEnabled = true
    @AppStorage(ReaderBehaviorSettingsKey.defaultWPM) private var defaultWPM: Int = ReadingSession.defaultWPM
    @AppStorage(AppLanguageStorageKey.selectedLanguage) private var selectedLanguageRawValue: String = AppLanguage.systemDefault.rawValue
    @State private var tokens: [ReadingToken] = []
    @State private var currentIndex = 0
    @State private var wordsPerMinute: Int?
    @State private var isPlaying = false
    @State private var displayedWordCount = 0

    var body: some View {
        OnboardingStepShell(
            title: L10n.string(.onboardingRSVPTitle),
            subtitle: L10n.string(.onboardingRSVPSubtitle)
        ) {
            VStack(spacing: 24) {
                readerStage

                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        Button {
                            isPlaying.toggle()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(AppTheme.primaryButtonForeground)
                                .frame(width: 54, height: 54)
                                .background(AppTheme.primaryButtonBackground, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPlaying ? L10n.string(.onboardingRSVPPause) : L10n.string(.onboardingRSVPPlay))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.format(.readerWPMBadgeFormat, currentWPM))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(AppTheme.primaryText)

                            Slider(value: wpmBinding, in: wpmRange, step: 25)
                                .tint(AppTheme.accent)
                                .accessibilityLabel(L10n.string(.onboardingRSVPSpeed))
                        }
                    }

                    ProgressView(value: progress)
                        .tint(AppTheme.progressIndicator)
                        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.24), value: progress)
                        .accessibilityLabel(L10n.string(.onboardingRSVPProgress))
                }
                .padding(16)
                .background(AppTheme.controlBackground.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
                }
            }
        }
        .task(id: playbackID) {
            guard isPlaying, !tokens.isEmpty else { return }

            while !Task.isCancelled, isPlaying {
                let delay = RSVPReadingEngine.delay(
                    for: [tokens[currentIndex]],
                    wpm: currentWPM,
                    behavior: .default
                )
                try? await Task.sleep(for: .milliseconds(max(Int(delay * 1_000), 120)))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    advance()
                }
            }
        }
        .onDisappear {
            isPlaying = false
        }
        .onAppear(perform: refreshTokens)
        .onChange(of: selectedLanguageRawValue) { _, _ in
            refreshTokens()
        }
    }

    private var readerStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.65), lineWidth: 1)
                }
                .shadow(color: AppTheme.subtleShadow, radius: 20, x: 0, y: 10)

            OnboardingRSVPStageGuide()

            if let word = currentWordText {
                OnboardingORPWordView(
                    word: word,
                    fontSize: 50,
                    usesAnchorLetter: anchorLetterEnabled
                )
                .id(currentIndex)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
                .animation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.24), value: currentIndex)
                .padding(.horizontal, 22)
            }
        }
        .frame(height: 238)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string(.onboardingRSVPDemoAccessibility))
        .accessibilityValue(accessibilityStageValue)
    }

    private var progress: Double {
        guard !tokens.isEmpty else { return 0 }
        return Double(currentIndex) / Double(max(tokens.count - 1, 1))
    }

    private var playbackID: String {
        "\(isPlaying)-\(currentWPM)"
    }

    private var currentWPM: Int {
        wordsPerMinute ?? defaultWPM
    }

    private var wpmRange: ClosedRange<Double> {
        Double(ReadingSession.minimumWPM)...Double(ReadingSession.maximumWPM)
    }

    private var currentWordText: String? {
        guard tokens.indices.contains(currentIndex) else { return nil }
        return tokens[currentIndex].text
    }

    private var accessibilityStageValue: String {
        let word = currentWordText ?? ""
        return L10n.format(.onboardingRSVPStageValueFormat, word, currentIndex + 1, tokens.count)
    }

    private var wpmBinding: Binding<Double> {
        Binding(
            get: { Double(currentWPM) },
            set: { newValue in
                let clamped = ReadingSession.clampWPM(Int(newValue.rounded()))
                wordsPerMinute = clamped
                defaultWPM = clamped
            }
        )
    }

    private func advance() {
        displayedWordCount += 1
        if displayedWordCount >= 6 {
            canContinue = true
        }

        if currentIndex >= max(tokens.count - 1, 0) {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.28)) {
                currentIndex = 0
            }
        } else {
            currentIndex += 1
        }
    }

    private func refreshTokens() {
        tokens = TextTokenizer().tokenize(FocusReadOnboardingSample.passage)
        currentIndex = min(currentIndex, max(tokens.count - 1, 0))
    }
}

struct OnboardingRSVPStageGuide: View {
    var body: some View {
        GeometryReader { proxy in
            let centerX = proxy.size.width / 2
            let centerY = proxy.size.height / 2

            ZStack {
                Rectangle()
                    .fill(AppTheme.accent.opacity(0.2))
                    .frame(width: 1, height: 138)
                    .position(x: centerX, y: centerY)

                Circle()
                    .strokeBorder(AppTheme.accent.opacity(0.16), lineWidth: 1)
                    .frame(width: 118, height: 118)
                    .position(x: centerX, y: centerY)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(AppTheme.secondaryText.opacity(0.08))
                        .frame(width: 150, height: 5)

                    Spacer()

                    Capsule()
                        .fill(AppTheme.secondaryText.opacity(0.08))
                        .frame(width: 106, height: 5)
                }
                .padding(.vertical, 34)
            }
        }
        .allowsHitTesting(false)
    }
}

struct OnboardingORPWordView: View {
    let word: String
    let fontSize: CGFloat
    let usesAnchorLetter: Bool

    var body: some View {
        Group {
            if usesAnchorLetter, let parts = OnboardingORPParts(word: word) {
                HStack(spacing: 0) {
                    Text(parts.prefix)
                    Text(parts.anchor)
                        .foregroundStyle(AppTheme.orpHighlight)
                    Text(parts.suffix)
                }
            } else {
                Text(word)
            }
        }
        .font(.system(size: fontSize, weight: .semibold, design: .serif))
        .foregroundStyle(AppTheme.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.38)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(word)
    }
}

struct OnboardingORPParts {
    let prefix: String
    let anchor: String
    let suffix: String

    init?(word: String) {
        let characters = Array(word)
        guard let contentStart = characters.firstIndex(where: Self.isAlphanumeric),
              let contentEndInclusive = characters.indices.reversed().first(where: { Self.isAlphanumeric(characters[$0]) }) else {
            return nil
        }

        let contentLength = contentEndInclusive - contentStart + 1
        let anchorOffset: Int
        switch contentLength {
        case 0...2:
            anchorOffset = 0
        case 3...6:
            anchorOffset = 1
        case 7...9:
            anchorOffset = 2
        default:
            anchorOffset = Int(floor(Double(contentLength) * 0.35))
        }

        let anchorIndex = contentStart + anchorOffset
        guard characters.indices.contains(anchorIndex) else { return nil }

        prefix = String(characters[..<anchorIndex])
        anchor = String(characters[anchorIndex])
        suffix = String(characters[(anchorIndex + 1)...])
    }

    private static func isAlphanumeric(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
