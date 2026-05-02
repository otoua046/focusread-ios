import SwiftUI

struct ReaderControlsView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Binding var isWPMControlInteracting: Bool

    init(
        viewModel: ReaderViewModel,
        isWPMControlInteracting: Binding<Bool> = .constant(false)
    ) {
        self.viewModel = viewModel
        self._isWPMControlInteracting = isWPMControlInteracting
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                if viewModel.sectionNavigationAvailable {
                    edgeButton(systemName: "chevron.left.to.line") {
                        viewModel.jumpToPreviousSection()
                    }
                    .disabled(!viewModel.canJumpToPreviousSection)
                    .opacity(viewModel.canJumpToPreviousSection ? 1 : 0.35)
                    .accessibilityLabel("Previous section")
                }

                Button {
                    viewModel.rewindWord()
                } label: {
                    Image(systemName: "gobackward")
                        .foregroundStyle(AppTheme.controlForeground)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.controlBackground, in: Circle())
                        .overlay {
                            Circle().strokeBorder(AppTheme.border, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rewind word")

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryButtonForeground)
                        .frame(width: 62, height: 62)
                        .background(AppTheme.primaryButtonBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

                Button {
                    viewModel.skipWord()
                } label: {
                    Image(systemName: "goforward")
                        .foregroundStyle(AppTheme.controlForeground)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.controlBackground, in: Circle())
                        .overlay {
                            Circle().strokeBorder(AppTheme.border, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip word")

                if viewModel.sectionNavigationAvailable {
                    edgeButton(systemName: "chevron.right.to.line") {
                        viewModel.jumpToNextSection()
                    }
                    .disabled(!viewModel.canJumpToNextSection)
                    .opacity(viewModel.canJumpToNextSection ? 1 : 0.35)
                    .accessibilityLabel("Next section")
                }
            }
            .font(.headline)

            WPMDialControl(
                currentWPM: viewModel.wordsPerMinute,
                updateWPM: { value, haptic in
                    viewModel.setWPM(value, haptic: haptic)
                },
                revealControls: {
                    viewModel.revealControls()
                },
                isInteracting: $isWPMControlInteracting
            )
        }
    }

    private func edgeButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(FlatReaderEdgeButtonStyle())
    }
}

private struct WPMDialControl: View {
    let currentWPM: Int
    let updateWPM: (_ value: Int, _ haptic: Bool) -> Void
    let revealControls: () -> Void
    @Binding var isInteracting: Bool

    @State private var dragStartWPM: Int?
    @State private var lastProposedWPM: Int?
    @State private var rulerOffset: CGFloat = 0
    @State private var revealToken = 0

    var body: some View {
        HStack(spacing: 1) {
            nudgeButton(systemName: "minus", label: "Decrease speed") {
                nudge(direction: -1)
            }

            dialFace

            nudgeButton(systemName: "plus", label: "Increase speed") {
                nudge(direction: 1)
            }
        }
        .frame(maxWidth: 360)
        .animation(.smooth(duration: 0.2), value: currentWPM)
        .animation(.smooth(duration: 0.18), value: isInteracting)
    }

    private var dialFace: some View {
        ZStack(alignment: .center) {
            tickRuler
                .offset(y: 18)
                .opacity(isInteracting ? 1 : 0.06)
                .blur(radius: isInteracting ? 0 : 1.6)

            Text("\(currentWPM) WPM")
                .font(.system(.headline, design: .default, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(currentWPM)))
                .scaleEffect(isInteracting ? 1.025 : 1)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(width: 180, height: 68)
        .contentShape(Rectangle())
        .gesture(speedDragGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading speed")
        .accessibilityValue("\(currentWPM) words per minute")
        .accessibilityHint("Drag left or right to adjust reading speed.")
    }

    private var tickRuler: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<41, id: \.self) { index in
                    let majorTick = index.isMultiple(of: 5)

                    Capsule()
                        .fill(AppTheme.secondaryText.opacity(majorTick ? 0.44 : 0.18))
                        .frame(width: majorTick ? 1.6 : 1, height: majorTick ? 18 : 8)
                }
            }
            .offset(x: rulerOffset)

            Capsule()
                .fill(Color(uiColor: .systemYellow))
                .frame(width: 2.2, height: 25)
                .shadow(color: Color(uiColor: .systemYellow).opacity(isInteracting ? 0.28 : 0), radius: 4)
        }
        .frame(width: 198, height: 30)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var speedDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartWPM == nil {
                    dragStartWPM = currentWPM
                    lastProposedWPM = currentWPM
                    revealDial()
                    revealControls()
                }

                guard let dragStartWPM else { return }

                let dragWidth = reversedDragDirection ? -value.translation.width : value.translation.width
                let proposedWPM = dragStartWPM + Int((dragWidth / 8).rounded())
                if proposedWPM != lastProposedWPM {
                    updateWPM(proposedWPM, true)
                    lastProposedWPM = proposedWPM
                }

                rulerOffset = dragWidth.truncatingRemainder(dividingBy: 9)
            }
            .onEnded { _ in
                dragStartWPM = nil
                lastProposedWPM = nil
                withAnimation(.smooth(duration: 0.2)) {
                    rulerOffset = 0
                }
                hideDial(after: 0.18)
            }
    }

    private func nudgeButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.callout.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 24, height: 42)
                .opacity(isInteracting ? 0.62 : 0.42)
                .contentShape(Rectangle())
        }
        .buttonStyle(WPMNudgeButtonStyle())
        .accessibilityLabel(label)
    }

    private func nudge(direction: Int) {
        revealControls()
        revealDial()

        let targetWPM = snappedButtonValue(direction: direction)
        updateWPM(targetWPM, true)

        withAnimation(.smooth(duration: 0.16)) {
            rulerOffset = CGFloat(direction) * -8
        }
        withAnimation(.smooth(duration: 0.18).delay(0.08)) {
            rulerOffset = 0
        }

        hideDial(after: 0.72)
    }

    private func revealDial() {
        revealToken += 1
        withAnimation(.smooth(duration: 0.16)) {
            isInteracting = true
        }
    }

    private func snappedButtonValue(direction: Int) -> Int {
        let step = 25
        let current = currentWPM

        if direction > 0 {
            let nextMultiple = ((current + step) / step) * step
            return nextMultiple == current ? current + step : nextMultiple
        } else {
            let previousMultiple = (current / step) * step
            return previousMultiple == current ? current - step : previousMultiple
        }
    }

    private func hideDial(after delay: TimeInterval) {
        let token = revealToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token == revealToken else { return }
            withAnimation(.smooth(duration: 0.22)) {
                isInteracting = false
            }
        }
    }

    @AppStorage(ReaderBehaviorSettingsKey.reverseWPMDialDirection) private var reversedDragDirection: Bool = false
}

private struct WPMNudgeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.68 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}

private struct FlatReaderEdgeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.62 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}
