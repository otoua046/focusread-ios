import SwiftUI

struct OnboardingWPMSetupView: View {
    private enum PacePreset: String, CaseIterable, Identifiable {
        case comfortable
        case balanced
        case fast
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .comfortable: return "Comfortable"
            case .balanced: return "Balanced"
            case .fast: return "Fast"
            case .custom: return "Custom"
            }
        }

        var value: Int? {
            switch self {
            case .comfortable: return 250
            case .balanced: return 350
            case .fast: return 500
            case .custom: return nil
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedWPM: Int
    @State private var selectedPreset: PacePreset = .balanced
    @State private var previewWordIndex = 0

    private let previewWords = FocusReadOnboardingSample.passageWords

    var body: some View {
        OnboardingStepShell(
            title: "Choose your starting pace.",
            subtitle: "\(selectedWPM) words per minute"
        ) {
            VStack(spacing: 22) {
                livePreview

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(PacePreset.allCases) { preset in
                        Button {
                            select(preset)
                        } label: {
                            VStack(spacing: 8) {
                                Text(preset.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(selectedPreset == preset ? AppTheme.primaryButtonForeground : AppTheme.primaryText)

                                if let value = preset.value {
                                    Text("\(value) WPM")
                                        .font(.caption.monospacedDigit().weight(.medium))
                                        .foregroundStyle(selectedPreset == preset ? AppTheme.primaryButtonForeground.opacity(0.78) : AppTheme.secondaryText)
                                } else {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selectedPreset == preset ? AppTheme.primaryButtonForeground.opacity(0.78) : AppTheme.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 92)
                            .background(
                                selectedPreset == preset ? AppTheme.primaryButtonBackground : AppTheme.controlBackground,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(selectedPreset == preset ? AppTheme.accent.opacity(0.9) : AppTheme.border.opacity(0.68), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selectedPreset == preset ? "Selected" : "")
                    }
                }

                VStack(spacing: 14) {
                    HStack {
                        Text("Pace")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer()

                        Text("\(selectedWPM)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Slider(value: selectedWPMBinding, in: 100...1_200, step: 25)
                        .tint(AppTheme.accent)
                        .accessibilityLabel("Default words per minute")
                }
                .padding(18)
                .background(AppTheme.cardBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
                }
            }
        }
        .onAppear {
            selectedWPM = ReadingSession.clampWPM(selectedWPM)
            selectedPreset = preset(matching: selectedWPM)
        }
        .task(id: selectedWPM) {
            guard !reduceMotion else {
                previewWordIndex = 0
                return
            }

            while !Task.isCancelled {
                let delay = max(60.0 / Double(max(selectedWPM, 1)), 0.08)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.smooth(duration: 0.16)) {
                        previewWordIndex = (previewWordIndex + 1) % previewWords.count
                    }
                }
            }
        }
    }

    private var livePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
                }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .textCase(.uppercase)

                    Text("\(selectedWPM) WPM")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer(minLength: 12)

                OnboardingORPWordView(
                    word: previewWords[previewWordIndex % previewWords.count],
                    fontSize: 34,
                    usesAnchorLetter: true
                )
                .id(previewWordIndex)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
                .frame(maxWidth: 190)
                .accessibilityLabel("Preview word \(previewWords[previewWordIndex % previewWords.count])")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(minHeight: 104)
    }

    private var selectedWPMBinding: Binding<Double> {
        Binding(
            get: { Double(selectedWPM) },
            set: { newValue in
                selectedWPM = ReadingSession.clampWPM(Int(newValue.rounded()))
                selectedPreset = preset(matching: selectedWPM)
            }
        )
    }

    private func select(_ preset: PacePreset) {
        selectedPreset = preset
        if let value = preset.value {
            selectedWPM = value
        }
    }

    private func preset(matching value: Int) -> PacePreset {
        PacePreset.allCases.first { $0.value == value } ?? .custom
    }
}
