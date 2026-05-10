import Foundation

@MainActor
protocol AIRecapStore: AnyObject {
    func recaps(for readID: UUID) -> [AIRecap]
    func save(_ recap: AIRecap)
    func deleteRecap(sessionID: UUID, for readID: UUID)
    func deleteRecaps(for readID: UUID)
}

@MainActor
final class LocalAIRecapStore: ObservableObject, AIRecapStore {
    @Published private(set) var recapsByReadID: [UUID: [AIRecap]] = [:]

    private let fileManager: FileManager
    private let storageDirectory: URL
    private var loadedReadIDs: Set<UUID> = []

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.storageDirectory = storageDirectory ?? Self.defaultStorageDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
    }

    func recaps(for readID: UUID) -> [AIRecap] {
        loadIfNeeded(readID: readID)
        return recapsByReadID[readID] ?? []
    }

    func save(_ recap: AIRecap) {
        loadIfNeeded(readID: recap.readID)

        var recaps = recapsByReadID[recap.readID] ?? []
        recaps.removeAll { $0.sessionID == recap.sessionID }
        recaps.insert(recap, at: 0)
        recaps = Array(recaps.sortedByRecapRecency().prefix(3))

        recapsByReadID[recap.readID] = recaps
        persist(recaps, for: recap.readID)
    }

    func deleteRecap(sessionID: UUID, for readID: UUID) {
        loadIfNeeded(readID: readID)

        var recaps = recapsByReadID[readID] ?? []
        recaps.removeAll { $0.sessionID == sessionID }
        recapsByReadID[readID] = recaps
        persist(recaps, for: readID)
    }

    func deleteRecaps(for readID: UUID) {
        recapsByReadID.removeValue(forKey: readID)
        loadedReadIDs.remove(readID)
        try? fileManager.removeItem(at: recapsFileURL(for: readID))
    }

    func syncSnapshotRecaps(for readIDs: [UUID]) -> [AIRecap] {
        readIDs.flatMap { recaps(for: $0) }
            .sortedByRecapRecency()
    }

    func applySyncMergedRecaps(_ recaps: [AIRecap]) {
        let grouped = Dictionary(grouping: recaps, by: \.readID)
        for (readID, remoteRecaps) in grouped {
            loadIfNeeded(readID: readID)
            let existing = recapsByReadID[readID] ?? []
            let merged = SyncConflictResolver.mergeAIRecaps(local: existing, cloud: remoteRecaps).value
            let capped = Array(merged.sortedByRecapRecency().prefix(3))
            guard capped != existing else { continue }
            recapsByReadID[readID] = capped
            persist(capped, for: readID)
        }
    }

    private func loadIfNeeded(readID: UUID) {
        guard !loadedReadIDs.contains(readID) else { return }
        loadedReadIDs.insert(readID)

        let fileURL = recapsFileURL(for: readID)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            recapsByReadID[readID] = []
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try Data(contentsOf: fileURL)
            let recaps = try decoder.decode([AIRecap].self, from: data)
            recapsByReadID[readID] = Array(recaps.sortedByRecapRecency().prefix(3))
        } catch {
            quarantineUnreadableRecapsFile(fileURL)
            recapsByReadID[readID] = []
        }
    }

    private func persist(_ recaps: [AIRecap], for readID: UUID) {
        let folderURL = folderURL(for: readID)
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(recaps.sortedByRecapRecency())
            try data.write(to: recapsFileURL(for: readID), options: [.atomic])
        } catch {
            assertionFailure("Unable to persist AI recaps: \(error)")
        }
    }

    private func quarantineUnreadableRecapsFile(_ fileURL: URL) {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantineURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("AIRecaps-unreadable-\(timestamp).json")

        try? fileManager.copyItem(at: fileURL, to: quarantineURL)
        try? fileManager.removeItem(at: fileURL)
    }

    private func recapsFileURL(for readID: UUID) -> URL {
        folderURL(for: readID).appendingPathComponent("AIRecaps.json")
    }

    private func folderURL(for readID: UUID) -> URL {
        storageDirectory.appendingPathComponent(readID.uuidString, isDirectory: true)
    }

    private static func defaultStorageDirectory(fileManager: FileManager) -> URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return supportDirectory
            .appendingPathComponent("FocusRead", isDirectory: true)
            .appendingPathComponent("SavedReads", isDirectory: true)
    }
}

private extension Array where Element == AIRecap {
    func sortedByRecapRecency() -> [AIRecap] {
        sorted {
            if $0.sessionEndedAt != $1.sessionEndedAt {
                return $0.sessionEndedAt > $1.sessionEndedAt
            }
            return $0.createdAt > $1.createdAt
        }
    }
}
