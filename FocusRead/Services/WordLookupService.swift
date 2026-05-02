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
        guard !trimmed.isEmpty else { return nil }

        let scalars = Array(trimmed.unicodeScalars)
        let alphanumerics = CharacterSet.alphanumerics
        
        guard let firstIndex = scalars.firstIndex(where: { alphanumerics.contains($0) }),
              let lastIndex = scalars.lastIndex(where: { alphanumerics.contains($0) }),
              firstIndex <= lastIndex else {
            return nil
        }

        let term = String(String.UnicodeScalarView(scalars[firstIndex...lastIndex]))
        return term.isEmpty ? nil : term
    }
}
