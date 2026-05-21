import Foundation
import PDFKit
import UIKit

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
        let previewImageData = firstPagePreviewData(for: document)

        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw DocumentImportError.noReadableText
        }

        var sections: [ImportedDocumentSection] = []

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()

            await progress(DocumentImportProgress(
                message: L10n.string(.importProgressExtractingPDFText),
                completedUnitCount: pageIndex,
                totalUnitCount: pageCount
            ))

            let pageText: String
            if let page = document.page(at: pageIndex),
               let extractedText = page.string?.focusReadNormalizedDocumentText {
                pageText = extractedText
            } else {
                pageText = ""
            }

            sections.append(ImportedDocumentSection(
                index: pageIndex,
                text: pageText,
                pageNumber: pageIndex + 1,
                chapterNumber: nil,
                chapterTitle: nil,
                wordRange: nil
            ))
        }

        await progress(DocumentImportProgress(
            message: L10n.string(.importProgressExtractingPDFText),
            completedUnitCount: pageCount,
            totalUnitCount: pageCount
        ))

        let text = sections.map(\.text).joined(separator: "\n\n").focusReadNormalizedDocumentText
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumNativeTextCharacterCount {
            return ImportedDocument(
                fileName: file.fileName,
                sourceType: .pdf,
                sections: sections,
                previewImageData: previewImageData
            )
        }

        await progress(DocumentImportProgress(
            message: L10n.string(.importProgressScannedPDFStartingOCR),
            completedUnitCount: nil,
            totalUnitCount: nil
        ))

        return try await ocrExtractor.extractText(from: file, progress: progress)
    }

    private func firstPagePreviewData(for document: PDFDocument) -> Data? {
        guard let page = document.page(at: 0) else {
            return nil
        }

        let thumbnail = page.thumbnail(of: CGSize(width: 480, height: 640), for: .cropBox)
        return thumbnail.jpegData(compressionQuality: 0.88)
    }
}
