import Foundation

struct DiscoverSearchCacheHit: Sendable {
    let books: [DiscoverBook]
    let isComplete: Bool
}

struct DiscoverSearchValidationSnapshot: Sendable {
    let result: OpenLibraryValidatedSearchResult
    let didComplete: Bool
}

struct DiscoverShelfPageResult: Sendable {
    let books: [DiscoverBook]
    let nextPage: Int
}

actor DiscoverService {
    private let gutenbergService: GutenbergDiscoveryService
    private let openLibraryService: OpenLibraryDiscoveryService
    private let archiveMetadataService: InternetArchiveMetadataService
    private let importService: DocumentImportService
    private let networkClient: DiscoverNetworkClient
    private let persistentMetadataCache: DiscoverPersistentBookCache
    private let shelfSnapshotCache: DiscoverShelfSnapshotCache
    private let coverImageCache: DiscoverCoverImageCache
    private var fastSearchCache: [String: [DiscoverBook]] = [:]
    private var searchCache: [String: [DiscoverBook]] = [:]
    private var curatedCache: [String: [DiscoverSection]] = [:]
    private var metadataCache: [String: [DiscoverBook]] = [:]
    private var readableCandidateCache: [String: [OpenLibraryBookCandidate]] = [:]
    private var validatedReadableCache: [String: [DiscoverBook]] = [:]
    private var coverReferenceCache: [String: URL] = [:]
    private var coverDataCache: [URL: Data] = [:]

    init(
        gutenbergService: GutenbergDiscoveryService = GutenbergDiscoveryService(),
        openLibraryService: OpenLibraryDiscoveryService = OpenLibraryDiscoveryService(),
        archiveMetadataService: InternetArchiveMetadataService = InternetArchiveMetadataService(),
        importService: DocumentImportService = DocumentImportService(),
        networkClient: DiscoverNetworkClient = .shared,
        persistentMetadataCache: DiscoverPersistentBookCache = .shared,
        shelfSnapshotCache: DiscoverShelfSnapshotCache = .shared,
        coverImageCache: DiscoverCoverImageCache = .shared,
        session: URLSession? = nil
    ) {
        self.gutenbergService = gutenbergService
        self.openLibraryService = openLibraryService
        self.archiveMetadataService = archiveMetadataService
        self.importService = importService
        self.networkClient = session.map { DiscoverNetworkClient(session: $0) } ?? networkClient
        self.persistentMetadataCache = persistentMetadataCache
        self.shelfSnapshotCache = shelfSnapshotCache
        self.coverImageCache = coverImageCache
    }

    func cachedSearchResults(for query: String, languageCodes: [String] = ["en"]) -> DiscoverSearchCacheHit? {
        let key = Self.searchCacheKey(query: query, languageCodes: languageCodes)
        if let cached = searchCache[key] {
            if !cached.isEmpty {
                DiscoverNetworkLog.cache("search hit \(key)")
                return DiscoverSearchCacheHit(books: cached, isComplete: true)
            }
            DiscoverNetworkLog.cache("search stale empty ignored \(key)")
        }
        if let cached = fastSearchCache[key] {
            if !cached.isEmpty {
                DiscoverNetworkLog.cache("fast search hit \(key)")
                return DiscoverSearchCacheHit(books: cached, isComplete: false)
            }
            DiscoverNetworkLog.cache("fast search stale empty ignored \(key)")
        }
        return nil
    }

    func fastSearch(_ query: String, languageCodes: [String] = ["en"]) async throws -> [DiscoverBook] {
        let key = Self.searchCacheKey(query: query, languageCodes: languageCodes)
        guard !key.isEmpty else { return [] }
        if let cached = searchCache[key], !cached.isEmpty {
            DiscoverNetworkLog.cache("fast search hit \(key)")
            return cached
        }
        if let cached = fastSearchCache[key], !cached.isEmpty {
            DiscoverNetworkLog.cache("fast search hit \(key)")
            return cached
        }

        let searchLimit = 30
        let trustedGutenbergMatches = Self.trustedGutenbergSearchMatches(query: query, limit: searchLimit)
        if !trustedGutenbergMatches.isEmpty {
            let merged = Self.curatedPresentation(Self.merged(trustedGutenbergMatches), limit: searchLimit)
            fastSearchCache[key] = merged
            Self.logSearch(
                query: query,
                gutenbergRawCount: trustedGutenbergMatches.count,
                gutenbergReadableCount: trustedGutenbergMatches.count,
                openLibraryRawCount: 0,
                openLibraryReadableCount: 0,
                filteredReasonCounts: [:],
                finalDisplayedCount: merged.count,
                phase: "fast-trusted-gutenberg"
            )
            return merged
        }

        let gutenbergService = self.gutenbergService
        let gutenbergResult = try await Self.withTimeout(seconds: 4) {
            try await Self.gutenbergSearchResult(
                query: query,
                languageCodes: languageCodes,
                limit: searchLimit,
                service: gutenbergService
            )
        }
        let merged = Self.curatedPresentation(Self.merged(gutenbergResult.books), limit: searchLimit)
        if !merged.isEmpty {
            fastSearchCache[key] = merged
        } else {
            fastSearchCache.removeValue(forKey: key)
        }
        Self.logSearch(
            query: query,
            gutenbergRawCount: gutenbergResult.rawCount,
            gutenbergReadableCount: gutenbergResult.books.count,
            openLibraryRawCount: 0,
            openLibraryReadableCount: 0,
            filteredReasonCounts: gutenbergResult.filteredReasonCounts,
            finalDisplayedCount: merged.count,
            phase: "fast"
        )
        return merged
    }

    private nonisolated static func trustedGutenbergSearchMatches(query: String, limit: Int) -> [DiscoverBook] {
        let normalizedQuery = query.discoverIdentityComponent
        guard !normalizedQuery.isEmpty else { return [] }

        var bestByFingerprint: [String: (book: DiscoverBook, score: Double, index: Int)] = [:]
        for (index, book) in defaultCuratedSections().flatMap(\.books).enumerated() {
            let score = trustedSearchScore(query: normalizedQuery, book: book)
            guard score >= 0.68 else { continue }
            let fingerprint = book.titleAuthorFingerprint
            if let existing = bestByFingerprint[fingerprint] {
                if score > existing.score || (score == existing.score && index < existing.index) {
                    bestByFingerprint[fingerprint] = (book, score, index)
                }
            } else {
                bestByFingerprint[fingerprint] = (book, score, index)
            }
        }

        return bestByFingerprint.values
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.index < rhs.index
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map(\.book)
    }

    private nonisolated static func trustedSearchScore(query: String, book: DiscoverBook) -> Double {
        let title = book.title.discoverCanonicalTitleComponent
        let author = book.author?.discoverCanonicalAuthorComponent ?? ""
        let searchable = [title, author, book.subjects.joined(separator: " ").discoverIdentityComponent]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !searchable.isEmpty else { return 0 }

        if title == query { return 1 }
        if title.contains(query) || query.contains(title) { return 0.96 }
        if author == query || author.contains(query) { return 0.82 }

        let queryTokens = significantSearchTokens(query)
        guard !queryTokens.isEmpty else { return 0 }
        let titleTokens = Set(significantSearchTokens(title))
        let searchableTokens = Set(significantSearchTokens(searchable))
        let sharedTitleCount = titleTokens.intersection(queryTokens).count
        let sharedSearchableCount = searchableTokens.intersection(queryTokens).count
        let queryCoverage = Double(sharedSearchableCount) / Double(queryTokens.count)
        let titleCoverage = titleTokens.isEmpty ? 0 : Double(sharedTitleCount) / Double(titleTokens.count)

        if sharedTitleCount >= min(2, queryTokens.count), queryCoverage >= 0.72 {
            return 0.9 + min(0.05, titleCoverage * 0.05)
        }
        if queryTokens.count == 1, sharedSearchableCount == 1 {
            return sharedTitleCount == 1 ? 0.88 : 0.72
        }
        if sharedSearchableCount >= min(2, queryTokens.count), queryCoverage >= 0.8 {
            return 0.76
        }
        return 0
    }

    private nonisolated static func significantSearchTokens(_ value: String) -> [String] {
        let stopWords: Set<String> = ["a", "an", "and", "in", "of", "s", "the", "to"]
        return value
            .split(separator: " ")
            .map(String.init)
            .filter { !stopWords.contains($0) }
    }

    func enrichedSearch(
        _ query: String,
        currentBooks: [DiscoverBook],
        languageCodes: [String] = ["en"]
    ) async throws -> [DiscoverBook] {
        let key = Self.searchCacheKey(query: query, languageCodes: languageCodes)
        guard !key.isEmpty else { return [] }
        if let cached = searchCache[key], !cached.isEmpty {
            DiscoverNetworkLog.cache("enriched search hit \(key)")
            return cached
        }

        async let metadataBooks = searchMetadataBooks(query: query, limit: 24, languageCodes: languageCodes)
        async let openLibraryResult = validatedSearchSnapshot(query: query, currentBooks: currentBooks, languageCodes: languageCodes)
        let resolvedMetadataBooks = await metadataBooks
        let resolvedOpenLibraryResult = await openLibraryResult
        let merged = Self.curatedPresentation(
            Self.merged(currentBooks + resolvedOpenLibraryResult.result.books + resolvedMetadataBooks),
            limit: 36
        )
        Self.logSearch(
            query: query,
            gutenbergRawCount: currentBooks.count,
            gutenbergReadableCount: currentBooks.count,
            openLibraryRawCount: resolvedOpenLibraryResult.result.rawCount,
            openLibraryReadableCount: resolvedOpenLibraryResult.result.books.count,
            filteredReasonCounts: resolvedOpenLibraryResult.result.filteredReasonCounts,
            finalDisplayedCount: merged.count,
            phase: "enriched"
        )
        if merged.isEmpty && currentBooks.isEmpty && !resolvedOpenLibraryResult.didComplete {
            throw DiscoverServiceError.unavailable
        }
        if !merged.isEmpty, resolvedOpenLibraryResult.didComplete {
            searchCache[key] = merged
        } else {
            searchCache.removeValue(forKey: key)
        }
        return merged
    }

    func metadataEnrichedSearch(
        _ query: String,
        currentBooks: [DiscoverBook],
        languageCodes: [String] = ["en"]
    ) async -> [DiscoverBook] {
        let key = Self.searchCacheKey(query: query, languageCodes: languageCodes)
        guard !key.isEmpty else { return [] }
        if let cached = searchCache[key], !cached.isEmpty {
            DiscoverNetworkLog.cache("metadata enriched search complete hit \(key)")
            return cached
        }

        let metadataBooks = await searchMetadataBooks(query: query, limit: 24, languageCodes: languageCodes)
        let merged = Self.curatedPresentation(
            Self.merged(currentBooks + metadataBooks),
            limit: 36
        )
        Self.logSearch(
            query: query,
            gutenbergRawCount: currentBooks.count,
            gutenbergReadableCount: currentBooks.count,
            openLibraryRawCount: metadataBooks.count,
            openLibraryReadableCount: 0,
            filteredReasonCounts: [:],
            finalDisplayedCount: merged.count,
            phase: "metadata"
        )
        if !merged.isEmpty {
            fastSearchCache[key] = merged
        }
        return merged
    }

    func validatedSearchSnapshot(
        query: String,
        currentBooks: [DiscoverBook],
        languageCodes: [String] = ["en"]
    ) async -> DiscoverSearchValidationSnapshot {
        let limit = Self.searchValidationLimit(currentBooks: currentBooks)
        guard limit > 0 else {
            return DiscoverSearchValidationSnapshot(
                result: OpenLibraryValidatedSearchResult(
                    books: [],
                    rawCount: 0,
                    candidateCount: 0,
                    filteredReasonCounts: [:]
                ),
                didComplete: true
            )
        }
        let snapshot = await searchValidatedReadableBooks(query: query, limit: limit, languageCodes: languageCodes)
        return DiscoverSearchValidationSnapshot(result: snapshot.result, didComplete: snapshot.didComplete)
    }

    func finalizeEnrichedSearch(
        _ query: String,
        currentBooks: [DiscoverBook],
        validationSnapshot: DiscoverSearchValidationSnapshot,
        languageCodes: [String] = ["en"]
    ) throws -> [DiscoverBook] {
        let key = Self.searchCacheKey(query: query, languageCodes: languageCodes)
        guard !key.isEmpty else { return [] }
        let merged = Self.curatedPresentation(
            Self.merged(currentBooks + validationSnapshot.result.books),
            limit: 36
        )
        Self.logSearch(
            query: query,
            gutenbergRawCount: currentBooks.count,
            gutenbergReadableCount: currentBooks.count,
            openLibraryRawCount: validationSnapshot.result.rawCount,
            openLibraryReadableCount: validationSnapshot.result.books.count,
            filteredReasonCounts: validationSnapshot.result.filteredReasonCounts,
            finalDisplayedCount: merged.count,
            phase: "validated"
        )
        if merged.isEmpty && currentBooks.isEmpty && !validationSnapshot.didComplete {
            throw DiscoverServiceError.unavailable
        }
        if !merged.isEmpty, validationSnapshot.didComplete {
            searchCache[key] = merged
        } else {
            searchCache.removeValue(forKey: key)
        }
        return merged
    }

    private func searchMetadataBooks(query: String, limit: Int, languageCodes: [String] = ["en"]) async -> [DiscoverBook] {
        do {
            return try await metadataBooks(query: query, limit: limit, languageCode: Self.primaryLanguageCode(from: languageCodes))
        } catch is CancellationError {
            return []
        } catch {
            discoverDebugLog("Discover search Open Library metadata failed query=\(query.discoverIdentityComponent)")
            return []
        }
    }

    private func searchValidatedReadableBooks(
        query: String,
        limit: Int,
        languageCodes: [String] = ["en"]
    ) async -> (result: OpenLibraryValidatedSearchResult, didComplete: Bool) {
        do {
            let openLibraryService = self.openLibraryService
            let languageCode = Self.primaryLanguageCode(from: languageCodes)
            let result = try await Self.withTimeout(seconds: 6) {
                try await openLibraryService.validatedSearchResult(query, limit: limit, languageCode: languageCode)
            }
            return (result, true)
        } catch is CancellationError {
            return (
                OpenLibraryValidatedSearchResult(
                    books: [],
                    rawCount: 0,
                    candidateCount: 0,
                    filteredReasonCounts: ["cancelled": 1]
                ),
                false
            )
        } catch {
            discoverDebugLog("Discover search Open Library validation failed query=\(query.discoverIdentityComponent)")
            return (
                OpenLibraryValidatedSearchResult(
                    books: [],
                    rawCount: 0,
                    candidateCount: 0,
                    filteredReasonCounts: ["requestFailed": 1]
                ),
                false
            )
        }
    }

    private nonisolated static func searchValidationLimit(currentBooks: [DiscoverBook]) -> Int {
        let readableCount = currentBooks.filter(\.isReadable).count
        guard readableCount > 0 else { return 24 }
        return readableCount >= 12 ? 4 : 8
    }

    private func metadataBooks(query: String, limit: Int, page: Int = 1, languageCode: String = "en") async throws -> [DiscoverBook] {
        let normalizedQuery = query.discoverIdentityComponent
        guard !normalizedQuery.isEmpty else { return [] }
        let normalizedLanguage = Self.primaryLanguageCode(from: [languageCode])
        let key = [
            normalizedQuery,
            "\(max(page, 1))",
            "\(max(limit, 1))",
            normalizedLanguage
        ].joined(separator: "|")
        if let cached = metadataCache[key] {
            DiscoverNetworkLog.cache("metadata hit \(key)")
            return cached
        }
        if let cached = await persistentMetadataCache.books(for: key) {
            metadataCache[key] = cached
            cacheCoverReferences(from: cached)
            return cached
        }

        let openLibraryService = self.openLibraryService
        let books = try await Self.withTimeout(seconds: 5) {
            try await openLibraryService.metadataSearch(query, limit: limit, page: page, languageCode: normalizedLanguage)
        }
        metadataCache[key] = books
        await persistentMetadataCache.store(books, for: key)
        cacheCoverReferences(from: books)
        return books
    }

    private func readableCandidates(query: String, limit: Int, page: Int = 1, languageCode: String = "en") async throws -> [OpenLibraryBookCandidate] {
        let normalizedQuery = query.discoverIdentityComponent
        guard !normalizedQuery.isEmpty else { return [] }
        let normalizedLanguage = Self.primaryLanguageCode(from: [languageCode])
        let key = [
            normalizedQuery,
            "\(max(page, 1))",
            "\(max(limit, 1))",
            normalizedLanguage
        ].joined(separator: "|")
        if let cached = readableCandidateCache[key] {
            DiscoverNetworkLog.cache("readable candidates hit \(key)")
            return cached
        }

        let openLibraryService = self.openLibraryService
        let candidates = try await Self.withTimeout(seconds: 5) {
            try await openLibraryService.readableCandidates(query, limit: limit, page: page, languageCode: normalizedLanguage)
        }
        readableCandidateCache[key] = candidates
        cacheCoverReferences(from: candidates.map(\.book))
        return candidates
    }

    private func validatedReadableBooks(query: String, limit: Int, page: Int = 1, languageCode: String = "en") async -> [DiscoverBook] {
        let normalizedQuery = query.discoverIdentityComponent
        guard !normalizedQuery.isEmpty else { return [] }
        let normalizedLanguage = Self.primaryLanguageCode(from: [languageCode])
        let key = [
            normalizedQuery,
            "\(max(page, 1))",
            "\(max(limit, 1))",
            normalizedLanguage
        ].joined(separator: "|")
        if let cached = validatedReadableCache[key] {
            DiscoverNetworkLog.cache("validated readable hit \(key)")
            return cached
        }

        do {
            let openLibraryService = self.openLibraryService
            let candidates = try await readableCandidates(
                query: query,
                limit: min(max(limit * 3, limit), 50),
                page: page,
                languageCode: normalizedLanguage
            )
            let books = try await Self.withTimeout(seconds: 6) {
                try await openLibraryService.validatedBooks(from: candidates, limit: limit)
            }
            let canonical = Self.merged(books)
            validatedReadableCache[key] = canonical
            cacheCoverReferences(from: canonical)
            return canonical
        } catch {
            return []
        }
    }

    func search(_ query: String) async throws -> [DiscoverBook] {
        let fastBooks = try await fastSearch(query)
        do {
            return try await enrichedSearch(query, currentBooks: fastBooks)
        } catch {
            guard !fastBooks.isEmpty else { throw error }
            return fastBooks
        }
    }

    func cachedCuratedSections() async -> [DiscoverSection]? {
        guard let sections = await shelfSnapshotCache.sections(for: Self.curatedShelfSnapshotKey) else {
            return nil
        }

        cacheCoverReferences(from: sections.flatMap(\.books))
        return sections
    }

    func curatedSections() async throws -> [DiscoverSection] {
        if let cached = curatedCache[Self.curatedCacheKey] {
            DiscoverNetworkLog.cache("curated sections hit")
            return cached
        }

        let fallbackSections = Self.defaultCuratedSections()
        async let classics = curatedBooks(
            ids: [1342, 11, 84, 1661, 2701, 345, 98, 2554],
            openLibraryQuery: "classic literature",
            fallback: fallbackSections.first { $0.id == "popular-classics" }?.books ?? []
        )
        async let shortReads = curatedBooks(
            ids: [43, 1952, 1080, 41, 46, 2542, 844, 215],
            openLibraryQuery: "short stories classic literature",
            fallback: fallbackSections.first { $0.id == "short-reads" }?.books ?? []
        )
        async let philosophy = curatedBooks(
            ids: [2680, 1497, 1656, 1600, 216, 1232, 4363, 3207],
            openLibraryQuery: "philosophy classics",
            fallback: fallbackSections.first { $0.id == "philosophy-focus" }?.books ?? []
        )
        async let fiction = curatedBooks(
            ids: [158, 1260, 174, 36, 345, 74, 76, 55, 768, 1400],
            openLibraryQuery: "classic fiction literature",
            fallback: fallbackSections.first { $0.id == "fiction-literature" }?.books ?? []
        )
        async let essays = curatedBooks(
            ids: [205, 71, 132, 20203, 2944, 4507, 2274, 935, 16317, 10715],
            openLibraryQuery: "essays philosophy self improvement",
            fallback: fallbackSections.first { $0.id == "ideas-productivity" }?.books ?? []
        )
        async let quickReads = curatedBooks(
            ids: [1952, 1080, 844, 2542, 43, 41, 46, 216],
            openLibraryQuery: "short essays classic stories",
            fallback: fallbackSections.first { $0.id == "quick-under-two-hours" }?.books ?? []
        )
        async let essentials = curatedBooks(
            ids: [1342, 11, 84, 1661, 2701, 98, 2554, 1400, 76, 74],
            openLibraryQuery: "public domain classic books",
            fallback: fallbackSections.first { $0.id == "public-domain-essentials" }?.books ?? []
        )

        let sections = await [
            DiscoverSection(id: "popular-classics", title: "Popular Classics", books: classics, layout: .classicRow, treatment: .open),
            DiscoverSection(id: "short-reads", title: "Short Reads", books: shortReads, layout: .compactGrid, treatment: .framed),
            DiscoverSection(id: "philosophy-focus", title: "Philosophy & Focus", books: philosophy, layout: .compactGrid, treatment: .open),
            DiscoverSection(id: "fiction-literature", title: "Fiction & Literature", books: fiction, layout: .editorialHero, treatment: .framed),
            DiscoverSection(id: "quick-under-two-hours", title: "Quick Reads Under 2 Hours", books: quickReads, layout: .compactGrid, treatment: .open),
            DiscoverSection(id: "ideas-productivity", title: "Ideas & Productivity", books: essays, layout: .compactGrid, treatment: .framed),
            DiscoverSection(id: "public-domain-essentials", title: "Public Domain Essentials", books: essentials, layout: .classicRow, treatment: .open)
        ]
        .filter { !$0.books.isEmpty }

        let resolvedSections = sections.isEmpty ? Self.defaultCuratedSections() : sections

        curatedCache[Self.curatedCacheKey] = resolvedSections
        await shelfSnapshotCache.store(resolvedSections, for: Self.curatedShelfSnapshotKey)
        discoverDebugLog("Loaded \(resolvedSections.count) Discover curated sections")
        return resolvedSections
    }

    func shelfPage(
        sectionID: String,
        title: String,
        existingBooks: [DiscoverBook],
        page: Int,
        pageSize: Int,
        languageCodes: [String] = ["en"]
    ) async -> DiscoverShelfPageResult {
        do {
            return try await networkClient.withShelfPaginationSlot(shelfID: sectionID) {
                await self.resolvedShelfPage(
                    sectionID: sectionID,
                    title: title,
                    existingBooks: existingBooks,
                    page: page,
                    pageSize: pageSize,
                    languageCodes: languageCodes
                )
            }
        } catch {
            discoverDebugLog("Discover shelf pagination skipped for \(sectionID)")
            return DiscoverShelfPageResult(books: [], nextPage: max(page, 1))
        }
    }

    private func resolvedShelfPage(
        sectionID: String,
        title: String,
        existingBooks: [DiscoverBook],
        page: Int,
        pageSize: Int,
        languageCodes: [String] = ["en"]
    ) async -> DiscoverShelfPageResult {
        let descriptor = Self.shelfDescriptor(sectionID: sectionID, title: title)
        let normalizedLanguages = Self.normalizedLanguageCodes(languageCodes)
        let existingFingerprints = Set(existingBooks.map(\.titleAuthorFingerprint))
        let existingStableIDs = Set(existingBooks.map(\.stableID))
        let requestedPageSize = max(pageSize, 1)
        var nextPage = max(page, 1)
        var resolvedBooks: [DiscoverBook] = []
        var seenFingerprints = existingFingerprints
        var seenStableIDs = existingStableIDs

        @discardableResult
        func appendUniqueReadableBooks(_ books: [DiscoverBook]) -> Int {
            let initialCount = resolvedBooks.count
            for book in books {
                guard book.isReadable else { continue }
                guard !seenStableIDs.contains(book.stableID) else { continue }
                guard !seenFingerprints.contains(book.titleAuthorFingerprint) else { continue }
                seenStableIDs.insert(book.stableID)
                seenFingerprints.insert(book.titleAuthorFingerprint)
                resolvedBooks.append(book)
                if resolvedBooks.count >= requestedPageSize {
                    break
                }
            }
            return resolvedBooks.count - initialCount
        }

        while resolvedBooks.count < requestedPageSize && nextPage < max(page, 1) + 3 {
            let sourcePage = descriptor.sourcePage(forAbsolutePage: nextPage)
            let queryPage = descriptor.queryPage(forAbsolutePage: nextPage)
            let languageCode = normalizedLanguages[(nextPage - 1) % normalizedLanguages.count]
            let fetchLimit = max(requestedPageSize * 2, 20)
            discoverDebugLog(
                "Discover pagination event=shelf-page-iteration shelf=\(sectionID) title=\(title.discoverIdentityComponent) requestedPage=\(page) absolutePage=\(nextPage) pageSize=\(requestedPageSize) existing=\(existingBooks.count) sourcePage=\(sourcePage.page) query=\(queryPage.query.discoverIdentityComponent) queryPage=\(queryPage.page) language=\(languageCode) fetchLimit=\(fetchLimit)"
            )
            let fetchedGutenbergBooks = await shelfGutenbergBooks(
                sourcePage.source,
                page: sourcePage.page,
                limit: fetchLimit,
                languageCode: languageCode
            )
            let curated = Self.curatedPresentation(Self.merged(fetchedGutenbergBooks), limit: fetchLimit)
            let gutenbergDelta = appendUniqueReadableBooks(curated)
            discoverDebugLog(
                "Discover pagination event=provider-result provider=gutenberg shelf=\(sectionID) absolutePage=\(nextPage) source=\(sourcePage.source.logLabel) requestedPage=\(sourcePage.page) requestedCursor=nil fetchedRaw=unavailable readable=\(fetchedGutenbergBooks.filter(\.isReadable).count) presentation=\(curated.count) uniqueAppended=\(gutenbergDelta) runningShelfPageCount=\(resolvedBooks.count) reason=\(fetchedGutenbergBooks.isEmpty ? "provider-empty" : gutenbergDelta == 0 ? "duplicate-only-batch" : "ok")"
            )

            let fetchedMetadataBooks: [DiscoverBook]
            if resolvedBooks.count < requestedPageSize {
                let metadataQuery = descriptor.metadataQuery(forAbsolutePage: nextPage)
                fetchedMetadataBooks = await shelfMetadataBooks(
                    metadataQuery.query,
                    page: metadataQuery.page,
                    limit: 32,
                    languageCode: languageCode
                )
                let enrichedGutenbergBooks = Self.curatedPresentation(
                    Self.merged(fetchedGutenbergBooks + fetchedMetadataBooks),
                    limit: fetchLimit
                )
                let metadataDelta = appendUniqueReadableBooks(enrichedGutenbergBooks)
                discoverDebugLog(
                    "Discover pagination event=provider-result provider=openlibrary-metadata shelf=\(sectionID) query=\(metadataQuery.query.discoverIdentityComponent) requestedPage=\(metadataQuery.page) requestedCursor=nil fetchedRaw=unavailable readable=\(fetchedMetadataBooks.filter(\.isReadable).count) presentation=\(enrichedGutenbergBooks.count) uniqueAppended=\(metadataDelta) runningShelfPageCount=\(resolvedBooks.count) reason=\(fetchedMetadataBooks.isEmpty ? "provider-empty" : metadataDelta == 0 ? "duplicate-only-batch" : "ok")"
                )
            } else {
                fetchedMetadataBooks = []
            }

            if resolvedBooks.count < requestedPageSize {
                let validatedBooks = await validatedReadableBooks(
                    query: queryPage.query,
                    limit: max(6, requestedPageSize - resolvedBooks.count + 4),
                    page: queryPage.page,
                    languageCode: languageCode
                )
                let enrichedValidatedBooks = Self.curatedPresentation(
                    Self.merged(validatedBooks + fetchedMetadataBooks),
                    limit: requestedPageSize
                )
                let validatedDelta = appendUniqueReadableBooks(enrichedValidatedBooks)
                discoverDebugLog(
                    "Discover pagination event=provider-result provider=openlibrary-validated shelf=\(sectionID) query=\(queryPage.query.discoverIdentityComponent) requestedPage=\(queryPage.page) requestedCursor=nil fetchedRaw=unavailable readable=\(validatedBooks.count) presentation=\(enrichedValidatedBooks.count) uniqueAppended=\(validatedDelta) runningShelfPageCount=\(resolvedBooks.count) reason=\(validatedBooks.isEmpty ? "provider-empty" : validatedDelta == 0 ? "duplicate-only-batch" : "ok")"
                )
            }

            nextPage += 1
        }

        let result = DiscoverShelfPageResult(books: resolvedBooks, nextPage: nextPage)
        discoverDebugLog(
            "Discover pagination event=shelf-page-finished shelf=\(sectionID) requestedPage=\(page) nextPage=\(result.nextPage) pageSize=\(requestedPageSize) returned=\(result.books.count) existing=\(existingBooks.count) finalCandidateCount=\(existingBooks.count + result.books.count)"
        )
        return result
    }

    func hydratedBook(_ book: DiscoverBook) async -> DiscoverBook {
        var resolvedBook = book.withCanonicalMetadata()
        if let cachedCoverURL = coverReferenceCache[resolvedBook.titleAuthorFingerprint] {
            resolvedBook = resolvedBook.withCoverURL(cachedCoverURL)
        }

        let query = Self.metadataQuery(for: resolvedBook)
        if let candidateMetadata = try? await metadataBooks(query: query, limit: 12),
           let metadata = Self.bestMetadataMatch(for: resolvedBook, in: candidateMetadata) {
            resolvedBook = resolvedBook.enrichedWithOpenLibraryMetadata(metadata)
        }

        if resolvedBook.source == .openLibrary, !resolvedBook.isReadable {
            let validatedBooks = await validatedReadableBooks(
                query: query,
                limit: 8,
                languageCode: Self.openLibraryPreferenceLanguageCode(from: resolvedBook.languageCode)
            )
            if let validatedBook = Self.bestMetadataMatch(for: resolvedBook, in: validatedBooks),
               let availability = validatedBook.availability {
                resolvedBook = resolvedBook
                    .enrichedWithOpenLibraryMetadata(validatedBook)
                    .withAvailability(availability)
            }
        }

        cacheCoverReferences(from: [resolvedBook])
        return resolvedBook
    }

    nonisolated static func defaultCuratedSections() -> [DiscoverSection] {
        GutenbergDiscoveryService.fallbackCuratedSections()
    }

    private nonisolated static func shelfDescriptor(sectionID: String, title: String) -> DiscoverShelfDescriptor {
        switch sectionID {
        case "popular-classics":
            return DiscoverShelfDescriptor(
                gutenbergSources: [.topic("classic literature"), .search("classic literature"), .topic("fiction")],
                readableQueries: ["classic literature", "public domain classics", "literary classics"],
                metadataQueries: ["classic literature", "public domain classics"]
            )
        case "short-reads", "quick-under-two-hours":
            return DiscoverShelfDescriptor(
                gutenbergSources: [.topic("short stories"), .search("short stories"), .topic("essays")],
                readableQueries: ["short stories", "short essays", "classic short reads"],
                metadataQueries: ["short stories classic literature", "short essays"]
            )
        case "philosophy-focus":
            return DiscoverShelfDescriptor(
                gutenbergSources: [.topic("philosophy"), .search("philosophy classics"), .topic("ethics")],
                readableQueries: ["philosophy classics", "ethics philosophy", "public domain philosophy"],
                metadataQueries: ["philosophy classics", "ethics philosophy"]
            )
        case "fiction-literature":
            return DiscoverShelfDescriptor(
                gutenbergSources: [.topic("fiction"), .search("classic fiction literature"), .topic("literature")],
                readableQueries: ["classic fiction literature", "literary fiction classics", "public domain novels"],
                metadataQueries: ["classic fiction literature", "literary fiction classics"]
            )
        case "ideas-productivity":
            return DiscoverShelfDescriptor(
                gutenbergSources: [.topic("essays"), .search("essays philosophy self improvement"), .topic("psychology")],
                readableQueries: ["essays philosophy", "self improvement classics", "psychology essays"],
                metadataQueries: ["essays philosophy self improvement", "psychology essays"]
            )
        case "public-domain-essentials":
            return DiscoverShelfDescriptor(
                gutenbergSources: [.topic("fiction"), .topic("history"), .search("public domain classic books")],
                readableQueries: ["public domain classic books", "classic literature", "history classics"],
                metadataQueries: ["public domain classic books", "classic literature"]
            )
        case "based-on-preferences":
            return DiscoverShelfDescriptor(
                gutenbergSources: [.topic("philosophy"), .topic("short stories"), .topic("fiction"), .topic("essays")],
                readableQueries: ["classic literature philosophy essays", "short stories classics", "public domain essays"],
                metadataQueries: ["classic literature philosophy essays", "public domain essays"]
            )
        case "featured-for-you":
            return DiscoverShelfDescriptor(
                gutenbergSources: [.topic("fiction"), .topic("philosophy"), .topic("short stories")],
                readableQueries: ["popular public domain classics", "classic literature", "readable classics"],
                metadataQueries: ["popular public domain classics", "classic literature"]
            )
        default:
            let query = title.discoverIdentityComponent.isEmpty ? "classic literature" : title
            return DiscoverShelfDescriptor(
                gutenbergSources: [.search(query), .topic("fiction"), .topic("essays")],
                readableQueries: [query, "classic literature"],
                metadataQueries: [query, "classic literature"]
            )
        }
    }

    private func curatedBooks(
        ids: [Int],
        openLibraryQuery: String,
        fallback: [DiscoverBook]
    ) async -> [DiscoverBook] {
        let shelfLimit = max(ids.count, fallback.count, 8)
        do {
            let gutenbergService = self.gutenbergService
            let books = try await gutenbergService.books(ids: ids)
            let curated = Self.curatedPresentation(Self.merged(books), limit: shelfLimit)
            return curated.isEmpty ? Self.curatedPresentation(fallback, limit: shelfLimit) : curated
        } catch {
            discoverDebugLog("Discover curated shelf fallback used for \(openLibraryQuery)")
            return Self.curatedPresentation(fallback, limit: shelfLimit)
        }
    }

    private func shelfGutenbergBooks(
        _ source: DiscoverShelfDescriptor.GutenbergSource,
        page: Int,
        limit: Int,
        languageCode: String
    ) async -> [DiscoverBook] {
        do {
            let gutenbergService = self.gutenbergService
            return try await Self.withTimeout(seconds: 5) {
                switch source {
                case .topic(let topic):
                    return try await gutenbergService.curated(
                        topic: topic,
                        limit: limit,
                        languageCode: languageCode,
                        page: page
                    )
                case .search(let query):
                    return try await gutenbergService.search(
                        query,
                        limit: limit,
                        languageCode: languageCode,
                        page: page
                    )
                }
            }
        } catch {
            discoverDebugLog("Discover Gutenberg shelf request failed for page \(page)")
            return []
        }
    }

    private func shelfMetadataBooks(_ query: String, page: Int, limit: Int, languageCode: String) async -> [DiscoverBook] {
        do {
            return try await metadataBooks(query: query, limit: limit, page: page, languageCode: languageCode)
        } catch {
            discoverDebugLog("Discover metadata shelf request failed for \(query) page \(page)")
            return []
        }
    }

    private func cacheCoverReferences(from books: [DiscoverBook]) {
        for book in books {
            guard let coverURL = book.coverURL else { continue }
            let key = book.titleAuthorFingerprint
            if let existing = coverReferenceCache[key] {
                let existingBook = book.withCoverURL(existing)
                guard book.coverQualityScore > existingBook.coverQualityScore else { continue }
            }
            coverReferenceCache[key] = coverURL
        }
    }

    private nonisolated static func metadataQuery(for book: DiscoverBook) -> String {
        [
            book.title.discoverCleanBookTitle,
            book.author?.discoverCleanAuthorName ?? ""
        ]
        .joined(separator: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func searchCacheKey(query: String, languageCodes: [String]) -> String {
        let normalizedQuery = query.discoverIdentityComponent
        guard !normalizedQuery.isEmpty else { return "" }
        let normalizedLanguages = normalizedLanguageCodes(languageCodes).joined(separator: ",")
        return [normalizedQuery, normalizedLanguages].joined(separator: "|")
    }

    private static let curatedCacheKey = "default"
    private static let curatedShelfSnapshotKey = "default"

    private static func normalizedLanguageCodes(_ languageCodes: [String]) -> [String] {
        let normalized = languageCodes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let unique = normalized.reduce(into: [String]()) { result, code in
            guard !result.contains(code) else { return }
            result.append(code)
        }
        return unique.isEmpty ? ["en"] : unique
    }

    private static func primaryLanguageCode(from languageCodes: [String]) -> String {
        normalizedLanguageCodes(languageCodes).first ?? "en"
    }

    private static func openLibraryPreferenceLanguageCode(from languageCode: String?) -> String {
        let normalized = languageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "-")
            .first
            .map(String.init) ?? ""
        switch normalized {
        case "ara": return "ar"
        case "chi", "zho": return "zh"
        case "fre", "fra": return "fr"
        case "ger", "deu": return "de"
        case "jpn": return "ja"
        case "kor": return "ko"
        case "por": return "pt"
        case "spa": return "es"
        case "eng": return "en"
        case "ita": return "it"
        default:
            return normalized.isEmpty ? "en" : normalized
        }
    }

    private nonisolated static func logSearch(
        query: String,
        gutenbergRawCount: Int,
        gutenbergReadableCount: Int,
        openLibraryRawCount: Int,
        openLibraryReadableCount: Int,
        filteredReasonCounts: [String: Int],
        finalDisplayedCount: Int,
        phase: String
    ) {
        let reasons = filteredReasonCounts
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        discoverDebugLog(
            "Discover search phase=\(phase) query=\(query.discoverIdentityComponent) gutenbergRaw=\(gutenbergRawCount) gutenbergReadable=\(gutenbergReadableCount) openLibraryRaw=\(openLibraryRawCount) openLibraryReadable=\(openLibraryReadableCount) filtered={\(reasons)} final=\(finalDisplayedCount)"
        )
    }

    private static func gutenbergBooks(
        query: String,
        languageCodes: [String],
        limit: Int,
        service: GutenbergDiscoveryService
    ) async throws -> [DiscoverBook] {
        let result = try await gutenbergSearchResult(
            query: query,
            languageCodes: languageCodes,
            limit: limit,
            service: service
        )
        return result.books
    }

    private static func gutenbergSearchResult(
        query: String,
        languageCodes: [String],
        limit: Int,
        service: GutenbergDiscoveryService
    ) async throws -> GutenbergSearchResult {
        var books: [DiscoverBook] = []
        var rawCount = 0
        var filteredReasonCounts: [String: Int] = [:]
        var lastError: Error?

        for languageCode in normalizedLanguageCodes(languageCodes) {
            do {
                let result = try await service.searchResult(query, limit: limit, languageCode: languageCode)
                books.append(contentsOf: result.books)
                rawCount += result.rawCount
                filteredReasonCounts.merge(result.filteredReasonCounts) { $0 + $1 }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }

            books = curatedPresentation(merged(books), limit: limit)
            if books.count >= limit {
                return GutenbergSearchResult(
                    books: Array(books.prefix(limit)),
                    rawCount: rawCount,
                    filteredReasonCounts: filteredReasonCounts
                )
            }
        }

        if books.isEmpty, let lastError {
            throw lastError
        }
        return GutenbergSearchResult(
            books: Array(books.prefix(limit)),
            rawCount: rawCount,
            filteredReasonCounts: filteredReasonCounts
        )
    }

    func importBook(_ book: DiscoverBook) async throws -> ImportedDocument {
        guard let availability = book.availability else {
            throw DiscoverServiceError.noReadableFormat
        }

        let fileURL = try await downloadedFileURL(for: availability)
        let document = try await importService.extractText(
            from: ImportedFile(
                localURL: fileURL,
                fileName: availability.localFileName,
                fileExtension: availability.preferredFormat.fileExtension
            ),
            smartCleanupMode: .off,
            progress: { _ in }
        )
        let coverData = try? await coverData(for: book.coverURL)

        return document.withDiscoverMetadata(
            from: book,
            coverData: coverData
        )
    }

    func coverImageData(for book: DiscoverBook) async -> Data? {
        if let coverData = try? await coverData(for: book.coverURL) {
            return coverData
        }
        if let cachedCoverURL = coverReferenceCache[book.titleAuthorFingerprint],
           cachedCoverURL != book.coverURL,
           let coverData = try? await coverData(for: cachedCoverURL) {
            return coverData
        }
        return nil
    }

    private func downloadedFileURL(for availability: DiscoverAvailability) async throws -> URL {
        let remoteURL: URL
        switch availability.location {
        case .direct(let url):
            remoteURL = url
        case .internetArchive(let identifier):
            remoteURL = try await archiveMetadataService.downloadableURL(
                for: identifier,
                format: availability.preferredFormat
            )
        }

        let temporaryURL = try await networkClient.download(
            for: URLRequest(url: remoteURL),
            kind: .download,
            timeout: 30
        )

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(availability.preferredFormat.fileExtension)
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func coverData(for url: URL?) async throws -> Data? {
        guard let url else { return nil }
        if let cached = coverDataCache[url] {
            DiscoverNetworkLog.cache("import cover hit \(url.absoluteString)")
            return cached
        }
        let data = await coverImageCache.imageData(for: url)
        if let data {
            coverDataCache[url] = data
        }
        return data
    }

    nonisolated static func merged(_ books: [DiscoverBook]) -> [DiscoverBook] {
        let metadataBooks = books.filter { $0.source == .openLibrary }
        let readableBooks = books.filter(\.isReadable)

        var bestByFingerprint: [String: DiscoverBook] = [:]
        var order: [String] = []
        for book in readableBooks {
            let book = canonicalBook(from: book, metadataBooks: metadataBooks)
            let fingerprint = book.titleAuthorFingerprint
            if let existing = bestByFingerprint[fingerprint] {
                if isBetterStorefrontCandidate(book, than: existing) {
                    bestByFingerprint[fingerprint] = book
                }
            } else {
                bestByFingerprint[fingerprint] = book
                order.append(fingerprint)
            }
        }
        return order.compactMap { bestByFingerprint[$0] }
    }

    private nonisolated static func canonicalBook(
        from readableBook: DiscoverBook,
        metadataBooks: [DiscoverBook]
    ) -> DiscoverBook {
        let cleanedBook = readableBook.withCanonicalMetadata()
        guard readableBook.source == .projectGutenberg,
              let metadata = bestMetadataMatch(for: cleanedBook, in: metadataBooks) else {
            return cleanedBook
        }
        return cleanedBook.enrichedWithOpenLibraryMetadata(metadata)
    }

    private nonisolated static func bestMetadataMatch(
        for book: DiscoverBook,
        in metadataBooks: [DiscoverBook]
    ) -> DiscoverBook? {
        metadataBooks
            .compactMap { metadata -> (book: DiscoverBook, confidence: Double, quality: Int)? in
                guard let confidence = metadataMatchConfidence(book: book, metadata: metadata),
                      confidence >= 0.86 else {
                    return nil
                }
                return (metadata, confidence, metadataQualityScore(metadata))
            }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.quality > rhs.quality
                }
                return lhs.confidence > rhs.confidence
            }
            .first?
            .book
    }

    private nonisolated static func metadataMatchConfidence(
        book: DiscoverBook,
        metadata: DiscoverBook
    ) -> Double? {
        let titleScore = tokenSimilarity(
            book.title.discoverCanonicalTitleComponent,
            metadata.title.discoverCanonicalTitleComponent
        )
        guard titleScore >= 0.86 else { return nil }

        let bookAuthor = book.author?.discoverCanonicalAuthorComponent ?? ""
        let metadataAuthor = metadata.author?.discoverCanonicalAuthorComponent ?? ""
        if book.source == .projectGutenberg,
           bookAuthor.isEmpty,
           !metadataAuthor.isEmpty,
           metadata.coverURL != nil,
           titleScore >= 0.96 {
            return titleScore
        }
        guard !bookAuthor.isEmpty, !metadataAuthor.isEmpty else { return nil }

        let authorScore = authorSimilarity(bookAuthor, metadataAuthor)
        guard authorScore >= 0.82 else { return nil }

        return titleScore * 0.62 + authorScore * 0.38
    }

    private nonisolated static func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhs = strippedLeadingArticle(lhs)
        let rhs = strippedLeadingArticle(rhs)
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }

        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let sharedCount = lhsTokens.intersection(rhsTokens).count
        return Double(sharedCount) / Double(max(lhsTokens.count, rhsTokens.count))
    }

    private nonisolated static func authorSimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        if lhs.contains(rhs) || rhs.contains(lhs) { return 0.92 }

        let lhsTokens = lhs.split(separator: " ").map(String.init)
        let rhsTokens = rhs.split(separator: " ").map(String.init)
        guard let lhsLast = lhsTokens.last, let rhsLast = rhsTokens.last, lhsLast == rhsLast else {
            return 0
        }
        if lhsTokens.first?.first == rhsTokens.first?.first {
            return 0.84
        }
        return 0
    }

    private nonisolated static func strippedLeadingArticle(_ value: String) -> String {
        value.replacingOccurrences(of: "^(the|a|an)\\s+", with: "", options: .regularExpression)
    }

    private nonisolated static func metadataQualityScore(_ book: DiscoverBook) -> Int {
        var score = 0
        if book.coverURL != nil { score += 8 }
        if book.description?.isEmpty == false { score += 5 }
        if book.firstPublishYear != nil { score += 3 }
        score += min(book.subjects.count, 6)
        score += min(book.editionCount ?? 0, 200) / 50
        score += min(book.ratingCount ?? 0, 1000) / 250
        return score
    }

    nonisolated static func curatedPresentation(_ books: [DiscoverBook], limit: Int) -> [DiscoverBook] {
        guard limit > 0 else { return [] }
        let ranked = books.enumerated()
            .filter { $0.element.isReadable }
            .sorted { lhs, rhs in
                let lhsPresentationScore = presentationRankingScore(for: lhs.element, originalIndex: lhs.offset)
                let rhsPresentationScore = presentationRankingScore(for: rhs.element, originalIndex: rhs.offset)
                if lhsPresentationScore != rhsPresentationScore {
                    return lhsPresentationScore > rhsPresentationScore
                }
                if lhs.element.storefrontScore != rhs.element.storefrontScore {
                    return lhs.element.storefrontScore > rhs.element.storefrontScore
                }
                let lhsPopularity = lhs.element.ratingCount ?? lhs.element.downloadCount ?? lhs.element.editionCount ?? 0
                let rhsPopularity = rhs.element.ratingCount ?? rhs.element.downloadCount ?? rhs.element.editionCount ?? 0
                if lhsPopularity == rhsPopularity {
                    return lhs.element.title.localizedCaseInsensitiveCompare(rhs.element.title) == .orderedAscending
                }
                return lhsPopularity > rhsPopularity
            }
            .map(\.element)

        var remaining = ranked
        var result: [DiscoverBook] = []
        var previousCluster: String?

        while !remaining.isEmpty && result.count < limit {
            let selectedIndex = remaining.firstIndex { candidate in
                previousCluster == nil || candidate.visualClusterKey != previousCluster
            } ?? remaining.startIndex
            let selected = remaining.remove(at: selectedIndex)
            result.append(selected)
            previousCluster = selected.visualClusterKey
        }

        return result
    }

    private nonisolated static func presentationRankingScore(
        for book: DiscoverBook,
        originalIndex: Int
    ) -> Int {
        max(0, 10_000 - originalIndex * 12) + book.coverPresentationBoost
    }

    private nonisolated static func isBetterStorefrontCandidate(
        _ candidate: DiscoverBook,
        than existing: DiscoverBook
    ) -> Bool {
        if candidate.source == .projectGutenberg, existing.source != .projectGutenberg {
            return true
        }
        if existing.source == .projectGutenberg, candidate.source != .projectGutenberg {
            return false
        }
        if candidate.storefrontScore != existing.storefrontScore {
            return candidate.storefrontScore > existing.storefrontScore
        }
        if candidate.availability?.preferredFormat != existing.availability?.preferredFormat {
            let candidatePriority = candidate.availability?.preferredFormat.priority ?? Int.max
            let existingPriority = existing.availability?.preferredFormat.priority ?? Int.max
            return candidatePriority < existingPriority
        }
        return candidate.source == .projectGutenberg && existing.source != .projectGutenberg
    }

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw DiscoverServiceError.unavailable
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

