import Foundation

struct ReaderSearchResult: Identifiable, Equatable, Sendable {
    let index: Int
    let snippet: String
    let snippetParts: [ReaderSearchSnippetPart]

    var id: Int { index }
}

struct ReaderSearchSnippetPart: Equatable, Sendable {
    let text: String
    let isMatch: Bool
}

struct ReaderSearchService: Sendable {
    private let snippetRadius = 5
    private let maximumResultCount = 60

    func search(_ query: String, in tokens: [ReadingToken]) -> [ReaderSearchResult] {
        let normalizedQuery = Self.normalizedSearchTerm(query)
        guard !normalizedQuery.isEmpty, !tokens.isEmpty else {
            return []
        }

        var results: [ReaderSearchResult] = []
        results.reserveCapacity(min(maximumResultCount, tokens.count))

        for token in tokens {
            guard Self.normalizedSearchTerm(token.rawText).contains(normalizedQuery)
                    || Self.normalizedSearchTerm(token.text).contains(normalizedQuery) else {
                continue
            }

            results.append(ReaderSearchResult(
                index: token.globalWordIndex,
                snippet: snippet(around: token.globalWordIndex, in: tokens),
                snippetParts: snippetParts(around: token.globalWordIndex, in: tokens, matching: normalizedQuery)
            ))

            if results.count >= maximumResultCount {
                break
            }
        }

        return results
    }

    static func normalizedSearchTerm(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func snippet(around index: Int, in tokens: [ReadingToken]) -> String {
        guard tokens.indices.contains(index) else {
            return ""
        }

        let lowerBound = max(tokens.startIndex, index - snippetRadius)
        let upperBound = min(tokens.endIndex, index + snippetRadius + 1)
        return tokens[lowerBound..<upperBound]
            .map(\.text)
            .joined(separator: " ")
    }

    private func snippetParts(
        around index: Int,
        in tokens: [ReadingToken],
        matching normalizedQuery: String
    ) -> [ReaderSearchSnippetPart] {
        guard tokens.indices.contains(index) else {
            return []
        }

        let lowerBound = max(tokens.startIndex, index - snippetRadius)
        let upperBound = min(tokens.endIndex, index + snippetRadius + 1)
        return tokens[lowerBound..<upperBound].map { token in
            let isMatch = Self.normalizedSearchTerm(token.rawText).contains(normalizedQuery)
                || Self.normalizedSearchTerm(token.text).contains(normalizedQuery)
            return ReaderSearchSnippetPart(text: token.text, isMatch: isMatch)
        }
    }
}
