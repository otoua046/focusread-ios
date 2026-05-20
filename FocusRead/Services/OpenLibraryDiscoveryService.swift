import Foundation

struct OpenLibraryDiscoveryService: Sendable {
    private let networkClient: DiscoverNetworkClient
    private let decoder: JSONDecoder
    private let archiveMetadataService: InternetArchiveMetadataService
    private static let readableSearchFields = [
        "key",
        "title",
        "author_name",
        "cover_i",
        "ia",
        "ebook_access",
        "public_scan_b",
        "subject",
        "language",
        "number_of_pages_median",
        "first_publish_year",
        "ratings_average",
        "ratings_count",
        "edition_count",
        "first_sentence"
    ].joined(separator: ",")

    init(
        networkClient: DiscoverNetworkClient = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        archiveMetadataService: InternetArchiveMetadataService? = nil
    ) {
        self.networkClient = networkClient
        self.decoder = decoder
        self.archiveMetadataService = archiveMetadataService ?? InternetArchiveMetadataService(networkClient: networkClient)
    }

    init(
        session: URLSession,
        decoder: JSONDecoder = JSONDecoder(),
        archiveMetadataService: InternetArchiveMetadataService? = nil
    ) {
        let networkClient = DiscoverNetworkClient(session: session)
        self.init(
            networkClient: networkClient,
            decoder: decoder,
            archiveMetadataService: archiveMetadataService ?? InternetArchiveMetadataService(networkClient: networkClient)
        )
    }

    func search(_ query: String, limit: Int = 18, page: Int = 1, languageCode: String = "en") async throws -> [DiscoverBook] {
        try await validatedSearchResult(query, limit: limit, page: page, languageCode: languageCode).books
    }

    func readableCandidates(_ query: String, limit: Int = 24, page: Int = 1, languageCode: String = "en") async throws -> [OpenLibraryBookCandidate] {
        try await readableCandidateResult(query, limit: limit, page: page, languageCode: languageCode).candidates
    }

