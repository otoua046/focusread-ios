import Foundation

struct ImportedFile: Sendable {
    let localURL: URL
    let fileName: String
    let fileExtension: String
}

struct ImportedDocument: Equatable, Sendable {
    let fileName: String
    let text: String
    let sourceType: DocumentSourceType

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

enum DocumentSourceType: Equatable, Sendable {
    case plainText
    case pdfText
    case pdfOCR
    case epub

    var label: String {
        switch self {
        case .plainText:
            "Plain text"
        case .pdfText:
            "PDF text"
        case .pdfOCR:
            "PDF OCR"
        case .epub:
            "EPUB"
        }
    }
}

struct DocumentImportProgress: Equatable, Sendable {
    let message: String
    let completedUnitCount: Int?
    let totalUnitCount: Int?

    static let starting = DocumentImportProgress(
        message: "Extracting text...",
        completedUnitCount: nil,
        totalUnitCount: nil
    )

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

        return "\(completedUnitCount) of \(totalUnitCount) pages"
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
            "FocusRead could not find readable text in this file."
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
