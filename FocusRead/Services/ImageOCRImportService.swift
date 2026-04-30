import Foundation

struct ImageOCRImportService: Sendable {
    private let ocrExtractor: OCRTextExtractor
    private let smartCleanupService: SmartCleanupService

    init(
        ocrExtractor: OCRTextExtractor = OCRTextExtractor(),
        smartCleanupService: SmartCleanupService = SmartCleanupService()
    ) {
        self.ocrExtractor = ocrExtractor
        self.smartCleanupService = smartCleanupService
    }

    func importImages(
        _ images: [OCRImagePage],
        title: String,
        fileName: String,
        smartCleanupMode: SmartCleanupMode,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument {
        let document = try await ocrExtractor.extractText(
            from: images,
            fileName: fileName,
            displayTitle: title,
            progress: progress
        )

        return await smartCleanupService.clean(
            document,
            mode: smartCleanupMode,
            progress: progress
        )
    }
}
