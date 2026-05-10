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
            "Image OCR"
        }
    }
}

enum ImportSource: String, CaseIterable, Identifiable, Sendable {
    case files
    case camera
    case photoLibrary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files:
            "Files"
        case .camera:
            "Camera"
        case .photoLibrary:
            "Photo Library"
        }
    }

    var systemImageName: String {
        switch self {
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

    static let starting = DocumentImportProgress(
        message: "Extracting text...",
        completedUnitCount: nil,
        totalUnitCount: nil
    )

    init(
        message: String,
        completedUnitCount: Int?,
        totalUnitCount: Int?,
        unitName: String = "pages"
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

        return "\(completedUnitCount) of \(totalUnitCount) \(unitName)"
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
            "Import Cancelled"
        case .fileCopyFailed:
            "Could Not Read File"
        case .invalidTextEncoding:
            "Unsupported Text Encoding"
        case .unreadablePDF:
            "Could Not Read PDF"
        case .noReadableText:
            "No Readable Text Found"
        case .ocrFailed:
            "OCR Failed"
        case .invalidEPUB:
            "Invalid EPUB File"
        case .epubContentsNotFound:
            "Could Not Find Book Contents"
        case .epubNoReadableText:
            "EPUB Contains No Readable Text"
        case .epubExtractionFailed:
            "EPUB Extraction Failed"
        case .cameraUnavailable:
            "Camera Unavailable"
        case .cameraAccessDenied:
            "Camera Access Needed"
        case .imageImportFailed:
            "Could Not Import Image"
        case .unsupportedFileType:
            "Unsupported File"
        }
    }

    var message: String {
        switch self {
        case .cancelled:
            "No file was selected."
        case .fileCopyFailed:
            "FocusRead could not safely copy this file for reading."
        case .invalidTextEncoding:
            "This text file is not valid UTF-8."
        case .unreadablePDF:
            "FocusRead could not open this PDF."
        case .noReadableText:
            "No readable text found."
        case .ocrFailed:
            "FocusRead could not recognize text from this scanned PDF."
        case .invalidEPUB:
            "FocusRead could not read this as a valid EPUB archive."
        case .epubContentsNotFound:
            "FocusRead could not find the EPUB package, manifest, or reading order."
        case .epubNoReadableText:
            "FocusRead opened the EPUB but did not find readable chapter text."
        case .epubExtractionFailed:
            "FocusRead could not extract text from this EPUB."
        case .cameraUnavailable:
            "This device does not have an available camera."
        case .cameraAccessDenied:
            "Allow camera access in Settings to scan text with FocusRead."
        case .imageImportFailed:
            "FocusRead could not load the selected image."
        case .unsupportedFileType:
            "This file type is not supported yet."
        }
    }

    var errorDescription: String? {
        title
    }

    var recoverySuggestion: String? {
        message
    }
}
