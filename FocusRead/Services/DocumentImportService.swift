import Foundation

struct DocumentImportService: Sendable {
    private let textExtractor: TextFileExtractor
    private let pdfExtractor: PDFTextExtractor
    private let epubExtractor: EPUBTextExtractor

    init(
        textExtractor: TextFileExtractor = TextFileExtractor(),
        pdfExtractor: PDFTextExtractor = PDFTextExtractor(),
        epubExtractor: EPUBTextExtractor = EPUBTextExtractor()
    ) {
        self.textExtractor = textExtractor
        self.pdfExtractor = pdfExtractor
        self.epubExtractor = epubExtractor
    }

    func extractText(
        from file: ImportedFile,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument {
        switch file.fileExtension {
        case "txt":
            return try await textExtractor.extractText(from: file, progress: progress)
        case "pdf":
            return try await pdfExtractor.extractText(from: file, progress: progress)
        case "epub":
            return try await epubExtractor.extractText(from: file, progress: progress)
        default:
            throw DocumentImportError.unsupportedFileType(file.fileExtension)
        }
    }
}

actor DocumentImportWorker {
    private let pickerService: DocumentPickerService
    private let importService: DocumentImportService

    init(
        pickerService: DocumentPickerService = DocumentPickerService(),
        importService: DocumentImportService = DocumentImportService()
    ) {
        self.pickerService = pickerService
        self.importService = importService
    }

    func importDocument(
        from url: URL,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument {
        let file = try pickerService.copySecurityScopedFile(from: url)
        return try await importService.extractText(from: file, progress: progress)
    }
}
