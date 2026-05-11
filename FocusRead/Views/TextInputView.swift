import SwiftUI
import UIKit

enum FocusReadHomeDemoContent {
    static var readerSampleText: String {
        L10n.string(.homeDemoSample)
    }

    static var heroWords: [String] {
        localizedWords(for: .homeHeroWords)
    }

    static var comparisonWords: [String] {
        localizedWords(for: .homeComparisonWords)
    }

    private static func localizedWords(for key: L10n.Key) -> [String] {
        L10n.string(key)
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private enum HomeSettingsKey {
    static let selectedReadingGoal = "home.selectedReadingGoal"
}

private enum HomeReadingGoal: String, CaseIterable, Identifiable {
    case study
    case books
    case focus
    case work
    case languages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .study:
            return L10n.string(.homeGoalStudy)
        case .books:
            return L10n.string(.homeGoalBooks)
        case .focus:
            return L10n.string(.homeGoalFocus)
        case .work:
            return L10n.string(.homeGoalWork)
        case .languages:
            return L10n.string(.homeGoalLanguages)
        }
    }

    var systemImageName: String {
        switch self {
        case .study:
            return "graduationcap"
        case .books:
            return "book.closed"
        case .focus:
            return "scope"
        case .work:
            return "briefcase"
        case .languages:
            return "character.book.closed"
        }
    }
}

struct TextInputView: View {
    let onStartDemo: () -> Void
    let onStartImportedDocument: (ImportedDocument) -> Void

    @StateObject private var documentImportViewModel = DocumentImportViewModel()
    @AppStorage(HomeSettingsKey.selectedReadingGoal) private var selectedGoalRawValue = HomeReadingGoal.focus.rawValue
    @AppStorage(AIRecapSettingsKey.isEnabled) private var aiRecapsEnabledPreference: Bool = AIRecapSettings.defaultEnabled()
    @State private var showingPremiumPlaceholder = false
    @State private var hasScrolledUnderTop = false

    private let aiRecapCapabilityService = AIRecapService()
    private let scrollCoordinateSpaceName = "homeScroll"

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    FocusReadScrollTopTracker(coordinateSpaceName: scrollCoordinateSpaceName)

                    HomeHeroDemoView()

                    HomeCTASection(
                        documentImportViewModel: documentImportViewModel,
                        onStartDemo: onStartDemo
                    )

                    ReadingComparisonCard()

                    ReadingGoalPicker(selectedGoal: selectedGoalBinding)

                    AIRecapPreviewCard(
                        localAIAvailable: aiRecapCapabilityService.isAvailable,
                        aiRecapsEnabled: aiRecapsEnabled
                    )

                    ThemePreviewStrip()

                    PremiumTeaserCard {
                        // TODO: Wire this button to the subscription flow when product configuration exists.
                        showingPremiumPlaceholder = true
                    }
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .coordinateSpace(name: scrollCoordinateSpaceName)
            .onPreferenceChange(FocusReadScrollOffsetPreferenceKey.self) { offset in
                hasScrolledUnderTop = offset < -1
            }
            .scrollIndicators(.hidden)
            .background(FocusReadBackground())
            .focusReadTopSafeAreaMaterial(isElevated: hasScrolledUnderTop)
            .documentImportFlow(
                viewModel: documentImportViewModel,
                onStartImportedDocument: onStartImportedDocument
            )
            .alert(L10n.string(.homePremiumPreviewTitle), isPresented: $showingPremiumPlaceholder) {
                Button(.commonOK, role: .cancel) {}
            } message: {
                Text(.homePremiumMessage)
            }
        }
        .focusReadThemeRefresh()
    }

    private var selectedGoalBinding: Binding<HomeReadingGoal> {
        Binding(
            get: {
                HomeReadingGoal(rawValue: selectedGoalRawValue) ?? .focus
            },
            set: { newGoal in
                selectedGoalRawValue = newGoal.rawValue
            }
        )
    }

    private var aiRecapsEnabled: Bool {
        AIRecapSettings.shouldShowEntryPoints(
            storedPreference: aiRecapsEnabledPreference,
            localAIAvailable: aiRecapCapabilityService.isAvailable
        )
    }
}

