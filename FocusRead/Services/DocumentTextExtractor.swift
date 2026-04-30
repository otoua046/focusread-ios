import Foundation

typealias DocumentImportProgressHandler = @Sendable (DocumentImportProgress) async -> Void

protocol DocumentTextExtractor: Sendable {
    func extractText(
        from file: ImportedFile,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument
}

extension String {
    var focusReadNormalizedDocumentText: String {
        let normalizedNewlines = replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalizedNewlines.components(separatedBy: "\n")
        var output: [String] = []
        var previousLineWasBlank = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !previousLineWasBlank, !output.isEmpty {
                    output.append("")
                }
                previousLineWasBlank = true
            } else {
                output.append(trimmed)
                previousLineWasBlank = false
            }
        }

        return output.joined(separator: "\n")
    }
}
