import Combine
import Foundation

enum DiscoverAction: Equatable {
    case add
    case read
}

enum DiscoverActionOutcome {
    case none
    case openExisting(SavedRead)
    case imported(ImportedDocument)
}

enum DiscoverBookActionState: Equatable {
    case idle
    case working(DiscoverAction)
    case added

    var isWorking: Bool {
        if case .working = self {
            return true
        }
        return false
    }

    var isAdded: Bool {
        self == .added
    }

    func isWorkingOn(_ action: DiscoverAction) -> Bool {
        self == .working(action)
    }
}

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var sections: [DiscoverSection] = [] {
        didSet { recommendationCache.removeAll() }
    }
    @Published private(set) var searchResults: [DiscoverBook] = [] {
        didSet { recommendationCache.removeAll() }
    }
    @Published private(set) var isLoadingSections = false
    @Published private(set) var isSearching = false
    @Published private(set) var message: String?
    @Published private(set) var actionStates: [String: DiscoverBookActionState] = [:]
    @Published private(set) var hasAttemptedCuratedLoad = false

    private let store: LocalReadingHistoryStore
    private let service: DiscoverService
    private var baseSections: [DiscoverSection]
    private var personalization: DiscoverPersonalization
    private var lastSearchKey = ""
    private var savedLookup = DiscoverSavedReadLookup(reads: [])
    private var recommendationCache: [String: [DiscoverBook]] = [:]
    private var shelfPaginationStates: [String: DiscoverShelfPaginationState] = [:]
    private var hydratedBookIDs: Set<String> = []
    private var hydratingBookIDs: Set<String> = []
    private static let paginationTriggerCooldown: TimeInterval = 0.75

    init(
        store: LocalReadingHistoryStore,
        service: DiscoverService = DiscoverService()
    ) {
        self.store = store
        self.service = service
        self.baseSections = DiscoverService.defaultCuratedSections()
        self.personalization = DiscoverPersonalization.current()
        self.sections = Self.personalizedSections(baseSections, personalization: personalization)
        refreshSavedLookup()
    }

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isShowingSearchResults: Bool {
        !trimmedSearchText.isEmpty
    }

    func loadCuratedIfNeeded() async {
        guard !isLoadingSections else { return }
        let initialLoadStartedAt = Date()
        isLoadingSections = true
        message = nil
        await applyInitialShelfSnapshotOrSeed(startedAt: initialLoadStartedAt)

        let refreshStartedAt = Date()
        defer {
            hasAttemptedCuratedLoad = true
            isLoadingSections = false
        }

        do {
            let refreshedSections = try await service.curatedSections()
            if !Task.isCancelled, !refreshedSections.isEmpty {
                applyRefreshedSections(refreshedSections)
                discoverDebugLog(
                    "Discover initial shelf refresh duration=\(Self.formattedDuration(since: refreshStartedAt)) sections=\(refreshedSections.count)"
                )
            }
        } catch {
            if sections.isEmpty {
                message = "Could not refresh Discover. Try again in a moment."
            }
        }
    }

    func searchAfterDelay() async {
        let requestedKey = trimmedSearchText.discoverIdentityComponent

        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        await searchNow(expectedKey: requestedKey)
    }

    func searchNow(expectedKey: String? = nil) async {
        let query = trimmedSearchText
        let queryKey = query.discoverIdentityComponent
        if let expectedKey, expectedKey != queryKey {
            return
        }
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            message = nil
            lastSearchKey = ""
            return
        }
        guard queryKey.count >= 2 else {
            searchResults = []
            isSearching = false
            message = nil
            lastSearchKey = queryKey
            return
        }

        isSearching = true
        message = nil
        lastSearchKey = queryKey

        let languageCodes = personalization.preferredLanguageCodes
        var latestBooks = searchResults
        if let cached = await service.cachedSearchResults(for: query, languageCodes: languageCodes) {
            searchResults = cached.books
            latestBooks = cached.books
            if cached.isComplete {
                isSearching = false
                if searchResults.isEmpty {
                    message = "No readable books found yet."
                }
                return
            }
        } else {
            searchResults = []
            latestBooks = []
        }

        var fastProviderReturned = false
        do {
            let fastResults = try await service.fastSearch(query, languageCodes: languageCodes)
            guard !Task.isCancelled, trimmedSearchText.discoverIdentityComponent == queryKey else { return }
            fastProviderReturned = true
            searchResults = fastResults
            latestBooks = fastResults
            if fastResults.isEmpty {
                discoverDebugLog("Discover search fastSearch empty query=\(queryKey)")
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, trimmedSearchText.discoverIdentityComponent == queryKey else { return }
            if latestBooks.isEmpty {
                discoverDebugLog("Discover search fastSearch failed query=\(queryKey)")
            }
        }

        if !fastProviderReturned || latestBooks.isEmpty {
            discoverDebugLog("Discover search continuing to enriched fallback query=\(queryKey)")
        }

        let validationBaseBooks = latestBooks
        async let validationSnapshot = service.validatedSearchSnapshot(
            query: query,
            currentBooks: validationBaseBooks
        )

        let metadataResults = await service.metadataEnrichedSearch(
            query,
            currentBooks: latestBooks,
            languageCodes: languageCodes
        )
        guard !Task.isCancelled, trimmedSearchText.discoverIdentityComponent == queryKey else { return }
        if !metadataResults.isEmpty {
            searchResults = metadataResults
            latestBooks = metadataResults
        }

        do {
            let enrichedResults = try await service.finalizeEnrichedSearch(
                query,
                currentBooks: latestBooks,
                validationSnapshot: await validationSnapshot,
                languageCodes: languageCodes
            )
            guard !Task.isCancelled, trimmedSearchText.discoverIdentityComponent == queryKey else { return }
            if latestBooks.isEmpty {
                discoverDebugLog("Discover search enriched fallback resultCount=\(enrichedResults.count) query=\(queryKey)")
            }
            searchResults = enrichedResults
            if searchResults.isEmpty {
                message = "No readable books found yet."
            }
            isSearching = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, trimmedSearchText.discoverIdentityComponent == queryKey else { return }
            if latestBooks.isEmpty {
                searchResults = []
                message = "Search is taking a rest. Try again soon."
            }
            isSearching = false
        }
    }

    func reloadPersonalization() {
        let updatedPersonalization = DiscoverPersonalization.current()
        guard updatedPersonalization != personalization else { return }
        personalization = updatedPersonalization
        lastSearchKey = ""
        shelfPaginationStates.removeAll()
        sections = Self.personalizedSections(baseSections, personalization: updatedPersonalization)
    }

    func loadMoreBooksIfNeeded(forSectionID sectionID: String) async {
        guard let section = sections.first(where: { $0.id == sectionID }) else { return }
        var state = shelfPaginationStates[sectionID] ?? DiscoverShelfPaginationState()
        let now = Date()

        guard !state.isLoading else {
            discoverDebugLog(
                "Discover pagination event=load-more-ignored shelf=\(sectionID) title=\(section.title.discoverIdentityComponent) reason=already-loading nextPage=\(state.nextPage) existing=\(section.books.count) emptyPages=\(state.emptyPageCount)"
            )
            return
        }
        guard !state.isExhausted else {
            discoverDebugLog(
                "Discover pagination event=load-more-ignored shelf=\(sectionID) title=\(section.title.discoverIdentityComponent) reason=no-more-results nextPage=\(state.nextPage) existing=\(section.books.count) emptyPages=\(state.emptyPageCount)"
            )
            return
        }
        if let lastTriggerAt = state.lastTriggerAt,
           now.timeIntervalSince(lastTriggerAt) < Self.paginationTriggerCooldown {
            let cooldownRemaining = max(0, Self.paginationTriggerCooldown - now.timeIntervalSince(lastTriggerAt))
            discoverDebugLog(
                "Discover pagination event=load-more-ignored shelf=\(sectionID) title=\(section.title.discoverIdentityComponent) reason=cooldown nextPage=\(state.nextPage) existing=\(section.books.count) emptyPages=\(state.emptyPageCount) cooldownRemaining=\(String(format: "%.2f", cooldownRemaining))"
            )
            return
        }

        let requestedPage = state.nextPage
        let requestedPageSize = Self.paginationPageSize(for: section.layout)
        state.isLoading = true
        state.lastTriggerAt = now
        shelfPaginationStates[sectionID] = state
        discoverDebugLog(
            "Discover pagination event=load-more-started shelf=\(sectionID) title=\(section.title.discoverIdentityComponent) requestedPage=\(requestedPage) requestedCursor=nil pageSize=\(requestedPageSize) existing=\(section.books.count) languageCodes=\(personalization.preferredLanguageCodes.joined(separator: ","))"
        )

        let result = await service.shelfPage(
            sectionID: section.id,
            title: section.title,
            existingBooks: section.books,
            page: requestedPage,
            pageSize: requestedPageSize,
            languageCodes: personalization.preferredLanguageCodes
        )
        guard !Task.isCancelled else {
            var cancelledState = shelfPaginationStates[sectionID] ?? DiscoverShelfPaginationState()
            cancelledState.isLoading = false
            shelfPaginationStates[sectionID] = cancelledState
            return
        }

        var updatedState = shelfPaginationStates[sectionID] ?? DiscoverShelfPaginationState()
        updatedState.isLoading = false
        updatedState.nextPage = result.nextPage
        let appendedCount = append(result.books, toSectionID: sectionID)
        updatedState.emptyPageCount = appendedCount == 0 ? updatedState.emptyPageCount + 1 : 0
        shelfPaginationStates[sectionID] = updatedState
        let finalShelfCount = sections.first(where: { $0.id == sectionID })?.books.count ?? section.books.count
        let reason = result.books.isEmpty ? "provider-empty" : appendedCount == 0 ? "duplicate-only-batch" : "ok"
        discoverDebugLog(
            "Discover pagination event=load-more-finished shelf=\(sectionID) requestedPage=\(requestedPage) nextPage=\(updatedState.nextPage) serviceReturned=\(result.books.count) uniqueAppended=\(appendedCount) finalShelfCount=\(finalShelfCount) emptyPages=\(updatedState.emptyPageCount) reason=\(reason)"
        )
    }

    func hydrateIfNeeded(_ book: DiscoverBook) async {
        let stableID = book.stableID
        guard !hydratedBookIDs.contains(stableID), !hydratingBookIDs.contains(stableID) else { return }
        guard Self.shouldHydrate(book) else {
            hydratedBookIDs.insert(stableID)
            return
        }
        hydratingBookIDs.insert(stableID)
        defer {
            hydratingBookIDs.remove(stableID)
        }

        let hydratedBook = await service.hydratedBook(book)
        guard !Task.isCancelled else { return }
        applyHydratedBook(hydratedBook, replacing: book)
        hydratedBookIDs.insert(stableID)
    }

    private static func shouldHydrate(_ book: DiscoverBook) -> Bool {
        if book.source == .openLibrary, !book.isReadable {
            return true
        }
        if book.coverURL == nil || book.hasLikelyGeneratedCover {
            return true
        }
        return false
    }

    func currentBook(matching book: DiscoverBook) -> DiscoverBook? {
        for section in sections {
            if let match = section.books.first(where: { $0.stableID == book.stableID }) {
                return match
            }
        }
        return searchResults.first { $0.stableID == book.stableID }
    }

    func actionState(for book: DiscoverBook) -> DiscoverBookActionState {
        if existingRead(for: book) != nil {
            return .added
        }
        return actionStates[book.id] ?? .idle
    }

    func perform(_ action: DiscoverAction, for book: DiscoverBook) async -> DiscoverActionOutcome {
        if let existing = existingRead(for: book) {
            let updatedExisting = await updateExistingReadIfBetter(existing, with: book)
            actionStates[book.id] = .added
            return action == .read ? .openExisting(updatedExisting) : .none
        }
        guard !(actionStates[book.id]?.isWorking ?? false) else {
            return .none
        }

        guard book.availability != nil else {
            message = "This book is not ready to read here yet."
            return .none
        }

        actionStates[book.id] = .working(action)
        message = nil

        do {
            let document = try await service.importBook(book)
            actionStates[book.id] = .added
            return .imported(document)
        } catch {
            actionStates[book.id] = .idle
            message = "Could not add that book. Try again in a moment."
            return .none
        }
    }

    func markAdded(_ book: DiscoverBook) {
        refreshSavedLookup()
        actionStates[book.id] = .added
    }

    func markImportFailed(_ book: DiscoverBook) {
        refreshSavedLookup()
        actionStates[book.id] = .idle
        message = "Could not add that book. Try again in a moment."
    }

    func refreshSavedLookup() {
        savedLookup = DiscoverSavedReadLookup(reads: store.savedReads)
    }

    func relatedBooks(for book: DiscoverBook, limit: Int = 10) -> [DiscoverBook] {
        let cacheKey = [
            book.titleAuthorFingerprint,
            "\(limit)",
            sections.map { "\($0.id):\($0.books.count)" }.joined(separator: ","),
            searchResults.map(\.stableID).joined(separator: ",")
        ].joined(separator: "|")
        if let cached = recommendationCache[cacheKey] {
            return cached
        }

        let activeSections = sections.isEmpty ? baseSections : sections
        let candidateSections = activeSections + DiscoverService.defaultCuratedSections()
        let candidates = Self.books(from: candidateSections, limit: 120) + searchResults
        let bookSubjects = Set(book.subjects.map(\.discoverIdentityComponent).filter { !$0.isEmpty })
        let bookShelfIDs = Self.sectionIDs(for: book, in: candidateSections)
        let bookVibes = Self.vibeTags(for: book, shelfIDs: bookShelfIDs)
        var seen = Set([book.titleAuthorFingerprint])

        let scored = candidates.compactMap { candidate -> (book: DiscoverBook, score: Int)? in
            guard candidate.isReadable else { return nil }
            guard candidate.titleAuthorFingerprint != book.titleAuthorFingerprint else { return nil }
            guard !seen.contains(candidate.titleAuthorFingerprint) else { return nil }
            seen.insert(candidate.titleAuthorFingerprint)

            var score = 0
            if let author = book.author?.discoverIdentityComponent,
               let candidateAuthor = candidate.author?.discoverIdentityComponent,
               !author.isEmpty,
               author == candidateAuthor {
                score += 9
            }

            let candidateShelfIDs = Self.sectionIDs(for: candidate, in: candidateSections)
            let sharedShelfCount = bookShelfIDs.intersection(candidateShelfIDs).count
            score += min(sharedShelfCount, 2) * 5

            let candidateVibes = Self.vibeTags(for: candidate, shelfIDs: candidateShelfIDs)
            score += min(bookVibes.intersection(candidateVibes).count, 3) * 3

            let candidateSubjects = Set(candidate.subjects.map(\.discoverIdentityComponent).filter { !$0.isEmpty })
            score += min(bookSubjects.intersection(candidateSubjects).count, 3) * 3
            if let category = book.primaryCategory?.discoverIdentityComponent,
               !category.isEmpty,
               category == candidate.primaryCategory?.discoverIdentityComponent {
                score += 4
            }
            if book.source == candidate.source {
                score += 2
            }
            if let candidateLanguage = candidate.languageCode,
               candidateLanguage == book.languageCode {
                score += 1
            }
            let preferenceScore = candidateShelfIDs
                .map { personalization.score(forSectionID: $0) }
                .max() ?? 0
            score += min(preferenceScore, 3)

            if let pageCount = book.pageCount,
               let candidatePageCount = candidate.pageCount,
               abs(pageCount - candidatePageCount) <= 90 {
                score += 1
            }
            return score > 0 ? (candidate, score) : nil
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.book.coverQualityScore != rhs.book.coverQualityScore {
                    return lhs.book.coverQualityScore > rhs.book.coverQualityScore
                }
                return lhs.book.title.localizedCaseInsensitiveCompare(rhs.book.title) == .orderedAscending
            }
            return lhs.score > rhs.score
        }

        let recommendations = Array(scored.map(\.book).prefix(limit))
        discoverDebugLog(
            "Discover recommendations event=related-books source=\(book.stableID) fingerprint=\(book.titleAuthorFingerprint) candidates=\(candidates.count) scored=\(scored.count) final=\(recommendations.count)"
        )
        recommendationCache[cacheKey] = recommendations
        return recommendations
    }

    private func existingRead(for book: DiscoverBook) -> SavedRead? {
        savedLookup.existingRead(for: book)
    }

    private func updateExistingReadIfBetter(_ existing: SavedRead, with book: DiscoverBook) async -> SavedRead {
        let canonicalBook = currentBook(matching: book) ?? book
        var updated = existing
        var didUpdate = false

        if updated.externalSourceID == nil {
            updated.externalSourceID = canonicalBook.externalSourceID
            didUpdate = true
        }

        let cleanTitle = canonicalBook.title.discoverCleanBookTitle
        if shouldReplaceLibraryTitle(updated.displayTitle, with: cleanTitle, originalFileName: updated.originalFileName) {
            updated.displayTitle = cleanTitle
            didUpdate = true
        }

        if let cleanAuthor = canonicalBook.author?.discoverCleanAuthorName.nilIfBlank,
           shouldReplaceLibraryAuthor(updated.author ?? updated.authorName, with: cleanAuthor) {
            updated.author = cleanAuthor
            updated.authorName = cleanAuthor
            didUpdate = true
        }

        if shouldRefreshLibraryCover(for: updated, with: canonicalBook) {
            let coverData = await service.coverImageData(for: canonicalBook)
            let readWithThumbnail = await ThumbnailGeneratorService.shared.attachThumbnail(
                to: updated,
                previewImageData: coverData
            )
            if readWithThumbnail.thumbnailPath != updated.thumbnailPath {
                updated.thumbnailPath = readWithThumbnail.thumbnailPath
                didUpdate = true
            }
        }

        guard didUpdate else { return existing }
        updated.updatedAt = Date()
        store.save(updated, durability: .immediate)
        refreshSavedLookup()
        return updated
    }

    private func shouldReplaceLibraryTitle(
        _ existingTitle: String,
        with incomingTitle: String,
        originalFileName: String?
    ) -> Bool {
        guard !incomingTitle.isEmpty else { return false }
        let existingCanonical = existingTitle.discoverCanonicalTitleComponent
        let incomingCanonical = incomingTitle.discoverCanonicalTitleComponent
        guard !incomingCanonical.isEmpty else { return false }
        if existingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let originalFileName,
           existingTitle.discoverIdentityComponent == originalFileName.discoverIdentityComponent {
            return true
        }
        return existingCanonical == incomingCanonical && incomingTitle.count < existingTitle.count
    }

    private func shouldReplaceLibraryAuthor(_ existingAuthor: String?, with incomingAuthor: String) -> Bool {
        guard !incomingAuthor.isEmpty else { return false }
        guard let existingAuthor = existingAuthor?.discoverCleanAuthorName.nilIfBlank else { return true }
        let existingCanonical = existingAuthor.discoverCanonicalAuthorComponent
        let incomingCanonical = incomingAuthor.discoverCanonicalAuthorComponent
        return existingCanonical == incomingCanonical && incomingAuthor.count < existingAuthor.count
    }

    private func shouldRefreshLibraryCover(for read: SavedRead, with book: DiscoverBook) -> Bool {
        guard book.coverURL != nil else { return false }
        if read.thumbnailPath == nil { return true }
        return book.coverQualityScore >= 40
    }

    private func applyInitialShelfSnapshotOrSeed(startedAt: Date) async {
        let fallbackSections = DiscoverService.defaultCuratedSections()

        if let cachedSections = await service.cachedCuratedSections(), !cachedSections.isEmpty {
            logInitialCache(cachedSections, fallbackSections: fallbackSections)
            baseSections = cachedSections
            sections = Self.personalizedSections(cachedSections, personalization: personalization)
            discoverDebugLog(
                "Discover initial shelf load duration=\(Self.formattedDuration(since: startedAt)) source=cache sections=\(cachedSections.count)"
            )
            return
        }

        logInitialCache(nil, fallbackSections: fallbackSections)
        if sections.isEmpty {
            baseSections = fallbackSections
            sections = Self.personalizedSections(fallbackSections, personalization: personalization)
        }
        discoverDebugLog(
            "Discover initial shelf load duration=\(Self.formattedDuration(since: startedAt)) source=seed sections=\(sections.count)"
        )
    }

    private func applyRefreshedSections(_ refreshedSections: [DiscoverSection]) {
        baseSections = refreshedSections
        let personalized = Self.personalizedSections(refreshedSections, personalization: personalization)
        sections = Self.mergedSectionsPreservingVisible(current: sections, refreshed: personalized)
    }

    private func logInitialCache(_ cachedSections: [DiscoverSection]?, fallbackSections: [DiscoverSection]) {
        let cachedByID = Dictionary((cachedSections ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for section in fallbackSections {
            if let cached = cachedByID[section.id] {
                discoverDebugLog("Discover initial cache hit shelf=\(section.id) count=\(cached.books.count)")
            } else {
                discoverDebugLog("Discover initial cache miss shelf=\(section.id) seeded=\(section.books.count)")
            }
        }
    }

    private static func personalizedSections(
        _ sections: [DiscoverSection],
        personalization: DiscoverPersonalization
    ) -> [DiscoverSection] {
        let baseSections = sections.filter { !Self.generatedSectionIDs.contains($0.id) }
        let sectionLookup = Dictionary(baseSections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scoredSections = baseSections.enumerated().sorted { lhs, rhs in
            let lhsScore = personalization.score(forSectionID: lhs.element.id)
            let rhsScore = personalization.score(forSectionID: rhs.element.id)
            if lhsScore == rhsScore {
                return lhs.offset < rhs.offset
            }
            return lhsScore > rhsScore
        }
        let preferredIDs = personalization.preferredSectionIDs
        let personalizedSourceSections = preferredIDs.compactMap { sectionLookup[$0] }
            + scoredSections.map(\.element)
        let preferredBooks = DiscoverService.curatedPresentation(
            Self.books(
                from: personalizedSourceSections,
                limit: 48
            ),
            limit: 30
        )
        let defaultFeaturedBooks = DiscoverService.curatedPresentation(
            Self.books(from: Array(baseSections.prefix(4)), limit: 28),
            limit: 10
        )
        let featuredBooks = DiscoverService.curatedPresentation(
            preferredBooks.isEmpty ? defaultFeaturedBooks : preferredBooks,
            limit: 10
        )
        let featuredFingerprints = Set(featuredBooks.map(\.titleAuthorFingerprint))

        var result: [DiscoverSection] = []
        if !featuredBooks.isEmpty {
            result.append(
                DiscoverSection(
                    id: "featured-for-you",
                    title: personalization.hasPersonalSignals ? "Featured for You" : "Start Reading Now",
                    books: Self.filledBooks(
                        from: featuredBooks,
                        fallback: defaultFeaturedBooks,
                        excluding: Set<String>(),
                        limit: 10
                    ),
                    layout: .editorialHero,
                    treatment: .framed
                )
            )
        }

        let preferenceShelfBooks = Self.filledBooks(
            from: preferredBooks,
            fallback: Self.books(from: scoredSections.map(\.element), limit: 48),
            excluding: featuredFingerprints,
            limit: 18
        )
        if personalization.hasPersonalSignals, !preferenceShelfBooks.isEmpty {
            result.append(
                DiscoverSection(
                    id: "based-on-preferences",
                    title: "Based on Your Preferences",
                    books: Self.initialWindowBooks(preferenceShelfBooks, layout: .compactGrid),
                    layout: .compactGrid,
                    treatment: .open
                )
            )
        }

        result.append(contentsOf: scoredSections.map { _, section in
            DiscoverSection(
                id: section.id,
                title: section.title,
                books: Self.initialWindowBooks(
                    DiscoverService.curatedPresentation(section.books, limit: section.books.count),
                    layout: section.layout
                ),
                layout: section.layout,
                treatment: section.treatment
            )
        })
        return result
    }

    private static let generatedSectionIDs: Set<String> = [
        "featured-for-you",
        "based-on-preferences"
    ]

    private static func books(from sections: [DiscoverSection], limit: Int) -> [DiscoverBook] {
        var seen = Set<String>()
        var books: [DiscoverBook] = []

        for section in sections {
            for book in section.books {
                guard book.isReadable else { continue }
                guard !seen.contains(book.titleAuthorFingerprint) else { continue }
                seen.insert(book.titleAuthorFingerprint)
                books.append(book)
                if books.count >= limit {
                    return books
                }
            }
        }
        return books
    }

    private static func mergedSectionsPreservingVisible(
        current: [DiscoverSection],
        refreshed: [DiscoverSection]
    ) -> [DiscoverSection] {
        guard !current.isEmpty else { return refreshed }

        let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let refreshedIDs = Set(refreshed.map(\.id))
        var result = refreshed.map { refreshedSection -> DiscoverSection in
            guard let currentSection = currentByID[refreshedSection.id] else {
                return refreshedSection
            }

            return DiscoverSection(
                id: refreshedSection.id,
                title: refreshedSection.title,
                books: mergedBooksPreservingVisible(
                    current: currentSection.books,
                    refreshed: refreshedSection.books
                ),
                layout: refreshedSection.layout,
                treatment: refreshedSection.treatment
            )
        }

        result.append(contentsOf: current.filter { !refreshedIDs.contains($0.id) })
        return result
    }

    private static func mergedBooksPreservingVisible(
        current: [DiscoverBook],
        refreshed: [DiscoverBook]
    ) -> [DiscoverBook] {
        let refreshedByStableID = Dictionary(refreshed.map { ($0.stableID, $0) }, uniquingKeysWith: { first, _ in first })
        let refreshedByFingerprint = Dictionary(refreshed.map { ($0.titleAuthorFingerprint, $0) }, uniquingKeysWith: { first, _ in first })
        var seenStableIDs = Set<String>()
        var seenFingerprints = Set<String>()
        var mergedBooks: [DiscoverBook] = []

        for book in current {
            let candidate = refreshedByStableID[book.stableID]
                ?? refreshedByFingerprint[book.titleAuthorFingerprint]
                ?? book
            guard candidate.isReadable else { continue }
            guard !seenStableIDs.contains(candidate.stableID) else { continue }
            guard !seenFingerprints.contains(candidate.titleAuthorFingerprint) else { continue }
            seenStableIDs.insert(candidate.stableID)
            seenFingerprints.insert(candidate.titleAuthorFingerprint)
            mergedBooks.append(candidate)
        }

        for book in refreshed where book.isReadable {
            guard !seenStableIDs.contains(book.stableID) else { continue }
            guard !seenFingerprints.contains(book.titleAuthorFingerprint) else { continue }
            seenStableIDs.insert(book.stableID)
            seenFingerprints.insert(book.titleAuthorFingerprint)
            mergedBooks.append(book)
        }

        return mergedBooks
    }

    private static func filledBooks(
        from primary: [DiscoverBook],
        fallback: [DiscoverBook],
        excluding excludedFingerprints: Set<String>,
        limit: Int
    ) -> [DiscoverBook] {
        var seen = excludedFingerprints
        var books: [DiscoverBook] = []

        for book in primary + fallback {
            guard book.isReadable else { continue }
            guard !seen.contains(book.titleAuthorFingerprint) else { continue }
            seen.insert(book.titleAuthorFingerprint)
            books.append(book)
            if books.count >= limit {
                break
            }
        }

        return books
    }

    @discardableResult
    private func append(_ books: [DiscoverBook], toSectionID sectionID: String) -> Int {
        guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }) else { return 0 }
        let section = sections[sectionIndex]
        var seenFingerprints = Set(section.books.map(\.titleAuthorFingerprint))
        var seenStableIDs = Set(section.books.map(\.stableID))
        var appendedBooks: [DiscoverBook] = []

        for book in books where book.isReadable {
            guard !seenFingerprints.contains(book.titleAuthorFingerprint) else { continue }
            guard !seenStableIDs.contains(book.stableID) else { continue }
            seenFingerprints.insert(book.titleAuthorFingerprint)
            seenStableIDs.insert(book.stableID)
            appendedBooks.append(book)
        }

        let readableIncomingCount = books.filter(\.isReadable).count
        let appendReason = books.isEmpty ? "provider-empty" : appendedBooks.isEmpty ? "duplicate-only-batch" : "ok"
        discoverDebugLog(
            "Discover pagination event=append-filtered shelf=\(sectionID) incoming=\(books.count) readableIncoming=\(readableIncomingCount) uniqueAppended=\(appendedBooks.count) existing=\(section.books.count) finalShelfCount=\(section.books.count + appendedBooks.count) reason=\(appendReason)"
        )

        guard !appendedBooks.isEmpty else { return 0 }

        var updatedSections = sections
        updatedSections[sectionIndex] = DiscoverSection(
            id: section.id,
            title: section.title,
            books: section.books + appendedBooks,
            layout: section.layout,
            treatment: section.treatment
        )
        sections = updatedSections
        return appendedBooks.count
    }

    private func applyHydratedBook(_ hydratedBook: DiscoverBook, replacing originalBook: DiscoverBook) {
        var didUpdate = false
        var updatedSections = sections

        for sectionIndex in updatedSections.indices {
            let section = updatedSections[sectionIndex]
            guard let bookIndex = section.books.firstIndex(where: { $0.stableID == originalBook.stableID }) else {
                continue
            }
            var updatedBooks = section.books
            updatedBooks[bookIndex] = hydratedBook
            updatedSections[sectionIndex] = DiscoverSection(
                id: section.id,
                title: section.title,
                books: updatedBooks,
                layout: section.layout,
                treatment: section.treatment
            )
            didUpdate = true
        }

        if didUpdate {
            sections = updatedSections
        }

        if let index = searchResults.firstIndex(where: { $0.stableID == originalBook.stableID }) {
            var updatedResults = searchResults
            updatedResults[index] = hydratedBook
            searchResults = updatedResults
        }
    }

    private static func initialWindowBooks(_ books: [DiscoverBook], layout: DiscoverShelfLayout) -> [DiscoverBook] {
        let limit = initialWindowLimit(for: layout)
        guard books.count > limit else { return books }
        return Array(books.prefix(limit))
    }

    private static func initialWindowLimit(for layout: DiscoverShelfLayout) -> Int {
        switch layout {
        case .classicRow:
            return 10
        case .compactGrid:
            return 12
        case .editorialHero:
            return 10
        }
    }

    private static func paginationPageSize(for layout: DiscoverShelfLayout) -> Int {
        switch layout {
        case .classicRow:
            return 10
        case .compactGrid:
            return 12
        case .editorialHero:
            return 10
        }
    }

    private static func formattedDuration(since startDate: Date) -> String {
        String(format: "%.2fs", Date().timeIntervalSince(startDate))
    }

    private static func sectionIDs(for book: DiscoverBook, in sections: [DiscoverSection]) -> Set<String> {
        Set(
            sections.compactMap { section in
                section.books.contains { $0.titleAuthorFingerprint == book.titleAuthorFingerprint } ? section.id : nil
            }
        )
    }

    private static func vibeTags(for book: DiscoverBook, shelfIDs: Set<String>) -> Set<String> {
        var tags = Set<String>()

        for shelfID in shelfIDs {
            switch shelfID {
            case "popular-classics", "fiction-literature", "public-domain-essentials":
                tags.insert("classic")
                tags.insert("literary")
            case "philosophy-focus", "ideas-productivity":
                tags.insert("reflective")
                tags.insert("ideas")
            case "short-reads", "quick-under-two-hours":
                tags.insert("short")
                tags.insert("focused")
            default:
                break
            }
        }

        for subject in book.cleanedSubjects.map(\.discoverIdentityComponent) {
            if subject.contains("philosophy") || subject.contains("ethics") {
                tags.insert("reflective")
                tags.insert("ideas")
            }
            if subject.contains("fiction") || subject.contains("literature") {
                tags.insert("literary")
            }
            if subject.contains("essay") || subject.contains("psychology") {
                tags.insert("ideas")
            }
            if subject.contains("short") {
                tags.insert("short")
            }
        }

        if book.source == .projectGutenberg {
            tags.insert("public-domain")
        }
        if let pageCount = book.pageCount, pageCount <= 180 {
            tags.insert("short")
        }

        return tags
    }
}

