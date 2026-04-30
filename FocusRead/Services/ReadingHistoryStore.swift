import Foundation

@MainActor
protocol ReadingHistoryStore: AnyObject {
    var savedReads: [SavedRead] { get }

    func load()
    func save(_ read: SavedRead)
    func delete(_ read: SavedRead)
    func toggleFavorite(_ read: SavedRead)
    func read(withID id: UUID) -> SavedRead?
}
