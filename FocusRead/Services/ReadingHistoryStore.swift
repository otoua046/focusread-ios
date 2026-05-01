import Foundation

@MainActor
protocol ReadingHistoryStore: AnyObject {
    var savedReads: [SavedRead] { get }

    func load()
    func save(_ read: SavedRead, durability: ReadingHistoryPersistenceDurability)
    func delete(_ read: SavedRead)
    func toggleFavorite(_ read: SavedRead)
    func read(withID id: UUID) -> SavedRead?
}

enum ReadingHistoryPersistenceDurability {
    case normal
    case immediate
}

extension ReadingHistoryStore {
    func save(_ read: SavedRead) {
        save(read, durability: .normal)
    }
}
