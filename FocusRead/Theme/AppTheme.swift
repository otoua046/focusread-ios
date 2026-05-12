import SwiftUI
import UIKit
import WidgetKit

enum FocusReadThemeStorageKey {
    static let selectedThemeID = "focusread.theme.selectedThemeID"
}

enum FocusReadThemeCategory: String, CaseIterable, Identifiable {
    case accent
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accent:
            return L10n.string(.themeCategoryAccent)
        case .full:
            return L10n.string(.themeCategoryFull)
        }
    }
}

struct FocusReadTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let category: FocusReadThemeCategory
    let description: String
    let lightPalette: FocusReadThemePalette
    let darkPalette: FocusReadThemePalette

    func palette(for userInterfaceStyle: UIUserInterfaceStyle) -> FocusReadThemePalette {
        userInterfaceStyle == .dark ? darkPalette : lightPalette
    }
}

struct FocusReadThemePalette: Equatable {
    let primaryBackground: UIColor
    let secondaryBackground: UIColor
    let cardSurface: UIColor
    let primaryText: UIColor
    let secondaryText: UIColor
    let tertiaryText: UIColor
    let accent: UIColor
    let orpHighlight: UIColor
    let progressIndicator: UIColor
    let contributionLevels: [UIColor]
    let primaryButtonBackground: UIColor
    let primaryButtonForeground: UIColor
    let controlBackground: UIColor
    let controlForeground: UIColor
    let separator: UIColor
    let ringTrack: UIColor
    let iconBackground: UIColor
    let searchHighlightBackground: UIColor
    let searchHighlightForeground: UIColor
    let destructive: UIColor
    let coverSelectionForeground: UIColor
    let coverSelectionBackground: UIColor
}

@MainActor
final class FocusReadThemeManager: ObservableObject {
    static let shared = FocusReadThemeManager()

