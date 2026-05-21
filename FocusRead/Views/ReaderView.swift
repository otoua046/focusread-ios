import SwiftUI
import Translation
import UIKit

struct ReaderView: View {
    @ObservedObject var viewModel: ReaderViewModel
    let onClose: () -> Void
    let onOpenRecapRSVP: (SavedRead, AIRecap) -> Void

    @AppStorage(TypographySettingsKey.fontFamily) private var fontFamily: String = ReaderFontFamily.serif.rawValue
    @AppStorage(TypographySettingsKey.fontSize) private var fontSize: Double = FontStyle.defaultSize
    @AppStorage(TypographySettingsKey.fontWeight) private var fontWeight: String = ReaderFontWeight.regular.rawValue
    @AppStorage(TypographySettingsKey.isItalic) private var isItalic: Bool = false
    @AppStorage(TypographySettingsKey.textColor) private var textColor: String = ReaderTextColor.primary.rawValue
    @AppStorage(ReaderBehaviorSettingsKey.punctuationPausesEnabled) private var punctuationPausesEnabled: Bool = true
    @AppStorage(ReaderBehaviorSettingsKey.longWordDelayMode) private var longWordDelayMode: String = LongWordDelayMode.moderate.rawValue
    @AppStorage(ReaderBehaviorSettingsKey.anchorLetterEnabled) private var anchorLetterEnabled: Bool = true
    @AppStorage(ReaderBehaviorSettingsKey.displayMode) private var displayMode: String = ReaderDisplayMode.oneWord.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var readingStatsStore: LocalReadingStatsStore
    @EnvironmentObject private var recapStore: LocalAIRecapStore

    @State private var verticalDragStartWPM: Int?
    @State private var wpmDialInteractionActive = false
    @State private var actionPaletteInteractionActive = false
    @State private var showingActionPalette = false
    @State private var showingTypographySettings = false
    @State private var showingGoToNavigation = false
    @State private var showingCurrentLocationPreview = false
    @State private var showingTranslation = false
    @State private var aiRecapTarget: SavedRead?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            FocusReadBackground()

            VStack {
                topBar
                    .opacity(viewModel.controlsVisible ? 1 : 0.18)
                    .offset(y: viewModel.controlsVisible ? 0 : -16)

                Spacer(minLength: 24)

                wordStage

                Spacer(minLength: 24)

                ReaderControlsView(
                    viewModel: viewModel,
                    isWPMControlInteracting: $wpmDialInteractionActive
                )
                    .opacity(viewModel.controlsVisible ? 1 : 0.08)
                    .offset(y: viewModel.controlsVisible ? 0 : 24)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            ReaderActionPaletteView(
                isPresented: $showingActionPalette,
                isInteracting: $actionPaletteInteractionActive,
                isVisible: viewModel.controlsVisible || showingActionPalette,
                isTranslateSupported: viewModel.isTranslationAvailable,
                isAIRecapSupported: viewModel.savedReadForAIRecap != nil,
                currentWord: viewModel.currentWord,
                onToggle: toggleActionPalette,
                onDictionary: {
                    viewModel.lookupCurrentWord()
                },
                onAIRecap: {
                    presentAIRecap()
                },
                onLookup: {
                    viewModel.prepareForSearchNavigation()
                    showingGoToNavigation = true
                },
                onTranslate: {
                    viewModel.pause(showControls: true)
                    showingTranslation = true
                },
                onSettings: {
                    viewModel.pause(showControls: true)
                    showingTypographySettings = true
                }
            )
            .zIndex(2)
        }
        .contentShape(Rectangle())
        .gesture(tapGesture)
        .simultaneousGesture(horizontalSwipeGesture)
        .simultaneousGesture(verticalSpeedGesture)
        .animation(.smooth(duration: 0.25), value: viewModel.controlsVisible)
        .sheet(isPresented: $showingTypographySettings) {
            TypographySettingsView(readingStatsStore: readingStatsStore)
        }
        .sheet(isPresented: $showingGoToNavigation) {
            GoToNavigationView(readerViewModel: viewModel)
        }
        .sheet(item: $aiRecapTarget) { read in
            AIRecapView(
                read: read,
                readingStatsStore: readingStatsStore,
                recapStore: recapStore,
                onOpenRSVP: { recap in
                    onOpenRecapRSVP(read, recap)
                }
            )
        }
        .sheet(isPresented: $showingCurrentLocationPreview) {
            CurrentLocationPreviewView(preview: viewModel.currentLocationPreview)
        }
        .sheet(item: $viewModel.lookupRequest) { request in
            DictionaryLookupView(term: request.term)
        }
        .translationPresentation(isPresented: $showingTranslation, text: viewModel.currentWordForTranslation)
        .alert(L10n.string(.readerNoDefinitionFound), isPresented: $viewModel.noDefinitionFound) {
            Button(.commonOK, role: .cancel) {}
        }
        .onAppear {
            syncBehaviorSettings()
        }
        .onChange(of: punctuationPausesEnabled) {
            syncBehaviorSettings()
        }
        .onChange(of: longWordDelayMode) {
            syncBehaviorSettings()
        }
        .onChange(of: anchorLetterEnabled) {
            syncBehaviorSettings()
        }
        .onChange(of: displayMode) {
            syncBehaviorSettings()
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                viewModel.prepareForInactiveScene()
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .focusReadThemeRefresh()
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Button {
                    viewModel.cleanup()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.focusReadIconControl())
                .accessibilityLabel(L10n.string(.readerClose))
                .zIndex(1)

                Spacer()

                Button {
                    presentCurrentLocationPreview()
                } label: {
                    Image(systemName: "text.page")
                }
                .buttonStyle(.focusReadIconControl())
                .accessibilityLabel(L10n.string(.readerCurrentLocation))
                .accessibilityHint(L10n.string(.readerCurrentLocationHint))
                .zIndex(1)
            }

