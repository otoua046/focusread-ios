import Foundation

@MainActor
final class LocalReadingHistoryStore: ObservableObject, ReadingHistoryStore {
    @Published private(set) var savedReads: [SavedRead] = []

    private let fileManager: FileManager
    private let storageDirectory: URL
    private let fileURL: URL
    private let deletedReadsURL: URL
    private let loader: ReadingHistoryFileLoader
    private let writer: ReadingHistoryFileWriter
    private var deletedReadTombstones: [SyncedDeletedLibraryItem] = []
    private var persistRevision = 0
    private var persistenceSuspended = false
    private var hasLocalMutations = false

    var hasPersistedReadingHistory: Bool {
        fileManager.fileExists(atPath: fileURL.path)
            || fileManager.fileExists(atPath: deletedReadsURL.path)
    }

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        self.fileManager = fileManager
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = storageDirectory ?? supportDirectory.appendingPathComponent("FocusRead", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageDirectory = directory
        self.fileURL = directory.appendingPathComponent("SavedReads.json")
        self.deletedReadsURL = directory.appendingPathComponent("DeletedLibraryItems.json")
        self.loader = ReadingHistoryFileLoader(fileURL: fileURL)
        self.writer = ReadingHistoryFileWriter(fileURL: fileURL)
        self.deletedReadTombstones = Self.loadDeletedReadTombstones(from: deletedReadsURL)

        load()
    }

    func load() {
        hasLocalMutations = false
        loader.load { [weak self] result in
            Task { @MainActor in
                self?.applyLoadResult(result)
            }
        }
    }

    func save(_ read: SavedRead, durability: ReadingHistoryPersistenceDurability = .normal) {
        hasLocalMutations = true
        if let index = savedReads.firstIndex(where: { $0.id == read.id }) {
            savedReads[index] = read
        } else {
            savedReads.append(read)
        }
        savedReads = savedReads.sortedByHistoryRecency()
        persist(durability: durability)
    }

    func delete(_ read: SavedRead) {
        hasLocalMutations = true
        recordDeletedLibraryItem(read)
        removeAssociatedFiles(for: read)
        savedReads.removeAll { $0.id == read.id }
        persist(durability: .normal)
    }

    func toggleFavorite(_ read: SavedRead) {
        guard var updated = self.read(withID: read.id) else { return }
        updated.isFavorite.toggle()
        updated.updatedAt = Date()
        save(updated)
    }

    func read(withID id: UUID) -> SavedRead? {
        savedReads.first { $0.id == id }
    }

    func syncSnapshotItems(now: Date = Date()) -> [SyncedSavedRead] {
        savedReads.map { SyncedSavedRead(read: $0) }
    }

    func syncDeletedLibraryItems() -> [SyncedDeletedLibraryItem] {
        deletedReadTombstones
    }

