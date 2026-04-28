import SwiftUI

struct ReaderView: View {
    @ObservedObject var viewModel: ReaderViewModel
    let onClose: () -> Void

    @AppStorage(TypographySettingsKey.fontFamily) private var fontFamily: String = ReaderFontFamily.serif.rawValue
    @AppStorage(TypographySettingsKey.fontSize) private var fontSize: Double = FontStyle.defaultSize
    @AppStorage(TypographySettingsKey.fontWeight) private var fontWeight: String = ReaderFontWeight.regular.rawValue
    @AppStorage(TypographySettingsKey.isItalic) private var isItalic: Bool = false
    @AppStorage(TypographySettingsKey.textColor) private var textColor: String = ReaderTextColor.primary.rawValue

    @State private var verticalDragStartWPM: Int?
    @State private var showingTypographySettings = false

    var body: some View {
        ZStack {
            FocusReadBackground()

            VStack {
                topBar
                    .opacity(viewModel.controlsVisible ? 1 : 0.18)
                    .offset(y: viewModel.controlsVisible ? 0 : -16)

                Spacer(minLength: 24)

                wordStage

                Spacer(minLength: 24)

                ReaderControlsView(viewModel: viewModel)
                    .opacity(viewModel.controlsVisible ? 1 : 0.08)
                    .offset(y: viewModel.controlsVisible ? 0 : 24)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
        }
        .contentShape(Rectangle())
        .gesture(tapGesture)
        .simultaneousGesture(horizontalSwipeGesture)
        .simultaneousGesture(verticalSpeedGesture)
        .animation(.smooth(duration: 0.25), value: viewModel.controlsVisible)
        .animation(.smooth(duration: 0.18), value: viewModel.currentWord)
        .sheet(isPresented: $showingTypographySettings) {
            TypographySettingsView()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                viewModel.cleanup()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(AppTheme.controlForeground)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(AppTheme.controlBackground, in: Circle())
            .overlay {
                Circle().strokeBorder(AppTheme.border, lineWidth: 1)
            }
            .accessibilityLabel("Close reader")
            .zIndex(1)

            Spacer()

            VStack(spacing: 3) {
                Text("\(viewModel.wordsPerMinute) WPM")
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.progressLabel)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .monospacedDigit()

            Spacer()

            Button {
                showingTypographySettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.headline)
                    .foregroundStyle(AppTheme.controlForeground)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(AppTheme.controlBackground, in: Circle())
            .overlay {
                Circle().strokeBorder(AppTheme.border, lineWidth: 1)
            }
            .accessibilityLabel("Typography settings")
            .zIndex(1)
        }
        .padding(.horizontal, 2)
    }

    private var wordStage: some View {
        VStack(spacing: 28) {
            ZStack {
                Text(viewModel.currentWord)
                    .typographyStyle(currentStyle)
                    .minimumScaleFactor(0.42)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .id(viewModel.currentWord)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .multilineTextAlignment(.center)

                Rectangle()
                    .fill(AppTheme.border.opacity(0.25))
                    .frame(width: 1, height: 130)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)

            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .tint(AppTheme.primaryText)
                .frame(maxWidth: 320)
                .opacity(viewModel.controlsVisible ? 0.75 : 0.18)
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

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                viewModel.togglePlayback()
            }
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
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
