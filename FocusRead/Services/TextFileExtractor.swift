import Foundation

struct TextFileExtractor: DocumentTextExtractor {
    func extractText(
        from file: ImportedFile,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument {
        await progress(.starting)

        let data = try Data(contentsOf: file.localURL, options: [.mappedIfSafe])
        guard let text = String(data: data, encoding: .utf8) else {
            throw DocumentImportError.invalidTextEncoding
        }

        let normalizedText = text.focusReadNormalizedDocumentText
        guard !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentImportError.noReadableText
        }

        return ImportedDocument(
            fileName: file.fileName,
            text: normalizedText,
            sourceType: .txt
        )
    }
}
