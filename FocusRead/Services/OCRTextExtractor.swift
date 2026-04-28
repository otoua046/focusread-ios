import Foundation
import PDFKit
import UIKit
import Vision

struct OCRTextExtractor: DocumentTextExtractor {
    private let maximumPages = 20
    private let maximumRenderedPixelDimension: CGFloat = 1_800

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

        let pagesToProcess = min(pageCount, maximumPages)
        var pageTexts: [String] = []

        for pageIndex in 0..<pagesToProcess {
            try Task.checkCancellation()

            await progress(DocumentImportProgress(
                message: "Recognizing scanned PDF text...",
                completedUnitCount: pageIndex,
                totalUnitCount: pagesToProcess
            ))

            guard let page = document.page(at: pageIndex),
                  let cgImage = renderPage(page) else {
                continue
            }

            let lines = try recognizeText(in: cgImage)
            if !lines.isEmpty {
                pageTexts.append(lines.joined(separator: "\n"))
            }
        }

        await progress(DocumentImportProgress(
            message: "Recognizing scanned PDF text...",
            completedUnitCount: pagesToProcess,
            totalUnitCount: pagesToProcess
        ))

        let text = pageTexts.joined(separator: "\n\n").focusReadNormalizedDocumentText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentImportError.ocrFailed
        }

        return ImportedDocument(
            fileName: file.fileName,
            text: text,
            sourceType: .pdfOCR
        )
    }

    private func renderPage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let largestDimension = max(bounds.width, bounds.height)
        let scale = min(maximumRenderedPixelDimension / largestDimension, 2)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }

        return image.cgImage
    }

    private func recognizeText(in cgImage: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw DocumentImportError.ocrFailed
        }

        return request.results?.compactMap { observation in
            observation.topCandidates(1).first?.string
        } ?? []
    }
}
