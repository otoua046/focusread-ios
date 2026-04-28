import SwiftUI

struct ReaderControlsView: View {
    @ObservedObject var viewModel: ReaderViewModel

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Button {
                    viewModel.rewindSentence()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .foregroundStyle(AppTheme.controlForeground)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.controlBackground, in: Circle())
                        .overlay {
                            Circle().strokeBorder(AppTheme.border, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rewind sentence")

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

                Button {
                    viewModel.adjustSpeed(by: 25)
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppTheme.controlForeground)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.controlBackground, in: Circle())
                        .overlay {
                            Circle().strokeBorder(AppTheme.border, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase speed")
            }
            .font(.headline)

            VStack(spacing: 8) {
                HStack {
                    Button {
                        viewModel.adjustSpeed(by: -25)
                    } label: {
                        Image(systemName: "minus")
                            .foregroundStyle(AppTheme.controlForeground)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.controlBackground, in: Circle())
                            .overlay {
                                Circle().strokeBorder(AppTheme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Decrease speed")

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.wordsPerMinute) },
                            set: { viewModel.setWPM(Int($0.rounded()), haptic: false) }
                        ),
                        in: Double(ReadingSession.minimumWPM)...Double(ReadingSession.maximumWPM),
                        step: 5
                    )
                    .tint(AppTheme.primaryText)

                    Button {
                        viewModel.adjustSpeed(by: 25)
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(AppTheme.controlForeground)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.controlBackground, in: Circle())
                            .overlay {
                                Circle().strokeBorder(AppTheme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Increase speed")
                }

                Text("\(viewModel.wordsPerMinute) words per minute")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .monospacedDigit()
            }
            .padding(16)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            }
            .frame(maxWidth: 440)
        }
    }
}
