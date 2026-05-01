import Foundation

@MainActor
final class LocalReadingHistoryStore: ObservableObject, ReadingHistoryStore {
    @Published private(set) var savedReads: [SavedRead] = []

    private let fileURL: URL
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let writer: ReadingHistoryFileWriter
    private var persistRevision = 0
    private var persistenceSuspended = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = supportDirectory.appendingPathComponent("FocusRead", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("SavedReads.json")
        self.writer = ReadingHistoryFileWriter(fileURL: fileURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            savedReads = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            savedReads = try decoder.decode([SavedRead].self, from: data)
                .sortedByHistoryRecency()
        } catch {
            quarantineUnreadableHistoryFile(error: error)
            savedReads = []
        }
    }

    func save(_ read: SavedRead) {
        if let index = savedReads.firstIndex(where: { $0.id == read.id }) {
            savedReads[index] = read
        } else {
            savedReads.append(read)
        }
        savedReads = savedReads.sortedByHistoryRecency()
        persist()
    }

    func delete(_ read: SavedRead) {
        savedReads.removeAll { $0.id == read.id }
        persist()
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

    private func persist() {
        guard !persistenceSuspended else { return }

        persistRevision += 1
        let revision = persistRevision
        let snapshot = savedReads
        let writer = writer

        Task(priority: .utility) {
            await writer.persist(snapshot, revision: revision)
        }
    }

    private func quarantineUnreadableHistoryFile(error loadError: Error) {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let quarantineURL = quarantinedFileURL()
        do {
            try fileManager.copyItem(at: fileURL, to: quarantineURL)
            try? fileManager.removeItem(at: fileURL)
            persistenceSuspended = false
        } catch {
            persistenceSuspended = true
            assertionFailure("Unable to quarantine unreadable reading history after \(loadError): \(error)")
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

private actor ReadingHistoryFileWriter {
    private let fileURL: URL
    private var latestRevision = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func persist(_ savedReads: [SavedRead], revision: Int) {
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
