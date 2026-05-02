import SwiftUI

struct TypographySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var readingStatsStore: LocalReadingStatsStore

    let showsDismissButton: Bool
    let showsPageHeader: Bool

    @AppStorage(TypographySettingsKey.fontFamily) private var fontFamily: String = ReaderFontFamily.serif.rawValue
    @AppStorage(TypographySettingsKey.fontSize) private var fontSize: Double = FontStyle.defaultSize
    @AppStorage(TypographySettingsKey.fontWeight) private var fontWeight: String = ReaderFontWeight.regular.rawValue
    @AppStorage(TypographySettingsKey.isItalic) private var isItalic: Bool = false
    @AppStorage(TypographySettingsKey.textColor) private var textColor: String = ReaderTextColor.primary.rawValue
    @AppStorage(TypographySettingsKey.appearance) private var appearance: String = AppAppearance.system.rawValue
    @AppStorage(ReaderBehaviorSettingsKey.defaultWPM) private var defaultWPM: Int = ReadingSession.defaultWPM
    @AppStorage(ReaderBehaviorSettingsKey.hapticsEnabled) private var hapticsEnabled: Bool = true
    @AppStorage(ReaderBehaviorSettingsKey.reverseWPMDialDirection) private var reverseWPMDialDirection: Bool = false
    @AppStorage(ReaderBehaviorSettingsKey.punctuationPausesEnabled) private var punctuationPausesEnabled: Bool = true
    @AppStorage(ReaderBehaviorSettingsKey.longWordDelayMode) private var longWordDelayMode: String = LongWordDelayMode.moderate.rawValue
    @AppStorage(ReaderBehaviorSettingsKey.smartCleanupMode) private var smartCleanupMode: String = ""

    init(
        readingStatsStore: LocalReadingStatsStore,
        showsDismissButton: Bool = true,
        showsPageHeader: Bool = false
    ) {
        _readingStatsStore = ObservedObject(wrappedValue: readingStatsStore)
        self.showsDismissButton = showsDismissButton
        self.showsPageHeader = showsPageHeader
    }

    var body: some View {
        Group {
            if showsDismissButton {
                NavigationStack {
                    settingsContent
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    dismiss()
                                }
                            }
                        }
                }
            } else {
                settingsContent
            }
        }
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
    }

    private var settingsContent: some View {
                ScrollView {
                    VStack(spacing: 16) {
                        if showsPageHeader {
                            FocusReadPageHeader(title: "Settings")
                                .padding(.bottom, 4)
                        }

                settingsSection("App Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                settingsSection("Typography") {
                    settingsInlineRow("Font Family") {
                        Picker("Font Family", selection: $fontFamily) {
                            ForEach(ReaderFontFamily.allCases) { family in
                                Text(family.title).tag(family.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    settingsRow("Font Size") {
                        HStack {
                            Slider(value: $fontSize, in: 24...96, step: 1)
                                .tint(AppTheme.primaryText)

                            Text("\(Int(fontSize))")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.secondaryText)
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    settingsRow("Font Weight") {
                        Picker("Font Weight", selection: $fontWeight) {
                            ForEach(ReaderFontWeight.allCases) { weight in
                                Text(weight.title).tag(weight.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    Toggle("Italic", isOn: $isItalic)
                        .tint(AppTheme.primaryText)

                    Divider().foregroundStyle(AppTheme.border)

                    settingsRow("Text Color") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ReaderTextColor.allCases) { color in
                                    Button {
                                        textColor = color.rawValue
                                    } label: {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(color.color(for: colorScheme))
                                                .frame(width: 10, height: 10)

                                            Text(color.title)
                                                .font(.footnote.weight(.medium))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .foregroundStyle(textColor == color.rawValue ? AppTheme.primaryButtonForeground : AppTheme.controlForeground)
                                        .background(textColor == color.rawValue ? AppTheme.primaryButtonBackground : AppTheme.controlBackground, in: Capsule())
                                        .overlay {
                                            Capsule()
                                                .strokeBorder(textColor == color.rawValue ? AppTheme.primaryText.opacity(0.18) : AppTheme.border, lineWidth: 1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preview")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)

                        Text("Focus")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(.vertical, 20)
                            .padding(.horizontal, 12)
                            .typographyStyle(currentStyle)
                            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(AppTheme.border, lineWidth: 1)
                            }
                    }
                }

                settingsSection("Reader Behavior") {
                    // Camera Control is intentionally absent: Apple's public capture-event APIs
                    // are limited to active media-capture experiences, not reader controls.
                    settingsRow("Default WPM") {
                        HStack {
                            Slider(value: defaultWPMBinding, in: 100...1_200, step: 25)
                                .tint(AppTheme.primaryText)

                            Text("\(defaultWPM)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.secondaryText)
                                .monospacedDigit()
                                .frame(width: 54, alignment: .trailing)
                        }
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    Toggle("Haptics", isOn: $hapticsEnabled)
                        .tint(AppTheme.primaryText)

                    Divider().foregroundStyle(AppTheme.border)

                    Toggle("Reverse WPM Drag", isOn: $reverseWPMDialDirection)
                        .tint(AppTheme.primaryText)

                    Divider().foregroundStyle(AppTheme.border)

                    Toggle("Punctuation Pauses", isOn: $punctuationPausesEnabled)
                        .tint(AppTheme.primaryText)

                    Divider().foregroundStyle(AppTheme.border)

                    settingsRow("Long Word Delay") {
                        Picker("Long Word Delay", selection: $longWordDelayMode) {
                            ForEach(LongWordDelayMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Punctuation pauses add natural reading pauses after commas, periods, and paragraph breaks.")
                        Text("Long-word delay gives extra time for longer words, names, and numbers.")
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                settingsSection("Progress") {
                    settingsRow("Daily Goal") {
                        Stepper(
                            value: dailyGoalBinding,
                            in: 100...100_000,
                            step: 100
                        ) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(readingStatsStore.snapshot.dailyGoalWords)")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .monospacedDigit()

                                Text("words")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                    }
                }

                settingsSection("Text Cleanup") {
                    settingsRow("Imported Text") {
                        Picker("Imported Text", selection: cleanupModeBinding) {
                            ForEach(availableCleanupModes) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(availableCleanupModes) { mode in
                            Text("\(mode.title): \(mode.description)")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                settingsSection("About / Reset") {
                    settingsActionRow(
                        title: "Reset Typography",
                        systemImage: "textformat.size",
                        action: resetTypography
                    )

                    Divider().foregroundStyle(AppTheme.border)

                    settingsActionRow(
                        title: "Reset All Settings",
                        systemImage: "arrow.counterclockwise",
                        action: resetAllSettings
                    )

                    Divider().foregroundStyle(AppTheme.border)

                    HStack {
                        Text(appNameString)
                        Spacer()
                        Text(appVersionString)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .font(.footnote)
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .onAppear {
            normalizeCleanupMode()
        }
    }

    private var currentStyle: FontStyle {
        FontStyle(
            family: ReaderFontFamily(rawValue: fontFamily) ?? .serif,
            size: fontSize,
            weight: ReaderFontWeight(rawValue: fontWeight) ?? .regular,
            isItalic: isItalic,
            textColor: ReaderTextColor(rawValue: textColor) ?? .primary
        )
    }

    private var defaultWPMBinding: Binding<Double> {
        Binding(
            get: { Double(defaultWPM) },
            set: { defaultWPM = Int($0.rounded()) }
        )
    }

    private var dailyGoalBinding: Binding<Int> {
        Binding(
            get: { readingStatsStore.snapshot.dailyGoalWords },
            set: { readingStatsStore.updateDailyGoalWords($0) }
        )
    }

    private var availableCleanupModes: [SmartCleanupMode] {
        SmartCleanupAvailability.availableModes
    }

    private var cleanupModeBinding: Binding<String> {
        Binding(
            get: {
                SmartCleanupAvailability.effectiveMode(savedRawValue: smartCleanupMode).rawValue
            },
            set: { newValue in
                smartCleanupMode = SmartCleanupAvailability.effectiveMode(savedRawValue: newValue).rawValue
            }
        )
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var appNameString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "FocusRead"
    }

    private func resetTypography() {
        fontFamily = ReaderFontFamily.serif.rawValue
        fontSize = FontStyle.defaultSize
        fontWeight = ReaderFontWeight.regular.rawValue
        isItalic = false
        textColor = ReaderTextColor.primary.rawValue
    }

    private func resetAllSettings() {
        appearance = AppAppearance.system.rawValue
        defaultWPM = ReadingSession.defaultWPM
        hapticsEnabled = true
        reverseWPMDialDirection = false
        punctuationPausesEnabled = true
        longWordDelayMode = LongWordDelayMode.moderate.rawValue
        smartCleanupMode = SmartCleanupAvailability.defaultMode.rawValue
        resetTypography()
    }

    private func normalizeCleanupMode() {
        let effectiveMode = SmartCleanupAvailability.effectiveMode(savedRawValue: smartCleanupMode)
        if smartCleanupMode != effectiveMode.rawValue {
            smartCleanupMode = effectiveMode.rawValue
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.08)
                .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(18)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            }
        }
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
            content()
        }
    }

    private func settingsInlineRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Spacer(minLength: 12)

            content()
        }
    }

    private func settingsActionRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .foregroundStyle(AppTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
