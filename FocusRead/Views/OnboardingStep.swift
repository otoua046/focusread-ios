import Foundation

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
            return "Research"
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

enum FocusReadOnboardingSample {
    static let title = "FocusRead Sample"

    static let passage = """
    Reading is easiest when attention has a place to land. On a busy page, your eyes keep crossing each line, remembering where the last thought ended, and finding the next one. FocusRead turns that same passage into a steady stream of centered words, helping you keep momentum and return later without rereading everything.
    """

    static let shortPassage = "Reading is easiest when attention has a place to land."

    static let comparisonPassage = passage

    static let recap = "The passage explains how normal reading makes your eyes cross each line while holding context in memory. FocusRead keeps words centered, helping attention stay steady and making it easier to return later without rereading."

    static let keyIdeas = [
        "Eye movement adds effort on busy pages",
        "Centered words give attention a steady place",
        "Recaps help restore context before continuing"
    ]

    static var passageWords: [String] {
        passage
            .split { $0.isWhitespace || $0.isNewline }
            .map(String.init)
    }
}