private struct DiscoverShelfDescriptor: Sendable {
    enum GutenbergSource: Sendable {
        case topic(String)
        case search(String)

        var logLabel: String {
            switch self {
            case .topic(let topic):
                return "topic:\(topic.discoverIdentityComponent)"
            case .search(let query):
                return "search:\(query.discoverIdentityComponent)"
            }
        }
    }

    let gutenbergSources: [GutenbergSource]
    let readableQueries: [String]
    let metadataQueries: [String]

    func sourcePage(forAbsolutePage page: Int) -> (source: GutenbergSource, page: Int) {
        let page = max(page, 1)
        let sources = gutenbergSources.isEmpty ? [.search("classic literature")] : gutenbergSources
        let sourceIndex = (page - 1) % sources.count
        return (sources[sourceIndex], ((page - 1) / sources.count) + 1)
    }

    func queryPage(forAbsolutePage page: Int) -> (query: String, page: Int) {
        pagedValue(readableQueries, fallback: "classic literature", absolutePage: page)
    }

    func metadataQuery(forAbsolutePage page: Int) -> (query: String, page: Int) {
        pagedValue(metadataQueries, fallback: readableQueries.first ?? "classic literature", absolutePage: page)
    }

    private func pagedValue(
        _ values: [String],
        fallback: String,
        absolutePage: Int
    ) -> (query: String, page: Int) {
        let page = max(absolutePage, 1)
        let values = values.isEmpty ? [fallback] : values
        let index = (page - 1) % values.count
        return (values[index], ((page - 1) / values.count) + 1)
    }
}