    @Published var selectedThemeID: String {
        didSet {
            guard oldValue != selectedThemeID else { return }
            UserDefaults.standard.set(selectedThemeID, forKey: FocusReadThemeStorageKey.selectedThemeID)
            FocusReadWidgetStatsStore.saveThemeID(selectedThemeID)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var selectedTheme: FocusReadTheme {
        FocusReadThemeCatalog.theme(matching: selectedThemeID)
    }

    private init() {
        let savedThemeID = UserDefaults.standard.string(forKey: FocusReadThemeStorageKey.selectedThemeID)
        selectedThemeID = FocusReadThemeCatalog.theme(matching: savedThemeID).id
        FocusReadWidgetStatsStore.saveThemeID(selectedThemeID)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func select(_ theme: FocusReadTheme) {
        selectedThemeID = theme.id
    }

    func reset() {
        selectedThemeID = FocusReadThemeCatalog.defaultTheme.id
    }

    func resolvedTheme(for colorScheme: ColorScheme) -> FocusReadResolvedTheme {
        FocusReadResolvedTheme(
            themeID: selectedThemeID,
            colorScheme: colorScheme,
            palette: selectedTheme.palette(
                for: colorScheme == .dark ? UIUserInterfaceStyle.dark : UIUserInterfaceStyle.light
            )
        )
    }
}

struct FocusReadResolvedTheme: Equatable {
    let themeID: String
    let colorScheme: ColorScheme
    let palette: FocusReadThemePalette

    var background: Color { color(\.primaryBackground) }
    var secondaryBackground: Color { color(\.secondaryBackground) }
    var cardBackground: Color { color(\.cardSurface) }
    var controlBackground: Color { color(\.controlBackground) }
    var controlForeground: Color { color(\.controlForeground) }
    var primaryText: Color { color(\.primaryText) }
    var secondaryText: Color { color(\.secondaryText) }
    var tertiaryText: Color { color(\.tertiaryText) }
    var border: Color { color(\.separator) }
    var accent: Color { color(\.accent) }
    var progressIndicator: Color { color(\.progressIndicator) }
    var ringTrack: Color { color(\.ringTrack) }
    var iconBackground: Color { color(\.iconBackground) }
    var destructive: Color { color(\.destructive) }
    var coverSelectionForeground: Color { color(\.coverSelectionForeground) }
    var coverSelectionBackground: Color { color(\.coverSelectionBackground) }
    var coverPlaceholderTop: Color { color(\.accent) }
    var coverPlaceholderBottom: Color { color(\.primaryText) }
    var coverText: Color { Color.white.opacity(0.96) }
    var coverSecondaryText: Color { Color.white.opacity(0.9) }
    var coverUnselectedForeground: Color { Color.white }
    var coverUnselectedBackground: Color { Color.black.opacity(0.4) }
    var overlayShadow: Color { Color.black.opacity(0.14) }
    var deepOverlayShadow: Color { Color.black.opacity(0.35) }
    var subtleShadow: Color { Color.black.opacity(0.07) }

    func contributionColor(for level: Int) -> Color {
        let safeLevel = min(max(level, 0), palette.contributionLevels.count - 1)
        return Color(uiColor: palette.contributionLevels[safeLevel])
    }

    private func color(_ keyPath: KeyPath<FocusReadThemePalette, UIColor>) -> Color {
        Color(uiColor: palette[keyPath: keyPath])
    }
}

private struct FocusReadResolvedThemeKey: EnvironmentKey {
    static let defaultValue = FocusReadThemeCatalog.defaultTheme
        .resolvedTheme(for: ColorScheme.light)
}

extension FocusReadTheme {
    func resolvedTheme(for colorScheme: ColorScheme) -> FocusReadResolvedTheme {
        FocusReadResolvedTheme(
            themeID: id,
            colorScheme: colorScheme,
            palette: palette(
                for: colorScheme == .dark ? UIUserInterfaceStyle.dark : UIUserInterfaceStyle.light
            )
        )
    }
}

extension EnvironmentValues {
    var focusReadTheme: FocusReadResolvedTheme {
        get { self[FocusReadResolvedThemeKey.self] }
        set { self[FocusReadResolvedThemeKey.self] = newValue }
    }
}

enum FocusReadThemeCatalog {
    static let defaultThemeID = "classic-gold"

    static let accentThemes: [FocusReadTheme] = [
        accentTheme(
            id: "classic-gold",
            name: "Classic Gold",
            description: "The original warm FocusRead accent.",
            accent: UIColor(hex: 0xBEA06E),
            buttonForeground: UIColor(hex: 0x17130C)
        ),
        accentTheme(
            id: "ocean-blue",
            name: "Ocean Blue",
            description: "Clear, steady blue for deep sessions.",
            accent: UIColor(hex: 0x3A78A8),
            buttonForeground: UIColor.white
        ),
        accentTheme(
            id: "rose-pink",
            name: "Rose Pink",
            description: "Soft rose with a composed editorial feel.",
            accent: UIColor(hex: 0xB65D75),
            buttonForeground: UIColor.white
        ),
        accentTheme(
            id: "forest-green",
            name: "Forest Green",
            description: "Grounded green for quiet concentration.",
            accent: UIColor(hex: 0x4F7D5A),
            buttonForeground: UIColor.white
        ),
        accentTheme(
            id: "lavender",
            name: "Lavender",
            description: "Muted violet, calm rather than flashy.",
            accent: UIColor(hex: 0x7D6FA8),
            buttonForeground: UIColor.white
        ),
        accentTheme(
            id: "crimson",
            name: "Crimson",
            description: "A restrained literary red.",
            accent: UIColor(hex: 0xA33A43),
            buttonForeground: UIColor.white
        ),
        accentTheme(
            id: "graphite",
            name: "Graphite",
            description: "Monochrome, precise, and minimal.",
            accent: UIColor(hex: 0x6E737A),
            buttonForeground: UIColor.white
        ),
        accentTheme(
            id: "amber",
            name: "Amber",
            description: "A warm amber glow for progress cues.",
            accent: UIColor(hex: 0xC17A2B),
            buttonForeground: UIColor(hex: 0x16100A)
        )
    ]

    static let fullThemes: [FocusReadTheme] = [
        FocusReadTheme(
            id: "sakura",
            name: "Sakura",
            category: .full,
            description: "Soft petal tones by day, deep rose by night.",
            lightPalette: palette(
                primaryBackground: 0xFFF8FA,
                secondaryBackground: 0xF8EEF2,
                cardSurface: 0xFFFFFF,
                primaryText: 0x25171C,
                secondaryText: 0x6E5660,
                tertiaryText: 0x9B7C87,
                accent: 0xB75E78,
                buttonForeground: 0xFFFFFF,
                separator: 0xE8CAD4,
                ringTrack: 0xF0DCE3,
                iconBackground: 0xF3E1E8,
                searchHighlightBackground: 0xF2D0DA,
                searchHighlightForeground: 0x281217
            ),
            darkPalette: palette(
                primaryBackground: 0x1A1014,
                secondaryBackground: 0x24161C,
                cardSurface: 0x2B1C23,
                primaryText: 0xF7ECEF,
                secondaryText: 0xCDB7C0,
                tertiaryText: 0x9F818D,
                accent: 0xD8899F,
                buttonForeground: 0x211018,
                separator: 0x4A303A,
                ringTrack: 0x3A252D,
                iconBackground: 0x38232B,
                searchHighlightBackground: 0x613142,
                searchHighlightForeground: 0xFFF4F6
            )
        ),
        FocusReadTheme(
            id: "midnight-blue",
            name: "Midnight Blue",
            category: .full,
            description: "Cool blue-gray surfaces with navy depth.",
            lightPalette: palette(
                primaryBackground: 0xF5F8FA,
                secondaryBackground: 0xEAF0F4,
                cardSurface: 0xFFFFFF,
                primaryText: 0x111B24,
                secondaryText: 0x536575,
                tertiaryText: 0x8291A0,
                accent: 0x3E739D,
                buttonForeground: 0xFFFFFF,
                separator: 0xD3DEE7,
                ringTrack: 0xE1E9EF,
                iconBackground: 0xE4ECF2,
                searchHighlightBackground: 0xCDE0EE,
                searchHighlightForeground: 0x0D1B26
            ),
            darkPalette: palette(
                primaryBackground: 0x07101D,
                secondaryBackground: 0x0D1828,
                cardSurface: 0x122033,
                primaryText: 0xEFF5FA,
                secondaryText: 0xB7C7D7,
                tertiaryText: 0x778CA2,
                accent: 0x7FB0DA,
                buttonForeground: 0x06111D,
                separator: 0x26394E,
                ringTrack: 0x1B2C40,
                iconBackground: 0x1D3046,
                searchHighlightBackground: 0x284965,
                searchHighlightForeground: 0xF2FAFF
            )
        ),
        FocusReadTheme(
            id: "crimson-noir",
            name: "Crimson Noir",
            category: .full,
            description: "Warm ivory and charcoal with a muted red accent.",
            lightPalette: palette(
                primaryBackground: 0xFBF6EF,
                secondaryBackground: 0xF1E8DC,
                cardSurface: 0xFFFDF9,
                primaryText: 0x211B18,
                secondaryText: 0x6A5A52,
                tertiaryText: 0x948175,
                accent: 0x9B3D3F,
                buttonForeground: 0xFFFFFF,
                separator: 0xE1D2C3,
                ringTrack: 0xE9DED2,
                iconBackground: 0xEEE3D7,
                searchHighlightBackground: 0xE9C6BF,
                searchHighlightForeground: 0x241514
            ),
            darkPalette: palette(
                primaryBackground: 0x111010,
                secondaryBackground: 0x1A1717,
                cardSurface: 0x231E1E,
                primaryText: 0xF3EDEA,
                secondaryText: 0xC9BAB3,
                tertiaryText: 0x927D75,
                accent: 0xC45658,
                buttonForeground: 0x1A0D0E,
                separator: 0x3F3433,
                ringTrack: 0x332A2A,
                iconBackground: 0x322728,
                searchHighlightBackground: 0x572829,
                searchHighlightForeground: 0xFFF5F2
            )
        ),
        FocusReadTheme(
            id: "matcha",
            name: "Matcha",
            category: .full,
            description: "Cream and muted green tuned for long reading.",
            lightPalette: palette(
                primaryBackground: 0xFAF8EC,
                secondaryBackground: 0xEEF0DF,
                cardSurface: 0xFFFFF7,
                primaryText: 0x1B2118,
                secondaryText: 0x5C6553,
                tertiaryText: 0x879077,
                accent: 0x5F7F54,
                buttonForeground: 0xFFFFFF,
                separator: 0xDADEC6,
                ringTrack: 0xE4E8D3,
                iconBackground: 0xE8ECD8,
                searchHighlightBackground: 0xDCE8C5,
                searchHighlightForeground: 0x15200F
            ),
            darkPalette: palette(
                primaryBackground: 0x0E150E,
                secondaryBackground: 0x151F15,
                cardSurface: 0x1B281A,
                primaryText: 0xEEF2E8,
                secondaryText: 0xBEC9B4,
                tertiaryText: 0x89977F,
                accent: 0x9AB37C,
                buttonForeground: 0x111A0E,
                separator: 0x31402D,
                ringTrack: 0x263422,
                iconBackground: 0x283823,
                searchHighlightBackground: 0x3E552F,
                searchHighlightForeground: 0xF8FFE9
            )
        ),
        FocusReadTheme(
            id: "paper-ink",
            name: "Paper Ink",
            category: .full,
            description: "Warm paper backgrounds and ink-style contrast.",
            lightPalette: palette(
                primaryBackground: 0xF7F0E2,
                secondaryBackground: 0xECE1CF,
                cardSurface: 0xFCF7ED,
                primaryText: 0x1D1A16,
                secondaryText: 0x62584B,
                tertiaryText: 0x8C7E6A,
                accent: 0x7A6042,
                buttonForeground: 0xFFF9EC,
                separator: 0xD9CBB7,
                ringTrack: 0xE2D6C4,
                iconBackground: 0xE7DCCB,
                searchHighlightBackground: 0xE7D2AD,
                searchHighlightForeground: 0x211910
            ),
            darkPalette: palette(
                primaryBackground: 0x18130D,
                secondaryBackground: 0x211A12,
                cardSurface: 0x2A2117,
                primaryText: 0xF2E8D6,
                secondaryText: 0xCDBEA6,
                tertiaryText: 0x9B8B72,
                accent: 0xC3A36F,
                buttonForeground: 0x1B1309,
                separator: 0x493B2A,
                ringTrack: 0x382D20,
                iconBackground: 0x3A2F22,
                searchHighlightBackground: 0x5B4423,
                searchHighlightForeground: 0xFFF4DE
            )
        ),
        FocusReadTheme(
            id: "amoled",
            name: "AMOLED",
            category: .full,
            description: "True black dark mode with sharp monochrome contrast.",
            lightPalette: palette(
                primaryBackground: 0xFFFFFF,
                secondaryBackground: 0xF4F4F4,
                cardSurface: 0xFFFFFF,
                primaryText: 0x050505,
                secondaryText: 0x555555,
                tertiaryText: 0x868686,
                accent: 0x5C6670,
                buttonForeground: 0xFFFFFF,
                separator: 0xD8D8D8,
                ringTrack: 0xE8E8E8,
                iconBackground: 0xECECEC,
                searchHighlightBackground: 0xD9D9D9,
                searchHighlightForeground: 0x050505
            ),
            darkPalette: palette(
                primaryBackground: 0x000000,
                secondaryBackground: 0x000000,
                cardSurface: 0x080808,
                primaryText: 0xF8F8F8,
                secondaryText: 0xC8C8C8,
                tertiaryText: 0x888888,
                accent: 0xD6D6D6,
                buttonForeground: 0x000000,
                separator: 0x242424,
                ringTrack: 0x181818,
                iconBackground: 0x121212,
                searchHighlightBackground: 0x303030,
                searchHighlightForeground: 0xFFFFFF
            )
        ),
        FocusReadTheme(
            id: "sunset",
            name: "Sunset",
            category: .full,
            description: "Peach and sand by day, burnt orange after dark.",
            lightPalette: palette(
                primaryBackground: 0xFFF5EA,
                secondaryBackground: 0xF4E2D2,
                cardSurface: 0xFFFDF8,
                primaryText: 0x241B15,
                secondaryText: 0x6B594B,
                tertiaryText: 0x998171,
                accent: 0xB86B3F,
                buttonForeground: 0xFFFFFF,
                separator: 0xE8D0BC,
                ringTrack: 0xEFDDCB,
                iconBackground: 0xF1E1D1,
                searchHighlightBackground: 0xF0CDB6,
                searchHighlightForeground: 0x25150E
            ),
            darkPalette: palette(
                primaryBackground: 0x17100B,
                secondaryBackground: 0x21170F,
                cardSurface: 0x2B1E14,
                primaryText: 0xF5ECE4,
                secondaryText: 0xCDB9A8,
                tertiaryText: 0x9B806A,
                accent: 0xD98A55,
                buttonForeground: 0x211006,
                separator: 0x4A3525,
                ringTrack: 0x382719,
                iconBackground: 0x3B291A,
                searchHighlightBackground: 0x62402A,
                searchHighlightForeground: 0xFFF4EC
            )
        ),
        FocusReadTheme(
            id: "arctic",
            name: "Arctic",
            category: .full,
            description: "Cold, minimal surfaces with an icy blue accent.",
            lightPalette: palette(
                primaryBackground: 0xF8FBFD,
                secondaryBackground: 0xEAF2F7,
                cardSurface: 0xF1F7FA,
                primaryText: 0x162431,
                secondaryText: 0x536B7C,
                tertiaryText: 0x7E94A3,
                accent: 0x4E9BC8,
                buttonForeground: 0xF7FCFF,
                separator: 0xD3E1EA,
                ringTrack: 0xDDEAF1,
                iconBackground: 0xE2EDF4,
                searchHighlightBackground: 0xCDEAF7,
                searchHighlightForeground: 0x0D2634
            ),
            darkPalette: palette(
                primaryBackground: 0x06111B,
                secondaryBackground: 0x0B1B29,
                cardSurface: 0x102434,
                primaryText: 0xEAF6FB,
                secondaryText: 0xB6CCD8,
                tertiaryText: 0x7D98A8,
                accent: 0x6FCBF0,
                buttonForeground: 0x05111A,
                separator: 0x253D4D,
                ringTrack: 0x1A3040,
                iconBackground: 0x183043,
                searchHighlightBackground: 0x1F5974,
                searchHighlightForeground: 0xF2FCFF
            )
        )
    ]

    static var allThemes: [FocusReadTheme] {
        accentThemes + fullThemes
    }

    static var defaultTheme: FocusReadTheme {
        theme(matching: defaultThemeID)
    }

    static func theme(matching id: String?) -> FocusReadTheme {
        allThemes.first { $0.id == id } ?? accentThemes[0]
    }

    static func themes(in category: FocusReadThemeCategory) -> [FocusReadTheme] {
        switch category {
        case .accent:
            return accentThemes
        case .full:
            return fullThemes
        }
    }

    private static func accentTheme(
        id: String,
        name: String,
        description: String,
        accent: UIColor,
        buttonForeground: UIColor
    ) -> FocusReadTheme {
        FocusReadTheme(
            id: id,
            name: name,
            category: .accent,
            description: description,
            lightPalette: monochromePalette(
                primaryBackground: 0xFFFFFF,
                secondaryBackground: 0xF7F7F8,
                cardSurface: 0xF2F2F4,
                primaryText: 0x111111,
                secondaryText: 0x606066,
                tertiaryText: 0x909096,
                accent: accent,
                buttonForeground: buttonForeground,
                separator: 0xD8D8DD,
                ringTrack: 0xE8E8EC,
                iconBackground: 0xEBEBEF,
                searchHighlightBackground: accent.withAlphaComponent(0.24),
                searchHighlightForeground: UIColor(hex: 0x111111),
                coverSelectionBackground: UIColor.white
            ),
            darkPalette: monochromePalette(
                primaryBackground: 0x000000,
                secondaryBackground: 0x0D0D0F,
                cardSurface: 0x171719,
                primaryText: 0xF7F7F7,
                secondaryText: 0xB8B8BE,
                tertiaryText: 0x77777E,
                accent: accent,
                buttonForeground: buttonForeground,
                separator: 0x303034,
                ringTrack: 0x242428,
                iconBackground: 0x202024,
                searchHighlightBackground: accent.withAlphaComponent(0.34),
                searchHighlightForeground: UIColor(hex: 0xFFFFFF),
                coverSelectionBackground: UIColor(hex: 0xF7F7F7)
            )
        )
    }

    private static func monochromePalette(
        primaryBackground: Int,
        secondaryBackground: Int,
        cardSurface: Int,
        primaryText: Int,
        secondaryText: Int,
        tertiaryText: Int,
        accent: UIColor,
        buttonForeground: UIColor,
        separator: Int,
        ringTrack: Int,
        iconBackground: Int,
        searchHighlightBackground: UIColor,
        searchHighlightForeground: UIColor,
        coverSelectionBackground: UIColor
    ) -> FocusReadThemePalette {
        FocusReadThemePalette(
            primaryBackground: UIColor(hex: primaryBackground),
            secondaryBackground: UIColor(hex: secondaryBackground),
            cardSurface: UIColor(hex: cardSurface),
            primaryText: UIColor(hex: primaryText),
            secondaryText: UIColor(hex: secondaryText),
            tertiaryText: UIColor(hex: tertiaryText),
            accent: accent,
            orpHighlight: accent,
            progressIndicator: accent,
            contributionLevels: contributionLevels(accent: accent, empty: UIColor(hex: ringTrack)),
            primaryButtonBackground: accent,
            primaryButtonForeground: buttonForeground,
            controlBackground: UIColor(hex: iconBackground),
            controlForeground: UIColor(hex: primaryText),
            separator: UIColor(hex: separator),
            ringTrack: UIColor(hex: ringTrack),
            iconBackground: UIColor(hex: iconBackground),
            searchHighlightBackground: searchHighlightBackground,
            searchHighlightForeground: searchHighlightForeground,
            destructive: UIColor(hex: 0xB34848),
            coverSelectionForeground: accent,
            coverSelectionBackground: coverSelectionBackground
        )
    }

    private static func palette(
        primaryBackground: Int,
        secondaryBackground: Int,
        cardSurface: Int,
        primaryText: Int,
        secondaryText: Int,
        tertiaryText: Int,
        accent: Int,
        buttonForeground: Int,
        separator: Int,
        ringTrack: Int,
        iconBackground: Int,
        searchHighlightBackground: Int,
        searchHighlightForeground: Int
    ) -> FocusReadThemePalette {
        let accentColor = UIColor(hex: accent)
        return FocusReadThemePalette(
            primaryBackground: UIColor(hex: primaryBackground),
            secondaryBackground: UIColor(hex: secondaryBackground),
            cardSurface: UIColor(hex: cardSurface),
            primaryText: UIColor(hex: primaryText),
            secondaryText: UIColor(hex: secondaryText),
            tertiaryText: UIColor(hex: tertiaryText),
            accent: accentColor,
            orpHighlight: accentColor,
            progressIndicator: accentColor,
            contributionLevels: contributionLevels(accent: accentColor, empty: UIColor(hex: ringTrack)),
            primaryButtonBackground: accentColor,
            primaryButtonForeground: UIColor(hex: buttonForeground),
            controlBackground: UIColor(hex: iconBackground),
            controlForeground: UIColor(hex: primaryText),
            separator: UIColor(hex: separator),
            ringTrack: UIColor(hex: ringTrack),
            iconBackground: UIColor(hex: iconBackground),
            searchHighlightBackground: UIColor(hex: searchHighlightBackground),
            searchHighlightForeground: UIColor(hex: searchHighlightForeground),
            destructive: UIColor(hex: 0xB34848),
            coverSelectionForeground: accentColor,
            coverSelectionBackground: UIColor(hex: cardSurface)
        )
    }

    private static func contributionLevels(accent: UIColor, empty: UIColor) -> [UIColor] {
        [
            empty,
            accent.withAlphaComponent(0.28),
            accent.withAlphaComponent(0.46),
            accent.withAlphaComponent(0.68),
            accent
        ]
    }
}

enum AppTheme {
    static var accent: Color { color(\.accent) }
    static var background: Color { color(\.primaryBackground) }
    static var secondaryBackground: Color { color(\.secondaryBackground) }
    static var cardBackground: Color { color(\.cardSurface) }
    static var controlBackground: Color { color(\.controlBackground) }
    static var controlForeground: Color { color(\.controlForeground) }
    static var primaryText: Color { color(\.primaryText) }
    static var secondaryText: Color { color(\.secondaryText) }
    static var tertiaryText: Color { color(\.tertiaryText) }
    static var border: Color { color(\.separator) }
    static var controlFill: Color { color(\.iconBackground) }
    static var readerTextDefault: Color { color(\.primaryText) }
    static var primaryButtonBackground: Color { color(\.primaryButtonBackground) }
    static var primaryButtonForeground: Color { color(\.primaryButtonForeground) }
    static var orpHighlight: Color { color(\.orpHighlight) }
    static var progressIndicator: Color { color(\.progressIndicator) }
    static var ringTrack: Color { color(\.ringTrack) }
    static var iconBackground: Color { color(\.iconBackground) }
    static var searchHighlightBackground: Color { color(\.searchHighlightBackground) }
    static var searchHighlightForeground: Color { color(\.searchHighlightForeground) }
    static var destructive: Color { color(\.destructive) }
    static var coverSelectionForeground: Color { color(\.coverSelectionForeground) }
    static var coverSelectionBackground: Color { color(\.coverSelectionBackground) }
    static var coverPlaceholderTop: Color { color(\.accent) }
    static var coverPlaceholderBottom: Color { color(\.primaryText) }
    static var coverUnselectedForeground: Color { Color.white }
    static var coverUnselectedBackground: Color { Color.black.opacity(0.4) }
    static var coverText: Color { Color.white.opacity(0.96) }
    static var coverSecondaryText: Color { Color.white.opacity(0.9) }
    static var overlayShadow: Color { Color.black.opacity(0.14) }
    static var deepOverlayShadow: Color { Color.black.opacity(0.35) }
    static var subtleShadow: Color { Color.black.opacity(0.07) }
    static var materialHighlightStroke: Color { Color.white.opacity(0.25) }
    static var materialLowlightStroke: Color { Color.black.opacity(0.08) }
    static var transparentHitTarget: Color { Color.black.opacity(0.001) }

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
        controlBackground
    }

    static func contributionColor(for level: Int) -> Color {
        Color(uiColor: UIColor { traits in
            let palette = palette(for: traits.userInterfaceStyle)
            let safeLevel = min(max(level, 0), palette.contributionLevels.count - 1)
            return palette.contributionLevels[safeLevel]
        })
    }

    static func palette(for colorScheme: ColorScheme) -> FocusReadThemePalette {
        palette(for: colorScheme == .dark ? UIUserInterfaceStyle.dark : UIUserInterfaceStyle.light)
    }

    private static func color(_ keyPath: KeyPath<FocusReadThemePalette, UIColor>) -> Color {
        Color(uiColor: uiColor(keyPath))
    }

    private static func uiColor(_ keyPath: KeyPath<FocusReadThemePalette, UIColor>) -> UIColor {
        UIColor { traits in
            palette(for: traits.userInterfaceStyle)[keyPath: keyPath]
        }
    }

    private static func palette(for style: UIUserInterfaceStyle) -> FocusReadThemePalette {
        let savedThemeID = UserDefaults.standard.string(forKey: FocusReadThemeStorageKey.selectedThemeID)
        return FocusReadThemeCatalog.theme(matching: savedThemeID).palette(for: style)
    }
}

struct FocusReadThemeRefreshModifier: ViewModifier {
    @ObservedObject private var themeManager = FocusReadThemeManager.shared
    @AppStorage(AppLanguageStorageKey.selectedLanguage) private var selectedLanguageRawValue: String = AppLanguage.systemDefault.rawValue

    func body(content: Content) -> some View {
        let _ = themeManager.selectedThemeID
        let _ = selectedLanguageRawValue
        content
    }
}

struct FocusReadThemeEnvironmentModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeManager = FocusReadThemeManager.shared

    func body(content: Content) -> some View {
        content
            .environment(\.focusReadTheme, themeManager.resolvedTheme(for: colorScheme))
    }
}

struct FocusReadSystemChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.focusReadTheme) private var theme

    func body(content: Content) -> some View {
        content
            .onAppear(perform: applyAppearance)
            .onChange(of: theme.themeID) { applyAppearance() }
            .onChange(of: colorScheme) { applyAppearance() }
    }

    private func applyAppearance() {
        let palette = theme.palette
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = palette.cardSurface
        tabAppearance.shadowColor = palette.separator

        applyTabItemColors(to: tabAppearance.stackedLayoutAppearance, palette: palette)
        applyTabItemColors(to: tabAppearance.inlineLayoutAppearance, palette: palette)
        applyTabItemColors(to: tabAppearance.compactInlineLayoutAppearance, palette: palette)

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = palette.primaryBackground
        navigationAppearance.shadowColor = palette.separator
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: palette.primaryText
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: palette.primaryText
        ]

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = palette.accent
    }

    private func applyTabItemColors(
        to appearance: UITabBarItemAppearance,
        palette: FocusReadThemePalette
    ) {
        appearance.normal.iconColor = palette.secondaryText
        appearance.normal.titleTextAttributes = [
            .foregroundColor: palette.secondaryText
        ]
        appearance.selected.iconColor = palette.accent
        appearance.selected.titleTextAttributes = [
            .foregroundColor: palette.accent
        ]
    }
}

