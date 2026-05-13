import SwiftUI

struct OnboardingComparisonView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case normal
        case focusRead

        var id: String { rawValue }
        var title: String { self == .normal ? "Normal" : "FocusRead" }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode = .normal
    @State private var normalWordIndex = 0
    @State private var focusWordIndex = 0
    @State private var userSelectedMode = false

    private let words = FocusReadOnboardingSample.passageWords

    var body: some View {
        OnboardingStepShell(
            title: "See the shift.",
            subtitle: "Same words. Less scanning."
        ) {
            VStack(spacing: 20) {
                Picker("Reading mode", selection: modeBinding) {
                    ForEach(Mode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                ZStack {
                    if mode == .normal {
                        normalReadingView
                            .transition(.opacity)
                    } else {
                        focusReadingView
                            .transition(.opacity)
                    }
                }
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? .easeInOut(duration: 0.14) : .smooth(duration: 0.28), value: mode)
            }
        }
        .task(id: mode) {
            guard !reduceMotion else {
                normalWordIndex = 0
                focusWordIndex = 0
                return
            }

            while !Task.isCancelled {
                if mode == .normal {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.smooth(duration: 0.22)) {
                            normalWordIndex = (normalWordIndex + 1) % max(words.count, 1)
                        }
                    }
                } else {
                    try? await Task.sleep(for: .milliseconds(360))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.smooth(duration: 0.24)) {
                            focusWordIndex = (focusWordIndex + 1) % max(words.count, 1)
                        }
                    }
                }
            }
        }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(4_400))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !userSelectedMode else { return }
                withAnimation(.smooth(duration: 0.32)) {
                    mode = .focusRead
                }
            }
        }
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: { mode },
            set: { newMode in
                userSelectedMode = true
                mode = newMode
            }
        )
    }

    private var normalReadingView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.88))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.68), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(normalLines.indices, id: \.self) { lineIndex in
                    HStack(spacing: 4) {
                        ForEach(normalLines[lineIndex], id: \.globalIndex) { item in
                            OnboardingHighlightedWord(
                                word: item.word,
                                isHighlighted: item.globalIndex == normalWordIndex
                            )
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 4)
        }
        .accessibilityLabel("Normal reading highlights words across multiple lines")
    }

    private var focusReadingView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.68), lineWidth: 1)
                }

            OnboardingRSVPStageGuide()

            OnboardingORPWordView(
                word: focusedWord,
                fontSize: 50,
                usesAnchorLetter: true
            )
            .id(focusWordIndex)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
            .padding(.horizontal, 24)
        }
        .accessibilityLabel("FocusRead mode shows one centered word at a time")
    }

    private var normalLines: [[OnboardingNormalWord]] {
        let lineLengths = [7, 7, 7, 7, 7, 7, 7, 7]
        var cursor = 0

        return lineLengths.compactMap { count in
            guard cursor < words.count else { return nil }
            let endIndex = min(cursor + count, words.count)
            let line = words[cursor..<endIndex].enumerated().map { offset, word in
                OnboardingNormalWord(globalIndex: cursor + offset, word: word)
            }
            cursor = endIndex
            return line
        }
    }

    private var focusedWord: String {
        guard words.indices.contains(focusWordIndex) else { return "FocusRead" }
        return words[focusWordIndex]
    }
}

private struct OnboardingNormalWord: Identifiable, Equatable {
    let globalIndex: Int
    let word: String

    var id: Int { globalIndex }
}

private struct OnboardingHighlightedWord: View {
    let word: String
    let isHighlighted: Bool

    var body: some View {
        Text(word)
            .font(.system(.footnote, design: .serif, weight: isHighlighted ? .semibold : .medium))
            .foregroundStyle(isHighlighted ? AppTheme.primaryText : AppTheme.primaryText.opacity(0.52))
            .lineLimit(1)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(AppTheme.accent.opacity(0.22), lineWidth: 1)
                        }
                        .transition(.opacity)
                }
            }
    }
}
