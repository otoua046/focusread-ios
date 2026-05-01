import Foundation

@MainActor
final class LocalReadingHistoryStore: ObservableObject, ReadingHistoryStore {
    @Published private(set) var savedReads: [SavedRead] = []

    private let fileURL: URL
    private let loader: ReadingHistoryFileLoader
    private let writer: ReadingHistoryFileWriter
    private var persistRevision = 0
    private var persistenceSuspended = false
    private var hasLocalMutations = false

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = supportDirectory.appendingPathComponent("FocusRead", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("SavedReads.json")
        self.loader = ReadingHistoryFileLoader(fileURL: fileURL)
        self.writer = ReadingHistoryFileWriter(fileURL: fileURL)

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
