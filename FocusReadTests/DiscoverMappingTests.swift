import Foundation
import Testing
@testable import FocusRead

@Suite(.serialized)
struct DiscoverMappingTests {
    private static let onePixelPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="

    @Test func gutenbergMappingPrefersEPUBAndCover() throws {
        let json = """
        {
          "results": [
            {
              "id": 1342,
              "title": "Pride and Prejudice",
              "authors": [{ "name": "Austen, Jane" }],
              "subjects": ["Fiction"],
              "download_count": 12345,
              "formats": {
                "application/epub+zip": "https://www.gutenberg.org/ebooks/1342.epub.images",
                "text/plain; charset=utf-8": "https://www.gutenberg.org/files/1342/1342-0.txt",
                "image/jpeg": "https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let books = try GutenbergDiscoveryService.books(from: json)

        #expect(books.count == 1)
        #expect(books[0].id == "gutenberg-1342")
        #expect(books[0].title == "Pride and Prejudice")
        #expect(books[0].author == "Jane Austen")
        #expect(books[0].availability?.preferredFormat == .epub)
        #expect(books[0].availability?.localFileName == "pride-and-prejudice.epub")
        #expect(books[0].coverURL?.absoluteString.contains("pg1342.cover") == true)
        #expect(books[0].downloadCount == 12345)
    }

    @Test func gutenbergMappingRejectsMetadataOnlyResults() throws {
        let json = """
        {
          "results": [
            {
              "id": 999,
              "title": "Metadata Only",
              "authors": [{ "name": "Nobody" }],
              "subjects": ["Fiction"],
              "formats": {
                "image/jpeg": "https://www.gutenberg.org/cache/epub/999/pg999.cover.medium.jpg"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let books = try GutenbergDiscoveryService.books(from: json)

        #expect(books.isEmpty)
    }

    @Test func gutenbergMappingTrustsReadableFormatURLs() throws {
        let json = """
        {
          "results": [
            {
              "id": 11,
              "title": "Alice's Adventures in Wonderland",
              "authors": [{ "name": "Carroll, Lewis" }],
              "subjects": ["Fantasy"],
              "formats": {
                "application/octet-stream": "https://www.gutenberg.org/ebooks/11.epub.noimages",
                "image/jpeg": "https://www.gutenberg.org/cache/epub/11/pg11.cover.medium.jpg"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let result = try GutenbergDiscoveryService.searchResult(from: json)

        #expect(result.rawCount == 1)
        #expect(result.books.count == 1)
        #expect(result.books[0].title == "Alice's Adventures in Wonderland")
        #expect(result.books[0].availability?.preferredFormat == .epub)
    }

    @Test func openLibraryMappingKeepsOnlyPublicArchiveCandidates() throws {
        let json = """
        {
          "docs": [
            {
              "key": "/works/OL45804W",
              "title": "Meditations",
              "author_name": ["Marcus Aurelius"],
              "cover_i": 12345,
              "ia": ["meditations-test"],
              "ebook_access": "public",
              "public_scan_b": true,
              "subject": ["Philosophy"],
              "first_publish_year": 180,
              "ratings_average": 4.2,
              "ratings_count": 27,
              "edition_count": 182,
              "number_of_pages_median": 304
            },
            {
              "key": "/works/OL999W",
              "title": "Borrow Only",
              "author_name": ["Someone"],
              "ebook_access": "borrowable",
              "public_scan_b": false
            }
          ]
        }
        """.data(using: .utf8)!

        let books = try OpenLibraryDiscoveryService.books(from: json)

        #expect(books.count == 1)
        #expect(books[0].source == .openLibrary)
        #expect(books[0].title == "Meditations")
        #expect(books[0].availability == nil)
        #expect(books[0].coverURL?.absoluteString == "https://covers.openlibrary.org/b/id/12345-L.jpg")
        #expect(books[0].firstPublishYear == 180)
        #expect(books[0].ratingAverage == 4.2)
        #expect(books[0].ratingCount == 27)
        #expect(books[0].editionCount == 182)
        #expect(books[0].pageCount == 304)
    }

    @Test func openLibrarySearchRequiresValidatedArchiveResources() async throws {
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "openlibrary.org", url.path == "/search.json" {
                return Self.jsonResponse(for: url, body: """
                {
                  "docs": [
                    {
                      "key": "/works/OLEPUBW",
                      "title": "EPUB Winner",
                      "author_name": ["Reader One"],
                      "ia": ["epub-id"],
                      "ebook_access": "public",
                      "public_scan_b": true
                    },
                    {
                      "key": "/works/OLPDFW",
                      "title": "PDF Backup",
                      "author_name": ["Reader Two"],
                      "ia": ["pdf-id"],
                      "ebook_access": "public",
                      "public_scan_b": true
                    },
                    {
                      "key": "/works/OLTXTW",
                      "title": "Text Backup",
                      "author_name": ["Reader Three"],
                      "ia": ["txt-id"],
                      "ebook_access": "public",
                      "public_scan_b": true
                    },
                    {
                      "key": "/works/OLMETAW",
                      "title": "Metadata Only",
                      "author_name": ["Reader Four"],
                      "ia": ["meta-id"],
                      "ebook_access": "public",
                      "public_scan_b": true
                    },
                    {
                      "key": "/works/OLBORROWW",
                      "title": "Borrow Only",
                      "author_name": ["Reader Five"],
                      "ia": ["borrow-id"],
                      "ebook_access": "borrowable",
                      "public_scan_b": false
                    }
                  ]
                }
                """)
            }

            if url.host == "archive.org", url.path == "/metadata/epub-id" {
                return Self.jsonResponse(for: url, body: """
                {
                  "files": [
                    { "name": "book.pdf", "format": "PDF" },
                    { "name": "book.epub", "format": "EPUB" }
                  ]
                }
                """)
            }

            if url.host == "archive.org", url.path == "/metadata/pdf-id" {
                return Self.jsonResponse(for: url, body: """
                {
                  "files": [
                    { "name": "scan.pdf", "format": "Text PDF" }
                  ]
                }
                """)
            }

            if url.host == "archive.org", url.path == "/metadata/txt-id" {
                return Self.jsonResponse(for: url, body: """
                {
                  "files": [
                    { "name": "plain.txt", "format": "Plain Text" }
                  ]
                }
                """)
            }

            if url.host == "archive.org", url.path == "/metadata/meta-id" {
                return Self.jsonResponse(for: url, body: """
                {
                  "files": [
                    { "name": "meta-id_meta.xml", "format": "Metadata" }
                  ]
                }
                """)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService)

        let books = try await service.search("readable classics", limit: 5)

        #expect(books.map(\.title) == ["EPUB Winner", "PDF Backup", "Text Backup"])
        #expect(books.map { $0.availability?.preferredFormat } == [.epub, .pdf, .plainText])
        #expect(books.allSatisfy { $0.isReadable })
        #expect(books[0].availability?.localFileName == "epub-winner.epub")
        #expect(books[1].availability?.localFileName == "pdf-backup.pdf")
        #expect(books[2].availability?.localFileName == "text-backup.txt")

        let urls = books.compactMap { book -> String? in
            guard case .direct(let url) = book.availability?.location else { return nil }
            return url.absoluteString
        }
        #expect(urls == [
            "https://archive.org/download/epub-id/book.epub",
            "https://archive.org/download/pdf-id/scan.pdf",
            "https://archive.org/download/txt-id/plain.txt"
        ])
    }

    @Test func archiveMetadataResourcesAreCachedAfterFirstLookup() async throws {
        let counter = DiscoverMockCounter()
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "archive.org", url.path == "/metadata/cache-id" {
                await counter.increment()
                return Self.jsonResponse(for: url, body: """
                {
                  "files": [
                    { "name": "cached.epub", "format": "EPUB" }
                  ]
                }
                """)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let service = Self.archiveService(session: session)

        let firstResource = try await service.downloadableResource(for: "cache-id")
        let secondResource = try await service.downloadableResource(for: "cache-id")

        #expect(firstResource == secondResource)
        #expect(await counter.value == 1)
    }

    @Test func archiveMetadataFailuresUseCooldown() async throws {
        let counter = DiscoverMockCounter()
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "archive.org", url.path == "/metadata/missing-readable" {
                await counter.increment()
                return Self.jsonResponse(for: url, body: """
                {
                  "files": [
                    { "name": "missing-readable_meta.xml", "format": "Metadata" }
                  ]
                }
                """)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let service = Self.archiveService(session: session)

        do {
            _ = try await service.downloadableResource(for: "missing-readable")
        } catch {
        }
        do {
            _ = try await service.downloadableResource(for: "missing-readable")
        } catch {
        }

        #expect(await counter.value == 1)
    }

    @Test func archiveMetadataDoesNotTreatRePublisherLogsAsEPUBs() async throws {
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "archive.org", url.path == "/metadata/repub-log-only" {
                return Self.jsonResponse(for: url, body: """
                {
                  "files": [
                    { "name": "repub-log-only_repub_final.log", "format": "RePublisher Final Processing Log" }
                  ]
                }
                """)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let service = Self.archiveService(session: session)

        do {
            _ = try await service.downloadableResource(for: "repub-log-only")
            Issue.record("RePublisher logs should not be treated as readable EPUB resources")
        } catch DiscoverServiceError.noReadableFormat {
            #expect(true)
        } catch {
            Issue.record("Expected noReadableFormat, got \(error)")
        }
    }

    @Test func curatedSectionsDoNotHydrateOpenLibraryBeforeVisibility() async throws {
        let counter = DiscoverMockCounter()
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "openlibrary.org" {
                await counter.increment()
            }
            if url.host == "gutendex.com" {
                return Self.jsonResponse(for: url, body: #"{"results":[]}"#)
            }
            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService),
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            session: session
        )

        let sections = try await service.curatedSections()

        #expect(!sections.isEmpty)
        #expect(await counter.value == 0)
    }

    @Test func openLibraryValidationQuietlySkipsRefusedArchiveURLs() async throws {
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "openlibrary.org", url.path == "/search.json" {
                return Self.jsonResponse(for: url, body: """
                {
                  "docs": [
                    {
                      "key": "/works/OLREFUSEDW",
                      "title": "Refused Archive",
                      "author_name": ["Reader One"],
                      "ia": ["refused-id"],
                      "ebook_access": "public",
                      "public_scan_b": true
                    },
                    {
                      "key": "/works/OLOKW",
                      "title": "Available Archive",
                      "author_name": ["Reader Two"],
                      "ia": ["available-id"],
                      "ebook_access": "public",
                      "public_scan_b": true
                    }
                  ]
                }
                """)
            }

            if url.host == "archive.org", url.path == "/metadata/refused-id" {
                throw URLError(.cannotConnectToHost)
            }

            if url.host == "archive.org", url.path == "/metadata/available-id" {
                return Self.jsonResponse(for: url, body: """
                {
                  "files": [
                    { "name": "available.epub", "format": "EPUB" }
                  ]
                }
                """)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService)

        let books = try await service.search("quiet failures", limit: 5)

        #expect(books.map(\.title) == ["Available Archive"])
        #expect(books.allSatisfy { $0.isReadable })
    }

    @Test func discoverNetworkLimitsMetadataConcurrency() async throws {
        let counter = DiscoverConcurrentRequestCounter()
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            await counter.begin()
            try await Task.sleep(for: .milliseconds(40))
            await counter.end()
            return Self.jsonResponse(for: url, body: #"{"ok":true}"#)
        }
        let client = DiscoverNetworkClient(
            session: session,
            metadataMaxConcurrent: 2,
            imageMaxConcurrent: 6,
            cooldownDuration: 1
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    let url = URL(string: "https://example.com/metadata/\(index)")!
                    _ = try await client.data(for: url, kind: .metadata, timeout: 2)
                }
            }
            try await group.waitForAll()
        }

        #expect(await counter.maximumActive <= 2)
    }

    @Test func discoverNetworkCooldownDoesNotSkipEnrichmentSearchURLs() async throws {
        let counter = DiscoverMockCounter()
        let session = Self.mockSession { _ in
            await counter.increment()
            throw URLError(.timedOut)
        }
        let client = DiscoverNetworkClient(
            session: session,
            metadataMaxConcurrent: 4,
            imageMaxConcurrent: 6,
            cooldownDuration: 10
        )
        let url = URL(string: "https://openlibrary.org/search.json?q=timeout")!

        _ = try? await client.data(for: url, kind: .enrichment, timeout: 1)
        _ = try? await client.data(for: url, kind: .enrichment, timeout: 1)

        #expect(await counter.value == 2)
    }

    @Test func discoverNetworkCooldownStillSkipsAvailabilityURLs() async throws {
        let counter = DiscoverMockCounter()
        let session = Self.mockSession { _ in
            await counter.increment()
            throw URLError(.timedOut)
        }
        let client = DiscoverNetworkClient(
            session: session,
            metadataMaxConcurrent: 4,
            imageMaxConcurrent: 6,
            cooldownDuration: 10
        )
        let url = URL(string: "https://archive.org/metadata/timeout")!

        _ = try? await client.data(for: url, kind: .availability, timeout: 1)
        _ = try? await client.data(for: url, kind: .availability, timeout: 1)

        #expect(await counter.value == 1)
    }

    @Test func discoverSearchReturnsFastGutenbergClassicsBeforeOpenLibrary() async throws {
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "gutendex.com" {
                let search = Self.queryValue("search", in: url) ?? ""
                return Self.jsonResponse(for: url, body: Self.gutenbergSearchResponse(for: search))
            }

            if url.host == "openlibrary.org", url.path == "/search.json" {
                throw URLError(.timedOut)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService),
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            session: session
        )

        for (query, expectedTitle) in [
            ("Alice", "Alice's Adventures in Wonderland"),
            ("Emma", "Emma"),
            ("Frankenstein", "Frankenstein"),
            ("Meditations", "Meditations")
        ] {
            let fastResults = try await service.fastSearch(query)
            #expect(fastResults.contains { $0.title == expectedTitle })

            let enrichedResults = try await service.enrichedSearch(query, currentBooks: fastResults)
            #expect(enrichedResults.contains { $0.title == expectedTitle })
        }
    }

    @Test func metadataEnrichedSearchUpgradesGutenbergCoverWithoutArchiveValidation() async throws {
        let archiveCounter = DiscoverMockCounter()
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "openlibrary.org", url.path == "/search.json" {
                return Self.jsonResponse(for: url, body: """
                {
                  "docs": [
                    {
                      "key": "/works/OLLITTLEWOMENLETTERS",
                      "title": "Little Women Letters from the House of Alcott",
                      "author_name": ["Louisa May Alcott"],
                      "cover_i": 5830276,
                      "edition_count": 8
                    },
                    {
                      "key": "/works/OLMETADATAONLY",
                      "title": "Little Women",
                      "author_name": ["Louisa May Alcott"],
                      "cover_i": 8775559,
                      "edition_count": 1888
                    }
                  ]
                }
                """)
            }

            if url.host == "archive.org" {
                await archiveCounter.increment()
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService),
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            session: session
        )
        let gutenberg = book(
            id: "gutenberg-34106",
            source: .projectGutenberg,
            sourceID: "34106",
            title: "Little Women Letters from the House of Alcott",
            author: nil,
            coverURL: URL(string: "https://www.gutenberg.org/cache/epub/34106/pg34106.cover.medium.jpg")
        )

        let enriched = await service.metadataEnrichedSearch("little women", currentBooks: [gutenberg])

        #expect(enriched.count == 1)
        #expect(enriched[0].id == "gutenberg-34106")
        #expect(enriched[0].isReadable)
        #expect(enriched[0].coverURL?.absoluteString == "https://covers.openlibrary.org/b/id/5830276-L.jpg")
        #expect(await archiveCounter.value == 0)
    }

    @Test func searchValidationStopsAfterEnoughReadableResults() async throws {
        let archiveCounter = DiscoverMockCounter()
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "openlibrary.org", url.path == "/search.json" {
                let docs = (0..<10).map { index in
                    """
                    {
                      "key": "/works/OL\(index)W",
                      "title": "Readable \(index)",
                      "author_name": ["Reader \(index)"],
                      "ia": ["archive-\(index)"],
                      "ebook_access": "public",
                      "public_scan_b": true
                    }
                    """
                }.joined(separator: ",")
                return Self.jsonResponse(for: url, body: #"{"docs":["# + docs + #"]}"#)
            }

            if url.host == "archive.org", url.path.hasPrefix("/metadata/archive-") {
                await archiveCounter.increment()
                try await Task.sleep(for: .milliseconds(80))
                let identifier = url.lastPathComponent
                return Self.jsonResponse(for: url, body: """
                {
                  "files": [
                    { "name": "\(identifier).epub", "format": "EPUB" }
                  ]
                }
                """)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService)

        let books = try await service.search("readable", limit: 2)

        #expect(books.count == 2)
        #expect(await archiveCounter.value < 10)
    }

    @Test func discoverSearchReturnsTrustedGutenbergForNaturalTitlePhraseWhenNetworkFails() async throws {
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "gutendex.com" {
                throw URLError(.timedOut)
            }

            if url.host == "openlibrary.org", url.path == "/search.json" {
                throw URLError(.timedOut)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService),
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            session: session
        )

        let fastResults = try await service.fastSearch("Alice adventures in wonderland")

        #expect(fastResults.first?.title == "Alice's Adventures in Wonderland")
        #expect(fastResults.first?.source == .projectGutenberg)
        #expect(fastResults.first?.isReadable == true)
    }

    @MainActor
    @Test func discoverSearchFallsBackToOpenLibraryWhenFastGutenbergFails() async throws {
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "gutendex.com" {
                throw URLError(.timedOut)
            }

            if url.host == "openlibrary.org", url.path == "/search.json" {
                return Self.jsonResponse(for: url, body: """
                {
                  "docs": [
                    {
                      "key": "/works/OL20867W",
                      "title": "Middlemarch",
                      "author_name": ["George Eliot"],
                      "cover_i": 252882,
                      "ia": ["middlemarch-readable"],
                      "ebook_access": "public",
                      "public_scan_b": true,
                      "language": ["eng"],
                      "edition_count": 328
                    }
                  ]
                }
                """)
            }

            if url.host == "archive.org", url.path == "/metadata/middlemarch-readable" {
                return Self.jsonResponse(for: url, body: """
                {
                  "files": [
                    { "name": "middlemarch-readable_meta.xml", "format": "Metadata" },
                    { "name": "middlemarch-readable.epub", "format": "EPUB" }
                  ]
                }
                """)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService),
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            session: session
        )
        let viewModel = DiscoverViewModel(store: temporaryStore(), service: service)
        viewModel.searchText = "Middlemarch"

        await viewModel.searchNow()

        #expect(viewModel.searchResults.count == 1)
        let middlemarch = try #require(viewModel.searchResults.first)
        #expect(middlemarch.title == "Middlemarch")
        #expect(middlemarch.author == "George Eliot")
        #expect(middlemarch.source == .openLibrary)
        #expect(middlemarch.isReadable)
        #expect(middlemarch.availability?.preferredFormat == .epub)
    }

    @Test func emptyEnrichedSearchCacheDoesNotBlockFastGutenbergSearch() async throws {
        let gutenbergCounter = DiscoverMockCounter()
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "gutendex.com" {
                await gutenbergCounter.increment()
                let search = Self.queryValue("search", in: url) ?? ""
                return Self.jsonResponse(for: url, body: Self.gutenbergSearchResponse(for: search))
            }

            if url.host == "openlibrary.org", url.path == "/search.json" {
                return Self.jsonResponse(for: url, body: #"{"docs":[]}"#)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService),
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            session: session
        )

        let emptyEnrichedResults = try await service.enrichedSearch("Odyssey", currentBooks: [])
        #expect(emptyEnrichedResults.isEmpty)

        let fastResults = try await service.fastSearch("Odyssey")
        #expect(await gutenbergCounter.value == 1)
        #expect(fastResults.contains { $0.title == "The Odyssey" })
    }

    @MainActor
    @Test func discoverSearchRetriesSameQueryAfterCancelledRequest() async throws {
        let gutenbergCounter = DiscoverMockCounter()
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "gutendex.com" {
                let callCount = await gutenbergCounter.incrementAndReturnValue()
                if callCount == 1 {
                    try await Task.sleep(for: .seconds(2))
                }
                let search = Self.queryValue("search", in: url) ?? ""
                return Self.jsonResponse(for: url, body: Self.gutenbergSearchResponse(for: search))
            }

            if url.host == "openlibrary.org", url.path == "/search.json" {
                return Self.jsonResponse(for: url, body: #"{"docs":[]}"#)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService),
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            session: session
        )
        let viewModel = DiscoverViewModel(store: temporaryStore(), service: service)
        viewModel.searchText = "Odyssey"

        let firstSearch = Task { await viewModel.searchNow() }
        try await Self.waitUntil { await gutenbergCounter.value == 1 }
        firstSearch.cancel()
        _ = await firstSearch.result

        await viewModel.searchAfterDelay()

        #expect(await gutenbergCounter.value == 2)
        #expect(viewModel.searchResults.contains { $0.title == "The Odyssey" })
    }

    @Test func shelfPageFiltersExistingAndFetchedDuplicates() async throws {
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "gutendex.com" {
                return Self.jsonResponse(for: url, body: Self.gutenbergShelfResponse(page: Self.gutenbergShelfPage(for: url)))
            }

            if url.host == "openlibrary.org", url.path == "/search.json" {
                return Self.jsonResponse(for: url, body: #"{"docs":[]}"#)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let openLibraryService = OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: openLibraryService,
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            session: session
        )
        let existingBook = book(
            id: "existing-duplicate",
            source: .projectGutenberg,
            sourceID: "100",
            title: "Duplicate Work",
            author: "Same Author",
            coverURL: nil
        )

        let result = await service.shelfPage(
            sectionID: "popular-classics",
            title: "Popular Classics",
            existingBooks: [existingBook],
            page: 1,
            pageSize: 2
        )

        #expect(result.books.map(\.title) == ["Unique One", "Unique Two"])
        #expect(Set(result.books.map(\.titleAuthorFingerprint)).count == result.books.count)
        #expect(result.nextPage == 3)
    }

    @Test func shelfPageUsesGutenbergPageBeforeOpenLibraryEnrichment() async throws {
        let openLibraryCounter = DiscoverMockCounter()
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "gutendex.com" {
                return Self.jsonResponse(for: url, body: Self.gutenbergUniqueShelfResponse(page: 1, count: 14))
            }

            if url.host == "openlibrary.org", url.path == "/search.json" {
                await openLibraryCounter.increment()
                return Self.jsonResponse(for: url, body: #"{"docs":[]}"#)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let openLibraryService = OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: openLibraryService,
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            shelfSnapshotCache: DiscoverShelfSnapshotCache(directoryURL: Self.temporaryCacheDirectory(named: "ShelfSnapshot")),
            session: session
        )

        let result = await service.shelfPage(
            sectionID: "popular-classics",
            title: "Popular Classics",
            existingBooks: [],
            page: 1,
            pageSize: 4
        )

        #expect(result.books.count == 4)
        #expect(await openLibraryCounter.value == 0)
    }

    @Test func shelfPageTreatsNetworkRefusalsAsEmptyPages() async throws {
        let session = Self.mockSession { _ in
            throw URLError(.cannotConnectToHost)
        }
        let archiveService = Self.archiveService(session: session)
        let openLibraryService = OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: openLibraryService,
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            session: session
        )

        let result = await service.shelfPage(
            sectionID: "popular-classics",
            title: "Popular Classics",
            existingBooks: [],
            page: 1,
            pageSize: 4
        )

        #expect(result.books.isEmpty)
        #expect(result.nextPage == 4)
    }

    @Test func shelfSnapshotCachePersistsInitialShelfPayloads() async throws {
        let cache = DiscoverShelfSnapshotCache(directoryURL: Self.temporaryCacheDirectory(named: "ShelfSnapshot"))
        let originalBook = book(
            id: "gutenberg-4242",
            source: .projectGutenberg,
            sourceID: "4242",
            title: "Cached Book",
            author: "Cached Author",
            coverURL: URL(string: "https://example.com/cover.jpg")
        )
        let section = DiscoverSection(
            id: "popular-classics",
            title: "Popular Classics",
            books: [originalBook],
            layout: .classicRow,
            treatment: .framed
        )

        await cache.store([section], for: "default")
        let resolvedSections = await cache.sections(for: "default")
        let cachedSections = try #require(resolvedSections)
        let cachedSection = try #require(cachedSections.first)
        let cachedBook = try #require(cachedSection.books.first)

        #expect(cachedSection.id == "popular-classics")
        #expect(cachedSection.treatment == .framed)
        #expect(cachedBook.stableID == originalBook.stableID)
        #expect(cachedBook.title == "Cached Book")
        #expect(cachedBook.author == "Cached Author")
        #expect(cachedBook.coverURL == originalBook.coverURL)
        #expect(cachedBook.availability?.localFileName == originalBook.availability?.localFileName)
    }

    @MainActor
    @Test func viewModelPaginationAppendsVisibleUniqueBooks() async throws {
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "gutendex.com" {
                let page = Self.queryValue("page", in: url).flatMap(Int.init) ?? 1
                return Self.jsonResponse(for: url, body: Self.gutenbergUniqueShelfResponse(page: page, count: 14))
            }

            if url.host == "openlibrary.org", url.path == "/search.json" {
                return Self.jsonResponse(for: url, body: #"{"docs":[]}"#)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService),
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            shelfSnapshotCache: DiscoverShelfSnapshotCache(directoryURL: Self.temporaryCacheDirectory(named: "ShelfSnapshot")),
            session: session
        )
        let viewModel = DiscoverViewModel(store: temporaryStore(), service: service)
        let initialSection = try #require(viewModel.sections.first { $0.id == "popular-classics" })
        let initialCount = initialSection.books.count

        await viewModel.loadMoreBooksIfNeeded(forSectionID: "popular-classics")
        let updatedSection = try #require(viewModel.sections.first { $0.id == "popular-classics" })

        #expect(updatedSection.books.count > initialCount)
        #expect(Set(updatedSection.books.map(\.stableID)).count == updatedSection.books.count)
        #expect(Set(updatedSection.books.map(\.titleAuthorFingerprint)).count == updatedSection.books.count)
    }

    @MainActor
    @Test func targetShelfPaginationStartsAfterSeededProviderCycle() async throws {
        let requestedPages = DiscoverRequestedPages()
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url.host == "gutendex.com" {
                let page = Self.queryValue("page", in: url).flatMap(Int.init) ?? 1
                await requestedPages.append(page)
                return Self.jsonResponse(for: url, body: Self.gutenbergUniqueShelfResponse(page: page, count: 14))
            }

            if url.host == "openlibrary.org", url.path == "/search.json" {
                return Self.jsonResponse(for: url, body: #"{"docs":[]}"#)
            }

            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService),
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            shelfSnapshotCache: DiscoverShelfSnapshotCache(directoryURL: Self.temporaryCacheDirectory(named: "ShelfSnapshot")),
            session: session
        )
        let viewModel = DiscoverViewModel(store: temporaryStore(), service: service)
        let shelfIDs = ["philosophy-focus", "public-domain-essentials"]
        let initialCounts = Dictionary(
            uniqueKeysWithValues: try shelfIDs.map { shelfID in
                let section = try #require(viewModel.sections.first { $0.id == shelfID })
                return (shelfID, section.books.count)
            }
        )

        for shelfID in shelfIDs {
            await viewModel.loadMoreBooksIfNeeded(forSectionID: shelfID)
        }

        for shelfID in shelfIDs {
            let section = try #require(viewModel.sections.first { $0.id == shelfID })
            #expect(section.books.count > (initialCounts[shelfID] ?? 0))
        }
        #expect(await requestedPages.values == [2, 2])
    }

    @Test func discoverImportedDocumentsRoundTripExternalSourceIDForAddAndReadDeduping() throws {
        let document = ImportedDocument(
            fileName: "meditations.epub",
            displayTitle: "Meditations",
            author: "Marcus Aurelius",
            externalSourceID: "projectGutenberg:2680",
            text: "Focus reading text with enough words to create tokens.",
            sourceType: .epub,
            languageCode: "en"
        )
        let tokens = TextTokenizer().tokenize(document)

        let savedRead = SavedReadMapper.makeSavedRead(from: document, tokens: tokens)
        let roundTrippedDocument = try #require(SavedReadMapper.importedDocument(from: savedRead))

        #expect(savedRead.externalSourceID == "projectGutenberg:2680")
        #expect(roundTrippedDocument.externalSourceID == "projectGutenberg:2680")
        #expect(roundTrippedDocument.displayTitle == "Meditations")
        #expect(roundTrippedDocument.author == "Marcus Aurelius")
    }

    @Test func discoverMetadataCoverWinsOverEPUBPreviewDuringImport() {
        let epubPreviewData = Data("generated-gutenberg-cover".utf8)
        let discoverCoverData = Data("open-library-cover".utf8)
        let document = ImportedDocument(
            fileName: "problems-of-philosophy.epub",
            displayTitle: "The Problems of Philosophy",
            author: "Russell, Bertrand",
            text: "Readable text with enough words for a library item.",
            sourceType: .epub,
            languageCode: "en",
            previewImageData: epubPreviewData
        )
        let book = book(
            id: "gutenberg-5827",
            source: .projectGutenberg,
            sourceID: "5827",
            title: "The Problems of Philosophy",
            author: "Bertrand Russell",
            coverURL: URL(string: "https://covers.openlibrary.org/b/id/12345-L.jpg")
        )

        let enrichedDocument = document.withDiscoverMetadata(from: book, coverData: discoverCoverData)

        #expect(enrichedDocument.displayTitle == "The Problems of Philosophy")
        #expect(enrichedDocument.author == "Bertrand Russell")
        #expect(enrichedDocument.externalSourceID == "projectGutenberg:5827")
        #expect(enrichedDocument.previewImageData == discoverCoverData)
    }

    @Test func discoverMetadataFallsBackToEPUBPreviewWhenCoverFetchFails() {
        let epubPreviewData = Data("existing-epub-cover".utf8)
        let document = ImportedDocument(
            fileName: "problems-of-philosophy.epub",
            displayTitle: "The Problems of Philosophy",
            author: "Bertrand Russell",
            text: "Readable text with enough words for a library item.",
            sourceType: .epub,
            languageCode: "en",
            previewImageData: epubPreviewData
        )
        let book = book(
            id: "gutenberg-5827",
            source: .projectGutenberg,
            sourceID: "5827",
            title: "The Problems of Philosophy",
            author: "Bertrand Russell",
            coverURL: URL(string: "https://covers.openlibrary.org/b/id/12345-L.jpg")
        )

        let enrichedDocument = document.withDiscoverMetadata(from: book, coverData: nil)

        #expect(enrichedDocument.previewImageData == epubPreviewData)
    }

    @MainActor
    @Test func duplicateDiscoverAddUpdatesMissingLibraryMetadataWithoutDuplicating() async throws {
        let coverURL = URL(string: "https://covers.openlibrary.org/b/id/5827-L.jpg")!
        let coverData = try #require(Data(base64Encoded: Self.onePixelPNGBase64))
        let session = Self.mockSession { request in
            let url = try #require(request.url)
            if url == coverURL {
                return Self.dataResponse(for: url, contentType: "image/png", body: coverData)
            }
            return Self.jsonResponse(for: url, statusCode: 404, body: #"{"error":"not found"}"#)
        }
        let archiveService = Self.archiveService(session: session)
        let service = DiscoverService(
            gutenbergService: GutenbergDiscoveryService(session: session),
            openLibraryService: OpenLibraryDiscoveryService(session: session, archiveMetadataService: archiveService),
            archiveMetadataService: archiveService,
            persistentMetadataCache: Self.persistentBookCache(),
            shelfSnapshotCache: DiscoverShelfSnapshotCache(directoryURL: Self.temporaryCacheDirectory(named: "ShelfSnapshot")),
            coverImageCache: DiscoverCoverImageCache(
                networkClient: DiscoverNetworkClient(session: session),
                directoryURL: Self.temporaryCacheDirectory(named: "CoverImage")
            ),
            session: session
        )
        let store = temporaryStore()
        let existingDocument = ImportedDocument(
            fileName: "problems-of-philosophy.epub",
            displayTitle: "The Problems of Philosophy",
            author: nil,
            text: "Readable text with enough words for a library item.",
            sourceType: .epub,
            languageCode: "en"
        )
        store.save(SavedReadMapper.makeSavedRead(from: existingDocument, tokens: TextTokenizer().tokenize(existingDocument)))

        let viewModel = DiscoverViewModel(store: store, service: service)
        let book = book(
            id: "gutenberg-5827",
            source: .projectGutenberg,
            sourceID: "5827",
            title: "The Problems of Philosophy",
            author: "Bertrand Russell",
            coverURL: coverURL
        )

        let outcome = await viewModel.perform(.add, for: book)
        let updatedRead = try #require(store.savedReads.first)

        if case .none = outcome {
            #expect(true)
        } else {
            Issue.record("Duplicate add should not import or open a second read")
        }
        #expect(store.savedReads.count == 1)
        #expect(updatedRead.externalSourceID == "projectGutenberg:5827")
        #expect(updatedRead.author == "Bertrand Russell")
        #expect(updatedRead.thumbnailPath != nil)
    }

    @Test func mergedEnrichesGutenbergDuplicateWorksWithoutReplacingReadableResource() {
        let gutenberg = book(
            id: "gutenberg-1342",
            source: .projectGutenberg,
            sourceID: "1342",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            coverURL: URL(string: "https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg"),
            downloadCount: 20_000
        )
        let openLibrary = book(
            id: "openlibrary-pride",
            source: .openLibrary,
            sourceID: "OL66554W",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            coverURL: URL(string: "https://covers.openlibrary.org/b/id/12345-L.jpg"),
            ratingAverage: 4.4,
            ratingCount: 1_200,
            editionCount: 400
        )

        let merged = DiscoverService.merged([gutenberg, openLibrary])

        #expect(merged.count == 1)
        #expect(merged[0].id == "gutenberg-1342")
        #expect(merged[0].source == .projectGutenberg)
        #expect(merged[0].externalSourceID == "projectGutenberg:1342")
        #expect(merged[0].availability?.localFileName == "pride-and-prejudice.epub")
        #expect(merged[0].coverURL?.absoluteString.contains("-L.jpg") == true)
        #expect(merged[0].ratingAverage == 4.4)
        #expect(merged[0].ratingCount == 1_200)
        #expect(merged[0].editionCount == 400)
    }

    @Test func meditationsKeepsGutenbergResourceWithOpenLibraryCoverAndCleanAuthor() {
        let gutenberg = book(
            id: "gutenberg-2680",
            source: .projectGutenberg,
            sourceID: "2680",
            title: "Meditations",
            author: "Aurelius, Marcus",
            coverURL: URL(string: "https://www.gutenberg.org/cache/epub/2680/pg2680.cover.medium.jpg")
        )
        let openLibrary = book(
            id: "openlibrary-meditations",
            source: .openLibrary,
            sourceID: "OL15358691W",
            title: "Meditations",
            author: "Marcus Aurelius",
            coverURL: URL(string: "https://covers.openlibrary.org/b/id/1516606-L.jpg"),
            ratingAverage: 4.5,
            ratingCount: 1_000,
            editionCount: 300
        )

        let merged = DiscoverService.merged([gutenberg, openLibrary])

        #expect(merged.count == 1)
        #expect(merged[0].id == "gutenberg-2680")
        #expect(merged[0].source == .projectGutenberg)
        #expect(merged[0].author == "Marcus Aurelius")
        #expect(merged[0].coverURL?.absoluteString == "https://covers.openlibrary.org/b/id/1516606-L.jpg")
        #expect(merged[0].availability?.localFileName == "meditations.epub")
    }

    @Test func coverQualityScorePrefersLargeOpenLibraryCoverOverGeneratedTemplate() {
        let enrichedCover = book(
            id: "gutenberg-enriched",
            source: .projectGutenberg,
            sourceID: "2680",
            title: "Meditations",
            coverURL: URL(string: "https://covers.openlibrary.org/b/id/1516606-L.jpg")
        )
        let generatedCover = book(
            id: "gutenberg-generated",
            source: .projectGutenberg,
            sourceID: "1497",
            title: "The Republic",
            coverURL: URL(string: "https://www.gutenberg.org/cache/epub/1497/pg1497.cover.medium.jpg")
        )
        let missingCover = book(
            id: "missing-cover",
            source: .projectGutenberg,
            sourceID: "1656",
            title: "Apology",
            coverURL: nil
        )

        #expect(enrichedCover.coverQualityScore > generatedCover.coverQualityScore)
        #expect(generatedCover.coverQualityScore > missingCover.coverQualityScore)
    }

    @Test func curatedPresentationUsesCoverQualityAsSoftBoostOnly() {
        let relevantGenerated = book(
            id: "relevant-generated",
            source: .projectGutenberg,
            sourceID: "1",
            title: "Relevant Generated",
            coverURL: URL(string: "https://www.gutenberg.org/cache/epub/1/pg1.cover.medium.jpg")
        )
        let nearbyEnriched = book(
            id: "nearby-enriched",
            source: .projectGutenberg,
            sourceID: "2",
            title: "Nearby Enriched",
            coverURL: URL(string: "https://covers.openlibrary.org/b/id/222-L.jpg")
        )
        let relevantMiddle = book(
            id: "relevant-middle",
            source: .projectGutenberg,
            sourceID: "3",
            title: "Relevant Middle",
            coverURL: nil
        )
        let relevantLater = book(
            id: "relevant-later",
            source: .projectGutenberg,
            sourceID: "5",
            title: "Relevant Later",
            coverURL: URL(string: "https://www.gutenberg.org/cache/epub/5/pg5.cover.medium.jpg")
        )
        let farEnriched = book(
            id: "far-enriched",
            source: .projectGutenberg,
            sourceID: "4",
            title: "Far Enriched",
            coverURL: URL(string: "https://covers.openlibrary.org/b/id/444-L.jpg")
        )

        let curated = DiscoverService.curatedPresentation(
            [relevantGenerated, nearbyEnriched, relevantMiddle, relevantLater, farEnriched],
            limit: 5
        )

        #expect(curated.first?.id == "nearby-enriched")
        #expect(curated.firstIndex { $0.id == "far-enriched" }! > curated.firstIndex { $0.id == "relevant-middle" }!)
    }

    @Test func curatedPresentationSeparatesRepeatedCoverTemplatesWhenPossible() {
        let firstGenerated = book(
            id: "gutenberg-1",
            source: .projectGutenberg,
            sourceID: "1",
            title: "Generated One",
            coverURL: URL(string: "https://www.gutenberg.org/cache/epub/1/pg1.cover.medium.jpg")
        )
        let secondGenerated = book(
            id: "gutenberg-2",
            source: .projectGutenberg,
            sourceID: "2",
            title: "Generated Two",
            coverURL: URL(string: "https://www.gutenberg.org/cache/epub/2/pg2.cover.medium.jpg")
        )
        let missingCover = book(
            id: "missing-cover",
            source: .projectGutenberg,
            sourceID: "3",
            title: "Missing Cover",
            coverURL: nil
        )

        let curated = DiscoverService.curatedPresentation(
            [firstGenerated, secondGenerated, missingCover],
            limit: 3
        )

        #expect(curated.count == 3)
        #expect(curated[0].visualClusterKey != curated[1].visualClusterKey)
    }

    @MainActor
    @Test func relatedBooksPrioritizeAustenClassics() {
        let viewModel = DiscoverViewModel(store: temporaryStore())
        let emma = defaultBook(titled: "Emma")

        let titles = viewModel.relatedBooks(for: emma, limit: 6).map(\.title)

        #expect(titles.contains("Pride and Prejudice"))
        #expect(titles.contains("Persuasion"))
        #expect(titles.contains("Sense and Sensibility"))
        #expect(titles.contains("Northanger Abbey"))
    }

    @MainActor
    @Test func relatedBooksKeepPhilosophyTogether() {
        let viewModel = DiscoverViewModel(store: temporaryStore())
        let meditations = defaultBook(titled: "Meditations")

        let titles = viewModel.relatedBooks(for: meditations, limit: 6).map(\.title)

        #expect(titles.contains("The Republic"))
        #expect(titles.contains("Apology"))
        #expect(titles.contains("Beyond Good and Evil"))
        #expect(titles.contains("The Problems of Philosophy"))
    }

    @MainActor
    @Test func relatedBooksKeepShortReadsTogether() {
        let viewModel = DiscoverViewModel(store: temporaryStore())
        let jekyll = defaultBook(titled: "The Strange Case of Dr. Jekyll and Mr. Hyde")

        let titles = viewModel.relatedBooks(for: jekyll, limit: 6).map(\.title)

        #expect(titles.contains("The Yellow Wallpaper"))
        #expect(titles.contains("Metamorphosis"))
        #expect(titles.contains("A Modest Proposal"))
    }

    private func book(
        id: String,
        source: BookSource,
        sourceID: String,
        title: String,
        author: String? = "Author",
        coverURL: URL?,
        downloadCount: Int? = nil,
        ratingAverage: Double? = nil,
        ratingCount: Int? = nil,
        editionCount: Int? = nil
    ) -> DiscoverBook {
        DiscoverBook(
            id: id,
            source: source,
            sourceID: sourceID,
            title: title,
            author: author,
            coverURL: coverURL,
            subjects: ["Fiction"],
            availability: DiscoverAvailability(
                preferredFormat: .epub,
                location: .direct(URL(string: "https://example.com/\(sourceID).epub")!),
                localFileName: "\(title.discoverReadableFileComponent).epub"
            ),
            webURL: nil,
            languageCode: "en",
            pageCount: nil,
            description: nil,
            firstPublishYear: nil,
            downloadCount: downloadCount,
            ratingAverage: ratingAverage,
            ratingCount: ratingCount,
            editionCount: editionCount
        )
    }

    private func defaultBook(titled title: String) -> DiscoverBook {
        let book = DiscoverService.defaultCuratedSections()
            .flatMap(\.books)
            .first { $0.title == title }
        #expect(book != nil)
        return book!
    }

    @MainActor
    private func temporaryStore() -> LocalReadingHistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusReadDiscoverTests-\(UUID().uuidString)", isDirectory: true)
        return LocalReadingHistoryStore(storageDirectory: directory)
    }

    private static func mockSession(
        handler: @escaping @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let sessionID = UUID().uuidString
        DiscoverMockURLProtocolRegistry.shared.set(handler, for: sessionID)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoverMockURLProtocol.self]
        configuration.httpAdditionalHeaders = [
            DiscoverMockURLProtocol.sessionHeader: sessionID
        ]
        return URLSession(configuration: configuration)
    }

    private static func archiveService(session: URLSession) -> InternetArchiveMetadataService {
        InternetArchiveMetadataService(
            networkClient: DiscoverNetworkClient(session: session),
            persistentCache: DiscoverArchiveResourceCache(directoryURL: temporaryCacheDirectory(named: "ArchiveResource"))
        )
    }

    private static func persistentBookCache() -> DiscoverPersistentBookCache {
        DiscoverPersistentBookCache(
            namespace: UUID().uuidString,
            directoryURL: temporaryCacheDirectory(named: "BookMetadata")
        )
    }

    @MainActor
    private static func waitUntil(
        _ condition: @MainActor @escaping () async -> Bool
    ) async throws {
        for _ in 0..<80 {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("Timed out waiting for async condition")
    }

    private static func temporaryCacheDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusReadDiscoverTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private static func jsonResponse(
        for url: URL,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, body.data(using: .utf8)!)
    }

    private static func dataResponse(
        for url: URL,
        statusCode: Int = 200,
        contentType: String,
        body: Data
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        return (response, body)
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private static func gutenbergShelfPage(for url: URL) -> Int {
        if let page = queryValue("page", in: url).flatMap(Int.init) {
            return page
        }
        if queryValue("search", in: url) != nil {
            return 2
        }
        if queryValue("topic", in: url) == "fiction" {
            return 3
        }
        return 1
    }

    private static func gutenbergShelfResponse(page: Int) -> String {
        let books: [(id: Int, title: String, author: String)]
        switch page {
        case 1:
            books = [
                (100, "Duplicate Work", "Same Author"),
                (101, "Unique One", "First Author")
            ]
        default:
            books = [
                (101, "Unique One", "First Author"),
                (102, "Unique Two", "Second Author")
            ]
        }

        let results = books.map { book in
            """
            {
              "id": \(book.id),
              "title": "\(book.title)",
              "authors": [{ "name": "\(book.author)" }],
              "subjects": ["Fiction"],
              "languages": ["en"],
              "download_count": \(book.id),
              "formats": {
                "application/epub+zip": "https://www.gutenberg.org/ebooks/\(book.id).epub.noimages",
                "image/jpeg": "https://www.gutenberg.org/cache/epub/\(book.id)/pg\(book.id).cover.medium.jpg"
              }
            }
            """
        }.joined(separator: ",")

        return #"{"results":["# + results + #"]}"#
    }

    private static func gutenbergUniqueShelfResponse(page: Int, count: Int) -> String {
        let pageOffset = max(page, 1) * 1_000
        let results = (0..<count).map { index in
            let id = pageOffset + index
            return """
            {
              "id": \(id),
              "title": "Paged Unique \(id)",
              "authors": [{ "name": "Page Author \(id)" }],
              "subjects": ["Fiction"],
              "languages": ["en"],
              "download_count": \(id),
              "formats": {
                "application/epub+zip": "https://www.gutenberg.org/ebooks/\(id).epub.noimages",
                "image/jpeg": "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).cover.medium.jpg"
              }
            }
            """
        }.joined(separator: ",")

        return #"{"results":["# + results + #"]}"#
    }

    private static func gutenbergSearchResponse(for query: String) -> String {
        let normalized = query.discoverIdentityComponent
        let book: (id: Int, title: String, author: String)
        switch normalized {
        case "alice":
            book = (11, "Alice's Adventures in Wonderland", "Carroll, Lewis")
        case "emma":
            book = (158, "Emma", "Austen, Jane")
        case "frankenstein":
            book = (84, "Frankenstein", "Shelley, Mary Wollstonecraft")
        case "meditations":
            book = (2680, "Meditations", "Aurelius, Marcus")
        case "odyssey":
            book = (1727, "The Odyssey", "Homer")
        default:
            return #"{"results":[]}"#
        }

        return """
        {
          "results": [
            {
              "id": \(book.id),
              "title": "\(book.title)",
              "authors": [{ "name": "\(book.author)" }],
              "subjects": ["Classic"],
              "languages": ["en"],
              "download_count": 1000,
              "formats": {
                "application/epub+zip": "https://www.gutenberg.org/ebooks/\(book.id).epub.noimages",
                "text/plain; charset=utf-8": "https://www.gutenberg.org/files/\(book.id)/\(book.id)-0.txt",
                "image/jpeg": "https://www.gutenberg.org/cache/epub/\(book.id)/pg\(book.id).cover.medium.jpg"
              }
            }
          ]
        }
        """
    }
}

private actor DiscoverMockCounter {
    private var count = 0

    var value: Int {
        count
    }

    func increment() {
        count += 1
    }

    func incrementAndReturnValue() -> Int {
        count += 1
        return count
    }
}

private actor DiscoverRequestedPages {
    private var pages: [Int] = []

    var values: [Int] {
        pages
    }

    func append(_ page: Int) {
        pages.append(page)
    }
}

private actor DiscoverConcurrentRequestCounter {
    private var activeCount = 0
    private var maximumActiveCount = 0

    var maximumActive: Int {
        maximumActiveCount
    }

    func begin() {
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
    }

    func end() {
        activeCount = max(activeCount - 1, 0)
    }
}

private final class DiscoverMockURLProtocolRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)

    static let shared = DiscoverMockURLProtocolRegistry()

    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]

    func set(_ handler: @escaping Handler, for sessionID: String) {
        lock.lock()
        handlers[sessionID] = handler
        lock.unlock()
    }

    func handler(for sessionID: String) -> Handler? {
        lock.lock()
        let handler = handlers[sessionID]
        lock.unlock()
        return handler
    }
}

private final class DiscoverMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let sessionHeader = "X-FocusRead-Discover-Mock-Session"

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let sessionID = request.value(forHTTPHeaderField: Self.sessionHeader),
              let handler = DiscoverMockURLProtocolRegistry.shared.handler(for: sessionID) else {
            client?.urlProtocol(self, didFailWithError: DiscoverMockURLError.missingHandler)
            return
        }

        Task {
            do {
                let (response, data) = try await handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private enum DiscoverMockURLError: Error {
    case missingHandler
}
