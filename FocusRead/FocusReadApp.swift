import SwiftUI

@main
struct FocusReadApp: App {
    @AppStorage(TypographySettingsKey.appearance) private var appearance: String = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        }
    }
}
