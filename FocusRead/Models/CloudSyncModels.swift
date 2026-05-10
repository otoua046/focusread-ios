import Foundation

enum CloudSyncSettingsKey {
    static let isEnabled = "icloudSync.isEnabled"
    static let lastSyncedAt = "icloudSync.lastSyncedAt"
    static let settingsUpdatedAtPrefix = "icloudSync.settings.updatedAt."
}

enum CloudSyncStatusKind: String, Codable, Equatable, Sendable {
    case off
    case unavailable
    case syncing
    case synced
    case error
}

struct SyncStatus: Equatable, Sendable {
    var kind: CloudSyncStatusKind
    var lastSyncedAt: Date?
    var message: String?

    static let off = SyncStatus(kind: .off, lastSyncedAt: nil, message: nil)
}

struct CloudSyncSnapshot: Codable, Equatable, Sendable {
    var libraryItems: [SyncedSavedRead]
    var readingStats: SyncedReadingStats?
    var settings: SyncedAppSettings?
    var aiRecaps: [AIRecap]
    var migrationState: CloudSyncMigrationState
    var generatedAt: Date

    static func empty(generatedAt: Date = Date()) -> CloudSyncSnapshot {
        CloudSyncSnapshot(
            libraryItems: [],
            readingStats: nil,
            settings: nil,
            aiRecaps: [],
            migrationState: CloudSyncMigrationState(),
            generatedAt: generatedAt
        )
    }
}

struct SavedReadCloudSyncMetadata: Codable, Equatable, Sendable {
    var isMetadataOnly: Bool
    var fileSyncState: CloudDocumentFileSyncState
    var contentFingerprint: String?
    var migratedAt: Date?

    static let localDocumentAvailable = SavedReadCloudSyncMetadata(
        isMetadataOnly: false,
        fileSyncState: .localOnly,
        contentFingerprint: nil,
        migratedAt: nil
    )
}

enum CloudDocumentFileSyncState: String, Codable, Equatable, Sendable {
    case localOnly
    case metadataOnly
    case pendingUpload
    case uploaded
    case unavailable
}

struct CloudDocumentFileSyncDescriptor: Codable, Equatable, Sendable {
    var readID: UUID
    var originalFileName: String?
    var sourceType: SavedReadSourceType
    var contentFingerprint: String
    var localRelativePath: String?
    var cloudAssetRecordName: String?
    var fileSizeBytes: Int64?
    var lastValidatedAt: Date?
}

struct SyncedSavedRead: Identifiable, Codable, Equatable, Sendable {
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
    var sections: [SyncedSavedReadSection]
    var cleanupModeUsed: String
    var isFavorite: Bool
    var readingStats: SavedReadStats
    var author: String?
    var manualSortIndex: Int?
    var contentFingerprint: String
    var isDocumentTextIncluded: Bool
    var fileSync: CloudDocumentFileSyncDescriptor?

    init(read: SavedRead, migratedAt: Date? = nil) {
        id = read.id
        displayTitle = read.displayTitle
        authorName = read.authorName
        originalFileName = read.originalFileName
        sourceType = read.sourceType
        languageCode = read.languageCode
        thumbnailPath = read.thumbnailPath
        createdAt = read.createdAt
        updatedAt = read.updatedAt
        lastOpenedAt = read.lastOpenedAt
        totalWordCount = read.totalWordCount
        currentWordIndex = read.currentWordIndex
        progressPercent = read.progressPercent
        currentPage = read.currentPage
        totalPages = read.totalPages
        currentChapter = read.currentChapter
        totalChapters = read.totalChapters
        sections = read.sections.map(SyncedSavedReadSection.init(section:))
        cleanupModeUsed = read.cleanupModeUsed
        isFavorite = read.isFavorite
        readingStats = read.readingStats
        author = read.author
        manualSortIndex = read.manualSortIndex
        contentFingerprint = Self.contentFingerprint(for: read)
        isDocumentTextIncluded = false
        fileSync = CloudDocumentFileSyncDescriptor(
            readID: read.id,
            originalFileName: read.originalFileName,
            sourceType: read.sourceType,
            contentFingerprint: contentFingerprint,
            localRelativePath: nil,
            cloudAssetRecordName: nil,
            fileSizeBytes: nil,
            lastValidatedAt: migratedAt
        )
    }

