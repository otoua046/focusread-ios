import SwiftUI

@main
struct FocusReadApp: App {
    @StateObject private var themeManager = FocusReadThemeManager.shared
    @AppStorage(TypographySettingsKey.appearance) private var appearance: String = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(themeManager)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .focusReadThemeEnvironment()
                .focusReadSystemChrome()
        }
    }
}
