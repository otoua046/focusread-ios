import SwiftUI

enum TypographySettingsKey {
    static let fontFamily = "fontFamily"
    static let fontSize = "fontSize"
    static let fontWeight = "fontWeight"
    static let isItalic = "isItalic"
    static let textColor = "textColor"
    static let appearance = "appearance"
}

enum ReaderBehaviorSettingsKey {
    static let defaultWPM = "defaultWPM"
    static let hapticsEnabled = "hapticsEnabled"
    static let punctuationPausesEnabled = "punctuationPausesEnabled"
    static let longWordDelayMode = "longWordDelayMode"
    static let smartCleanupMode = "smartCleanupMode"
}

struct ReaderBehaviorSettings: Equatable, Sendable {
    var punctuationPausesEnabled: Bool
    var longWordDelayMode: LongWordDelayMode

    static let `default` = ReaderBehaviorSettings(
        punctuationPausesEnabled: true,
        longWordDelayMode: .moderate
    )
}

enum LongWordDelayMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case moderate
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .moderate: return "Moderate"
        case .strong: return "Strong"
        }
    }

    func extraMultiplier(for token: ReadingToken) -> Double {
        switch self {
        case .off:
            return 0
        case .moderate:
            return moderateExtraMultiplier(for: token)
        case .strong:
            return strongExtraMultiplier(for: token)
        }
    }

    private func moderateExtraMultiplier(for token: ReadingToken) -> Double {
        var multiplier = 0.0
        if token.isLongWord {
            multiplier += min(Double(token.text.count - 8) * 0.05, 0.35)
        }
        if token.containsNumber {
            multiplier += 0.25
        }
        return multiplier
    }

    private func strongExtraMultiplier(for token: ReadingToken) -> Double {
        var multiplier = 0.0
        if token.isLongWord {
            multiplier += min(Double(token.text.count - 8) * 0.08, 0.55)
        }
        if token.containsNumber {
            multiplier += 0.4
        }
        return multiplier
    }
}

enum SmartCleanupMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case smart
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .smart: return "Smart Cleanup"
        case .ai: return "AI Cleanup"
        }
    }

    var description: String {
        switch self {
        case .off:
            return "No cleanup applied."
        case .smart:
            return "Uses local rules to clean spacing, line breaks, headers, and OCR artifacts."
        case .ai:
            return "Uses on-device intelligence when available to clean imported text while preserving meaning."
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ReaderFontFamily: String, CaseIterable, Identifiable, Sendable {
    case serif
    case system
    case rounded
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .serif: return "Serif"
        case .system: return "System"
        case .rounded: return "Rounded"
        case .monospaced: return "Monospaced"
        }
    }

    var design: Font.Design {
        switch self {
        case .serif: return .serif
        case .system: return .default
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }
}

enum ReaderFontWeight: String, CaseIterable, Identifiable, Sendable {
    case regular
    case medium
    case bold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .bold: return "Bold"
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .bold: return .bold
        }
    }
}

enum ReaderTextColor: String, CaseIterable, Identifiable, Sendable {
    case primary
    case black
    case gray
    case blue
    case sepia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary: return "Primary"
        case .black: return "Black"
        case .gray: return "Gray"
        case .blue: return "Blue"
        case .sepia: return "Sepia"
        }
    }

    func color(for colorScheme: ColorScheme) -> Color {
        AppTheme.semanticReaderColor(self)
    }
}

struct FontStyle: Equatable, Sendable {
    var family: ReaderFontFamily
    var size: Double
    var weight: ReaderFontWeight
    var isItalic: Bool
    var textColor: ReaderTextColor

    static let defaultSize: Double = 58

    static let `default` = FontStyle(
        family: .serif,
        size: defaultSize,
        weight: .regular,
        isItalic: false,
        textColor: .primary
    )

    var font: Font {
        .system(size: size, weight: weight.fontWeight, design: family.design)
    }

    func foregroundColor(for colorScheme: ColorScheme) -> Color {
        textColor.color(for: colorScheme)
    }
}

struct TypographyTextModifier: ViewModifier {
    let style: FontStyle
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let styled = content
            .font(style.font)
            .foregroundStyle(style.foregroundColor(for: colorScheme))

        if style.isItalic {
            styled.italic()
        } else {
            styled
        }
    }
}

extension View {
    func typographyStyle(_ style: FontStyle) -> some View {
        modifier(TypographyTextModifier(style: style))
    }
}
