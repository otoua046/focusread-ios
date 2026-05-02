import SwiftUI

struct ReaderActionPaletteView: View {
    @Binding var isPresented: Bool
    let isVisible: Bool
    let currentWord: String
    let onToggle: () -> Void
    let onDictionary: () -> Void
    let onLookup: () -> Void
    let onSettings: () -> Void

    private let triggerSize: CGFloat = 50
    private let actionSize: CGFloat = 48

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isPresented {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closePalette()
                    }
            }

            VStack(alignment: .trailing, spacing: 10) {
                if isPresented {
                    actionCluster
                        .padding(.bottom, 2)
                        .transition(.scale(scale: 0.72, anchor: .bottomTrailing).combined(with: .opacity))
                }

                triggerButton
            }
            .opacity(isVisible ? 1 : 0.22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isPresented)
    }

    private var actionCluster: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ReaderActionItem(
                title: "Settings",
                systemImage: "gearshape",
                size: actionSize
            ) {
                runAndClose(onSettings)
            }

            HStack(spacing: 10) {
                ReaderActionItem(
                    title: "Dictionary",
                    systemImage: "book",
                    size: actionSize
                ) {
                    runAndClose(onDictionary)
                }
                .accessibilityHint(currentWord.isEmpty ? "Open the current word in the dictionary." : "Open \"\(currentWord)\" in the dictionary.")

                ReaderActionItem(
                    title: "Lookup",
                    systemImage: "magnifyingglass",
                    size: actionSize
                ) {
                    runAndClose(onLookup)
                }
            }
        }
    }

    private var triggerButton: some View {
        Button {
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
        .buttonStyle(ReaderPaletteButtonStyle())
        .accessibilityLabel(isPresented ? "Close quick actions" : "Quick actions")
        .accessibilityHint("Open reader actions")
    }

    private func closePalette() {
        withAnimation(.smooth(duration: 0.18)) {
            isPresented = false
        }
    }

    private func runAndClose(_ action: () -> Void) {
        action()
        DispatchQueue.main.async {
            closePalette()
        }
    }
}

private struct ReaderActionItem: View {
    let title: String
    let systemImage: String
    let size: CGFloat
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
        .buttonStyle(ReaderPaletteButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to open.")
    }
}

private struct ReaderPaletteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.74 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}