private struct HomeHeroDemoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentWordIndex = 0

    var body: some View {
        let heroWords = FocusReadHomeDemoContent.heroWords

        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("FocusRead")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text(.homeHeroSubtitle)
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: 460)
            }
            .padding(.horizontal, 6)

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.82))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(AppTheme.border.opacity(0.68), lineWidth: 1)
                    }
                    .shadow(color: AppTheme.subtleShadow, radius: 18, x: 0, y: 10)

                RSVPStageBackground()

                if !heroWords.isEmpty {
                    HomeRSVPWordView(
                        word: heroWords[currentWordIndex % heroWords.count],
                        size: 46
                    )
                    .id(currentWordIndex)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .padding(.horizontal, 28)
                }
            }
            .frame(height: 174)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.string(.homeAnimatedDemoAccessibility))
        }
        .task(id: reduceMotion) {
            if reduceMotion {
                await MainActor.run {
                    currentWordIndex = 0
                }
                return
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(780))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(.smooth(duration: 0.34)) {
                        let wordCount = max(FocusReadHomeDemoContent.heroWords.count, 1)
                        currentWordIndex = (currentWordIndex + 1) % wordCount
                    }
                }
            }
        }
    }
}

private struct RSVPStageBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let centerX = proxy.size.width / 2

            ZStack {
                Rectangle()
                    .fill(AppTheme.accent.opacity(0.16))
                    .frame(width: 1, height: 104)
                    .position(x: centerX, y: proxy.size.height / 2)

                Circle()
                    .strokeBorder(AppTheme.accent.opacity(0.14), lineWidth: 1)
                    .frame(width: 92, height: 92)
                    .position(x: centerX, y: proxy.size.height / 2)

                VStack(spacing: 12) {
                    Capsule()
                        .fill(AppTheme.secondaryText.opacity(0.08))
                        .frame(width: 148, height: 4)

                    Spacer()

                    Capsule()
                        .fill(AppTheme.secondaryText.opacity(0.08))
                        .frame(width: 96, height: 4)
                }
                .padding(.vertical, 28)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ReadingComparisonCard: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case normal
        case focusRead

        var id: String { rawValue }

        var title: String {
            switch self {
            case .normal:
                return L10n.string(.homeModeNormal)
            case .focusRead:
                return L10n.string(.homeModeFocusRead)
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode = .normal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(.homeSeeShift)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    ForEach(Mode.allCases) { item in
                        Button {
                            withAnimation(.smooth(duration: 0.22)) {
                                mode = item
                            }
                        } label: {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                                .foregroundStyle(mode == item ? AppTheme.primaryButtonForeground : AppTheme.secondaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(minWidth: 72)
                                .background {
                                    if mode == item {
                                        Capsule()
                                            .fill(AppTheme.primaryButtonBackground)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(AppTheme.controlBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
                }
            }

            ZStack {
                if mode == .normal {
                    NormalReadingComparisonView(reduceMotion: reduceMotion)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    FocusReadingComparisonView(reduceMotion: reduceMotion)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .frame(height: 138)
        }
        .homeCard()
    }
}

private struct NormalReadingComparisonView: View {
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            normalReadingLayout(progress: 0.58)
        } else {
            TimelineView(.animation) { context in
                let progress = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.8)) / 3.8
                normalReadingLayout(progress: progress)
            }
        }
    }

    private func normalReadingLayout(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 11) {
                    Text(.homeNormalReadingDescription)
                        .font(.callout)
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(index == 0 ? AppTheme.secondaryText.opacity(0.24) : AppTheme.secondaryText.opacity(0.14))
                                .frame(width: lineWidth(for: index, in: proxy.size.width), height: 5)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)

                ScanIndicator(progress: progress)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func lineWidth(for index: Int, in availableWidth: CGFloat) -> CGFloat {
        let widths: [CGFloat] = [0.82, 0.94, 0.62]
        return max(80, availableWidth * widths[index])
    }
}

private struct ScanIndicator: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 0.999)
            let lineProgress = clampedProgress * 3
            let lineIndex = min(Int(lineProgress), 2)
            let localProgress = lineProgress - Double(lineIndex)
            let availableWidth = max(proxy.size.width - 52, 1)
            let x = 16 + availableWidth * localProgress
            let y = 24 + CGFloat(lineIndex) * 31

            ZStack {
                Capsule()
                    .fill(AppTheme.accent.opacity(0.18))
                    .frame(width: 52, height: 16)
                    .position(x: x, y: y)

                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 8, height: 8)
                    .position(x: x + 18, y: y)
            }
            .opacity(0.86)
        }
        .allowsHitTesting(false)
    }
}