    func localRead(preservingDocumentTextFrom existing: SavedRead?) -> SavedRead {
        let existingSectionsByIndex = Dictionary(
            (existing?.sections ?? []).map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let restoredSections = sections.map { section in
            section.localSection(existing: existingSectionsByIndex[section.index])
        }
        let hasLocalText = restoredSections.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return SavedRead(
            id: id,
            displayTitle: displayTitle,
            authorName: authorName,
            originalFileName: originalFileName,
            sourceType: sourceType,
            languageCode: languageCode,
            thumbnailPath: thumbnailPath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastOpenedAt: lastOpenedAt,
            totalWordCount: totalWordCount,
            currentWordIndex: currentWordIndex,
            progressPercent: progressPercent,
            currentPage: currentPage,
            totalPages: totalPages,
            currentChapter: currentChapter,
            totalChapters: totalChapters,
            sections: restoredSections,
            cleanupModeUsed: cleanupModeUsed,
            isFavorite: isFavorite,
            readingStats: readingStats,
            author: author,
            manualSortIndex: manualSortIndex,
            cloudSync: SavedReadCloudSyncMetadata(
                isMetadataOnly: !hasLocalText,
                fileSyncState: hasLocalText ? .localOnly : .metadataOnly,
                contentFingerprint: contentFingerprint,
                migratedAt: fileSync?.lastValidatedAt
            )
        )
    }

    static func contentFingerprint(for read: SavedRead) -> String {
        let sectionSignature = read.sections
            .map { "\($0.index):\($0.title ?? ""):\($0.pageNumber ?? -1):\($0.chapterNumber ?? -1)" }
            .joined(separator: "|")
        return stableHash([
            read.originalFileName ?? "",
            read.displayTitle,
            read.author ?? read.authorName ?? "",
            read.sourceType.rawValue,
            "\(read.totalWordCount)",
            sectionSignature
        ].joined(separator: "#"))
    }

    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

struct SyncedSavedReadSection: Codable, Equatable, Sendable {
    var index: Int
    var title: String?
    var pageNumber: Int?
    var chapterNumber: Int?
    var wordRange: SavedReadWordRange?
    var epubNavigationLevel: Int?
    var epubSectionRole: EPUBSectionRole
    var epubStructureSource: EPUBStructureSource?
    var epubStructureConfidence: Double?

    init(section: SavedReadSection) {
        index = section.index
        title = section.title
        pageNumber = section.pageNumber
        chapterNumber = section.chapterNumber
        wordRange = section.wordRange
        epubNavigationLevel = section.epubNavigationLevel
        epubSectionRole = section.epubSectionRole
        epubStructureSource = section.epubStructureSource
        epubStructureConfidence = section.epubStructureConfidence
    }

    func localSection(existing: SavedReadSection?) -> SavedReadSection {
        SavedReadSection(
            index: index,
            title: title,
            text: existing?.text ?? "",
            pageNumber: pageNumber,
            chapterNumber: chapterNumber,
            wordRange: wordRange,
            epubNavigationLevel: epubNavigationLevel,
            epubSectionRole: epubSectionRole,
            epubStructureSource: epubStructureSource,
            epubStructureConfidence: epubStructureConfidence
        )
    }
}

struct SyncedReadingStats: Codable, Equatable, Sendable {
    var dailyGoalWords: Int
    var dailyStats: [DailyReadingStats]
    var sessionEvents: [ReadingSessionEvent]
    var completedReadIDs: [UUID]
    var updatedAt: Date
}

struct SyncedAppSettings: Codable, Equatable, Sendable {
    var values: [SyncedSettingValue]
    var updatedAt: Date
}

struct SyncedSettingValue: Identifiable, Codable, Equatable, Sendable {
    var id: String { key }

    var key: String
    var value: String
    var kind: SyncedSettingValueKind
    var updatedAt: Date
}

enum SyncedSettingValueKind: String, Codable, Equatable, Sendable {
    case string
    case integer
    case double
    case bool
}

struct CloudSyncMigrationState: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var migratedReadIDs: [UUID] = []
    var migratedSettingKeys: [String] = []
    var migratedStatsAt: Date?
    var migratedRecapIDs: [UUID] = []
    var lastMigrationRunAt: Date?
    var localSnapshotSignature: String?
    var logEntries: [CloudSyncMigrationLogEntry] = []
}

struct CloudSyncMigrationLogEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var message: String
}
