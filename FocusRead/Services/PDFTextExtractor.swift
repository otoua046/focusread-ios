import Foundation
import PDFKit

struct PDFTextExtractor: DocumentTextExtractor {
    private let ocrExtractor: OCRTextExtractor
    private let minimumNativeTextCharacterCount = 80

    init(ocrExtractor: OCRTextExtractor = OCRTextExtractor()) {
        self.ocrExtractor = ocrExtractor
    }

    func extractText(
        from file: ImportedFile,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument {
        guard let document = PDFDocument(url: file.localURL) else {
            throw DocumentImportError.unreadablePDF
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw DocumentImportError.noReadableText
        }

        var pageTexts: [String] = []

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()

            await progress(DocumentImportProgress(
                message: "Extracting PDF text...",
                completedUnitCount: pageIndex,
                totalUnitCount: pageCount
            ))

            guard let page = document.page(at: pageIndex),
                  let pageText = page.string?.focusReadNormalizedDocumentText,
                  !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            pageTexts.append(pageText)
        }

        await progress(DocumentImportProgress(
            message: "Extracting PDF text...",
            completedUnitCount: pageCount,
            totalUnitCount: pageCount
        ))

        let text = pageTexts.joined(separator: "\n\n").focusReadNormalizedDocumentText
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumNativeTextCharacterCount {
            return ImportedDocument(
                fileName: file.fileName,
                text: text,
                sourceType: .pdfText
            )
        }

        await progress(DocumentImportProgress(
            message: "PDF looks scanned. Starting OCR...",
            completedUnitCount: nil,
            totalUnitCount: nil
        ))

        return try await ocrExtractor.extractText(from: file, progress: progress)
    }
}