extension ImportedDocument {
    func withDiscoverMetadata(
        from book: DiscoverBook,
        coverData: Data?
    ) -> ImportedDocument {
        let cleanTitle = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanTitle.isEmpty ? displayTitle : cleanTitle
        let resolvedAuthor = book.author ?? author
        return ImportedDocument(
            fileName: fileName,
            displayTitle: resolvedTitle,
            author: resolvedAuthor,
            externalSourceID: book.externalSourceID,
            sourceType: sourceType,
            languageCode: languageCode?.nilIfSuspiciousMetadataValue ?? book.languageCode?.nilIfSuspiciousMetadataValue,
            sections: sections,
            previewImageData: coverData ?? previewImageData,
            cleanupMode: cleanupMode,
            cleanupChunks: cleanupChunks
        )
    }
}

private extension DiscoverBook {
    func withCanonicalMetadata() -> DiscoverBook {
        let cleanTitle = title.discoverCleanBookTitle
        let cleanAuthor = author?.discoverCleanAuthorName.nilIfBlank
        return DiscoverBook(
            id: id,
            source: source,
            sourceID: sourceID,
            title: cleanTitle.isEmpty ? title : cleanTitle,
            author: cleanAuthor,
            coverURL: coverURL,
            subjects: subjects,
            availability: availability,
            webURL: webURL,
            languageCode: languageCode?.nilIfSuspiciousMetadataValue,
            pageCount: pageCount,
            description: description?.nilIfSuspiciousDescription,
            firstPublishYear: firstPublishYear,
            downloadCount: downloadCount,
            ratingAverage: ratingAverage,
            ratingCount: ratingCount,
            editionCount: editionCount
        )
    }