    func applySyncMergedReads(_ syncedReads: [SyncedSavedRead]) {
        let existingByID = Dictionary(savedReads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingByFingerprint = Dictionary(
            savedReads.map { (SyncedSavedRead.reconciliationFingerprint(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let mergedReads = syncedReads.map { syncedRead in
            let existing = existingByID[syncedRead.id] ?? existingByFingerprint[syncedRead.contentFingerprint]
            var mergedRead = syncedRead.localRead(preservingDocumentTextFrom: existing)
            if let existing, existing.id != mergedRead.id {
                migrateAssociatedFiles(from: existing, to: &mergedRead)
            }
            return mergedRead
        }
        let mergedReadIDs = Set(mergedReads.map(\.id))

        guard mergedReads.sortedByHistoryRecency() != savedReads else { return }
        savedReads
            .filter { !mergedReadIDs.contains($0.id) }
            .forEach(removeAssociatedFiles)
        hasLocalMutations = true
        savedReads = mergedReads.sortedByHistoryRecency()
        persist(durability: .immediate)
    }

    func applySyncMergedDeletedLibraryItems(_ deletedItems: [SyncedDeletedLibraryItem]) {
        let merged = Self.mergeDeletedReadTombstones(deletedReadTombstones + deletedItems)
        guard merged != deletedReadTombstones else { return }
        deletedReadTombstones = merged
        persistDeletedReadTombstones()
    }

    private func applyLoadResult(_ result: ReadingHistoryLoadResult) {
        guard !hasLocalMutations else { return }

        switch result {
        case .missing:
            savedReads = []
        case .loaded(let reads):
            savedReads = reads.sortedByHistoryRecency()
        case .failed(let quarantineSucceeded, let message):
            savedReads = []
            persistenceSuspended = !quarantineSucceeded
            if !quarantineSucceeded {
                assertionFailure("Unable to quarantine unreadable reading history: \(message)")
            }
        }
    }

    private func persist(durability: ReadingHistoryPersistenceDurability) {
        guard !persistenceSuspended else { return }

        persistRevision += 1
        let revision = persistRevision
        let snapshot = savedReads

        switch durability {
        case .normal:
            writer.persist(snapshot, revision: revision)
        case .immediate:
            writer.persistSynchronously(snapshot, revision: revision)
        }
    }

    private func removeAssociatedFiles(for read: SavedRead) {
        try? fileManager.removeItem(at: associatedFilesURL(for: read.id))
    }

    private func migrateAssociatedFiles(from existing: SavedRead, to mergedRead: inout SavedRead) {
        let existingFolderURL = associatedFilesURL(for: existing.id)
        guard fileManager.fileExists(atPath: existingFolderURL.path) else { return }

        let mergedFolderURL = associatedFilesURL(for: mergedRead.id)
        do {
            if fileManager.fileExists(atPath: mergedFolderURL.path) {
                try copyMissingAssociatedFiles(from: existingFolderURL, to: mergedFolderURL)
                try? fileManager.removeItem(at: existingFolderURL)
            } else {
                try fileManager.createDirectory(
                    at: mergedFolderURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: existingFolderURL, to: mergedFolderURL)
            }

            let migratedThumbnailURL = mergedFolderURL.appendingPathComponent("thumbnail.jpg")
            if fileManager.fileExists(atPath: migratedThumbnailURL.path) {
                mergedRead.thumbnailPath = "SavedReads/\(mergedRead.id.uuidString)/thumbnail.jpg"
            }
        } catch {
            assertionFailure("Unable to migrate associated files for synced read \(existing.id): \(error)")
        }
    }

    private func copyMissingAssociatedFiles(from sourceFolderURL: URL, to destinationFolderURL: URL) throws {
        try fileManager.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
        let sourceItems = try fileManager.contentsOfDirectory(
            at: sourceFolderURL,
            includingPropertiesForKeys: nil
        )
        for sourceURL in sourceItems {
            let destinationURL = destinationFolderURL.appendingPathComponent(sourceURL.lastPathComponent)
            guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func associatedFilesURL(for readID: UUID) -> URL {
        storageDirectory
            .appendingPathComponent("SavedReads", isDirectory: true)
            .appendingPathComponent(readID.uuidString, isDirectory: true)
    }

    private func recordDeletedLibraryItem(_ read: SavedRead) {
        let tombstone = SyncedDeletedLibraryItem(
            id: read.id,
            contentFingerprint: SyncedSavedRead.reconciliationFingerprint(for: read),
            deletedAt: Date()
        )
        deletedReadTombstones = Self.mergeDeletedReadTombstones(deletedReadTombstones + [tombstone])
        persistDeletedReadTombstones()
    }

    private func persistDeletedReadTombstones() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(deletedReadTombstones)
            try data.write(to: deletedReadsURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to persist deleted reading history tombstones: \(error)")
        }
    }

    private static func loadDeletedReadTombstones(from url: URL) -> [SyncedDeletedLibraryItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try Data(contentsOf: url)
            return mergeDeletedReadTombstones(try decoder.decode([SyncedDeletedLibraryItem].self, from: data))
        } catch {
            assertionFailure("Unable to load deleted reading history tombstones: \(error)")
            return []
        }
    }

    private static func mergeDeletedReadTombstones(_ tombstones: [SyncedDeletedLibraryItem]) -> [SyncedDeletedLibraryItem] {
        var byID: [UUID: SyncedDeletedLibraryItem] = [:]
        for tombstone in tombstones {
            guard let existing = byID[tombstone.id] else {
                byID[tombstone.id] = tombstone
                continue
            }
            byID[tombstone.id] = existing.deletedAt >= tombstone.deletedAt ? existing : tombstone
        }
        return byID.values.sorted { $0.deletedAt > $1.deletedAt }
    }
}

private enum ReadingHistoryLoadResult: Sendable {
    case missing
    case loaded([SavedRead])
    case failed(quarantineSucceeded: Bool, message: String)
}

private final class ReadingHistoryFileLoader: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "FocusRead.ReadingHistoryFileLoader", qos: .utility)

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load(completion: @escaping @Sendable (ReadingHistoryLoadResult) -> Void) {
        queue.async { [self] in
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                completion(.missing)
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let data = try Data(contentsOf: fileURL)
                let reads = try decoder.decode([SavedRead].self, from: data)
                completion(.loaded(reads))
            } catch {
                completion(quarantineUnreadableHistoryFile(loadError: error))
            }
        }
    }

    private func quarantineUnreadableHistoryFile(loadError: Error) -> ReadingHistoryLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failed(quarantineSucceeded: true, message: "\(loadError)")
        }

        let quarantineURL = quarantinedFileURL()
        do {
            try FileManager.default.copyItem(at: fileURL, to: quarantineURL)
            try? FileManager.default.removeItem(at: fileURL)
            return .failed(quarantineSucceeded: true, message: "\(loadError)")
        } catch {
            return .failed(quarantineSucceeded: false, message: "\(loadError); quarantine error: \(error)")
        }
    }

    private func quarantinedFileURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("SavedReads-unreadable-\(timestamp).json")
    }
}

private final class ReadingHistoryFileWriter: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "FocusRead.ReadingHistoryFileWriter", qos: .utility)
    private var latestRevision = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func persist(_ savedReads: [SavedRead], revision: Int) {
        queue.async { [self] in
            persistOnQueue(savedReads, revision: revision)
        }
    }

    func persistSynchronously(_ savedReads: [SavedRead], revision: Int) {
        queue.sync {
            persistOnQueue(savedReads, revision: revision)
        }
    }

    private func persistOnQueue(_ savedReads: [SavedRead], revision: Int) {
        guard revision >= latestRevision else { return }
        latestRevision = revision

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(savedReads)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to persist reading history: \(error)")
        }
    }
}

private extension Array where Element == SavedRead {
    func sortedByHistoryRecency() -> [SavedRead] {
        sorted {
            if $0.isFavorite != $1.isFavorite {
                return $0.isFavorite && !$1.isFavorite
            }
            return $0.lastOpenedAt > $1.lastOpenedAt
        }
    }
}
