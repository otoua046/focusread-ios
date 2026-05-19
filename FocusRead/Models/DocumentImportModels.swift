import Foundation

struct ImportedFile: Sendable {
    let localURL: URL
    let fileName: String
    let fileExtension: String
}

struct ImportedDocument: Equatable, Sendable {
    let fileName: String
    let displayTitle: String
    let author: String?
    let externalSourceID: String?
    let sourceType: DocumentSourceType
    let languageCode: String?
    let previewImageData: Data?
    let sections: [ImportedDocumentSection]
    let cleanupMode: SmartCleanupMode
    let cleanupChunks: [DocumentCleanupChunk]

    init(
        fileName: String,
        displayTitle: String? = nil,
        author: String? = nil,
        externalSourceID: String? = nil,
        text: String,
        sourceType: DocumentSourceType,
        languageCode: String? = nil,
        previewImageData: Data? = nil,
        cleanupMode: SmartCleanupMode = .off,
        cleanupChunks: [DocumentCleanupChunk] = []
    ) {
        self.fileName = fileName
        self.displayTitle = displayTitle ?? fileName
        self.author = author
        self.externalSourceID = externalSourceID
        self.sourceType = sourceType
        self.languageCode = languageCode
        self.previewImageData = previewImageData
        self.cleanupMode = cleanupMode
        self.cleanupChunks = cleanupChunks
        self.sections = [
            ImportedDocumentSection(
                index: 0,
                text: text,
                pageNumber: nil,
                chapterNumber: nil,
                chapterTitle: nil,
                wordRange: nil
            )
        ]
    }

    init(
        fileName: String,
        displayTitle: String? = nil,
        author: String? = nil,
        externalSourceID: String? = nil,
        sourceType: DocumentSourceType,
        languageCode: String? = nil,
        sections: [ImportedDocumentSection],
        previewImageData: Data? = nil,
        cleanupMode: SmartCleanupMode = .off,
        cleanupChunks: [DocumentCleanupChunk] = []
    ) {
        self.fileName = fileName
        self.displayTitle = displayTitle ?? fileName
        self.author = author
        self.externalSourceID = externalSourceID
        self.sourceType = sourceType
        self.languageCode = languageCode
        self.previewImageData = previewImageData
        self.sections = sections
        self.cleanupMode = cleanupMode
        self.cleanupChunks = cleanupChunks
    }

    func withCleanup(
        displayTitle: String,
        sections: [ImportedDocumentSection],
        cleanupMode: SmartCleanupMode,
        cleanupChunks: [DocumentCleanupChunk]
    ) -> ImportedDocument {
        ImportedDocument(
            fileName: fileName,
            displayTitle: displayTitle,
            author: author,
            externalSourceID: externalSourceID,
            sourceType: sourceType,
            languageCode: languageCode,
            sections: sections,
            previewImageData: previewImageData,
            cleanupMode: cleanupMode,
            cleanupChunks: cleanupChunks
        )
    }

    var text: String {
        sections.map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
            .focusReadNormalizedDocumentText
    }

    var estimatedWordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var previewText: String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.prefix(6).joined(separator: "\n")
    }
}

struct ImportedDocumentSection: Equatable, Sendable {
    let index: Int
    let text: String
    let pageNumber: Int?
    let chapterNumber: Int?
    let chapterTitle: String?

    let wordRange: Range<Int>?

    let epubNavigationLevel: Int?
    let epubSectionRole: EPUBSectionRole
    let epubStructureSource: EPUBStructureSource?
    let epubStructureConfidence: Double?

    init(
        index: Int,
        text: String,
        pageNumber: Int?,
        chapterNumber: Int?,
        chapterTitle: String?,
        wordRange: Range<Int>?,
        epubNavigationLevel: Int? = nil,
        epubSectionRole: EPUBSectionRole = .body,
        epubStructureSource: EPUBStructureSource? = nil,
        epubStructureConfidence: Double? = nil
    ) {
        self.index = index
        self.text = text
        self.pageNumber = pageNumber
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.wordRange = wordRange
        self.epubNavigationLevel = epubNavigationLevel
        self.epubSectionRole = epubSectionRole
        self.epubStructureSource = epubStructureSource
        self.epubStructureConfidence = epubStructureConfidence
    }
}

