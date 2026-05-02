import SwiftUI
import Translation

extension HorizontalAlignment {
    private enum AnchorCenter: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat {
            d[HorizontalAlignment.center]
        }
    }
    static let anchorCenter = HorizontalAlignment(AnchorCenter.self)
}

struct ReaderView: View {
    @ObservedObject var viewModel: ReaderViewModel
    let onClose: () -> Void

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

    @State private var verticalDragStartWPM: Int?
    @State private var wpmDialInteractionActive = false
    @State private var actionPaletteInteractionActive = false
    @State private var showingActionPalette = false
    @State private var showingTypographySettings = false
    @State private var showingGoToNavigation = false
    @State private var showingTranslation = false

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
                currentWord: viewModel.currentWord,
                onToggle: toggleActionPalette,
                onDictionary: {
                    viewModel.lookupCurrentWord()
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
        .animation(.smooth(duration: 0.18), value: viewModel.currentWord)
        .sheet(isPresented: $showingTypographySettings) {
            TypographySettingsView(readingStatsStore: readingStatsStore)
        }
        .sheet(isPresented: $showingGoToNavigation) {
            GoToNavigationView(readerViewModel: viewModel)
        }
        .sheet(item: $viewModel.lookupRequest) { request in
            DictionaryLookupView(term: request.term)
        }
        .translationPresentation(isPresented: $showingTranslation, text: viewModel.currentWord)
        .alert("No definition found.", isPresented: $viewModel.noDefinitionFound) {
            Button("OK", role: .cancel) {}
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
                .buttonStyle(.topReaderControl)
                .accessibilityLabel("Close reader")
                .zIndex(1)

                Spacer()
            }

            VStack(spacing: 3) {
                Text(viewModel.locationIndicatorTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                Text(viewModel.progressLabel)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .padding(.horizontal, 58)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 2)
        .frame(height: 44)
    }

    private var wordStage: some View {
        VStack(spacing: 28) {
            let parts = viewModel.currentWordParts
            
            ZStack {
                if parts.isAnchorEnabled && !viewModel.isTwoWordMode {
                    ViewThatFits(in: .horizontal) {
                        anchoredLayout(parts: parts)
                            .fixedSize(horizontal: true, vertical: false)
                        
                        Text(viewModel.currentAttributedWord)
                            .minimumScaleFactor(0.4)
                            .multilineTextAlignment(.center)
                    }
                    .typographyStyle(currentStyle)
                    .lineLimit(1)
                } else {
                    Text(viewModel.currentAttributedWord)
                        .typographyStyle(currentStyle)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Rectangle()
                    .fill(AppTheme.border.opacity(0.25))
                    .frame(width: 1, height: 130)
                    .allowsHitTesting(false)
            }
            .id(viewModel.currentWord)
            .contentTransition(.opacity)
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
                    .tint(AppTheme.accent)
                    .frame(maxWidth: 320)
                    .opacity(viewModel.controlsVisible ? 0.75 : 0.18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reading progress")
            .accessibilityHint("Tap to search words")
            .accessibilityAction(named: "Search Word") {
                    viewModel.prepareForSearchNavigation()
                    showingGoToNavigation = true
            }
        }
        .padding(.horizontal, 8)
    }

    private func anchoredLayout(parts: WordParts) -> some View {
        HStack(spacing: 0) {
            Text(parts.prefix)
            Text(parts.anchor)
                .foregroundStyle(AppTheme.accent)
                .alignmentGuide(.anchorCenter) { d in d[HorizontalAlignment.center] }
            Text(parts.suffix)
        }
        .alignmentGuide(HorizontalAlignment.center) { d in d[.anchorCenter] }
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
