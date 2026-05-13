import SwiftUI

struct OnboardingThemePickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeManager: FocusReadThemeManager

    private var previewThemes: [FocusReadTheme] {
        [
            FocusReadThemeCatalog.theme(matching: "classic-gold"),
            FocusReadThemeCatalog.theme(matching: "ocean-blue"),
            FocusReadThemeCatalog.theme(matching: "forest-green"),
            FocusReadThemeCatalog.theme(matching: "sakura"),
            FocusReadThemeCatalog.theme(matching: "paper-ink"),
            FocusReadThemeCatalog.theme(matching: "amoled")
        ]
    }

    var body: some View {
        OnboardingStepShell(
            title: "Pick a reading feel.",
            subtitle: "Theme changes apply instantly."
        ) {
            VStack(spacing: 18) {
                OnboardingThemeLivePreview(theme: themeManager.selectedTheme, colorScheme: colorScheme)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(previewThemes) { theme in
                        OnboardingThemeTile(
                            theme: theme,
                            colorScheme: colorScheme,
                            isSelected: themeManager.selectedThemeID == theme.id
                        ) {
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                                themeManager.select(theme)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct OnboardingThemeLivePreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let theme: FocusReadTheme
    let colorScheme: ColorScheme

    private var palette: FocusReadThemePalette {
        theme.palette(for: colorScheme == .dark ? .dark : .light)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: palette.primaryBackground))

            VStack(spacing: 16) {
                Text(theme.name)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Color(uiColor: palette.primaryText))

                HStack(spacing: 0) {
                    Text("Foc")
                    Text("u")
                        .foregroundStyle(Color(uiColor: palette.orpHighlight))
                    Text("sRead")
                }
                .font(.system(size: 46, weight: .semibold, design: .serif))
                .foregroundStyle(Color(uiColor: palette.primaryText))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                Capsule()
                    .fill(Color(uiColor: palette.progressIndicator))
                    .frame(width: 118, height: 6)
            }
            .padding(24)
        }
        .frame(height: 210)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color(uiColor: palette.separator), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: theme.id)
    }
}

private struct OnboardingThemeTile: View {
    let theme: FocusReadTheme
    let colorScheme: ColorScheme
    let isSelected: Bool
    let action: () -> Void

    private var palette: FocusReadThemePalette {
        theme.palette(for: colorScheme == .dark ? .dark : .light)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: palette.primaryBackground))

                    HStack(spacing: 5) {
                        Circle().fill(Color(uiColor: palette.accent))
                        Circle().fill(Color(uiColor: palette.cardSurface))
                        Circle().fill(Color(uiColor: palette.primaryText))
                    }
                    .frame(height: 18)
                    .padding(10)
                }
                .frame(height: 74)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(uiColor: palette.separator), lineWidth: 1)
                }

                HStack(spacing: 6) {
                    Text(theme.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 4)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .padding(10)
            .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent : AppTheme.border.opacity(0.68), lineWidth: isSelected ? 1.4 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}
