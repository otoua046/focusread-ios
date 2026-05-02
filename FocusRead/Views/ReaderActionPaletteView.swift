import SwiftUI

struct ReaderActionPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var isInteracting: Bool
    let isVisible: Bool
    let currentWord: String
    let onToggle: () -> Void
    let onDictionary: () -> Void
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
                Color.black.opacity(0.001)
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
                    ReaderActionItem(
                        title: "Translate",
                        systemImage: "translate",
                        size: actionSize,
                        onPressedChange: updateInteractionState
                    ) {
                        runAndClose(onTranslate)
                    }
                    
                    ReaderActionItem(
                        title: "Settings",
                        systemImage: "gearshape",
                        size: actionSize,
                        onPressedChange: updateInteractionState
                    ) {
                        runAndClose(onSettings)
                    }
                }

                HStack(spacing: spacing) {
                    ReaderActionItem(
                        title: "Dictionary",
                        systemImage: "book",
                        size: actionSize,
                        onPressedChange: updateInteractionState
                    ) {
                        runAndClose(onDictionary)
                    }
                    .accessibilityHint(currentWord.isEmpty ? "Open the current word in the dictionary." : "Open \"\(currentWord)\" in the dictionary.")

                    ReaderActionItem(
                        title: "Lookup",
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
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(isPresented ? 0.14 : 0.08), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(ReaderPaletteButtonStyle(onPressedChange: updateInteractionState))
        .accessibilityLabel(isPresented ? "Close quick actions" : "Quick actions")
        .accessibilityHint("Open reader actions.")
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
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(ReaderPaletteButtonStyle(onPressedChange: onPressedChange))
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to open.")
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
