import Foundation
import UIKit

struct WordLookupService: Sendable {
    func sanitizedTerm(from text: String) -> String? {
        Self.sanitizedTerm(from: text)
    }

    @MainActor
    func hasDefinition(for term: String) -> Bool {
        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) {
            return true
        }
        let lowercased = term.lowercased()
        if lowercased != term {
            return UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: lowercased)
        }
        return false
    }

    static func sanitizedTerm(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.trimmingCharacters(in: .punctuationCharacters)
        return cleaned.isEmpty ? nil : cleaned
    }
}