private struct DiscoverShelfPaginationState {
    // Initial shelves are seeded from fixed curated IDs, so load-more starts at the first provider page.
    var nextPage = 1
    var isLoading = false
    var emptyPageCount = 0
    var lastTriggerAt: Date?

    var isExhausted: Bool {
        emptyPageCount >= 4
    }
}

private struct DiscoverPersonalization: Equatable {
    let interests: Set<FocusReadReadingInterest>
    let goals: Set<FocusReadReadingGoal>
    let defaultWPM: Int
    let preferredLanguageCodes: [String]

    var hasPersonalSignals: Bool {
        !interests.isEmpty || defaultWPM >= 450 || !goals.isEmpty
    }

    var preferredSectionIDs: [String] {
        var ids: [String] = []

        func append(_ sectionIDs: [String]) {
            for sectionID in sectionIDs where !ids.contains(sectionID) {
                ids.append(sectionID)
            }
        }

        for interest in FocusReadReadingInterest.allCases where interests.contains(interest) {
            switch interest {
            case .classics:
                append(["popular-classics", "public-domain-essentials"])
            case .fiction:
                append(["fiction-literature", "popular-classics"])
            case .philosophy:
                append(["philosophy-focus", "ideas-productivity"])
            case .selfImprovement:
                append(["ideas-productivity", "philosophy-focus"])
            case .shortReads:
                append(["quick-under-two-hours", "short-reads"])
            case .science, .history:
                append(["public-domain-essentials", "ideas-productivity"])
            case .poetry:
                append(["short-reads", "public-domain-essentials"])
            case .business:
                append(["ideas-productivity", "public-domain-essentials"])
            }
        }

        for goal in FocusReadReadingGoal.allCases where goals.contains(goal) {
            switch goal {
            case .study:
                append(["short-reads", "philosophy-focus", "public-domain-essentials"])
            case .books:
                append(["popular-classics", "fiction-literature"])
            case .work:
                append(["ideas-productivity", "quick-under-two-hours"])
            case .research:
                append(["philosophy-focus", "public-domain-essentials"])
            case .languages:
                append(["popular-classics", "short-reads"])
            }
        }

        if defaultWPM >= 450 {
            append(["quick-under-two-hours", "short-reads"])
        }

        if ids.isEmpty {
            append(["popular-classics", "short-reads", "philosophy-focus"])
        }
        return ids
    }