    func enrichedWithOpenLibraryMetadata(_ metadata: DiscoverBook) -> DiscoverBook {
        let metadata = metadata.withCanonicalMetadata()
        return DiscoverBook(
            id: id,
            source: source,
            sourceID: sourceID,
            title: Self.bestTitle(primary: self, metadata: metadata),
            author: Self.bestAuthor(primary: self, metadata: metadata),
            coverURL: Self.bestCoverURL(primary: self, metadata: metadata),
            subjects: Self.bestSubjects(primary: self, metadata: metadata),
            availability: availability,
            webURL: webURL,
            languageCode: languageCode?.nilIfSuspiciousMetadataValue ?? metadata.languageCode?.nilIfSuspiciousMetadataValue,
            pageCount: pageCount ?? metadata.pageCount,
            description: Self.bestDescription(primary: self, metadata: metadata),
            firstPublishYear: Self.bestPublishYear(primary: self, metadata: metadata),
            downloadCount: downloadCount,
            ratingAverage: ratingAverage ?? metadata.ratingAverage,
            ratingCount: ratingCount ?? metadata.ratingCount,
            editionCount: editionCount ?? metadata.editionCount
        )
    }

    func withAvailability(_ availability: DiscoverAvailability) -> DiscoverBook {
        DiscoverBook(
            id: id,
            source: source,
            sourceID: sourceID,
            title: title,
            author: author,
            coverURL: coverURL,
            subjects: subjects,
            availability: availability,
            webURL: webURL,
            languageCode: languageCode,
            pageCount: pageCount,
            description: description,
            firstPublishYear: firstPublishYear,
            downloadCount: downloadCount,
            ratingAverage: ratingAverage,
            ratingCount: ratingCount,
            editionCount: editionCount
        )
    }

