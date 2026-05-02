import Combine
import Foundation

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }
}

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case recent
    case title
    case author
    case manual

    var id: String { rawValue }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet {
            applyFilterAndSort()
        }
    }

    @Published var sortMode: LibrarySortMode = .recent {
        didSet {
            applyFilterAndSort()
        }
    }

    @Published private(set) var reads: [SavedRead] = []
    @Published private(set) var isLibraryEmpty = true

    private let store: LocalReadingHistoryStore
    private var allReads: [SavedRead] = []
    private var searchIndex: [UUID: String] = [:]
    private var cancellables: Set<AnyCancellable> = []

    var isSearching: Bool {
        !normalizedSearchText.isEmpty
    }

    init(store: LocalReadingHistoryStore) {
        self.store = store

        store.$savedReads
            .sink { [weak self] reads in
                self?.updateReads(reads)
            }
            .store(in: &cancellables)
    }

    private func updateReads(_ reads: [SavedRead]) {
        allReads = reads
        isLibraryEmpty = reads.isEmpty
        searchIndex = Dictionary(reads.map { read in
            (read.id, Self.searchableText(for: read))
        }, uniquingKeysWith: { first, _ in first })
        applyFilterAndSort()
    }

    private func applyFilterAndSort() {
        let query = normalizedSearchText
        var filtered = allReads
        
        if !query.isEmpty {
            filtered = allReads.filter { read in
                searchIndex[read.id]?.contains(query) == true
            }
        }

        switch sortMode {
        case .recent:
            filtered.sort {
                if $0.lastOpenedAt != $1.lastOpenedAt {
                    return $0.lastOpenedAt > $1.lastOpenedAt
                } else if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.createdAt > $1.createdAt
            }
        case .title:
            filtered.sort {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .author:
            filtered.sort {
                let author1 = $0.author ?? ""
                let author2 = $1.author ?? ""
                if author1.isEmpty && !author2.isEmpty { return false }
                if !author1.isEmpty && author2.isEmpty { return true }
                if author1.isEmpty && author2.isEmpty {
                    return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                if author1.localizedCaseInsensitiveCompare(author2) == .orderedSame {
                    return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                return author1.localizedCaseInsensitiveCompare(author2) == .orderedAscending
            }
        case .manual:
            filtered.sort {
                let s1 = $0.manualSortIndex ?? Int.max
                let s2 = $1.manualSortIndex ?? Int.max
                if s1 == s2 {
                    return $0.createdAt > $1.createdAt
                }
                return s1 < s2
            }
        }

        reads = filtered
    }

    private var normalizedSearchText: String {
        Self.normalized(searchText)
    }

    private static func searchableText(for read: SavedRead) -> String {
        [
            read.displayTitle,
            read.author,
            read.originalFileName
        ]
        .compactMap { $0 }
        .map(normalized)
        .joined(separator: " ")
    }

    private static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