    static func current(defaults: UserDefaults = .standard) -> DiscoverPersonalization {
        let interests = Set(
            (defaults.string(forKey: FocusReadOnboardingSettingsKey.selectedReadingInterests) ?? "")
                .split(separator: ",")
                .compactMap { FocusReadReadingInterest(rawValue: String($0)) }
        )

        let goalsRawValue = defaults.string(forKey: FocusReadOnboardingSettingsKey.selectedReadingGoals) ?? ""
        let goals = Set(
            goalsRawValue
                .split(separator: ",")
                .compactMap { FocusReadReadingGoal(rawValue: String($0)) }
        )
        let legacyGoal = FocusReadReadingGoal(
            savedRawValue: defaults.string(forKey: FocusReadOnboardingSettingsKey.selectedReadingGoal)
                ?? FocusReadReadingGoal.research.rawValue
        )
        let resolvedGoals = goals.isEmpty ? Set([legacyGoal]) : goals

        let defaultWPM = defaults.integer(forKey: ReaderBehaviorSettingsKey.defaultWPM)
        let readingPace = defaultWPM == 0 ? ReadingSession.defaultWPM : defaultWPM

        return DiscoverPersonalization(
            interests: interests,
            goals: resolvedGoals,
            defaultWPM: readingPace,
            preferredLanguageCodes: Self.preferredLanguageCodes(defaults: defaults)
        )
    }

