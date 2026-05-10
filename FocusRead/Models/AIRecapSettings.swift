import Foundation

enum AIRecapSettingsKey {
    static let isEnabled = "aiRecapsEnabled"
}

enum AIRecapSettings {
    static var disabledMessage: String {
        L10n.string(.aiRecapDisabled)
    }

    static func defaultEnabled(localAIAvailable: Bool = AIRecapService().isAvailable) -> Bool {
        localAIAvailable
    }

    static func isEnabled(
        storedPreference: Bool,
        localAIAvailable: Bool
    ) -> Bool {
        localAIAvailable && storedPreference
    }

    static func shouldShowEntryPoints(
        storedPreference: Bool,
        localAIAvailable: Bool
    ) -> Bool {
        isEnabled(storedPreference: storedPreference, localAIAvailable: localAIAvailable)
    }

    static func shouldShowEntryPoints(
        userDefaults: UserDefaults = .standard,
        localAIAvailable: Bool = AIRecapService().isAvailable
    ) -> Bool {
        isEnabled(userDefaults: userDefaults, localAIAvailable: localAIAvailable)
    }

    static func isEnabled(
        userDefaults: UserDefaults = .standard,
        localAIAvailable: Bool = AIRecapService().isAvailable
    ) -> Bool {
        guard localAIAvailable else { return false }
        guard userDefaults.object(forKey: AIRecapSettingsKey.isEnabled) != nil else {
            return true
        }
        return userDefaults.bool(forKey: AIRecapSettingsKey.isEnabled)
    }

    static func setEnabled(_ isEnabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(isEnabled, forKey: AIRecapSettingsKey.isEnabled)
    }
}