struct FocusReadTabBarUpdater: UIViewControllerRepresentable {
    @Environment(\.focusReadTheme) private var theme

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let palette = theme.palette

        DispatchQueue.main.async {
            guard let tabBar = uiViewController.parent?.tabBarController?.tabBar else { return }
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = palette.cardSurface
            appearance.shadowColor = palette.separator

            Self.applyTabItemColors(to: appearance.stackedLayoutAppearance, palette: palette)
            Self.applyTabItemColors(to: appearance.inlineLayoutAppearance, palette: palette)
            Self.applyTabItemColors(to: appearance.compactInlineLayoutAppearance, palette: palette)

            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.tintColor = palette.accent
            tabBar.unselectedItemTintColor = palette.secondaryText
            tabBar.setNeedsLayout()
        }
    }

    private static func applyTabItemColors(
        to appearance: UITabBarItemAppearance,
        palette: FocusReadThemePalette
    ) {
        appearance.normal.iconColor = palette.secondaryText
        appearance.normal.titleTextAttributes = [
            .foregroundColor: palette.secondaryText
        ]
        appearance.selected.iconColor = palette.accent
        appearance.selected.titleTextAttributes = [
            .foregroundColor: palette.accent
        ]
    }
}

struct FocusReadTopSafeAreaMaterialModifier: ViewModifier {
    let isElevated: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: 4)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(topBackgroundFill)
                        .opacity(isElevated ? 0.94 : 0)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(AppTheme.border.opacity(isElevated ? 0.12 : 0))
                                .frame(height: 0.5)
                                .offset(y: max(proxy.safeAreaInsets.top - 6, 0))
                        }
                        .frame(height: proxy.safeAreaInsets.top + 4)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .allowsHitTesting(false)
            }
    }

    private var topBackgroundFill: AnyShapeStyle {
        AnyShapeStyle(.regularMaterial)
    }
}