    func withCoverURL(_ coverURL: URL) -> DiscoverBook {
        DiscoverBook(
            id: id,
            source: source,
            sourceID: sourceID,
            title: title,
            author: author,
            coverURL: coverURL,
            subjects: subjects,
            availability: availability,
            webURL: webURL,
            languageCode: languageCode,
            pageCount: pageCount,
            description: description,
            firstPublishYear: firstPublishYear,
            downloadCount: downloadCount,
            ratingAverage: ratingAverage,
            ratingCount: ratingCount,
            editionCount: editionCount
        )
    }

    private static func bestTitle(primary: DiscoverBook, metadata: DiscoverBook) -> String {
        let primaryTitle = primary.title.discoverCleanBookTitle
        let metadataTitle = metadata.title.discoverCleanBookTitle
        guard !metadataTitle.isEmpty else { return primaryTitle.isEmpty ? primary.title : primaryTitle }
        guard primaryTitle.discoverCanonicalTitleComponent == metadataTitle.discoverCanonicalTitleComponent else {
            return primaryTitle.isEmpty ? primary.title : primaryTitle
        }
        if primaryTitle.isEmpty { return metadataTitle }
        return metadataTitle.count <= primaryTitle.count ? metadataTitle : primaryTitle
    }

    private static func bestAuthor(primary: DiscoverBook, metadata: DiscoverBook) -> String? {
        metadata.author?.discoverCleanAuthorName.nilIfBlank
            ?? primary.author?.discoverCleanAuthorName.nilIfBlank
    }

