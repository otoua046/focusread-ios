import Foundation
import UIKit

struct WordLookupService: Sendable {
    private let definitionAvailability: @MainActor @Sendable (String) -> Bool

    init(
        definitionAvailability: @escaping @MainActor @Sendable (String) -> Bool = {
            UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: $0)
        }
    ) {
        self.definitionAvailability = definitionAvailability
    }

    func sanitizedTerm(from text: String) -> String? {
        Self.sanitizedTerm(from: text)
    }

    @MainActor
    func hasDefinition(for term: String) -> Bool {
        if definitionAvailability(term) {
            return true
        }
        let lowercased = term.lowercased()
        if lowercased != term {
            return definitionAvailability(lowercased)
        }
        return false
    }

    static func sanitizedTerm(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.trimmingCharacters(in: .punctuationCharacters)
        return cleaned.isEmpty ? nil : cleaned
    }
}
