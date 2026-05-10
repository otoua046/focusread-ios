import Foundation

struct SavedRead: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var displayTitle: String
    var authorName: String?
    var originalFileName: String?
    var sourceType: SavedReadSourceType
    var languageCode: String?
    var thumbnailPath: String?
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date
    var totalWordCount: Int
    var currentWordIndex: Int
    var progressPercent: Double
    var currentPage: Int?
    var totalPages: Int?
    var currentChapter: Int?
    var totalChapters: Int?
    var sections: [SavedReadSection]
    var cleanupModeUsed: String
    var isFavorite: Bool
    var readingStats: SavedReadStats
    var author: String?
    var manualSortIndex: Int?

    var documentText: String {
        sections.map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}

enum SavedReadSourceType: String, Codable, Equatable, Sendable {
    case pastedText
    case txt
    case pdf
    case epub
    case image

    var debugLogName: String {
        switch self {
        case .pastedText:
            return "Pasted Text"
        case .txt:
            return "TXT"
        case .pdf:
            return "PDF"
        case .epub:
            return "EPUB"
        case .image:
            return "Image"
        }
    }
}

struct SavedReadSection: Identifiable, Codable, Equatable, Sendable {
    var id: Int { index }

    let index: Int
    var title: String?
    var text: String
    var pageNumber: Int?
    var chapterNumber: Int?
    var wordRange: SavedReadWordRange?
    var epubNavigationLevel: Int?
    var epubSectionRole: EPUBSectionRole
    var epubStructureSource: EPUBStructureSource?
    var epubStructureConfidence: Double?
}

struct SavedReadWordRange: Codable, Equatable, Sendable {
    let lowerBound: Int
    let upperBound: Int

    init(_ range: Range<Int>) {
        self.lowerBound = range.lowerBound
        self.upperBound = range.upperBound
    }

    var range: Range<Int> {
        lowerBound..<upperBound
    }
}

struct SavedReadStats: Codable, Equatable, Sendable {
    var totalTimeRead: TimeInterval
    var sessionsCount: Int

    static let empty = SavedReadStats(totalTimeRead: 0, sessionsCount: 0)
}