private struct FocusReadingComparisonView: View {
    let reduceMotion: Bool

    var body: some View {
        let comparisonWords = FocusReadHomeDemoContent.comparisonWords

        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.controlBackground.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.58), lineWidth: 1)
                }

            RSVPStageBackground()
                .opacity(0.72)

            if reduceMotion, let firstWord = comparisonWords.first {
                HomeRSVPWordView(word: firstWord, size: 34)
                    .padding(.horizontal, 20)
            } else {
                TimelineView(.animation) { context in
                    let rawIndex = Int(context.date.timeIntervalSinceReferenceDate / 0.78)
                    let word = comparisonWords.isEmpty ? "" : comparisonWords[
                        rawIndex % comparisonWords.count
                    ]

                    HomeRSVPWordView(word: word, size: 34)
                        .id(word)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .padding(.horizontal, 20)
                }
            }
        }
    }
}

private struct ReadingGoalPicker: View {
    @Binding var selectedGoal: HomeReadingGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.homeReadingGoalPrompt)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 104), spacing: 8)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(HomeReadingGoal.allCases) { goal in
                    Button {
                        withAnimation(.smooth(duration: 0.18)) {
                            selectedGoal = goal
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: goal.systemImageName)
                                .font(.footnote.weight(.semibold))
                                .frame(width: 16)

                            Text(goal.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                        .foregroundStyle(selectedGoal == goal ? AppTheme.primaryButtonForeground : AppTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 11)
                        .background(
                            selectedGoal == goal ? AppTheme.primaryButtonBackground : AppTheme.controlBackground,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    selectedGoal == goal ? AppTheme.accent.opacity(0.9) : AppTheme.border.opacity(0.65),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selectedGoal == goal ? L10n.string(.commonSelected) : L10n.string(.commonNotSelected))
                }
            }
        }
        .homeCard()
        .sensoryFeedback(.selection, trigger: selectedGoal)
    }
}

private struct AIRecapPreviewCard: View {
    let localAIAvailable: Bool
    let aiRecapsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.controlBackground, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(cardTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 9) {
                RecapFlowStep(title: L10n.string(.homeRecapFlowRead), systemImageName: "book.pages")
                FlowChevron()
                RecapFlowStep(title: L10n.string(.homeRecapFlowRecap), systemImageName: "sparkles")
                FlowChevron()
                RecapFlowStep(title: L10n.string(.homeRecapFlowKeyIdeas), systemImageName: "checklist")
            }
        }
        .homeCard()
    }

    private var cardTitle: String {
        if aiRecapsEnabled {
            return L10n.string(.homeAIRecapEnabledTitle)
        }

        return L10n.string(.homeAIRecapUnavailableTitle)
    }

    private var statusText: String {
        if aiRecapsEnabled {
            return L10n.string(.homeAIRecapEnabledStatus)
        }

        if localAIAvailable {
            return L10n.string(.homeAIRecapAvailableStatus)
        }

        return L10n.string(.homeAIRecapRequiresStatus)
    }
}

