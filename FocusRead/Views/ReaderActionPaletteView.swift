import SwiftUI

struct ReaderActionPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var isInteracting: Bool
    let isVisible: Bool
    let isTranslateSupported: Bool
    let isAIRecapSupported: Bool
    let currentWord: String
    let onToggle: () -> Void
    let onDictionary: () -> Void
    let onAIRecap: () -> Void
    let onLookup: () -> Void
    let onTranslate: () -> Void
    let onSettings: () -> Void

    private let triggerSize: CGFloat = 50
    private let actionSize: CGFloat = 48
    private let spacing: CGFloat = 10
    private let bottomControlClearance: CGFloat = 162

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isPresented {
                AppTheme.transparentHitTarget
                    .ignoresSafeArea()
                    .onTapGesture {
                        closePalette()
                    }
            }

            VStack(alignment: .trailing, spacing: spacing) {
                actionCluster
                triggerButton
            }
            .opacity(isVisible ? 1 : 0.22)
            .safeAreaPadding(.trailing, 18)
            .safeAreaPadding(.bottom, bottomControlClearance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isPresented)
    }

    @ViewBuilder
    private var actionCluster: some View {
        if isPresented {
            VStack(alignment: .trailing, spacing: spacing) {
                HStack(spacing: spacing) {
                    if isTranslateSupported {
                        ReaderActionItem(
                            title: L10n.string(.readerTranslate),
                            systemImage: "translate",
                            size: actionSize,
                            onPressedChange: updateInteractionState
                        ) {
                            runAndClose(onTranslate)
                        }
                    }
                    
                    ReaderActionItem(
                        title: L10n.string(.readerSettings),
                        systemImage: "gearshape",
                        size: actionSize,
                        onPressedChange: updateInteractionState
                    ) {
                        runAndClose(onSettings)
                    }

                    ReaderActionItem(
                        title: L10n.string(.readerAIRecap),
                        systemImage: "sparkles",
                        size: actionSize,
                        isEnabled: isAIRecapSupported,
                        onPressedChange: updateInteractionState
                    ) {
                        runAndClose(onAIRecap)
                    }
                }

                HStack(spacing: spacing) {
                    ReaderActionItem(
                        title: L10n.string(.readerDictionary),
                        systemImage: "book",
                        size: actionSize,
                        onPressedChange: updateInteractionState
                    ) {
                        runAndClose(onDictionary)
                    }
                    .accessibilityHint(currentWord.isEmpty ? L10n.string(.readerDictionaryHint) : L10n.format(.readerDictionaryCurrentWordHintFormat, currentWord))

                    ReaderActionItem(
                        title: L10n.string(.readerLookup),
                        systemImage: "magnifyingglass",
                        size: actionSize,
                        onPressedChange: updateInteractionState
                    ) {
                        runAndClose(onLookup)
                    }
                }
            }
            .transition(actionTransition)
        }
    }

    private var triggerButton: some View {
        Button {
            suppressReaderGesturesBriefly()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                onToggle()
            }
        } label: {
            Image(systemName: isPresented ? "xmark" : "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: triggerSize, height: triggerSize)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.materialHighlightStroke, lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.materialLowlightStroke, lineWidth: 0.5)
                }
                .shadow(color: AppTheme.overlayShadow.opacity(isPresented ? 1 : 0.58), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(ReaderPaletteButtonStyle(onPressedChange: updateInteractionState))
        .accessibilityLabel(isPresented ? L10n.string(.readerCloseQuickActions) : L10n.string(.readerQuickActions))
        .accessibilityHint(L10n.string(.readerQuickActionsHint))
    }

    private func closePalette() {
        withAnimation(.smooth(duration: 0.18)) {
            isPresented = false
        }
    }

    private func runAndClose(_ action: () -> Void) {
        suppressReaderGesturesBriefly()
        action()
        DispatchQueue.main.async {
            closePalette()
        }
    }

    private var actionTransition: AnyTransition {
        .scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity)
    }

    private func updateInteractionState(_ pressed: Bool) {
        isInteracting = pressed
        if !pressed {
            suppressReaderGesturesBriefly()
        }
    }

    private func suppressReaderGesturesBriefly() {
        isInteracting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isInteracting = false
        }
    }
}

private struct ReaderActionItem: View {
    let title: String
    let systemImage: String
    let size: CGFloat
    var isEnabled: Bool = true
    let onPressedChange: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.materialHighlightStroke, lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.materialLowlightStroke, lineWidth: 0.5)
                }
                .shadow(color: AppTheme.overlayShadow.opacity(0.86), radius: 10, x: 0, y: 5)
                .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(ReaderPaletteButtonStyle(onPressedChange: onPressedChange))
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint(L10n.string(.readerActionOpenHint))
    }
}

private struct ReaderPaletteButtonStyle: ButtonStyle {
    var onPressedChange: ((Bool) -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.74 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressedChange?(isPressed)
            }
    }
}
