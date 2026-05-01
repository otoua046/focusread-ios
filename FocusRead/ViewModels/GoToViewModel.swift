import Foundation

@MainActor
final class GoToViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [ReaderSearchResult] = []
    @Published private(set) var isSearching = false

    private let reader: ReaderViewModel
    private let searchService: ReaderSearchService
    private var searchTask: Task<Void, Never>?

    init(
        reader: ReaderViewModel,
        searchService: ReaderSearchService = ReaderSearchService()
    ) {
        self.reader = reader
        self.searchService = searchService
    }

    var showNoSearchResults: Bool {
        !isSearching
            && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && searchResults.isEmpty
    }

    func jumpToSearchResult(_ result: ReaderSearchResult) {
        reader.jumpToWordIndex(result.index)
    }

    func updateSearchQuery(_ query: String) {
        searchTask?.cancel()
        searchQuery = query

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        let tokens = reader.searchableTokens
        let searchService = searchService

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }

            let results = await Task.detached(priority: .userInitiated) {
                searchService.search(trimmedQuery, in: tokens)
            }.value

            guard !Task.isCancelled else { return }
            self?.searchResults = results
            self?.isSearching = false
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }
}