    private static func bestCoverURL(primary: DiscoverBook, metadata: DiscoverBook) -> URL? {
        guard let metadataCoverURL = metadata.coverURL else { return primary.coverURL }
        guard let primaryCoverURL = primary.coverURL else { return metadataCoverURL }
        if primary.hasLikelyGeneratedCover {
            return metadataCoverURL
        }
        let metadataURL = metadataCoverURL.absoluteString.lowercased()
        let primaryURL = primaryCoverURL.absoluteString.lowercased()
        if metadataURL.contains("covers.openlibrary.org"), !primaryURL.contains("covers.openlibrary.org") {
            return metadataCoverURL
        }
        return primaryCoverURL
    }

    private static func bestSubjects(primary: DiscoverBook, metadata: DiscoverBook) -> [String] {
        var seen = Set<String>()
        var subjects: [String] = []
        for subject in metadata.subjects + primary.subjects {
            let key = subject.discoverIdentityComponent
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            subjects.append(subject)
        }
        return subjects
    }

    private static func bestDescription(primary: DiscoverBook, metadata: DiscoverBook) -> String? {
        metadata.description?.nilIfSuspiciousDescription
            ?? primary.description?.nilIfSuspiciousDescription
    }

    private static func bestPublishYear(primary: DiscoverBook, metadata: DiscoverBook) -> Int? {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date()) + 1
        if let year = metadata.firstPublishYear, (-1000...currentYear).contains(year) {
            return year
        }
        if let year = primary.firstPublishYear, (-1000...currentYear).contains(year) {
            return year
        }
        return nil
    }
}

extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var nilIfSuspiciousMetadataValue: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 40 else { return nil }
        guard value.range(of: "[<>{}]", options: .regularExpression) == nil else { return nil }
        return value
    }

    var nilIfSuspiciousDescription: String? {
        let value = replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 24, value.count <= 2_400 else { return nil }
        guard value.range(of: "<[^>]+>", options: .regularExpression) == nil else { return nil }
        return value
    }
}