struct FocusReadScrollTopTracker: View {
    let coordinateSpaceName: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: FocusReadScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName)).minY
                )
        }
        .frame(height: 0)
    }
}

struct FocusReadScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func focusReadThemeEnvironment() -> some View {
        modifier(FocusReadThemeEnvironmentModifier())
    }

    func focusReadThemeRefresh() -> some View {
        modifier(FocusReadThemeRefreshModifier())
    }

    func focusReadSystemChrome() -> some View {
        modifier(FocusReadSystemChromeModifier())
    }

    func focusReadTopSafeAreaMaterial(isElevated: Bool = true) -> some View {
        modifier(FocusReadTopSafeAreaMaterialModifier(isElevated: isElevated))
    }

    func focusReadSettingsPageChrome() -> some View {
        background(AppTheme.background.ignoresSafeArea())
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
    private let title: String?
    private let subtitle: String?
    private let titleKey: L10n.Key?
    private let subtitleKey: L10n.Key?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.titleKey = nil
        self.subtitleKey = nil
    }

    init(titleKey: L10n.Key, subtitleKey: L10n.Key? = nil) {
        self.title = nil
        self.subtitle = nil
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(resolvedTitle)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)

            if let resolvedSubtitle {
                Text(resolvedSubtitle)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var resolvedTitle: String {
        if let titleKey {
            return L10n.string(titleKey)
        }
        return title ?? ""
    }

    private var resolvedSubtitle: String? {
        if let subtitleKey {
            return L10n.string(subtitleKey)
        }
        return subtitle
    }
}

private extension UIColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