private struct RecapFlowStep: View {
    let title: String
    let systemImageName: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImageName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.controlBackground, in: Circle())

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AppTheme.controlBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct FlowChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.tertiaryText)
            .frame(width: 10)
            .accessibilityHidden(true)
    }
}

private struct ThemePreviewStrip: View {
    @Environment(\.colorScheme) private var colorScheme
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                    Text(.homeReadingSpace)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text(.homeThemes)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(previewThemes) { theme in
                        ThemePreviewTile(
                            theme: theme,
                            colorScheme: colorScheme,
                            isSelected: themeManager.selectedThemeID == theme.id
                        ) {
                            withAnimation(.smooth(duration: 0.2)) {
                                themeManager.select(theme)
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
        }
        .homeCard()
    }
}

private struct ThemePreviewTile: View {
    let theme: FocusReadTheme
    let colorScheme: ColorScheme
    let isSelected: Bool
    let action: () -> Void

    private var palette: FocusReadThemePalette {
        theme.palette(for: colorScheme == .dark ? .dark : .light)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: palette.primaryBackground))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(uiColor: palette.accent))
                                .frame(width: 18, height: 18)

                            Capsule()
                                .fill(Color(uiColor: palette.primaryText))
                                .frame(width: 44, height: 5)
                        }

                        Spacer(minLength: 0)

                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(uiColor: palette.cardSurface))
                            .frame(height: 28)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color(uiColor: palette.secondaryText).opacity(0.44))
                                    .frame(width: 48, height: 4)
                                    .padding(.leading, 8)
                            }
                    }
                    .padding(10)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(uiColor: palette.accent))
                            .padding(7)
                    }
                }
                .frame(width: 116, height: 76)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isSelected ? Color(uiColor: palette.accent) : Color(uiColor: palette.separator), lineWidth: isSelected ? 1.5 : 1)
                }

                Text(theme.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(width: 116, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityValue(isSelected ? L10n.string(.commonSelected) : L10n.string(.commonNotSelected))
    }
}

private struct HomeCTASection: View {
    @ObservedObject var documentImportViewModel: DocumentImportViewModel
    let onStartDemo: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onStartDemo) {
                Label(.homeTryFocusRead, systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryButtonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.primaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            ImportSourceMenu(
                viewModel: documentImportViewModel,
                onSourceSelected: {}
            ) {
                Label(.homeImportBook, systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppTheme.border.opacity(0.76), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PremiumTeaserCard: View {
    let onViewPremium: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "crown")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.controlBackground, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(.homePremiumTeaser)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onViewPremium) {
                Label(.homeViewPremium, systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .homeCard()
    }
}

private struct HomeRSVPWordView: View {
    let word: String
    let size: CGFloat

    @AppStorage(ReaderBehaviorSettingsKey.anchorLetterEnabled) private var anchorLetterEnabled = true

    var body: some View {
        Group {
            if anchorLetterEnabled, let parts = HomeORPParts(word: word) {
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
        .font(.system(size: size, weight: .semibold, design: .serif))
        .foregroundStyle(AppTheme.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.42)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(word)
    }
}

private struct HomeORPParts {
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
        character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}

private extension View {
    func homeCard() -> some View {
        padding(16)
            .background(AppTheme.cardBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AppTheme.border.opacity(0.68), lineWidth: 1)
            }
            .shadow(color: AppTheme.subtleShadow.opacity(0.72), radius: 12, x: 0, y: 6)
    }
}

struct FocusReadBackground: View {
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        LinearGradient(
            colors: [
                theme.background,
                theme.secondaryBackground.opacity(0.78),
                theme.cardBackground.opacity(0.72),
                theme.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
