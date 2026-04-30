import Foundation

@MainActor
final class LocalReadingHistoryStore: ObservableObject, ReadingHistoryStore {
    @Published private(set) var savedReads: [SavedRead] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = supportDirectory.appendingPathComponent("FocusRead", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("SavedReads.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

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
        do {
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
