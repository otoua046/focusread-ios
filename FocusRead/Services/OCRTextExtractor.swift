import Foundation
import ImageIO
import PDFKit
import UIKit
import Vision

struct OCRImagePage: @unchecked Sendable {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation

    init(cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) {
        self.cgImage = cgImage
        self.orientation = orientation
    }
}

struct OCRTextExtractor: DocumentTextExtractor {
    private let maximumRenderedPixelDimension: CGFloat = 1_800

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

        var sections = (0..<pageCount).map { pageIndex in
            ImportedDocumentSection(
                index: pageIndex,
                text: "",
                pageNumber: pageIndex + 1,
                chapterNumber: nil,
                chapterTitle: nil,
                wordRange: nil
            )
        }

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()

            await progress(DocumentImportProgress(
                message: "Recognizing scanned PDF text...",
                completedUnitCount: pageIndex,
                totalUnitCount: pageCount
            ))

            guard let page = document.page(at: pageIndex),
                  let cgImage = renderPage(page) else {
                continue
            }

            let lines = try recognizeText(in: cgImage)
            if !lines.isEmpty {
                sections[pageIndex] = ImportedDocumentSection(
                    index: pageIndex,
                    text: lines.joined(separator: "\n").focusReadNormalizedDocumentText,
                    pageNumber: pageIndex + 1,
                    chapterNumber: nil,
                    chapterTitle: nil,
                    wordRange: nil
                )
            }
        }

        await progress(DocumentImportProgress(
            message: "Recognizing scanned PDF text...",
            completedUnitCount: pageCount,
            totalUnitCount: pageCount
        ))

        let text = sections.map(\.text).joined(separator: "\n\n").focusReadNormalizedDocumentText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentImportError.ocrFailed
        }

        return ImportedDocument(
            fileName: file.fileName,
            sourceType: .pdf,
            sections: sections,
            previewImageData: previewImageData
        )
    }

    func extractText(
        from images: [OCRImagePage],
        fileName: String,
        displayTitle: String,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument {
        guard !images.isEmpty else {
            throw DocumentImportError.noReadableText
        }
        let previewImageData = previewImageData(from: images.first)

        var sections = images.indices.map { imageIndex in
            ImportedDocumentSection(
                index: imageIndex,
                text: "",
                pageNumber: imageIndex + 1,
                chapterNumber: nil,
                chapterTitle: nil,
                wordRange: nil
            )
        }

        for (imageIndex, image) in images.enumerated() {
            try Task.checkCancellation()

            await progress(DocumentImportProgress(
                message: "Recognizing text...",
                completedUnitCount: imageIndex,
                totalUnitCount: images.count,
                unitName: "images"
            ))

            let lines = try recognizeText(in: image.cgImage, orientation: image.orientation)
            if !lines.isEmpty {
                sections[imageIndex] = ImportedDocumentSection(
                    index: imageIndex,
                    text: lines.joined(separator: "\n").focusReadNormalizedDocumentText,
                    pageNumber: imageIndex + 1,
                    chapterNumber: nil,
                    chapterTitle: nil,
                    wordRange: nil
                )
            }
        }

        await progress(DocumentImportProgress(
            message: "Recognizing text...",
            completedUnitCount: images.count,
            totalUnitCount: images.count,
            unitName: "images"
        ))

        let text = sections.map(\.text).joined(separator: "\n\n").focusReadNormalizedDocumentText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentImportError.noReadableText
        }

        return ImportedDocument(
            fileName: fileName,
            displayTitle: displayTitle,
            sourceType: .image,
            sections: sections,
            previewImageData: previewImageData
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

    private func recognizeText(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw DocumentImportError.ocrFailed
        }

        return request.results?.compactMap { observation in
            observation.topCandidates(1).first?.string
        } ?? []
    }

    private func firstPagePreviewData(for document: PDFDocument) -> Data? {
        guard let page = document.page(at: 0) else {
            return nil
        }

        let thumbnail = page.thumbnail(of: CGSize(width: 480, height: 640), for: .cropBox)
        return thumbnail.jpegData(compressionQuality: 0.88)
    }

    private func previewImageData(from image: OCRImagePage?) -> Data? {
        guard let image else { return nil }
        let uiImage = UIImage(cgImage: image.cgImage, scale: 1, orientation: image.orientation.uiImageOrientation)
        return uiImage.jpegData(compressionQuality: 0.88)
    }
}

private extension CGImagePropertyOrientation {
    var uiImageOrientation: UIImage.Orientation {
        switch self {
        case .up:
            return .up
        case .down:
            return .down
        case .left:
            return .left
        case .right:
            return .right
        case .upMirrored:
            return .upMirrored
        case .downMirrored:
            return .downMirrored
        case .leftMirrored:
            return .leftMirrored
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}
