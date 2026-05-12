import SwiftUI

struct FocusReadWidgetTheme {
    let background: Color
    let cardBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let progressIndicator: Color
    let ringTrack: Color
    let iconBackground: Color
    let border: Color
    let shadow: Color
    let isDark: Bool

    func contributionColor(for level: Int) -> Color {
        switch min(max(level, 0), 4) {
        case 0:
            return ringTrack
        case 1:
            return progressIndicator.opacity(0.28)
        case 2:
            return progressIndicator.opacity(0.46)
        case 3:
            return progressIndicator.opacity(0.68)
        default:
            return progressIndicator
        }
    }

    init(themeID: String, colorScheme: ColorScheme) {
        isDark = colorScheme == .dark
        let palette = Self.palette(themeID: themeID, isDark: isDark)
        background = palette.background
        cardBackground = palette.cardBackground
        primaryText = palette.primaryText
        secondaryText = palette.secondaryText
        tertiaryText = palette.tertiaryText
        progressIndicator = palette.accent
        ringTrack = palette.ringTrack
        iconBackground = palette.iconBackground
        border = palette.border
        shadow = isDark ? .clear : .black.opacity(0.07)
    }

    private static func palette(themeID: String, isDark: Bool) -> FocusReadWidgetPalette {
        switch themeID {
        case "sakura":
            return isDark
                ? FocusReadWidgetPalette(0x1A1014, 0x2B1C23, 0xF7ECEF, 0xCDB7C0, 0x9F818D, 0xD8899F, 0x3A252D, 0x38232B, 0x4A303A)
                : FocusReadWidgetPalette(0xFFF8FA, 0xFFFFFF, 0x25171C, 0x6E5660, 0x9B7C87, 0xB75E78, 0xF0DCE3, 0xF3E1E8, 0xE8CAD4)
        case "midnight-blue":
            return isDark
                ? FocusReadWidgetPalette(0x07101D, 0x122033, 0xEFF5FA, 0xB7C7D7, 0x778CA2, 0x7FB0DA, 0x1B2C40, 0x1D3046, 0x26394E)
                : FocusReadWidgetPalette(0xF5F8FA, 0xFFFFFF, 0x111B24, 0x536575, 0x8291A0, 0x3E739D, 0xE1E9EF, 0xE4ECF2, 0xD3DEE7)
        case "crimson-noir":
            return isDark
                ? FocusReadWidgetPalette(0x111010, 0x231E1E, 0xF3EDEA, 0xC9BAB3, 0x927D75, 0xC45658, 0x332A2A, 0x322728, 0x3F3433)
                : FocusReadWidgetPalette(0xFBF6EF, 0xFFFDF9, 0x211B18, 0x6A5A52, 0x948175, 0x9B3D3F, 0xE9DED2, 0xEEE3D7, 0xE1D2C3)
        case "matcha":
            return isDark
                ? FocusReadWidgetPalette(0x0E150E, 0x1B281A, 0xEEF2E8, 0xBEC9B4, 0x89977F, 0x9AB37C, 0x263422, 0x283823, 0x31402D)
                : FocusReadWidgetPalette(0xFAF8EC, 0xFFFFF7, 0x1B2118, 0x5C6553, 0x879077, 0x5F7F54, 0xE4E8D3, 0xE8ECD8, 0xDADEC6)
        case "paper-ink":
            return isDark
                ? FocusReadWidgetPalette(0x18130D, 0x2A2117, 0xF2E8D6, 0xCDBEA6, 0x9B8B72, 0xC3A36F, 0x382D20, 0x3A2F22, 0x493B2A)
                : FocusReadWidgetPalette(0xF7F0E2, 0xFCF7ED, 0x1D1A16, 0x62584B, 0x8C7E6A, 0x7A6042, 0xE2D6C4, 0xE7DCCB, 0xD9CBB7)
        case "amoled":
            return isDark
                ? FocusReadWidgetPalette(0x000000, 0x080808, 0xF8F8F8, 0xC8C8C8, 0x888888, 0xD6D6D6, 0x181818, 0x121212, 0x242424)
                : FocusReadWidgetPalette(0xFFFFFF, 0xFFFFFF, 0x050505, 0x555555, 0x868686, 0x5C6670, 0xE8E8E8, 0xECECEC, 0xD8D8D8)
        case "sunset":
            return isDark
                ? FocusReadWidgetPalette(0x17100B, 0x2B1E14, 0xF5ECE4, 0xCDB9A8, 0x9B806A, 0xD98A55, 0x382719, 0x3B291A, 0x4A3525)
                : FocusReadWidgetPalette(0xFFF5EA, 0xFFFDF8, 0x241B15, 0x6B594B, 0x998171, 0xB86B3F, 0xEFDDCB, 0xF1E1D1, 0xE8D0BC)
        case "arctic":
            return isDark
                ? FocusReadWidgetPalette(0x06111B, 0x102434, 0xEAF6FB, 0xB6CCD8, 0x7D98A8, 0x6FCBF0, 0x1A3040, 0x183043, 0x253D4D)
                : FocusReadWidgetPalette(0xF8FBFD, 0xF1F7FA, 0x162431, 0x536B7C, 0x7E94A3, 0x4E9BC8, 0xDDEAF1, 0xE2EDF4, 0xD3E1EA)
        case "ocean-blue":
            return accentPalette(accent: 0x3A78A8, isDark: isDark)
        case "rose-pink":
            return accentPalette(accent: 0xB65D75, isDark: isDark)
        case "forest-green":
            return accentPalette(accent: 0x4F7D5A, isDark: isDark)
        case "lavender":
            return accentPalette(accent: 0x7D6FA8, isDark: isDark)
        case "crimson":
            return accentPalette(accent: 0xA33A43, isDark: isDark)
        case "graphite":
            return accentPalette(accent: 0x6E737A, isDark: isDark)
        case "amber":
            return accentPalette(accent: 0xC17A2B, isDark: isDark)
        default:
            return accentPalette(accent: 0xBEA06E, isDark: isDark)
        }
    }

    private static func accentPalette(accent: Int, isDark: Bool) -> FocusReadWidgetPalette {
        isDark
            ? FocusReadWidgetPalette(0x000000, 0x171719, 0xF7F7F7, 0xB8B8BE, 0x77777E, accent, 0x242428, 0x202024, 0x303034)
            : FocusReadWidgetPalette(0xFFFFFF, 0xF2F2F4, 0x111111, 0x606066, 0x909096, accent, 0xE8E8EC, 0xEBEBEF, 0xD8D8DD)
    }
}

private struct FocusReadWidgetPalette {
    let background: Color
    let cardBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let accent: Color
    let ringTrack: Color
    let iconBackground: Color
    let border: Color

    init(
        _ background: Int,
        _ cardBackground: Int,
        _ primaryText: Int,
        _ secondaryText: Int,
        _ tertiaryText: Int,
        _ accent: Int,
        _ ringTrack: Int,
        _ iconBackground: Int,
        _ border: Int
    ) {
        self.background = Color(hex: background)
        self.cardBackground = Color(hex: cardBackground)
        self.primaryText = Color(hex: primaryText)
        self.secondaryText = Color(hex: secondaryText)
        self.tertiaryText = Color(hex: tertiaryText)
        self.accent = Color(hex: accent)
        self.ringTrack = Color(hex: ringTrack)
        self.iconBackground = Color(hex: iconBackground)
        self.border = Color(hex: border)
    }
}

private extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