    func score(forSectionID sectionID: String) -> Int {
        let preferredIDs = preferredSectionIDs
        guard let index = preferredIDs.firstIndex(of: sectionID) else { return 0 }
        return preferredIDs.count - index
    }

    private static func preferredLanguageCodes(defaults: UserDefaults) -> [String] {
        let selectedLanguage = AppLanguage(rawValue: defaults.string(forKey: AppLanguageStorageKey.selectedLanguage) ?? "")
            ?? .systemDefault
        let languageCode = selectedLanguage.resolvedLanguage.gutenbergLanguageCode
        if languageCode == "en" {
            return ["en"]
        }
        return [languageCode, "en"]
    }
}

private extension AppLanguage {
    var gutenbergLanguageCode: String {
        switch self {
        case .english, .systemDefault:
            return "en"
        case .french:
            return "fr"
        case .spanish:
            return "es"
        case .german:
            return "de"
        case .italian:
            return "it"
        case .portuguese:
            return "pt"
        case .chineseSimplified:
            return "zh"
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        case .arabic:
            return "ar"
        }
    }
}

private struct DiscoverSavedReadLookup {
    private let byExternalSourceID: [String: SavedRead]
    private let byFileName: [String: SavedRead]
    private let byTitleAuthor: [String: SavedRead]
    private let byTitle: [String: [SavedRead]]

