import Foundation
import NaturalLanguage

enum FocusReadOnboardingMode: Equatable {
    case firstLaunch
    case replay
}

enum FocusReadOnboardingStep: Int, CaseIterable, Identifiable {
    case promise
    case rsvpDemo
    case comparison
    case wpmSetup
    case readingGoal
    case theme
    case readAnything
    case aiRecap
    case finish

    var id: Int { rawValue }

    var progressIndex: Int {
        rawValue + 1
    }

    var next: FocusReadOnboardingStep? {
        Self(rawValue: rawValue + 1)
    }

    var previous: FocusReadOnboardingStep? {
        Self(rawValue: rawValue - 1)
    }
}

enum FocusReadOnboardingCompletionAction {
    case showLibrary
    case importBook
    case trySampleText
}

enum FocusReadOnboardingSettingsKey {
    static let hasCompletedOnboarding = "focusread.onboarding.hasCompletedOnboarding"
    static let selectedReadingGoal = "home.selectedReadingGoal"
    static let selectedReadingGoals = "home.selectedReadingGoals"
    static let selectedReadingInterests = "home.selectedReadingInterests"
}

enum FocusReadOnboardingMigration {
    static func hasExistingInstallSignal(
        userDefaults: UserDefaults = .standard,
        hasPersistedReadingHistory: Bool
    ) -> Bool {
        if hasPersistedReadingHistory {
            return true
        }

        return existingInstallDefaultsKeys.contains { key in
            userDefaults.object(forKey: key) != nil
        }
    }

    private static let existingInstallDefaultsKeys = [
        FocusReadOnboardingSettingsKey.selectedReadingGoal,
        FocusReadOnboardingSettingsKey.selectedReadingGoals,
        TypographySettingsKey.fontFamily,
        TypographySettingsKey.fontSize,
        TypographySettingsKey.fontWeight,
        TypographySettingsKey.isItalic,
        TypographySettingsKey.textColor,
        TypographySettingsKey.appearance,
        ReaderBehaviorSettingsKey.defaultWPM,
        ReaderBehaviorSettingsKey.hapticsEnabled,
        ReaderBehaviorSettingsKey.reverseWPMDialDirection,
        ReaderBehaviorSettingsKey.punctuationPausesEnabled,
        ReaderBehaviorSettingsKey.longWordDelayMode,
        ReaderBehaviorSettingsKey.smartCleanupMode,
        ReaderBehaviorSettingsKey.anchorLetterEnabled,
        ReaderBehaviorSettingsKey.displayMode,
        AppLanguageStorageKey.selectedLanguage,
        FocusReadThemeStorageKey.selectedThemeID,
        "library_view_mode",
        "library_sort_mode"
    ]
}

enum FocusReadReadingGoal: String, CaseIterable, Identifiable {
    case study
    case books
    case work
    case research
    case languages

    var id: String { rawValue }

    init(savedRawValue: String) {
        if savedRawValue == "focus" {
            self = .research
        } else {
            self = Self(rawValue: savedRawValue) ?? .research
        }
    }

    var title: String {
        switch self {
        case .study:
            return L10n.string(.onboardingGoalStudy)
        case .books:
            return L10n.string(.onboardingGoalBooks)
        case .work:
            return L10n.string(.onboardingGoalWork)
        case .research:
            return L10n.string(.onboardingGoalResearch)
        case .languages:
            return L10n.string(.onboardingGoalLanguages)
        }
    }

    var systemImageName: String {
        switch self {
        case .study:
            return "graduationcap"
        case .books:
            return "book.closed"
        case .work:
            return "briefcase"
        case .research:
            return "doc.text.magnifyingglass"
        case .languages:
            return "character.book.closed"
        }
    }
}

enum FocusReadReadingInterest: String, CaseIterable, Identifiable, Sendable {
    case classics
    case fiction
    case philosophy
    case selfImprovement
    case shortReads
    case science
    case history
    case poetry
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classics:
            return "Classics"
        case .fiction:
            return "Fiction"
        case .philosophy:
            return "Philosophy"
        case .selfImprovement:
            return "Self-Improvement"
        case .shortReads:
            return "Short Reads"
        case .science:
            return "Science"
        case .history:
            return "History"
        case .poetry:
            return "Poetry"
        case .business:
            return "Business"
        }
    }

    var systemImageName: String {
        switch self {
        case .classics:
            return "building.columns"
        case .fiction:
            return "text.book.closed"
        case .philosophy:
            return "brain.head.profile"
        case .selfImprovement:
            return "sparkles"
        case .shortReads:
            return "timer"
        case .science:
            return "atom"
        case .history:
            return "scroll"
        case .poetry:
            return "quote.opening"
        case .business:
            return "chart.line.uptrend.xyaxis"
        }
    }
}

enum FocusReadOnboardingSample {
    static var title: String {
        L10n.string(.onboardingSampleTitle)
    }

    static var passage: String {
        L10n.string(.onboardingSamplePassage)
    }

    static var shortPassage: String {
        L10n.string(.onboardingSampleShortPassage)
    }

    static var comparisonPassage: String { passage }

    static var recap: String {
        L10n.string(.onboardingSampleRecap)
    }

    static var keyIdeas: [String] {
        [
            L10n.string(.onboardingSampleKeyIdea1),
            L10n.string(.onboardingSampleKeyIdea2),
            L10n.string(.onboardingSampleKeyIdea3)
        ]
    }

    static var passageWords: [String] {
        words(in: passage)
    }

    static func words(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { String(text[$0]) }
    }
}
