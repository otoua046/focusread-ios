import SwiftUI

struct AIRecapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.focusReadTheme) private var theme
    @StateObject private var viewModel: AIRecapViewModel
    @State private var readingRecap: AIRecap?
    @AppStorage(AIRecapSettingsKey.isEnabled) private var aiRecapsEnabledPreference: Bool = AIRecapSettings.defaultEnabled()

    let onOpenRSVP: (AIRecap) -> Void

    init(
        read: SavedRead,
        readingStatsStore: ReadingStatsStore,
        recapStore: AIRecapStore,
        onOpenRSVP: @escaping (AIRecap) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: AIRecapViewModel(
            read: read,
            readingStatsStore: readingStatsStore,
            recapStore: recapStore
        ))
        self.onOpenRSVP = onOpenRSVP
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                    }

                    if !viewModel.isLocalAIAvailable {
                        unavailableState
                    } else if !isAIRecapsEnabled {
                        disabledState
                    } else if viewModel.items.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.items) { item in
                                AIRecapSessionRow(
                                    item: item,
                                    isGenerating: viewModel.generatingSessionID == item.id,
                                    canGenerate: isAIRecapsEnabled && viewModel.isLocalAIAvailable && !viewModel.isGenerating,
                                    onRead: { recap in
                                        readingRecap = recap
                                    },
                                    onRSVP: { recap in
                                        guard isAIRecapsEnabled else { return }
                                        dismiss()
                                        onOpenRSVP(recap)
                                    },
                                    onGenerate: {
                                        viewModel.generate(for: item)
                                    },
                                    onRegenerate: {
                                        viewModel.generate(for: item, regenerate: true)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background(FocusReadBackground())
            .navigationTitle(L10n.key(.aiRecapTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.commonDone) {
                        dismiss()
                    }
                }

                if viewModel.isGenerating {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(.commonCancel) {
                            viewModel.cancelGeneration()
                        }
                    }
                }
            }
        }
        .sheet(item: $readingRecap) { recap in
            AIRecapTextView(recap: recap, bookTitle: viewModel.read.displayTitle)
        }
        .onChange(of: aiRecapsEnabledPreference) {
            viewModel.refresh()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .focusReadThemeRefresh()
    }

    private var isAIRecapsEnabled: Bool {
        _ = aiRecapsEnabledPreference
        return AIRecapSettings.isEnabled(localAIAvailable: viewModel.isLocalAIAvailable)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.read.displayTitle)
                .font(.headline)
                .foregroundStyle(theme.primaryText)
                .lineLimit(2)

            if viewModel.hasEligibleSessions {
                Label(.aiRecapGeneratedFromLastSession, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryButtonForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.primaryButtonBackground, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 54, height: 54)
                .background(theme.controlBackground, in: Circle())

            Text(.aiRecapNoReadySessions)
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            Text(viewModel.hasOnlyTooShortSessions ? L10n.string(.aiRecapTooShort) : L10n.string(.aiRecapEmptyHint))
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(20)
    }

    private var disabledState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 54, height: 54)
                .background(theme.controlBackground, in: Circle())

            Text(.aiRecapDisabled)
                .font(.headline)
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(20)
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 54, height: 54)
                .background(theme.controlBackground, in: Circle())

            Text(.aiRecapUnavailable)
                .font(.headline)
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(20)
    }

    private func errorBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(theme.destructive)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AIRecapSessionRow: View {
    let item: AIRecapSessionItem
    let isGenerating: Bool
    let canGenerate: Bool
    let onRead: (AIRecap) -> Void
    let onRSVP: (AIRecap) -> Void
    let onGenerate: () -> Void
    let onRegenerate: () -> Void

    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.isMostRecent ? L10n.string(.aiRecapLastSession) : L10n.string(.aiRecapRecentSession))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    Text(sessionSubtitle)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 10)

                if isGenerating {
                    ProgressView()
                        .tint(theme.primaryText)
                } else if item.recap != nil {
                    Text(.aiRecapReady)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.controlBackground, in: Capsule())
                }
            }

            if isGenerating {
                Text(.aiRecapGenerating)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
            } else if let recap = item.recap {
                Text(recap.generatedText)
                    .font(.callout)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(4)
                    .lineSpacing(3)

                ViewThatFits(in: .horizontal) {
                    horizontalActionButtons(for: recap)

                    VStack(alignment: .leading, spacing: 8) {
                        verticalActionButtons(for: recap)
                    }
                }
            } else if item.isMostRecent {
                Button {
                    onGenerate()
                } label: {
                    Label(.aiRecapGenerate, systemImage: "sparkles")
                }
                .buttonStyle(.focusReadProminentAction(
                    shape: .rounded(10),
                    minHeight: 38,
                    horizontalPadding: 12,
                    verticalPadding: 9,
                    font: .footnote.weight(.semibold)
                ))
                .disabled(!canGenerate)
            } else {
                Text(.aiRecapNoGenerated)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.border.opacity(0.45), lineWidth: 1)
        }
    }

    private var sessionSubtitle: String {
        let date = item.session.endedAt.formatted(date: .abbreviated, time: .shortened)
        let formattedWordCount = NumberFormatter.localizedString(
            from: NSNumber(value: item.session.wordsRead),
            number: .decimal
        )
        let words = L10n.format(.statsWordsReadFormat, formattedWordCount)
        return "\(date) · \(words)"
    }

    private func horizontalActionButtons(for recap: AIRecap) -> some View {
        HStack(spacing: 10) {
            Button(.aiRecapRead) {
                onRead(recap)
            }
            .buttonStyle(primaryActionStyle)

            Button(.aiRecapRSVP) {
                onRSVP(recap)
            }
            .buttonStyle(secondaryActionStyle)

            Button(.aiRecapRegenerate) {
                onRegenerate()
            }
            .buttonStyle(secondaryActionStyle)
            .disabled(!canGenerate)
        }
    }

    private func verticalActionButtons(for recap: AIRecap) -> some View {
        Group {
            Button(.aiRecapRead) {
                onRead(recap)
            }
            .buttonStyle(primaryActionStyle)

            Button(.aiRecapRSVP) {
                onRSVP(recap)
            }
            .buttonStyle(secondaryActionStyle)

            Button(.aiRecapRegenerate) {
                onRegenerate()
            }
            .buttonStyle(secondaryActionStyle)
            .disabled(!canGenerate)
        }
    }

    private var primaryActionStyle: FocusReadProminentActionButtonStyle {
        .focusReadProminentAction(
            shape: .rounded(10),
            fullWidth: false,
            minHeight: 38,
            horizontalPadding: 12,
            verticalPadding: 9,
            font: .footnote.weight(.semibold)
        )
    }

    private var secondaryActionStyle: FocusReadSecondaryActionButtonStyle {
        .focusReadSecondaryAction(
            shape: .rounded(10),
            fullWidth: false,
            minHeight: 38,
            horizontalPadding: 12,
            verticalPadding: 9,
            font: .footnote.weight(.semibold)
        )
    }
}

private struct AIRecapTextView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.focusReadTheme) private var theme

    let recap: AIRecap
    let bookTitle: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(bookTitle)
                        .font(.headline)
                        .foregroundStyle(theme.primaryText)

                    Label(.aiRecapGeneratedLabel, systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryButtonForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.primaryButtonBackground, in: Capsule())

                    Text(recap.generatedText)
                        .font(.body)
                        .foregroundStyle(theme.primaryText)
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
            .background(FocusReadBackground())
            .navigationTitle(L10n.key(.aiRecapTitle))
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
}
