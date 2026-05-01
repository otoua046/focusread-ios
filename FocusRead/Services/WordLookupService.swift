import Foundation
import UIKit

struct WordLookupService: Sendable {
    func sanitizedTerm(from text: String) -> String? {
        Self.sanitizedTerm(from: text)
    }

    @MainActor
    func hasDefinition(for term: String) -> Bool {
        UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term)
    }

    static func sanitizedTerm(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let scalars = Array(trimmed.unicodeScalars)
        guard let firstContentIndex = scalars.firstIndex(where: isLookupContent),
              let lastContentIndex = scalars.lastIndex(where: isLookupContent),
              firstContentIndex <= lastContentIndex else {
            return nil
        }

        let term = String(String.UnicodeScalarView(scalars[firstContentIndex...lastContentIndex]))
        return term.isEmpty ? nil : term
    }

    private static func isLookupContent(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
    }
}
