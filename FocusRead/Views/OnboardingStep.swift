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
