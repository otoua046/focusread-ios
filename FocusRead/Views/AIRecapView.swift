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
            .navigationTitle("AI Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if viewModel.isGenerating {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Cancel") {
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
                Label("Generated from your last reading session", systemImage: "sparkles")
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

            Text("No recap-ready sessions yet")
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            Text(viewModel.hasOnlyTooShortSessions ? "This reading session is too short to summarize." : "Read a little in RSVP mode, then come back to generate a short on-device recap.")
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

            Text("AI Recaps are disabled in Settings.")
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

            Text("AI Recap requires on-device Apple Intelligence support.")
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
                    Text(item.isMostRecent ? "Last session" : "Recent session")
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
                    Text("Ready")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.controlBackground, in: Capsule())
                }
            }

            if isGenerating {
                Text("Generating recap on device...")
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
                    Label("Generate Recap", systemImage: "sparkles")
                }
                .buttonStyle(.aiRecapPrimary)
                .disabled(!canGenerate)
            } else {
                Text("No recap generated for this session.")
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
        let words = "\(item.session.wordsRead) words"
        return "\(date) · \(words)"
    }

    private func horizontalActionButtons(for recap: AIRecap) -> some View {
        HStack(spacing: 10) {
            Button("Read Recap") {
                onRead(recap)
            }
            .buttonStyle(.aiRecapPrimary)

            Button("RSVP Recap") {
                onRSVP(recap)
            }
            .buttonStyle(.aiRecapSecondary)

            Button("Regenerate") {
                onRegenerate()
            }
            .buttonStyle(.aiRecapSecondary)
            .disabled(!canGenerate)
        }
    }

    private func verticalActionButtons(for recap: AIRecap) -> some View {
        Group {
            Button("Read Recap") {
                onRead(recap)
            }
            .buttonStyle(.aiRecapPrimary)

            Button("RSVP Recap") {
                onRSVP(recap)
            }
            .buttonStyle(.aiRecapSecondary)

            Button("Regenerate") {
                onRegenerate()
            }
            .buttonStyle(.aiRecapSecondary)
            .disabled(!canGenerate)
        }
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

                    Label("AI-generated recap", systemImage: "sparkles")
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
            .navigationTitle("AI Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
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

private struct AIRecapButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    @Environment(\.focusReadTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(backgroundColor.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.border.opacity(0.55), lineWidth: 1)
                }
            }
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return AppTheme.primaryButtonForeground
        case .secondary:
            return theme.primaryText
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary:
            return AppTheme.primaryButtonBackground
        case .secondary:
            return theme.controlBackground
        }
    }
}

private extension ButtonStyle where Self == AIRecapButtonStyle {
    static var aiRecapPrimary: AIRecapButtonStyle {
        AIRecapButtonStyle(kind: .primary)
    }

    static var aiRecapSecondary: AIRecapButtonStyle {
        AIRecapButtonStyle(kind: .secondary)
    }
}
