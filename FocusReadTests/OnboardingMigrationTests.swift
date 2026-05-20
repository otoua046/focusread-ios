import XCTest
@testable import FocusRead

final class OnboardingMigrationTests: XCTestCase {
    func testFreshInstallWithoutHistoryDoesNotSkipOnboarding() throws {
        let suiteName = "FocusReadOnboardingMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        XCTAssertFalse(
            FocusReadOnboardingMigration.hasExistingInstallSignal(
                userDefaults: defaults,
                hasPersistedReadingHistory: false
            )
        )
    }

    func testExistingPreferenceSkipsOnboardingWhenLibraryIsEmpty() throws {
        let suiteName = "FocusReadOnboardingMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        defaults.set(ReadingSession.defaultWPM, forKey: ReaderBehaviorSettingsKey.defaultWPM)

        XCTAssertTrue(
            FocusReadOnboardingMigration.hasExistingInstallSignal(
                userDefaults: defaults,
                hasPersistedReadingHistory: false
            )
        )
    }

    func testPersistedHistorySkipsOnboardingEvenWhenCurrentLibraryIsEmpty() {
        XCTAssertTrue(
            FocusReadOnboardingMigration.hasExistingInstallSignal(
                userDefaults: UserDefaults.standard,
                hasPersistedReadingHistory: true
            )
        )
    }
}
