import SwiftUI

@main
struct FocusReadApp: App {
    @StateObject private var themeManager = FocusReadThemeManager.shared
    @AppStorage(TypographySettingsKey.appearance) private var appearance: String = AppAppearance.system.rawValue
    @AppStorage(UISettingsKey.liquidGlassEnabled) private var liquidGlassEnabled = true

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(themeManager)
                .focusReadLocalizationRefresh()
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .focusReadThemeEnvironment()
                .focusReadLiquidGlassEnabled(liquidGlassEnabled)
                .focusReadSystemChrome()
        }
    }
}