            VStack(spacing: viewModel.readerModeBadge == nil ? 2 : 3) {
                if let readerModeBadge = viewModel.readerModeBadge {
                    Text(readerModeBadge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryButtonForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.primaryButtonBackground, in: Capsule())
                        .lineLimit(1)
                }

                Text(viewModel.locationIndicatorPrimaryTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)

                if let secondaryTitle = viewModel.locationIndicatorSecondaryTitle {
                    Text(secondaryTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity)
                }

                Text(viewModel.progressLabel)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: topBarTitleHeight)
            .padding(.horizontal, 58)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 2)
        .frame(height: topBarHeight)
    }

    private var topBarTitleHeight: CGFloat {
        if viewModel.readerModeBadge != nil {
            return 66
        }

        return viewModel.locationIndicatorSecondaryTitle == nil ? 38 : 54
    }

    private var topBarHeight: CGFloat {
        if viewModel.readerModeBadge != nil {
            return 70
        }

        return viewModel.locationIndicatorSecondaryTitle == nil ? 44 : 60
    }

    private var wordStage: some View {
        VStack(spacing: 28) {
            ZStack {
                if let parts = viewModel.currentWordParts {
                    ORPTextView(parts: parts, style: currentStyle)
                } else {
                    // Two-word mode or anchor highlighting only (centered)
                    Text(viewModel.currentAttributedWord)
                        .typographyStyle(currentStyle)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                ORPFixationGuide()
            }
            .id(viewModel.currentWord)
            .contentTransition(.opacity)
            .transaction { transaction in
                transaction.animation = nil
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .onLongPressGesture {
                viewModel.lookupCurrentWord()
            }

            Button {
                viewModel.prepareForSearchNavigation()
                showingGoToNavigation = true
            } label: {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .tint(AppTheme.progressIndicator)
                    .frame(maxWidth: 320)
                    .opacity(viewModel.controlsVisible ? 0.75 : 0.18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string(.readerProgress))
            .accessibilityHint(L10n.string(.readerProgressHint))
            .accessibilityAction(named: Text(L10n.key(.readerSearchWordAction))) {
                    viewModel.prepareForSearchNavigation()
                    showingGoToNavigation = true
            }
        }
        .padding(.horizontal, 8)
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

    private func syncBehaviorSettings() {
        viewModel.updateBehaviorSettings(ReaderBehaviorSettings(
            punctuationPausesEnabled: punctuationPausesEnabled,
            longWordDelayMode: LongWordDelayMode(rawValue: longWordDelayMode) ?? .moderate,
            anchorLetterEnabled: anchorLetterEnabled,
            displayMode: ReaderDisplayMode(rawValue: displayMode) ?? .oneWord
        ))
    }

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                guard !showingActionPalette else {
                    withAnimation(.smooth(duration: 0.18)) {
                        showingActionPalette = false
                    }
                    return
                }
                viewModel.togglePlayback()
            }
    }

    private func toggleActionPalette() {
        withAnimation(.smooth(duration: 0.2)) {
            if showingActionPalette {
                showingActionPalette = false
                return
            }

            showingActionPalette = true
            viewModel.pause(showControls: true)
            viewModel.revealControls()
        }
    }

    private func presentCurrentLocationPreview() {
        showingActionPalette = false
        viewModel.pause(showControls: true)
        viewModel.revealControls()
        showingCurrentLocationPreview = true
    }

    private func presentAIRecap() {
        showingActionPalette = false
        viewModel.pause(showControls: true)
        viewModel.revealControls()
        aiRecapTarget = viewModel.savedReadForAIRecap
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
                guard !showingActionPalette else { return }
                guard !actionPaletteInteractionActive else { return }
                guard !wpmDialInteractionActive else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width > 0 {
                    viewModel.rewindWord()
                } else {
                    viewModel.skipWord()
                }
            }
    }

    private var verticalSpeedGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onChanged { value in
                guard !showingActionPalette else { return }
                guard !actionPaletteInteractionActive else { return }
                guard !wpmDialInteractionActive else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                if verticalDragStartWPM == nil {
                    verticalDragStartWPM = viewModel.wordsPerMinute
                    viewModel.revealControls()
                }
                guard let start = verticalDragStartWPM else { return }
                let steps = Int((-value.translation.height / 18).rounded())
                viewModel.setWPM(start + steps * 25, haptic: false)
            }
            .onEnded { _ in
                verticalDragStartWPM = nil
            }
    }
}