    init(reads: [SavedRead]) {
        byExternalSourceID = Dictionary(
            reads.compactMap { read in
                read.externalSourceID.map { ($0, read) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        byFileName = Dictionary(
            reads.compactMap { read in
                read.originalFileName.map { ($0, read) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        byTitleAuthor = Dictionary(
            reads.map { read in
                (
                    [
                        read.displayTitle.discoverCanonicalTitleComponent,
                        (read.author ?? read.authorName ?? "").discoverCanonicalAuthorComponent
                    ].joined(separator: "|"),
                    read
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
        byTitle = Dictionary(grouping: reads, by: { read in
            read.displayTitle.discoverCanonicalTitleComponent
        }).filter { !$0.key.isEmpty }
    }

    func existingRead(for book: DiscoverBook) -> SavedRead? {
        byExternalSourceID[book.externalSourceID]
            ?? book.duplicateFileName.flatMap { byFileName[$0] }
            ?? byTitleAuthor[book.titleAuthorFingerprint]
            ?? byTitle[book.title.discoverCanonicalTitleComponent]?.first {
                authorsAreCompatible($0, book: book)
            }
    }

    private func authorsAreCompatible(_ read: SavedRead, book: DiscoverBook) -> Bool {
        let readAuthor = (read.author ?? read.authorName ?? "").discoverCanonicalAuthorComponent
        let bookAuthor = (book.author ?? "").discoverCanonicalAuthorComponent
        return readAuthor.isEmpty || bookAuthor.isEmpty || readAuthor == bookAuthor
    }
}