    func readableCandidateResult(_ query: String, limit: Int = 24, page: Int = 1, languageCode: String = "en") async throws -> OpenLibraryCandidateSearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return OpenLibraryCandidateSearchResult(candidates: [], rawCount: 0, filteredReasonCounts: [:])
        }
        let language = Self.openLibraryLanguage(for: languageCode)
        let searchQuery = Self.query(trimmed, constrainedTo: language.searchCode)

        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: searchQuery),
            URLQueryItem(name: "has_fulltext", value: "true"),
            URLQueryItem(name: "public_scan", value: "true"),
            URLQueryItem(name: "lang", value: language.preferenceCode),
            URLQueryItem(name: "fields", value: Self.readableSearchFields),
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 50))"),
            URLQueryItem(name: "page", value: "\(max(page, 1))")
        ]

        let data = try await networkClient.data(for: components.url!, kind: .enrichment, timeout: 8)
        let result = try Self.candidateSearchResult(from: data, decoder: decoder)
        discoverDebugLog(
            "Discover pagination event=provider-raw provider=openlibrary-readable-candidates query=\(trimmed.discoverIdentityComponent) requestedPage=\(page) requestedCursor=nil limit=\(limit) fetchedRaw=\(result.rawCount) candidates=\(result.candidates.count) filtered=\(Self.formattedReasons(result.filteredReasonCounts))"
        )
        return result
    }

    func metadataSearch(_ query: String, limit: Int = 24, page: Int = 1, languageCode: String = "en") async throws -> [DiscoverBook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let language = Self.openLibraryLanguage(for: languageCode)
        let searchQuery = Self.query(trimmed, constrainedTo: language.searchCode)

        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: searchQuery),
            URLQueryItem(name: "lang", value: language.preferenceCode),
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 50))"),
            URLQueryItem(name: "page", value: "\(max(page, 1))")
        ]

        let data = try await networkClient.data(for: components.url!, kind: .enrichment, timeout: 5)
        let response = try decoder.decode(OpenLibrarySearchResponse.self, from: data)
        let books = response.docs.compactMap(Self.mapMetadata)
        discoverDebugLog(
            "Discover pagination event=provider-raw provider=openlibrary-metadata query=\(trimmed.discoverIdentityComponent) requestedPage=\(page) requestedCursor=nil limit=\(limit) fetchedRaw=\(response.docs.count) readable=\(books.filter(\.isReadable).count) mapped=\(books.count)"
        )
        return books
    }

    private static func query(_ query: String, constrainedTo languageSearchCode: String) -> String {
        guard query.range(of: #"(?i)\blanguage:"#, options: .regularExpression) == nil else {
            return query
        }
        return "\(query) language:\(languageSearchCode)"
    }

    private static func openLibraryLanguage(for languageCode: String) -> (preferenceCode: String, searchCode: String) {
        let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let preferenceCode = normalized.split(separator: "-").first.map(String.init) ?? "en"
        let searchCode: String
        switch preferenceCode {
        case "ar": searchCode = "ara"
        case "de": searchCode = "ger"
        case "en": searchCode = "eng"
        case "es": searchCode = "spa"
        case "fr": searchCode = "fre"
        case "it": searchCode = "ita"
        case "ja": searchCode = "jpn"
        case "ko": searchCode = "kor"
        case "pt": searchCode = "por"
        case "zh": searchCode = "chi"
        default: searchCode = "eng"
        }
        return (preferenceCode.isEmpty ? "en" : preferenceCode, searchCode)
    }

    static func books(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> [DiscoverBook] {
        try candidateSearchResult(from: data, decoder: decoder).candidates.map(\.book)
    }

    static func metadataBooks(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> [DiscoverBook] {
        let response = try decoder.decode(OpenLibrarySearchResponse.self, from: data)
        return response.docs.compactMap(mapMetadata)
    }

    private static func candidateSearchResult(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> OpenLibraryCandidateSearchResult {
        let response = try decoder.decode(OpenLibrarySearchResponse.self, from: data)
        var filteredReasonCounts: [String: Int] = [:]
        let candidates = response.docs.compactMap { result -> OpenLibraryBookCandidate? in
            switch mapResult(result) {
            case .candidate(let candidate):
                return candidate
            case .filtered(let reason):
                filteredReasonCounts[reason.rawValue, default: 0] += 1
                return nil
            }
        }
        return OpenLibraryCandidateSearchResult(
            candidates: candidates,
            rawCount: response.docs.count,
            filteredReasonCounts: filteredReasonCounts
        )
    }

    private static func formattedReasons(_ reasons: [String: Int]) -> String {
        reasons
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }

    private static func mapResult(_ result: OpenLibraryDocResponse) -> OpenLibraryMapResult {
        let title = result.title.discoverCleanBookTitle
        guard !title.isEmpty else { return .filtered(.emptyTitle) }
        guard result.publicScan == true || result.ebookAccess == "public" else {
            return .filtered(.notPublicReadable)
        }
        let archiveIdentifiers = (result.ia ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !archiveIdentifiers.isEmpty else { return .filtered(.missingArchiveIdentifier) }

        let sourceID = (result.key ?? archiveIdentifiers[0]).discoverSafeFileComponent
        let book = metadataBook(from: result, sourceID: sourceID, title: title)
        return .candidate(OpenLibraryBookCandidate(book: book, archiveIdentifiers: archiveIdentifiers))
    }

    private static func mapMetadata(_ result: OpenLibraryDocResponse) -> DiscoverBook? {
        let title = result.title.discoverCleanBookTitle
        guard !title.isEmpty else { return nil }
        let sourceID = (result.key ?? result.coverID.map { "cover-\($0)" } ?? title).discoverSafeFileComponent
        return metadataBook(from: result, sourceID: sourceID, title: title)
    }

    private static func metadataBook(
        from result: OpenLibraryDocResponse,
        sourceID: String,
        title: String
    ) -> DiscoverBook {
        let coverURL = result.coverID.map { URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg") } ?? nil
        let description = result.firstSentence?.value
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return DiscoverBook(
            id: "openlibrary-\(sourceID)",
            source: .openLibrary,
            sourceID: sourceID,
            title: title,
            author: result.authorNames?.first?.discoverCleanAuthorName,
            coverURL: coverURL,
            subjects: result.subjects ?? [],
            availability: nil,
            webURL: result.key.flatMap { URL(string: "https://openlibrary.org\($0)") },
            languageCode: result.languages?.first,
            pageCount: result.pageCount,
            description: description?.isEmpty == false ? description : nil,
            firstPublishYear: result.firstPublishYear,
            downloadCount: nil,
            ratingAverage: result.ratingAverage,
            ratingCount: result.ratingCount,
            editionCount: result.editionCount
        )
    }

    func validatedBooks(from candidates: [OpenLibraryBookCandidate], limit: Int) async throws -> [DiscoverBook] {
        await validatedBooksWithDiagnostics(from: candidates, limit: limit).books
    }

    func validatedSearchResult(_ query: String, limit: Int = 18, page: Int = 1, languageCode: String = "en") async throws -> OpenLibraryValidatedSearchResult {
        let candidateResult = try await readableCandidateResult(
            query,
            limit: min(max(limit * 3, limit), 50),
            page: page,
            languageCode: languageCode
        )
        let validation = await validatedBooksWithDiagnostics(from: candidateResult.candidates, limit: limit)
        return OpenLibraryValidatedSearchResult(
            books: validation.books,
            rawCount: candidateResult.rawCount,
            candidateCount: candidateResult.candidates.count,
            filteredReasonCounts: candidateResult.filteredReasonCounts.merging(validation.filteredReasonCounts) { $0 + $1 }
        )
    }

    func validatedBooksWithDiagnostics(
        from candidates: [OpenLibraryBookCandidate],
        limit: Int
    ) async -> OpenLibraryValidationResult {
        guard limit > 0 else {
            return OpenLibraryValidationResult(books: [], filteredReasonCounts: [:])
        }

        return await withTaskGroup(of: (Int, DiscoverBook?).self) { group in
            var nextIndex = 0
            let maxConcurrentValidationRequests = 4

            func enqueueNextCandidate() {
                guard nextIndex < candidates.count else { return }
                let index = nextIndex
                let candidate = candidates[index]
                nextIndex += 1
                group.addTask {
                    let book = await validatedBook(from: candidate)
                    return (index, book)
                }
            }

            for _ in 0..<min(maxConcurrentValidationRequests, candidates.count) {
                enqueueNextCandidate()
            }

            var resolved: [(Int, DiscoverBook)] = []
            var unreadableCount = 0
            for await (index, book) in group {
                if let book {
                    resolved.append((index, book))
                    if resolved.count >= limit {
                        group.cancelAll()
                        break
                    }
                } else {
                    unreadableCount += 1
                }
                enqueueNextCandidate()
            }

            let books = resolved
                .sorted { $0.0 < $1.0 }
                .map(\.1)
                .prefix(limit)
                .map { $0 }
            return OpenLibraryValidationResult(
                books: books,
                filteredReasonCounts: unreadableCount > 0 ? [OpenLibraryFilteredReason.noReadableArchiveResource.rawValue: unreadableCount] : [:]
            )
        }
    }

    private func validatedBook(from candidate: OpenLibraryBookCandidate) async -> DiscoverBook? {
        for identifier in candidate.archiveIdentifiers {
            do {
                let resource = try await archiveMetadataService.downloadableResource(for: identifier)
                return candidate.book.withAvailability(
                    DiscoverAvailability(
                        preferredFormat: resource.format,
                        location: .direct(resource.url),
                        localFileName: "\(candidate.book.title.discoverReadableFileComponent).\(resource.format.fileExtension)"
                    )
                )
            } catch is CancellationError {
                return nil
            } catch {
                discoverDebugLog("Discover archive metadata unavailable for \(identifier.discoverSafeFileComponent)")
                continue
            }
        }
        return nil
    }
}

final actor InternetArchiveMetadataService {
    private let networkClient: DiscoverNetworkClient
    private let decoder: JSONDecoder
    private let persistentCache: DiscoverArchiveResourceCache
    private var resourceCache: [String: DiscoverArchiveResource] = [:]
    private var failedResourceRetryAfter: [String: Date] = [:]
    private let failureCooldown: TimeInterval = 60 * 20

    init(
        networkClient: DiscoverNetworkClient = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        persistentCache: DiscoverArchiveResourceCache = .shared
    ) {
        self.networkClient = networkClient
        self.decoder = decoder
        self.persistentCache = persistentCache
    }

    init(session: URLSession, decoder: JSONDecoder = JSONDecoder()) {
        self.init(networkClient: DiscoverNetworkClient(session: session), decoder: decoder)
    }

    func downloadableEPUBURL(for identifier: String) async throws -> URL {
        let resource = try await downloadableResource(for: identifier)
        guard resource.format == .epub else {
            throw DiscoverServiceError.noReadableFormat
        }
        return resource.url
    }

    func downloadableURL(for identifier: String, format: DiscoverDownloadFormat) async throws -> URL {
        let resource = try await downloadableResource(for: identifier)
        guard resource.format == format else {
            throw DiscoverServiceError.noReadableFormat
        }
        return resource.url
    }

    func downloadableResource(for identifier: String) async throws -> DiscoverArchiveResource {
        let archiveIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !archiveIdentifier.isEmpty,
              let encodedIdentifier = Self.encodedArchiveIdentifierPathComponent(archiveIdentifier) else {
            throw DiscoverServiceError.noReadableFormat
        }

        if let cached = resourceCache[archiveIdentifier] {
            DiscoverNetworkLog.cache("archive metadata hit \(archiveIdentifier.discoverSafeFileComponent)")
            return cached
        }
        if let cached = await persistentCache.resource(for: archiveIdentifier) {
            resourceCache[archiveIdentifier] = cached
            return cached
        }
        if let retryAfter = failedResourceRetryAfter[archiveIdentifier], retryAfter > Date() {
            throw DiscoverServiceError.noReadableFormat
        }

        let url = URL(string: "https://archive.org/metadata/\(encodedIdentifier)")!
        do {
            let data = try await networkClient.data(for: url, kind: .availability, timeout: 10)
            let metadata = try decoder.decode(InternetArchiveMetadataResponse.self, from: data)
            guard let resource = Self.preferredResource(in: metadata.files, identifier: archiveIdentifier) else {
                discoverDebugLog("Discover archive metadata has no readable resource for \(archiveIdentifier.discoverSafeFileComponent)")
                markResourceFailure(for: archiveIdentifier)
                throw DiscoverServiceError.noReadableFormat
            }
            failedResourceRetryAfter[archiveIdentifier] = nil
            resourceCache[archiveIdentifier] = resource
            await persistentCache.store(resource, for: archiveIdentifier)
            return resource
        } catch let error as DiscoverServiceError {
            throw error
        } catch {
            markResourceFailure(for: archiveIdentifier)
            throw DiscoverServiceError.unavailable
        }
    }

    private func markResourceFailure(for identifier: String) {
        failedResourceRetryAfter[identifier] = Date().addingTimeInterval(failureCooldown)
    }

    private nonisolated static func preferredResource(
        in files: [InternetArchiveFileResponse],
        identifier: String
    ) -> DiscoverArchiveResource? {
        files.compactMap { resource(from: $0, identifier: identifier) }
            .sorted { lhs, rhs in
                if lhs.format.priority == rhs.format.priority {
                    return lhs.url.absoluteString < rhs.url.absoluteString
                }
                return lhs.format.priority < rhs.format.priority
            }
            .first
    }

    private nonisolated static func resource(
        from file: InternetArchiveFileResponse,
        identifier: String
    ) -> DiscoverArchiveResource? {
        guard let encodedIdentifier = encodedArchiveIdentifierPathComponent(identifier) else {
            return nil
        }
        guard let encodedName = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://archive.org/download/\(encodedIdentifier)/\(encodedName)") else {
            return nil
        }

        let name = file.name.lowercased()
        let format = file.format?.lowercased() ?? ""

        if isEPUB(name: name, format: format) {
            return DiscoverArchiveResource(format: .epub, url: url)
        }
        if isPDF(name: name, format: format) {
            return DiscoverArchiveResource(format: .pdf, url: url)
        }
        if isPlainText(name: name, format: format) {
            return DiscoverArchiveResource(format: .plainText, url: url)
        }
        return nil
    }

    private nonisolated static func isEPUB(name: String, format: String) -> Bool {
        name.hasSuffix(".epub") || format == "epub" || format == "openlibrary epub"
    }

    private nonisolated static func isPDF(name: String, format: String) -> Bool {
        name.hasSuffix(".pdf") || format == "pdf" || format.contains("pdf")
    }

    private nonisolated static func isPlainText(name: String, format: String) -> Bool {
        guard name.hasSuffix(".txt") || format.contains("plain text") || format == "text" else {
            return false
        }
        return !name.contains("_meta") && !name.contains("_files")
    }

    private nonisolated static func encodedArchiveIdentifierPathComponent(_ identifier: String) -> String? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return identifier.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

struct OpenLibraryBookCandidate: Sendable {
    let book: DiscoverBook
    let archiveIdentifiers: [String]
}

struct OpenLibraryCandidateSearchResult: Sendable {
    let candidates: [OpenLibraryBookCandidate]
    let rawCount: Int
    let filteredReasonCounts: [String: Int]
}

struct OpenLibraryValidationResult: Sendable {
    let books: [DiscoverBook]
    let filteredReasonCounts: [String: Int]
}

struct OpenLibraryValidatedSearchResult: Sendable {
    let books: [DiscoverBook]
    let rawCount: Int
    let candidateCount: Int
    let filteredReasonCounts: [String: Int]
}

private enum OpenLibraryMapResult {
    case candidate(OpenLibraryBookCandidate)
    case filtered(OpenLibraryFilteredReason)
}

private enum OpenLibraryFilteredReason: String {
    case emptyTitle
    case notPublicReadable
    case missingArchiveIdentifier
    case noReadableArchiveResource
}

struct DiscoverArchiveResource: Hashable, Codable, Sendable {
    let format: DiscoverDownloadFormat
    let url: URL
}

private extension DiscoverBook {
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
}

private struct OpenLibrarySearchResponse: Decodable {
    let docs: [OpenLibraryDocResponse]
}

private struct OpenLibraryDocResponse: Decodable {
    let key: String?
    let title: String
    let authorNames: [String]?
    let coverID: Int?
    let ia: [String]?
    let ebookAccess: String?
    let publicScan: Bool?
    let subjects: [String]?
    let pageCount: Int?
    let languages: [String]?
    let firstPublishYear: Int?
    let ratingAverage: Double?
    let ratingCount: Int?
    let editionCount: Int?
    let firstSentence: OpenLibraryFirstSentence?

    enum CodingKeys: String, CodingKey {
        case key
        case title
        case authorNames = "author_name"
        case coverID = "cover_i"
        case ia
        case ebookAccess = "ebook_access"
        case publicScan = "public_scan_b"
        case subjects = "subject"
        case pageCount = "number_of_pages_median"
        case languages = "language"
        case firstPublishYear = "first_publish_year"
        case ratingAverage = "ratings_average"
        case ratingCount = "ratings_count"
        case editionCount = "edition_count"
        case firstSentence = "first_sentence"
    }
}

private enum OpenLibraryFirstSentence: Decodable {
    case value(String)

    var value: String {
        switch self {
        case .value(let value):
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .value(value)
            return
        }
        if let values = try? container.decode([String].self),
           let value = values.first {
            self = .value(value)
            return
        }
        self = .value("")
    }
}

private struct InternetArchiveMetadataResponse: Decodable {
    let files: [InternetArchiveFileResponse]
}

private struct InternetArchiveFileResponse: Decodable {
    let name: String
    let format: String?
}
