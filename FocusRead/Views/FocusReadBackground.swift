import SwiftUI

struct FocusReadBackground: View {
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        LinearGradient(
            colors: [
                theme.background,
                theme.secondaryBackground.opacity(0.78),
                theme.cardBackground.opacity(0.72),
                theme.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