enum EPUBSectionRole: String, Codable, Equatable, Sendable {
    case body
    case chapter
    case part
    case frontMatter
    case backMatter
    case appendix
    case reference
}

enum EPUBStructureSource: String, Codable, Equatable, Sendable {
    case navigation
    case heading
    case spine
    case chunk
}

struct DocumentCleanupChunk: Identifiable, Equatable, Sendable {
    let id: UUID
    let sectionIndex: Int
    let sectionIndices: [Int]
    let wordRange: Range<Int>
    let sourcePageRange: ClosedRange<Int>?
    let chapterNumber: Int?
    let chapterTitle: String?
    let originalText: String
    let smartCleanedText: String
    var aiCleanedText: String?
    var status: DocumentCleanupChunkStatus

    var effectiveText: String {
        aiCleanedText ?? smartCleanedText
    }
}

enum DocumentCleanupChunkStatus: Equatable, Sendable {
    case pending
    case processing
    case completed
    case failed
}

struct DocumentStructureState: Equatable, Sendable {
    var detectedSections: [DetectedDocumentSection]
    var currentPartTitle: String?
    var currentChapterNumber: Int?
    var currentChapterTitle: String?
    var recentChunkSummaries: [ChunkStructureSummary]
    var confidence: Double

    static let empty = DocumentStructureState(
        detectedSections: [],
        currentPartTitle: nil,
        currentChapterNumber: nil,
        currentChapterTitle: nil,
        recentChunkSummaries: [],
        confidence: 0
    )
}

struct DetectedDocumentSection: Identifiable, Equatable, Sendable {
    let id: UUID
    let chunkID: UUID
    let sectionIndex: Int
    let sourcePageRange: ClosedRange<Int>?
    let chapterNumber: Int?
    let title: String
    let inferredSectionType: String?
    let confidence: Double
}

struct ChunkStructureSummary: Identifiable, Equatable, Sendable {
    var id: UUID { chunkID }

    let chunkID: UUID
    let sourcePageRange: ClosedRange<Int>?
    let chapterNumber: Int?
    let detectedHeading: String?
    let inferredSectionType: String?
    let epubStructureRepairAction: EPUBStructureRepairAction?
    let evidence: String?
    let startsNewSection: Bool
    let continuationOfPrevious: Bool
    let shortLabel: String?
    let confidence: Double
}

enum EPUBStructureRepairAction: String, Equatable, Sendable {
    case keep
    case mergeWithPrevious
    case splitAtEvidence
}

enum DocumentSourceType: Equatable, Sendable {
    case txt
    case pdf
    case epub
    case image

    var label: String {
        switch self {
        case .txt:
            "TXT"
        case .pdf:
            "PDF"
        case .epub:
            "EPUB"
        case .image:
            L10n.string(.importSourceImageOCR)
        }
    }
}

enum ImportSource: String, CaseIterable, Identifiable, Sendable {
    case quickRead
    case files
    case camera
    case photoLibrary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickRead:
            L10n.string(.importSourceQuickRead)
        case .files:
            L10n.string(.importSourceFiles)
        case .camera:
            L10n.string(.importSourceCamera)
        case .photoLibrary:
            L10n.string(.importSourcePhotoLibrary)
        }
    }

    var systemImageName: String {
        switch self {
        case .quickRead:
            "doc.on.clipboard"
        case .files:
            "folder"
        case .camera:
            "camera"
        case .photoLibrary:
            "photo.on.rectangle"
        }
    }
}

struct DocumentImportProgress: Equatable, Sendable {
    let message: String
    let completedUnitCount: Int?
    let totalUnitCount: Int?
    let unitName: String

    static var starting: DocumentImportProgress {
        DocumentImportProgress(
            message: L10n.string(.importProgressExtractingText),
            completedUnitCount: nil,
            totalUnitCount: nil
        )
    }

