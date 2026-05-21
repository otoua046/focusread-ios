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
        try await FocusReadBenchmarkSignposts.measure("DocumentImport") {
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
}

actor DocumentImportWorker {
    private let pickerService: DocumentPickerService
    private let importService: DocumentImportService
    private let imageImportService: ImageOCRImportService

    init(
        pickerService: DocumentPickerService = DocumentPickerService(),
        importService: DocumentImportService = DocumentImportService(),
        imageImportService: ImageOCRImportService = ImageOCRImportService()
    ) {
        self.pickerService = pickerService
        self.importService = importService
        self.imageImportService = imageImportService
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

    func importImages(
        _ images: [OCRImagePage],
        title: String,
        fileName: String,
        smartCleanupMode: SmartCleanupMode,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument {
        try await imageImportService.importImages(
            images,
            title: title,
            fileName: fileName,
            smartCleanupMode: smartCleanupMode,
            progress: progress
        )
    }
}
