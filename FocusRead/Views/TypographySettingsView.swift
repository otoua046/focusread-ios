import StoreKit
import SwiftUI

struct TypographySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.focusReadTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var themeManager: FocusReadThemeManager
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @ObservedObject private var readingStatsStore: LocalReadingStatsStore

    let showsDismissButton: Bool
    let showsPageHeader: Bool
    let onReplayOnboarding: (() -> Void)?

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
    @AppStorage(ReaderBehaviorSettingsKey.anchorLetterEnabled) private var anchorLetterEnabled: Bool = true
    @AppStorage(ReaderBehaviorSettingsKey.displayMode) private var displayMode: String = ReaderDisplayMode.oneWord.rawValue
    @AppStorage(AIRecapSettingsKey.isEnabled) private var aiRecapsEnabledPreference: Bool = AIRecapSettings.defaultEnabled()
    @AppStorage(AppLanguageStorageKey.selectedLanguage) private var selectedLanguageRawValue: String = AppLanguage.systemDefault.rawValue
    @State private var isResetTypographyConfirmationPresented = false
    @State private var isResetAllConfirmationPresented = false
    @State private var hasScrolledUnderTop = false
    @State private var proCTAFeedbackTrigger = 0

    private let scrollCoordinateSpaceName = "settingsScroll"

    private let aiRecapCapabilityService = AIRecapService()

    init(
        readingStatsStore: LocalReadingStatsStore,
        showsDismissButton: Bool = true,
        showsPageHeader: Bool = false,
        onReplayOnboarding: (() -> Void)? = nil
    ) {
        _readingStatsStore = ObservedObject(wrappedValue: readingStatsStore)
        self.showsDismissButton = showsDismissButton
        self.showsPageHeader = showsPageHeader
        self.onReplayOnboarding = onReplayOnboarding
    }

    var body: some View {
        Group {
            if showsDismissButton {
                NavigationStack {
                    settingsContent
                        .navigationTitle(L10n.key(.settingsTitle))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(.commonDone) {
                                    dismiss()
                                }
                            }
                        }
                }
            } else {
                NavigationStack {
                    settingsContent
                        .navigationTitle(L10n.key(.settingsTitle))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .focusReadThemeRefresh()
    }

    private var settingsContent: some View {
        settingsScrollView
            .background(AppTheme.background.ignoresSafeArea())
            .onAppear {
                normalizeCleanupMode()
            }
    }

    @ViewBuilder
    private var settingsScrollView: some View {
        let scrollView = ScrollView {
            VStack(spacing: 22) {
                FocusReadScrollTopTracker(coordinateSpaceName: scrollCoordinateSpaceName)

                if showsPageHeader {
                    FocusReadPageHeader(titleKey: .settingsTitle)
                        .padding(.bottom, 2)
                }

                NavigationLink {
                    FocusReadProSettingsView()
                } label: {
                    ProCTAHeaderView()
                }
                .buttonStyle(.proCTAHeader)
                .sensoryFeedback(.selection, trigger: proCTAFeedbackTrigger)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        proCTAFeedbackTrigger += 1
                    }
                )

                settingsSection("Appearance") {
                    settingsRow(
                        title: L10n.string(.settingsAppearance)
                    ) {
                        Picker(L10n.key(.settingsAppearance), selection: $appearance) {
                            ForEach(AppAppearance.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 214)
                    }

                    settingsDivider

                    languageNavigationRow

                    settingsDivider

                    themeNavigationRow
                }

                settingsSection("Reading") {
                    typographyNavigationRow

                    settingsDivider

                    readerBehaviorNavigationRow

                    settingsDivider

                    settingsRow(
                        title: L10n.string(.settingsDailyGoal)
                    ) {
                        HStack(spacing: 10) {
                            Text(dailyGoalSummary)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                                .monospacedDigit()
                                .lineLimit(1)

                            dailyGoalControl
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    settingsSection(textCleanupSectionTitle) {
                        if isAIRecapCapabilityAvailable {
                            settingsRow(
                                title: L10n.string(.settingsAIRecaps),
                                subtitle: L10n.string(.settingsAIRecapsDescription)
                            ) {
                                Toggle(L10n.string(.settingsAIRecaps), isOn: aiRecapsEnabledBinding)
                                    .labelsHidden()
                                    .tint(AppTheme.accent)
                            }

                            settingsDivider
                        }

                        cleanupSettingsRow
                    }

                    Text(cleanupDescriptionText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .lineSpacing(1)
                }

                settingsSection("Sync") {
                    cloudSyncNavigationRow
                }

                settingsSection(L10n.string(.settingsAboutReset)) {
                    settingsActionRow(
                        title: L10n.string(.settingsResetTypography),
                        action: { isResetTypographyConfirmationPresented = true }
                    )

                    settingsDivider

                    settingsActionRow(
                        title: L10n.string(.settingsResetAll),
                        action: { isResetAllConfirmationPresented = true }
                    )
                }

                settingsSection("Support") {
                    if let onReplayOnboarding {
                        settingsActionRow(
                            title: "Replay FocusRead Demo",
                            action: onReplayOnboarding
                        )

                        settingsDivider
                    }

                    settingsLinkButtonRow(title: "Rate Us") {
                        requestReview()
                    }

                    settingsDivider

                    ShareLink(item: shareMessage) {
                        settingsLinkRow(title: "Share with friends")
                    }
                    .buttonStyle(.plain)

                    settingsDivider

                    settingsLinkButtonRow(title: "Share Feedback") {
                        openURL(feedbackURL)
                    }
                }

                settingsSection("Legal") {
                    Link(destination: privacyPolicyURL) {
                        settingsLinkRow(title: "Privacy Policy")
                    }
                    .buttonStyle(.plain)

                    settingsDivider

                    Link(destination: termsOfServiceURL) {
                        settingsLinkRow(title: "Terms of Service")
                    }
                    .buttonStyle(.plain)
                }

                appVersionFooter

                madeInCanadaFooter
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .coordinateSpace(name: scrollCoordinateSpaceName)
        .onPreferenceChange(FocusReadScrollOffsetPreferenceKey.self) { offset in
            hasScrolledUnderTop = offset < -1
        }
        .alert(L10n.string(.settingsResetTypographyConfirmTitle), isPresented: $isResetTypographyConfirmationPresented) {
            Button(.commonCancel, role: .cancel) {}
            Button(L10n.string(.settingsResetTypography), role: .destructive) {
                resetTypography()
            }
        } message: {
            Text(.settingsResetTypographyConfirmMessage)
        }
        .alert(L10n.string(.settingsResetAllConfirmTitle), isPresented: $isResetAllConfirmationPresented) {
            Button(.commonCancel, role: .cancel) {}
            Button(L10n.string(.settingsResetAll), role: .destructive) {
                resetAllSettings()
            }
        } message: {
            Text(.settingsResetAllConfirmMessage)
        }

        if showsPageHeader {
            scrollView.focusReadTopSafeAreaMaterial(isElevated: hasScrolledUnderTop)
        } else {
            scrollView
        }
    }

    private var themeNavigationRow: some View {
        settingsNavigationRow(
            title: L10n.string(.settingsTheme),
            value: themeManager.selectedTheme.name
        ) {
            ThemeSettingsView()
                .toolbar(.visible, for: .navigationBar)
        }
    }

    private var languageNavigationRow: some View {
        settingsNavigationRow(
            title: L10n.string(.settingsAppLanguage),
            value: (AppLanguage(rawValue: selectedLanguageRawValue) ?? .systemDefault).displayName
        ) {
            AppLanguageSettingsView(selectedLanguageRawValue: $selectedLanguageRawValue)
                .toolbar(.visible, for: .navigationBar)
        }
    }

    private var typographyNavigationRow: some View {
        settingsNavigationRow(
            title: L10n.string(.settingsTypography),
            value: typographySummary
        ) {
            TypographyDetailSettingsView()
                .toolbar(.visible, for: .navigationBar)
        }
    }

    private var readerBehaviorNavigationRow: some View {
        settingsNavigationRow(
            title: L10n.string(.settingsReaderBehavior),
            value: readerBehaviorSummary
        ) {
            ReaderBehaviorSettingsView()
                .toolbar(.visible, for: .navigationBar)
        }
    }

    private var cloudSyncNavigationRow: some View {
        settingsNavigationRow(
            title: "iCloud Sync",
            value: syncStatusText,
            valueColor: syncStatusColor,
            showsProgress: cloudSyncManager.status.kind == .syncing
        ) {
            CloudSyncSettingsView()
                .toolbar(.visible, for: .navigationBar)
        }
    }

    private var typographySummary: String {
        let family = ReaderFontFamily(rawValue: fontFamily) ?? .serif
        let weight = ReaderFontWeight(rawValue: fontWeight) ?? .regular
        let color = ReaderTextColor(rawValue: textColor) ?? .primary
        let italicSuffix = isItalic ? ", \(L10n.string(.typographySummaryItalic))" : ""
        return "\(family.title), \(Int(fontSize)) pt, \(weight.title), \(color.title)\(italicSuffix)"
    }

    private var readerBehaviorSummary: String {
        let mode = ReaderDisplayMode(rawValue: displayMode) ?? .oneWord
        return "\(defaultWPM) WPM, \(mode.title)"
    }

    private var dailyGoalSummary: String {
        let formattedGoal = NumberFormatter.localizedString(
            from: NSNumber(value: readingStatsStore.snapshot.dailyGoalWords),
            number: .decimal
        )
        return "\(formattedGoal) \(L10n.string(.commonWords))"
    }

    private var dailyGoalControl: some View {
        HStack(spacing: 0) {
            Button {
                let nextGoal = max(100, readingStatsStore.snapshot.dailyGoalWords - 100)
                readingStatsStore.updateDailyGoalWords(nextGoal)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Decrease Daily Goal")

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1, height: 18)

            Button {
                let nextGoal = min(100_000, readingStatsStore.snapshot.dailyGoalWords + 100)
                readingStatsStore.updateDailyGoalWords(nextGoal)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Increase Daily Goal")
        }
        .frame(width: 118, height: 30, alignment: .center)
        .foregroundStyle(AppTheme.primaryText)
        .background(AppTheme.controlBackground, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(AppTheme.border, lineWidth: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string(.settingsDailyGoal))
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

    private var cleanupDescriptionText: String {
        availableCleanupModes
            .map { mode in
                "\(mode.title): \(mode.description)"
            }
            .joined(separator: "\n")
    }

    private var textCleanupSectionTitle: String {
        isAIRecapCapabilityAvailable ? "Text & AI" : "Text Cleanup"
    }

    private var shareMessage: String {
        "FocusRead helps you read with less eye movement and more focus."
    }

    private var feedbackURL: URL {
        URL(string: "mailto:support@focusread.app?subject=FocusRead%20Feedback")!
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://focusread.app/privacy")!
    }

    private var termsOfServiceURL: URL {
        URL(string: "https://focusread.app/terms")!
    }

    private var cleanupSettingsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Imported Text Cleanup")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            Picker("Imported Text Cleanup", selection: cleanupModeBinding) {
                ForEach(availableCleanupModes) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var madeInCanadaFooter: some View {
        HStack(spacing: 7) {
            Text("Made in Canada")
                .font(.system(.footnote, design: .default, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.72))

            Image(canadaFooterIconName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 24, height: 24)
                .opacity(0.82)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Made in Canada")
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 32)
    }

    private var appVersionFooter: some View {
        HStack(spacing: 6) {
            Text(appNameString)

            Text(appVersionString)
        }
        .font(.system(.footnote, design: .default, weight: .regular))
        .foregroundStyle(AppTheme.secondaryText.opacity(0.64))
        .lineLimit(1)
        .minimumScaleFactor(0.86)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, -2)
    }

    private var canadaFooterIconName: String {
        theme.colorScheme == .dark ? "CanadaIconWhite" : "CanadaIconGrey"
    }

    private var isAIRecapCapabilityAvailable: Bool {
        aiRecapCapabilityService.isAvailable
    }

    private var aiRecapsEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                _ = aiRecapsEnabledPreference
                return AIRecapSettings.isEnabled(localAIAvailable: isAIRecapCapabilityAvailable)
            },
            set: { newValue in
                aiRecapsEnabledPreference = newValue
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

    private var syncStatusText: String {
        switch cloudSyncManager.status.kind {
        case .off:
            return "Off"
        case .unavailable:
            return "Unavailable"
        case .syncing:
            return "Syncing"
        case .synced:
            return "On"
        case .error:
            return "Error"
        }
    }

    private var syncStatusColor: Color {
        switch cloudSyncManager.status.kind {
        case .synced:
            return AppTheme.accent
        case .error:
            return AppTheme.destructive
        default:
            return AppTheme.secondaryText
        }
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
        themeManager.reset()
        defaultWPM = ReadingSession.defaultWPM
        hapticsEnabled = true
        reverseWPMDialDirection = false
        punctuationPausesEnabled = true
        longWordDelayMode = LongWordDelayMode.moderate.rawValue
        smartCleanupMode = SmartCleanupAvailability.defaultMode.rawValue
        anchorLetterEnabled = true
        displayMode = ReaderDisplayMode.oneWord.rawValue
        aiRecapsEnabledPreference = AIRecapSettings.defaultEnabled(localAIAvailable: isAIRecapCapabilityAvailable)
        selectedLanguageRawValue = AppLanguage.systemDefault.rawValue
        resetTypography()
    }

    private func normalizeCleanupMode() {
        let effectiveMode = SmartCleanupAvailability.effectiveMode(savedRawValue: smartCleanupMode)
        if smartCleanupMode != effectiveMode.rawValue {
            smartCleanupMode = effectiveMode.rawValue
        }
    }

    private func settingsSection<Content: View>(_: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.border.opacity(0.72), lineWidth: 1)
            }
        }
    }

    private var settingsDivider: some View {
        Divider()
            .foregroundStyle(AppTheme.border)
            .padding(.leading, 14)
    }

    private func settingsRow<Accessory: View>(
        title: String,
        subtitle: String? = nil,
        titleColor: Color = AppTheme.primaryText,
        minHeight: CGFloat = 56,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, subtitle == nil ? 8 : 9)
        .frame(minHeight: minHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func settingsRow(
        title: String,
        subtitle: String? = nil,
        titleColor: Color = AppTheme.primaryText,
        minHeight: CGFloat = 56
    ) -> some View {
        settingsRow(
            title: title,
            subtitle: subtitle,
            titleColor: titleColor,
            minHeight: minHeight
        ) {
            EmptyView()
        }
    }

    private func settingsNavigationRow<Destination: View>(
        title: String,
        value: String,
        valueColor: Color = AppTheme.secondaryText,
        showsProgress: Bool = false,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            settingsRow(
                title: title
            ) {
                HStack(spacing: 7) {
                    if showsProgress {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func settingsActionRow(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsRow(title: title, titleColor: .blue)
        }
        .buttonStyle(.plain)
    }

    private func settingsLinkButtonRow(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsLinkRow(title: title)
        }
        .buttonStyle(.plain)
    }

    private func settingsLinkRow(title: String) -> some View {
        settingsRow(title: title) {
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityHidden(true)
        }
    }
}

struct ProCTAHeaderView: View {
    @Environment(\.focusReadTheme) private var theme
    @AppStorage(FocusReadProStorageKey.isActive) private var isProActive = false

    private var title: String {
        isProActive ? "FocusRead Pro Active" : "FocusRead Pro"
    }

    private var subtitle: String {
        isProActive ? "Sync and intelligence are enabled" : "AI Recaps, Cloud Sync, and more"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        HStack(spacing: 14) {
            proAvatar

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)

                    proBadge
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.tertiaryText)
                .frame(width: 18)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape
                .fill(theme.cardBackground.opacity(0.92))
                .background(.regularMaterial, in: shape)
                .shadow(color: theme.subtleShadow.opacity(0.72), radius: 14, x: 0, y: 6)
        }
        .overlay {
            shape
                .strokeBorder(theme.border.opacity(0.72), lineWidth: 1)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    private var proAvatar: some View {
        ZStack {
            Circle()
                .fill(theme.controlBackground.opacity(0.82))
                .background(.thinMaterial, in: Circle())

            Circle()
                .strokeBorder(theme.accent.opacity(0.28), lineWidth: 1)

            Image(systemName: "crown.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(theme.accent)
                .offset(y: -1)
        }
        .frame(width: 52, height: 52)
        .shadow(color: theme.accent.opacity(0.10), radius: 10, x: 0, y: 4)
        .accessibilityHidden(true)
    }

    private var proBadge: some View {
        Text("PRO")
            .font(.caption2.weight(.bold))
            .foregroundStyle(theme.accent)
            .tracking(0.4)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(theme.accent.opacity(0.10), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(theme.accent.opacity(0.18), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct ProCTAHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.smooth(duration: 0.16), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ProCTAHeaderButtonStyle {
    static var proCTAHeader: ProCTAHeaderButtonStyle { ProCTAHeaderButtonStyle() }
}

struct FocusReadProSettingsView: View {
    @Environment(\.focusReadTheme) private var theme
    @AppStorage(FocusReadProStorageKey.isActive) private var isProActive = false

    private let features: [FocusReadProFeature] = [
        FocusReadProFeature(title: "AI Recaps", detail: "Reading-session summaries", symbolName: "sparkles"),
        FocusReadProFeature(title: "iCloud Sync", detail: "Library and progress across devices", symbolName: "icloud"),
        FocusReadProFeature(title: "Advanced Cleanup", detail: "Cleaner imports for dense documents", symbolName: "wand.and.stars"),
        FocusReadProFeature(title: "Reading Analytics", detail: "Deeper pace and consistency insights", symbolName: "chart.xyaxis.line"),
        FocusReadProFeature(title: "Early Access", detail: "Future reading intelligence tools", symbolName: "leaf")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                proIdentityCard

                proSettingsSection("Included with Pro") {
                    ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                        ProFeatureRow(feature: feature)

                        if index < features.count - 1 {
                            Divider()
                                .foregroundStyle(theme.border)
                                .padding(.leading, 54)
                        }
                    }
                }

                proSettingsSection("Status") {
                    HStack(spacing: 12) {
                        Text("Membership")
                            .font(.subheadline)
                            .foregroundStyle(theme.primaryText)

                        Spacer(minLength: 12)

                        Text(isProActive ? "Active" : "Not Active")
                            .font(.subheadline)
                            .foregroundStyle(isProActive ? theme.accent : theme.secondaryText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 54)
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .focusReadSettingsPageChrome()
        .navigationTitle("FocusRead Pro")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent)
        .focusReadThemeRefresh()
    }

    private var proIdentityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(theme.controlBackground)
                        .frame(width: 48, height: 48)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isProActive ? "FocusRead Pro Active" : "FocusRead Pro")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    Text("Advanced reading intelligence")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Text("A quieter layer of AI, sync, and reading insight for longer sessions and larger libraries.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.border.opacity(0.72), lineWidth: 1)
        }
    }

    private func proSettingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.08)
                .padding(.horizontal, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(theme.border.opacity(0.72), lineWidth: 1)
            }
        }
    }
}

private enum FocusReadProStorageKey {
    static let isActive = "focusread.pro.isActive"
}

private struct FocusReadProFeature: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbolName: String
}

private struct ProFeatureRow: View {
    @Environment(\.focusReadTheme) private var theme
    let feature: FocusReadProFeature

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feature.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(theme.controlBackground, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.primaryText)

                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }
}

struct TypographyDetailSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(TypographySettingsKey.fontFamily) private var fontFamily: String = ReaderFontFamily.serif.rawValue
    @AppStorage(TypographySettingsKey.fontSize) private var fontSize: Double = FontStyle.defaultSize
    @AppStorage(TypographySettingsKey.fontWeight) private var fontWeight: String = ReaderFontWeight.regular.rawValue
    @AppStorage(TypographySettingsKey.isItalic) private var isItalic: Bool = false
    @AppStorage(TypographySettingsKey.textColor) private var textColor: String = ReaderTextColor.primary.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                settingsSection(L10n.string(.typographyFont)) {
                    settingsInlineRow(L10n.string(.typographyFontFamily)) {
                        Picker(L10n.key(.typographyFontFamily), selection: $fontFamily) {
                            ForEach(ReaderFontFamily.allCases) { family in
                                Text(family.title).tag(family.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    settingsRow(L10n.string(.typographyFontSize)) {
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

                    settingsRow(L10n.string(.typographyFontWeight)) {
                        Picker(L10n.key(.typographyFontWeight), selection: $fontWeight) {
                            ForEach(ReaderFontWeight.allCases) { weight in
                                Text(weight.title).tag(weight.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    Toggle(L10n.string(.typographyItalic), isOn: $isItalic)
                        .tint(AppTheme.accent)
                }

                settingsSection(L10n.string(.typographyTextColor)) {
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

                settingsSection(L10n.string(.typographyPreview)) {
                    Text(.typographyPreviewWord)
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
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .focusReadSettingsPageChrome()
        .navigationTitle(L10n.key(.settingsTypography))
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
        .focusReadThemeRefresh()
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
}

struct ReaderBehaviorSettingsView: View {
    @AppStorage(ReaderBehaviorSettingsKey.defaultWPM) private var defaultWPM: Int = ReadingSession.defaultWPM
    @AppStorage(ReaderBehaviorSettingsKey.hapticsEnabled) private var hapticsEnabled: Bool = true
    @AppStorage(ReaderBehaviorSettingsKey.reverseWPMDialDirection) private var reverseWPMDialDirection: Bool = false
    @AppStorage(ReaderBehaviorSettingsKey.punctuationPausesEnabled) private var punctuationPausesEnabled: Bool = true
    @AppStorage(ReaderBehaviorSettingsKey.longWordDelayMode) private var longWordDelayMode: String = LongWordDelayMode.moderate.rawValue
    @AppStorage(ReaderBehaviorSettingsKey.anchorLetterEnabled) private var anchorLetterEnabled: Bool = true
    @AppStorage(ReaderBehaviorSettingsKey.displayMode) private var displayMode: String = ReaderDisplayMode.oneWord.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                settingsSection(L10n.string(.settingsReaderBehavior)) {
                    settingsRow(L10n.string(.settingsDefaultWPM)) {
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

                    settingsRow(L10n.string(.settingsDisplayMode)) {
                        Picker(L10n.key(.settingsDisplayMode), selection: $displayMode) {
                            ForEach(ReaderDisplayMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    Toggle(L10n.string(.settingsAnchorLetter), isOn: $anchorLetterEnabled)
                        .tint(AppTheme.accent)

                    Divider().foregroundStyle(AppTheme.border)

                    Toggle(L10n.string(.settingsHaptics), isOn: $hapticsEnabled)
                        .tint(AppTheme.accent)

                    Divider().foregroundStyle(AppTheme.border)

                    Toggle(L10n.string(.settingsReverseWPMDrag), isOn: $reverseWPMDialDirection)
                        .tint(AppTheme.accent)

                    Divider().foregroundStyle(AppTheme.border)

                    Toggle(L10n.string(.settingsPunctuationPauses), isOn: $punctuationPausesEnabled)
                        .tint(AppTheme.accent)

                    Divider().foregroundStyle(AppTheme.border)

                    settingsRow(L10n.string(.settingsLongWordDelay)) {
                        Picker(L10n.key(.settingsLongWordDelay), selection: $longWordDelayMode) {
                            ForEach(LongWordDelayMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(.settingsDisplayModeHelp)
                        Text(.settingsAnchorLetterHelp)
                        Text(.settingsPunctuationPausesHelp)
                        Text(.settingsLongWordDelayHelp)
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .focusReadSettingsPageChrome()
        .navigationTitle(L10n.key(.settingsReaderBehavior))
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
        .focusReadThemeRefresh()
    }

    private var defaultWPMBinding: Binding<Double> {
        Binding(
            get: { Double(defaultWPM) },
            set: { defaultWPM = Int($0.rounded()) }
        )
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
}

struct ThemeSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: FocusReadThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(FocusReadThemeCategory.allCases) { category in
                    themeSection(category)
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .focusReadSettingsPageChrome()
        .navigationTitle(L10n.key(.settingsTheme))
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
        .focusReadThemeRefresh()
    }

    private func themeSection(_ category: FocusReadThemeCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(category.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.08)
                .padding(.horizontal, 6)

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(FocusReadThemeCatalog.themes(in: category)) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: themeManager.selectedThemeID == theme.id,
                        colorScheme: colorScheme
                    ) {
                        withAnimation(.smooth(duration: 0.18)) {
                            themeManager.select(theme)
                        }
                    }
                }
            }
        }
    }
}

private struct ThemePreviewCard: View {
    let theme: FocusReadTheme
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    private var palette: FocusReadThemePalette {
        theme.palette(for: colorScheme == .dark ? .dark : .light)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                previewSurface

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(theme.name)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Spacer(minLength: 4)

                        if isSelected {
                            Text(.commonSelected)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }

                    Text(theme.description)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent : AppTheme.border, lineWidth: isSelected ? 1.4 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityValue(isSelected ? L10n.string(.commonSelected) : L10n.string(.commonNotSelected))
    }

    private var previewSurface: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: palette.primaryBackground))

            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(uiColor: palette.cardSurface))
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule()
                                .fill(Color(uiColor: palette.primaryText))
                                .frame(width: 36, height: 4)

                            Capsule()
                                .fill(Color(uiColor: palette.secondaryText))
                                .frame(width: 48, height: 3)

                            Spacer(minLength: 0)

                            HStack(spacing: 3) {
                                ForEach(0..<5, id: \.self) { level in
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(Color(uiColor: palette.contributionLevels[level]))
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                        .padding(8)
                    }

                VStack(spacing: 6) {
                    Circle()
                        .fill(Color(uiColor: palette.accent))
                        .frame(width: 22, height: 22)

                    Capsule()
                        .fill(Color(uiColor: palette.progressIndicator))
                        .frame(width: 30, height: 5)
                }
                .frame(width: 34)
            }
            .padding(8)
        }
        .frame(height: 62)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(uiColor: palette.separator), lineWidth: 1)
        }
    }
}
