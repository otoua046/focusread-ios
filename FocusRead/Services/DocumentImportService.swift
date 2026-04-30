import Foundation

struct DocumentImportService: Sendable {
    private let textExtractor: TextFileExtractor
    private let pdfExtractor: PDFTextExtractor
    private let epubExtractor: EPUBTextExtractor
    private let smartCleanupService: SmartCleanupService

    init(
        textExtractor: TextFileExtractor = TextFileExtractor(),
        pdfExtractor: PDFTextExtractor = PDFTextExtractor(),
        epubExtractor: EPUBTextExtractor = EPUBTextExtractor(),
        smartCleanupService: SmartCleanupService = SmartCleanupService()
    ) {
        self.textExtractor = textExtractor
        self.pdfExtractor = pdfExtractor
        self.epubExtractor = epubExtractor
        self.smartCleanupService = smartCleanupService
    }

    func extractText(
        from file: ImportedFile,
        smartCleanupMode: SmartCleanupMode,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument {
        let document = switch file.fileExtension {
        case "txt":
            try await textExtractor.extractText(from: file, progress: progress)
        case "pdf":
            try await pdfExtractor.extractText(from: file, progress: progress)
        case "epub":
            try await epubExtractor.extractText(from: file, progress: progress)
        default:
            throw DocumentImportError.unsupportedFileType(file.fileExtension)
        }

        return await smartCleanupService.clean(
            document,
            mode: smartCleanupMode,
            progress: progress
        )
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
        smartCleanupMode: SmartCleanupMode,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument {
        let file = try pickerService.copySecurityScopedFile(from: url)
        return try await importService.extractText(
            from: file,
            smartCleanupMode: smartCleanupMode,
            progress: progress
        )
    }
}
