import SwiftUI
import UIKit

enum AppTheme {
    static let background = Color(uiColor: .systemBackground)
    static let cardBackground = Color(uiColor: .secondarySystemBackground)
    static let controlBackground = Color(uiColor: .tertiarySystemBackground)
    static let controlForeground = Color(uiColor: .label)
    static let primaryText = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let tertiaryText = Color(uiColor: .tertiaryLabel)
    static let border = Color(uiColor: .separator)
    static let controlFill = Color(uiColor: .systemFill)
    static let readerTextDefault = Color(uiColor: .label)
    static let primaryButtonBackground = Color(uiColor: .label)
    static let primaryButtonForeground = Color(uiColor: .systemBackground)

    static func semanticReaderColor(_ style: ReaderTextColor) -> Color {
        switch style {
        case .primary:
            return readerTextDefault
        case .black:
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? .white : .black
            })
        case .gray:
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? .systemGray3 : .systemGray
            })
        case .blue:
            return Color(uiColor: .systemBlue)
        case .sepia:
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.88, green: 0.78, blue: 0.62, alpha: 1)
                    : UIColor(red: 0.42, green: 0.30, blue: 0.18, alpha: 1)
            })
        }
    }

    static func controlFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(uiColor: .systemGray5) : Color(uiColor: .systemGray6)
    }
}

struct TopReaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppTheme.controlForeground)
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle().strokeBorder(AppTheme.border.opacity(0.72), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .frame(width: 56, height: 56)
            .contentShape(Circle())
    }
}

extension ButtonStyle where Self == TopReaderButtonStyle {
    static var topReaderControl: TopReaderButtonStyle { TopReaderButtonStyle() }
}

struct FocusReadPageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)

            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }
}
