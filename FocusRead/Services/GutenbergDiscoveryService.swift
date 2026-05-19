import Foundation

struct GutenbergDiscoveryService: Sendable {
    private let networkClient: DiscoverNetworkClient
    private let decoder: JSONDecoder

    init(
        networkClient: DiscoverNetworkClient = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.networkClient = networkClient
        self.decoder = decoder
    }

    init(session: URLSession, decoder: JSONDecoder = JSONDecoder()) {
        self.init(networkClient: DiscoverNetworkClient(session: session), decoder: decoder)
    }

    func search(_ query: String, limit: Int = 24, languageCode: String? = "en", page: Int = 1) async throws -> [DiscoverBook] {
        try await searchResult(query, limit: limit, languageCode: languageCode, page: page).books
    }

    func searchResult(_ query: String, limit: Int = 24, languageCode: String? = "en", page: Int = 1) async throws -> GutenbergSearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return GutenbergSearchResult(books: [], rawCount: 0, filteredReasonCounts: [:]) }

        var components = URLComponents(string: "https://gutendex.com/books/")!
        var queryItems = [
            URLQueryItem(name: "search", value: trimmed)
        ]
        if let languageCode, !languageCode.isEmpty {
            queryItems.append(URLQueryItem(name: "languages", value: languageCode))
        }
        if page > 1 {
            queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
        }
        components.queryItems = queryItems
        let response = try await searchResult(from: components.url!)
        discoverDebugLog(
            "Discover pagination event=provider-raw provider=gutenberg-search query=\(trimmed.discoverIdentityComponent) requestedPage=\(page) requestedCursor=nil limit=\(limit) fetchedRaw=\(response.rawCount) readable=\(response.books.count) filtered=\(Self.formattedReasons(response.filteredReasonCounts))"
        )
        return response.limited(to: limit)
    }

    func curated(topic: String, limit: Int = 14, languageCode: String = "en", page: Int = 1) async throws -> [DiscoverBook] {
        var components = URLComponents(string: "https://gutendex.com/books/")!
        var queryItems = [
            URLQueryItem(name: "topic", value: topic),
            URLQueryItem(name: "languages", value: languageCode),
            URLQueryItem(name: "sort", value: "popular")
        ]
        if page > 1 {
            queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
        }
        components.queryItems = queryItems
        let response = try await searchResult(from: components.url!)
        discoverDebugLog(
            "Discover pagination event=provider-raw provider=gutenberg-topic topic=\(topic.discoverIdentityComponent) requestedPage=\(page) requestedCursor=nil limit=\(limit) fetchedRaw=\(response.rawCount) readable=\(response.books.count) filtered=\(Self.formattedReasons(response.filteredReasonCounts))"
        )
        return Array(response.books.prefix(limit))
    }

    func books(ids: [Int]) async throws -> [DiscoverBook] {
        guard !ids.isEmpty else { return [] }
        var components = URLComponents(string: "https://gutendex.com/books/")!
        components.queryItems = [
            URLQueryItem(name: "ids", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "languages", value: "en")
        ]
        let response = try await books(from: components.url!)
        let booksByID = Dictionary(response.map { ($0.sourceID, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { booksByID[String($0)] }
    }

    private func books(from url: URL) async throws -> [DiscoverBook] {
        let data = try await networkClient.data(for: url, kind: .metadata, timeout: 8)
        return try Self.books(from: data, decoder: decoder)
    }

    private func searchResult(from url: URL) async throws -> GutenbergSearchResult {
        let data = try await networkClient.data(for: url, kind: .metadata, timeout: 8)
        return try Self.searchResult(from: data, decoder: decoder)
    }

    static func books(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> [DiscoverBook] {
        try searchResult(from: data, decoder: decoder).books
    }

    static func searchResult(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> GutenbergSearchResult {
        let response = try decoder.decode(GutenbergResponse.self, from: data)
        var filteredReasonCounts: [String: Int] = [:]
        let books = response.results.compactMap { result -> DiscoverBook? in
            switch mapResult(result) {
            case .book(let book):
                return book
            case .filtered(let reason):
                filteredReasonCounts[reason.rawValue, default: 0] += 1
                return nil
            }
        }
        return GutenbergSearchResult(
            books: books,
            rawCount: response.results.count,
            filteredReasonCounts: filteredReasonCounts
        )
    }

    private static func mapResult(_ result: GutenbergBookResponse) -> GutenbergMapResult {
        let title = result.title.discoverCleanBookTitle
        guard !title.isEmpty else { return .filtered(.emptyTitle) }

        guard let availability = availability(from: result.formats, title: title) else {
            return .filtered(.noReadableFormat)
        }

        return .book(DiscoverBook(
            id: "gutenberg-\(result.id)",
            source: .projectGutenberg,
            sourceID: "\(result.id)",
            title: title,
            author: result.authors.first?.name.discoverCleanAuthorName,
            coverURL: preferredFormatURL(in: result.formats, matching: "image/"),
            subjects: result.subjects ?? [],
            availability: availability,
            webURL: URL(string: "https://www.gutenberg.org/ebooks/\(result.id)"),
            languageCode: result.languages?.first,
            pageCount: nil,
            description: nil,
            firstPublishYear: nil,
            downloadCount: result.downloadCount,
            ratingAverage: nil,
            ratingCount: nil,
            editionCount: nil
        ))
    }

    private static func availability(from formats: [String: String], title: String) -> DiscoverAvailability? {
        let candidates: [(DiscoverDownloadFormat, URL?)] = [
            (.epub, preferredFormatURL(in: formats, matching: "epub")),
            (.pdf, preferredFormatURL(in: formats, matching: "pdf")),
            (.plainText, preferredFormatURL(in: formats, matching: "text/plain"))
        ]

        for (format, url) in candidates {
            guard let url else { continue }
            return DiscoverAvailability(
                preferredFormat: format,
                location: .direct(url),
                localFileName: readableFileName(title: title, fileExtension: format.fileExtension)
            )
        }
        return nil
    }

    private static func preferredFormatURL(in formats: [String: String], matching token: String) -> URL? {
        let lowercasedToken = token.lowercased()
        let candidates = formats
            .filter { key, value in
                let lowercasedKey = key.lowercased()
                let lowercasedValue = value.lowercased()
                return formatEntryMatches(
                    key: lowercasedKey,
                    value: lowercasedValue,
                    token: lowercasedToken
                )
                    && !lowercasedValue.hasSuffix(".zip")
            }
            .sorted { lhs, rhs in
                let lhsKey = lhs.key.lowercased()
                let rhsKey = rhs.key.lowercased()
                if lhsKey.contains("noimages") != rhsKey.contains("noimages") {
                    return lhsKey.contains("noimages")
                }
                if lhsKey.contains("images") != rhsKey.contains("images") {
                    return lhsKey.contains("images")
                }
                return lhs.key < rhs.key
            }

        for candidate in candidates {
            if let url = URL(string: candidate.value) {
                return url
            }
        }
        return nil
    }

    private static func formattedReasons(_ reasons: [String: Int]) -> String {
        reasons
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }

    private static func formatEntryMatches(key: String, value: String, token: String) -> Bool {
        if key.contains(token) {
            return true
        }
        switch token {
        case "epub":
            return value.contains(".epub")
        case "pdf":
            return value.contains(".pdf")
        case "text/plain":
            return value.contains(".txt") || value.contains("text/plain")
        default:
            return value.contains(token)
        }
    }

    static func fallbackCuratedSections() -> [DiscoverSection] {
        [
            DiscoverSection(
                id: "popular-classics",
                title: "Popular Classics",
                books: [
                    fallbackBook(id: 1342, title: "Pride and Prejudice", author: "Jane Austen"),
                    fallbackBook(id: 105, title: "Persuasion", author: "Jane Austen"),
                    fallbackBook(id: 161, title: "Sense and Sensibility", author: "Jane Austen"),
                    fallbackBook(id: 11, title: "Alice's Adventures in Wonderland", author: "Lewis Carroll"),
                    fallbackBook(id: 84, title: "Frankenstein", author: "Mary Wollstonecraft Shelley"),
                    fallbackBook(id: 1661, title: "The Adventures of Sherlock Holmes", author: "Arthur Conan Doyle"),
                    fallbackBook(id: 2701, title: "Moby-Dick", author: "Herman Melville")
                ],
                layout: .classicRow,
                treatment: .open
            ),
            DiscoverSection(
                id: "short-reads",
                title: "Short Reads",
                books: [
                    fallbackBook(id: 43, title: "The Strange Case of Dr. Jekyll and Mr. Hyde", author: "Robert Louis Stevenson"),
                    fallbackBook(id: 1952, title: "The Yellow Wallpaper", author: "Charlotte Perkins Gilman"),
                    fallbackBook(id: 5200, title: "Metamorphosis", author: "Franz Kafka"),
                    fallbackBook(id: 1080, title: "A Modest Proposal", author: "Jonathan Swift"),
                    fallbackBook(id: 41, title: "The Legend of Sleepy Hollow", author: "Washington Irving"),
                    fallbackBook(id: 215, title: "The Call of the Wild", author: "Jack London")
                ],
                layout: .compactGrid,
                treatment: .framed
            ),
            DiscoverSection(
                id: "philosophy-focus",
                title: "Philosophy & Focus",
                books: [
                    fallbackBook(id: 2680, title: "Meditations", author: "Marcus Aurelius"),
                    fallbackBook(id: 1497, title: "The Republic", author: "Plato"),
                    fallbackBook(id: 1656, title: "Apology", author: "Plato"),
                    fallbackBook(id: 216, title: "Tao Te Ching", author: "Laozi"),
                    fallbackBook(id: 4363, title: "Beyond Good and Evil", author: "Friedrich Nietzsche"),
                    fallbackBook(id: 5827, title: "The Problems of Philosophy", author: "Bertrand Russell")
                ],
                layout: .compactGrid,
                treatment: .open
            ),
            DiscoverSection(
                id: "fiction-literature",
                title: "Fiction & Literature",
                books: [
                    fallbackBook(id: 158, title: "Emma", author: "Jane Austen"),
                    fallbackBook(id: 1342, title: "Pride and Prejudice", author: "Jane Austen"),
                    fallbackBook(id: 105, title: "Persuasion", author: "Jane Austen"),
                    fallbackBook(id: 161, title: "Sense and Sensibility", author: "Jane Austen"),
                    fallbackBook(id: 121, title: "Northanger Abbey", author: "Jane Austen"),
                    fallbackBook(id: 1260, title: "Jane Eyre", author: "Charlotte Bronte"),
                    fallbackBook(id: 174, title: "The Picture of Dorian Gray", author: "Oscar Wilde"),
                    fallbackBook(id: 36, title: "The War of the Worlds", author: "H. G. Wells"),
                    fallbackBook(id: 345, title: "Dracula", author: "Bram Stoker")
                ],
                layout: .editorialHero,
                treatment: .framed
            ),
            DiscoverSection(
                id: "quick-under-two-hours",
                title: "Quick Reads Under 2 Hours",
                books: [
                    fallbackBook(id: 1952, title: "The Yellow Wallpaper", author: "Charlotte Perkins Gilman"),
                    fallbackBook(id: 5200, title: "Metamorphosis", author: "Franz Kafka"),
                    fallbackBook(id: 1080, title: "A Modest Proposal", author: "Jonathan Swift"),
                    fallbackBook(id: 844, title: "The Importance of Being Earnest", author: "Oscar Wilde"),
                    fallbackBook(id: 2542, title: "A Doll's House", author: "Henrik Ibsen"),
                    fallbackBook(id: 43, title: "The Strange Case of Dr. Jekyll and Mr. Hyde", author: "Robert Louis Stevenson")
                ],
                layout: .compactGrid,
                treatment: .open
            ),
            DiscoverSection(
                id: "ideas-productivity",
                title: "Ideas & Productivity",
                books: [
                    fallbackBook(id: 205, title: "Walden", author: "Henry David Thoreau"),
                    fallbackBook(id: 71, title: "On the Duty of Civil Disobedience", author: "Henry David Thoreau"),
                    fallbackBook(id: 132, title: "The Art of War", author: "Sun Tzu"),
                    fallbackBook(id: 20203, title: "The Autobiography of Benjamin Franklin", author: "Benjamin Franklin"),
                    fallbackBook(id: 2944, title: "Essays", author: "Ralph Waldo Emerson")
                ],
                layout: .compactGrid,
                treatment: .framed
            ),
            DiscoverSection(
                id: "public-domain-essentials",
                title: "Public Domain Essentials",
                books: [
                    fallbackBook(id: 1342, title: "Pride and Prejudice", author: "Jane Austen"),
                    fallbackBook(id: 11, title: "Alice's Adventures in Wonderland", author: "Lewis Carroll"),
                    fallbackBook(id: 84, title: "Frankenstein", author: "Mary Wollstonecraft Shelley"),
                    fallbackBook(id: 1661, title: "The Adventures of Sherlock Holmes", author: "Arthur Conan Doyle"),
                    fallbackBook(id: 2701, title: "Moby-Dick", author: "Herman Melville")
                ],
                layout: .classicRow,
                treatment: .open
            )
        ]
    }

    private static func fallbackBook(id: Int, title: String, author: String) -> DiscoverBook {
        let cleanTitle = title.discoverCleanBookTitle
        return DiscoverBook(
            id: "gutenberg-\(id)",
            source: .projectGutenberg,
            sourceID: "\(id)",
            title: cleanTitle,
            author: author.discoverCleanAuthorName,
            coverURL: URL(string: "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).cover.medium.jpg"),
            subjects: [],
            availability: DiscoverAvailability(
                preferredFormat: .epub,
                location: .direct(URL(string: "https://www.gutenberg.org/ebooks/\(id).epub.noimages")!),
                localFileName: readableFileName(title: cleanTitle, fileExtension: "epub")
            ),
            webURL: URL(string: "https://www.gutenberg.org/ebooks/\(id)"),
            languageCode: "en",
            pageCount: nil,
            description: nil,
            firstPublishYear: nil,
            downloadCount: nil,
            ratingAverage: nil,
            ratingCount: nil,
            editionCount: nil
        )
    }

    private static func readableFileName(title: String, fileExtension: String) -> String {
        "\(title.discoverReadableFileComponent).\(fileExtension)"
    }
}

struct GutenbergSearchResult: Sendable {
    let books: [DiscoverBook]
    let rawCount: Int
    let filteredReasonCounts: [String: Int]

    func limited(to limit: Int) -> GutenbergSearchResult {
        GutenbergSearchResult(
            books: Array(books.prefix(limit)),
            rawCount: rawCount,
            filteredReasonCounts: filteredReasonCounts
        )
    }
}

private enum GutenbergMapResult {
    case book(DiscoverBook)
    case filtered(GutenbergFilteredReason)
}

private enum GutenbergFilteredReason: String {
    case emptyTitle
    case noReadableFormat
}

private struct GutenbergResponse: Decodable {
    let results: [GutenbergBookResponse]
}

private struct GutenbergBookResponse: Decodable {
    let id: Int
    let title: String
    let authors: [GutenbergAuthorResponse]
    let subjects: [String]?
    let formats: [String: String]
    let languages: [String]?
    let downloadCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case authors
        case subjects
        case formats
        case languages
        case downloadCount = "download_count"
    }
}

private struct GutenbergAuthorResponse: Decodable {
    let name: String
}