    init(
        message: String,
        completedUnitCount: Int?,
        totalUnitCount: Int?,
        unitName: String = L10n.string(.importUnitPages)
    ) {
        self.message = message
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.unitName = unitName
    }

    var fractionCompleted: Double? {
        guard let completedUnitCount,
              let totalUnitCount,
              totalUnitCount > 0 else {
            return nil
        }

        return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
    }

    var detail: String? {
        guard let completedUnitCount,
              let totalUnitCount,
              totalUnitCount > 0 else {
            return nil
        }

        return L10n.format(.importProgressDetailFormat, completedUnitCount, totalUnitCount, unitName)
    }
}

enum DocumentImportError: LocalizedError, Equatable, Sendable {
    case cancelled
    case fileCopyFailed
    case invalidTextEncoding
    case unreadablePDF
    case noReadableText
    case ocrFailed
    case invalidEPUB
    case epubContentsNotFound
    case epubNoReadableText
    case epubExtractionFailed
    case cameraUnavailable
    case cameraAccessDenied
    case imageImportFailed
    case unsupportedFileType(String)

    var title: String {
        switch self {
        case .cancelled:
            L10n.string(.importErrorCancelledTitle)
        case .fileCopyFailed:
            L10n.string(.importErrorFileCopyTitle)
        case .invalidTextEncoding:
            L10n.string(.importErrorInvalidTextEncodingTitle)
        case .unreadablePDF:
            L10n.string(.importErrorUnreadablePDFTitle)
        case .noReadableText:
            L10n.string(.importErrorNoReadableTextTitle)
        case .ocrFailed:
            L10n.string(.importErrorOCRFailedTitle)
        case .invalidEPUB:
            L10n.string(.importErrorInvalidEPUBTitle)
        case .epubContentsNotFound:
            L10n.string(.importErrorEPUBContentsNotFoundTitle)
        case .epubNoReadableText:
            L10n.string(.importErrorEPUBNoReadableTextTitle)
        case .epubExtractionFailed:
            L10n.string(.importErrorEPUBExtractionFailedTitle)
        case .cameraUnavailable:
            L10n.string(.importErrorCameraUnavailableTitle)
        case .cameraAccessDenied:
            L10n.string(.importErrorCameraAccessDeniedTitle)
        case .imageImportFailed:
            L10n.string(.importErrorImageImportFailedTitle)
        case .unsupportedFileType:
            L10n.string(.importErrorUnsupportedFileTitle)
        }
    }

    var message: String {
        switch self {
        case .cancelled:
            L10n.string(.importErrorCancelledMessage)
        case .fileCopyFailed:
            L10n.string(.importErrorFileCopyMessage)
        case .invalidTextEncoding:
            L10n.string(.importErrorInvalidTextEncodingMessage)
        case .unreadablePDF:
            L10n.string(.importErrorUnreadablePDFMessage)
        case .noReadableText:
            L10n.string(.importErrorNoReadableTextMessage)
        case .ocrFailed:
            L10n.string(.importErrorOCRFailedMessage)
        case .invalidEPUB:
            L10n.string(.importErrorInvalidEPUBMessage)
        case .epubContentsNotFound:
            L10n.string(.importErrorEPUBContentsNotFoundMessage)
        case .epubNoReadableText:
            L10n.string(.importErrorEPUBNoReadableTextMessage)
        case .epubExtractionFailed:
            L10n.string(.importErrorEPUBExtractionFailedMessage)
        case .cameraUnavailable:
            L10n.string(.importErrorCameraUnavailableMessage)
        case .cameraAccessDenied:
            L10n.string(.importErrorCameraAccessDeniedMessage)
        case .imageImportFailed:
            L10n.string(.importErrorImageImportFailedMessage)
        case .unsupportedFileType:
            L10n.string(.importErrorUnsupportedFileMessage)
        }
    }

    var errorDescription: String? {
        title
    }

    var recoverySuggestion: String? {
        message
    }
}