struct CurrentLocationPreviewView: View {
    let preview: CurrentLocationPreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(preview.subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                    previewContainer
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(FocusReadBackground())
            .navigationTitle(preview.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.commonDone) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .focusReadThemeRefresh()
    }

    private var previewContainer: some View {
        Text(attributedPreviewText)
            .font(.body)
            .lineSpacing(7)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.border.opacity(0.45), lineWidth: 1)
            }
            .accessibilityLabel(accessibilityPreviewText)
    }

    private var attributedPreviewText: AttributedString {
        var result = AttributedString()

        for (index, part) in preview.parts.enumerated() {
            if index > 0 {
                result.append(AttributedString(" "))
            }

            var text = AttributedString(part.text)
            switch part.role {
            case .read:
                text.foregroundColor = AppTheme.primaryText
            case .current:
                text.foregroundColor = AppTheme.primaryText
                text.backgroundColor = AppTheme.searchHighlightBackground
                text.font = .body.weight(.semibold)
            case .unread:
                text.foregroundColor = AppTheme.secondaryText
            }
            result.append(text)
        }

        return result
    }

    private var accessibilityPreviewText: String {
        preview.parts
            .map(\.text)
            .joined(separator: " ")
    }
}

private enum ORPLayout {
    static let fixationRatio: CGFloat = 0.45
}

private struct ORPFixationGuide: View {
    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(AppTheme.border.opacity(0.25))
                .frame(width: 1, height: 130)
                .position(
                    x: proxy.size.width * ORPLayout.fixationRatio,
                    y: proxy.size.height / 2
                )
        }
        .frame(height: 130)
        .allowsHitTesting(false)
    }
}

private struct ORPTextView: View {
    let parts: WordParts
    let style: FontStyle

    var body: some View {
        let metrics = ORPTextMetrics(parts: parts, style: style)

        GeometryReader { proxy in
            let availableWidth = max(proxy.size.width, 1)
            let fixationX = availableWidth * ORPLayout.fixationRatio
            let layout = metrics.layout(fixationX: fixationX, availableWidth: availableWidth)

            HStack(spacing: 0) {
                Text(parts.prefix)
                Text(parts.anchor)
                    .foregroundStyle(AppTheme.orpHighlight)
                Text(parts.suffix)
            }
            .typographyStyle(style)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .scaleEffect(layout.scale, anchor: .topLeading)
            .offset(
                x: layout.leadingX,
                y: (proxy.size.height - metrics.lineHeight * layout.scale) / 2
            )
        }
        .frame(height: metrics.lineHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parts.fullWord)
    }
}

private struct ORPTextMetrics {
    let prefixWidth: CGFloat
    let anchorWidth: CGFloat
    let suffixWidth: CGFloat
    let lineHeight: CGFloat

    init(parts: WordParts, style: FontStyle) {
        let font = style.uiFont
        prefixWidth = Self.measure(parts.prefix, font: font)
        anchorWidth = Self.measure(parts.anchor, font: font)
        suffixWidth = Self.measure(parts.suffix, font: font)
        lineHeight = ceil(font.lineHeight)
    }

    func layout(fixationX: CGFloat, availableWidth: CGFloat) -> ORPTextLayout {
        let anchorCenterFromLeading = prefixWidth + anchorWidth / 2
        let rightReach = anchorWidth / 2 + suffixWidth
        let scale = min(
            1,
            Self.scaleLimit(available: fixationX, required: anchorCenterFromLeading),
            Self.scaleLimit(available: availableWidth - fixationX, required: rightReach)
        )
        let leadingX = fixationX - anchorCenterFromLeading * scale

        return ORPTextLayout(leadingX: leadingX, scale: scale)
    }

    private static func scaleLimit(available: CGFloat, required: CGFloat) -> CGFloat {
        guard required > 0 else { return 1 }
        return max(0.01, available / required)
    }

    private static func measure(_ text: String, font: UIFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }

        let size = (text as NSString).size(withAttributes: [.font: font])
        return ceil(size.width)
    }
}

private struct ORPTextLayout {
    let leadingX: CGFloat
    let scale: CGFloat
}

private extension FontStyle {
    var uiFont: UIFont {
        var descriptor = UIFont
            .systemFont(ofSize: size, weight: weight.uiFontWeight)
            .fontDescriptor

        if let design = family.uiFontDesign,
           let designedDescriptor = descriptor.withDesign(design) {
            descriptor = designedDescriptor
        }

        if isItalic,
           let italicDescriptor = descriptor.withSymbolicTraits(
                descriptor.symbolicTraits.union(.traitItalic)
           ) {
            descriptor = italicDescriptor
        }

        return UIFont(descriptor: descriptor, size: size)
    }
}

private extension ReaderFontFamily {
    var uiFontDesign: UIFontDescriptor.SystemDesign? {
        switch self {
        case .serif:
            return .serif
        case .system:
            return nil
        case .rounded:
            return .rounded
        case .monospaced:
            return .monospaced
        }
    }
}

private extension ReaderFontWeight {
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .bold:
            return .bold
        }
    }
}
