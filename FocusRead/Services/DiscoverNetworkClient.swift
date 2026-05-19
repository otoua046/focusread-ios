import Foundation
#if DEBUG
import OSLog
#endif

#if DEBUG
private let discoverLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FocusRead", category: "Discover")

func discoverDebugLog(_ message: @autoclosure () -> String) {
    let resolvedMessage = message()
    discoverLogger.debug("\(resolvedMessage, privacy: .public)")
}
#else
func discoverDebugLog(_ message: @autoclosure () -> String) {}
#endif

enum DiscoverServiceError: Error, Equatable, Sendable {
    case unavailable
    case noReadableFormat
    case unreadableBook
}

enum DiscoverNetworkRequestKind: Sendable {
    case metadata
    case enrichment
    case availability
    case image
    case download

    var logName: String {
        switch self {
        case .metadata:
            "metadata"
        case .enrichment:
            "enrichment"
        case .availability:
            "availability"
        case .image:
            "image"
        case .download:
            "download"
        }
    }
}

struct DiscoverNetworkClient: Sendable {
    static let shared = DiscoverNetworkClient()

    private let session: URLSession
    private let metadataLimiter: DiscoverConcurrencyLimiter
    private let imageLimiter: DiscoverConcurrencyLimiter
    private let shelfLimiter: DiscoverKeyedConcurrencyLimiter
    private let cooldowns: DiscoverRequestCooldownStore
    private let metrics: DiscoverNetworkMetrics

    init(
        session: URLSession = .shared,
        metadataMaxConcurrent: Int = 4,
        imageMaxConcurrent: Int = 6,
        cooldownDuration: TimeInterval = 45,
        metrics: DiscoverNetworkMetrics = .shared
    ) {
        self.session = session
        self.metadataLimiter = DiscoverConcurrencyLimiter(limit: metadataMaxConcurrent)
        self.imageLimiter = DiscoverConcurrencyLimiter(limit: imageMaxConcurrent)
        self.shelfLimiter = DiscoverKeyedConcurrencyLimiter(limit: 1)
        self.cooldowns = DiscoverRequestCooldownStore(duration: cooldownDuration)
        self.metrics = metrics
    }

    func data(
        for url: URL,
        kind: DiscoverNetworkRequestKind,
        timeout: TimeInterval
    ) async throws -> Data {
        try await data(for: URLRequest(url: url), kind: kind, timeout: timeout)
    }

    func data(
        for request: URLRequest,
        kind: DiscoverNetworkRequestKind,
        timeout: TimeInterval
    ) async throws -> Data {
        guard let url = request.url else {
            throw DiscoverServiceError.unavailable
        }

        if Self.usesCooldown(kind: kind) {
            try await cooldowns.check(url: url)
        }
        return try await withNetworkPermit(kind: kind, label: Self.logLabel(for: url)) {
            try Task.checkCancellation()
            var request = request
            request.timeoutInterval = timeout
            let timedRequest = request
            let requestNumber = await metrics.recordRequest(kind: kind, url: url)
            DiscoverNetworkLog.request("#\(requestNumber) \(kind.logName) GET \(Self.logLabel(for: url))")

            do {
                let (data, response) = try await Self.withTimeout(seconds: timeout) {
                    try await session.data(for: timedRequest)
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode else {
                    throw DiscoverServiceError.unavailable
                }
                await cooldowns.recordSuccess(url: url)
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Self.usesCooldown(kind: kind), Self.shouldCooldown(for: error) {
                    await cooldowns.recordFailure(url: url)
                }
                throw DiscoverServiceError.unavailable
            }
        }
    }

    func download(
        for request: URLRequest,
        kind: DiscoverNetworkRequestKind = .download,
        timeout: TimeInterval
    ) async throws -> URL {
        guard let url = request.url else {
            throw DiscoverServiceError.unavailable
        }

        if Self.usesCooldown(kind: kind) {
            try await cooldowns.check(url: url)
        }
        return try await withNetworkPermit(kind: kind, label: Self.logLabel(for: url)) {
            try Task.checkCancellation()
            var request = request
            request.timeoutInterval = timeout
            let timedRequest = request
            let requestNumber = await metrics.recordRequest(kind: kind, url: url)
            DiscoverNetworkLog.request("#\(requestNumber) \(kind.logName) DOWNLOAD \(Self.logLabel(for: url))")

            do {
                let (temporaryURL, response) = try await Self.withTimeout(seconds: timeout) {
                    try await session.download(for: timedRequest)
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode else {
                    throw DiscoverServiceError.unavailable
                }
                await cooldowns.recordSuccess(url: url)
                return temporaryURL
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Self.usesCooldown(kind: kind), Self.shouldCooldown(for: error) {
                    await cooldowns.recordFailure(url: url)
                }
                throw DiscoverServiceError.unavailable
            }
        }
    }

    func withShelfPaginationSlot<T: Sendable>(
        shelfID: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let key = shelfID.isEmpty ? "unknown-shelf" : shelfID
        var didLogWait = false
        while !(await shelfLimiter.tryAcquire(key: key)) {
            if !didLogWait {
                DiscoverNetworkLog.throttle("pagination waiting shelf=\(key)")
                didLogWait = true
            }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(35))
        }

        do {
            let result = try await operation()
            await shelfLimiter.release(key: key)
            return result
        } catch {
            await shelfLimiter.release(key: key)
            throw error
        }
    }

    private func withNetworkPermit<T: Sendable>(
        kind: DiscoverNetworkRequestKind,
        label: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard let limiter = limiter(for: kind) else {
            return try await operation()
        }

        var didLogWait = false
        while !(await limiter.tryAcquire()) {
            if !didLogWait {
                DiscoverNetworkLog.throttle("\(kind.logName) waiting \(label)")
                didLogWait = true
            }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(35))
        }

        do {
            let result = try await operation()
            await limiter.release()
            return result
        } catch {
            await limiter.release()
            throw error
        }
    }

    private func limiter(for kind: DiscoverNetworkRequestKind) -> DiscoverConcurrencyLimiter? {
        switch kind {
        case .metadata, .enrichment, .availability:
            metadataLimiter
        case .image:
            imageLimiter
        case .download:
            nil
        }
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
                throw DiscoverNetworkTimeoutError()
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    private static func shouldCooldown(for error: Error) -> Bool {
        if error is DiscoverNetworkTimeoutError {
            return true
        }
        if let serviceError = error as? DiscoverServiceError {
            return serviceError == .unavailable
        }
        guard let urlError = error as? URLError else {
            return false
        }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private static func usesCooldown(kind: DiscoverNetworkRequestKind) -> Bool {
        switch kind {
        case .availability, .download:
            return true
        case .metadata, .enrichment, .image:
            return false
        }
    }

    private static func logLabel(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }
}

enum DiscoverNetworkLog {
    static func request(_ message: @autoclosure () -> String) {
        #if DEBUG
        discoverDebugLog(message())
        #endif
    }

    static func cache(_ message: @autoclosure () -> String) {
        #if DEBUG
        discoverDebugLog(message())
        #endif
    }

    static func throttle(_ message: @autoclosure () -> String) {
        #if DEBUG
        discoverDebugLog(message())
        #endif
    }
}

actor DiscoverNetworkMetrics {
    static let shared = DiscoverNetworkMetrics()

    private var countsByKind: [String: Int] = [:]

    func recordRequest(kind: DiscoverNetworkRequestKind, url: URL) -> Int {
        let key = "\(kind.logName):\(url.host ?? "unknown")"
        let count = countsByKind[key, default: 0] + 1
        countsByKind[key] = count
        return count
    }
}

actor DiscoverPersistentBookCache {
    static let shared = DiscoverPersistentBookCache(namespace: "metadata")

    private struct Entry: Codable {
        let storedAt: Date
        let books: [DiscoverBook]

        func isExpired(maxAge: TimeInterval, now: Date = Date()) -> Bool {
            now.timeIntervalSince(storedAt) > maxAge
        }
    }

    private let namespace: String
    private let directoryURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var memory: [String: Entry] = [:]

    init(
        namespace: String,
        directoryURL: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("DiscoverBookCache", isDirectory: true)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("DiscoverBookCache", isDirectory: true)
    ) {
        self.namespace = namespace
        self.directoryURL = directoryURL.appendingPathComponent(namespace, isDirectory: true)
    }

    func books(for key: String, maxAge: TimeInterval = 60 * 60 * 24 * 7) -> [DiscoverBook]? {
        if let entry = memory[key], !entry.isExpired(maxAge: maxAge) {
            DiscoverNetworkLog.cache("metadata memory hit \(namespace):\(key.discoverCacheLogLabel)")
            return entry.books
        }

        let fileURL = fileURL(for: key)
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? decoder.decode(Entry.self, from: data),
              !entry.isExpired(maxAge: maxAge) else {
            DiscoverNetworkLog.cache("metadata miss \(namespace):\(key.discoverCacheLogLabel)")
            return nil
        }

        memory[key] = entry
        DiscoverNetworkLog.cache("metadata disk hit \(namespace):\(key.discoverCacheLogLabel)")
        return entry.books
    }

    func store(_ books: [DiscoverBook], for key: String) {
        let entry = Entry(storedAt: Date(), books: books)
        memory[key] = entry
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(entry)
            try data.write(to: fileURL(for: key), options: [.atomic])
            DiscoverNetworkLog.cache("metadata store \(namespace):\(key.discoverCacheLogLabel) count=\(books.count)")
        } catch {
            DiscoverNetworkLog.cache("metadata disk skipped \(namespace):\(key.discoverCacheLogLabel)")
        }
    }

    private func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent("\(key.discoverStableHexDigest).json", isDirectory: false)
    }
}

actor DiscoverShelfSnapshotCache {
    static let shared = DiscoverShelfSnapshotCache()

    private struct Entry: Codable {
        let storedAt: Date
        let sections: [SnapshotSection]

        func isExpired(maxAge: TimeInterval, now: Date = Date()) -> Bool {
            now.timeIntervalSince(storedAt) > maxAge
        }
    }

    private struct SnapshotSection: Codable, Sendable {
        let sectionID: String
        let title: String
        let layout: DiscoverShelfLayout
        let treatment: DiscoverSectionTreatment?
        let timestamp: Date
        let books: [SnapshotBook]

        init(section: DiscoverSection, timestamp: Date) {
            self.sectionID = section.id
            self.title = section.title
            self.layout = section.layout
            self.treatment = section.treatment
            self.timestamp = timestamp
            self.books = section.books.map(SnapshotBook.init(book:))
        }

        var section: DiscoverSection {
            DiscoverSection(
                id: sectionID,
                title: title,
                books: books.map(\.book),
                layout: layout,
                treatment: treatment
            )
        }
    }

    private struct SnapshotBook: Codable, Sendable {
        let id: String
        let stableID: String
        let source: BookSource
        let sourceID: String
        let title: String
        let author: String?
        let coverURL: URL?
        let readableResource: DiscoverAvailability?
        let webURL: URL?
        let languageCode: String?
        let pageCount: Int?
        let description: String?
        let firstPublishYear: Int?
        let downloadCount: Int?
        let ratingAverage: Double?
        let ratingCount: Int?
        let editionCount: Int?
        let subjects: [String]

        init(book: DiscoverBook) {
            self.id = book.id
            self.stableID = book.stableID
            self.source = book.source
            self.sourceID = book.sourceID
            self.title = book.title
            self.author = book.author
            self.coverURL = book.coverURL
            self.readableResource = book.availability
            self.webURL = book.webURL
            self.languageCode = book.languageCode
            self.pageCount = book.pageCount
            self.description = book.description
            self.firstPublishYear = book.firstPublishYear
            self.downloadCount = book.downloadCount
            self.ratingAverage = book.ratingAverage
            self.ratingCount = book.ratingCount
            self.editionCount = book.editionCount
            self.subjects = book.subjects
        }

        var book: DiscoverBook {
            DiscoverBook(
                id: id,
                source: source,
                sourceID: sourceID,
                title: title,
                author: author,
                coverURL: coverURL,
                subjects: subjects,
                availability: readableResource,
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

    private let directoryURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var memory: [String: Entry] = [:]

    init(
        directoryURL: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("DiscoverShelfSnapshotCache", isDirectory: true)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("DiscoverShelfSnapshotCache", isDirectory: true)
    ) {
        self.directoryURL = directoryURL
    }

    func sections(for key: String, maxAge: TimeInterval = 60 * 60 * 24 * 3) -> [DiscoverSection]? {
        if let entry = memory[key], !entry.isExpired(maxAge: maxAge) {
            return nonEmptySections(from: entry)
        }

        let fileURL = fileURL(for: key)
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? decoder.decode(Entry.self, from: data),
              !entry.isExpired(maxAge: maxAge) else {
            return nil
        }

        memory[key] = entry
        return nonEmptySections(from: entry)
    }

    func store(_ sections: [DiscoverSection], for key: String) {
        let timestamp = Date()
        let snapshotSections = sections
            .filter { !$0.books.isEmpty }
            .map { SnapshotSection(section: $0, timestamp: timestamp) }
        guard !snapshotSections.isEmpty else { return }

        let entry = Entry(storedAt: timestamp, sections: snapshotSections)
        memory[key] = entry

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(entry)
            try data.write(to: fileURL(for: key), options: [.atomic])
        } catch {
            discoverDebugLog("Discover shelf snapshot store skipped")
        }
    }

    private func nonEmptySections(from entry: Entry) -> [DiscoverSection]? {
        let sections = entry.sections
            .map(\.section)
            .filter { !$0.books.isEmpty }
        return sections.isEmpty ? nil : sections
    }

    private func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent("\(key.discoverStableHexDigest).json", isDirectory: false)
    }
}

actor DiscoverArchiveResourceCache {
    static let shared = DiscoverArchiveResourceCache()

    private struct Entry: Codable {
        let storedAt: Date
        let resource: DiscoverArchiveResource

        func isExpired(maxAge: TimeInterval, now: Date = Date()) -> Bool {
            now.timeIntervalSince(storedAt) > maxAge
        }
    }

    private let directoryURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var memory: [String: Entry] = [:]

    init(
        directoryURL: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("DiscoverArchiveResourceCache", isDirectory: true)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("DiscoverArchiveResourceCache", isDirectory: true)
    ) {
        self.directoryURL = directoryURL
    }

    func resource(for identifier: String, maxAge: TimeInterval = 60 * 60 * 24 * 30) -> DiscoverArchiveResource? {
        let key = identifier.discoverSafeFileComponent
        if let entry = memory[key], !entry.isExpired(maxAge: maxAge) {
            DiscoverNetworkLog.cache("availability memory hit \(key)")
            return entry.resource
        }

        let fileURL = fileURL(for: key)
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? decoder.decode(Entry.self, from: data),
              !entry.isExpired(maxAge: maxAge) else {
            DiscoverNetworkLog.cache("availability miss \(key)")
            return nil
        }

        memory[key] = entry
        DiscoverNetworkLog.cache("availability disk hit \(key)")
        return entry.resource
    }

    func store(_ resource: DiscoverArchiveResource, for identifier: String) {
        let key = identifier.discoverSafeFileComponent
        let entry = Entry(storedAt: Date(), resource: resource)
        memory[key] = entry
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(entry)
            try data.write(to: fileURL(for: key), options: [.atomic])
            DiscoverNetworkLog.cache("availability store \(key)")
        } catch {
            DiscoverNetworkLog.cache("availability disk skipped \(key)")
        }
    }

    private func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent("\(key.discoverStableHexDigest).json", isDirectory: false)
    }
}

actor DiscoverCoverImageCache {
    static let shared = DiscoverCoverImageCache()

    private let cache = NSCache<NSURL, NSData>()
    private let networkClient: DiscoverNetworkClient
    private let directoryURL: URL

    init(
        networkClient: DiscoverNetworkClient = .shared,
        directoryURL: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("DiscoverCoverImageCache", isDirectory: true)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("DiscoverCoverImageCache", isDirectory: true)
    ) {
        self.networkClient = networkClient
        self.directoryURL = directoryURL
        cache.countLimit = 240
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func imageData(for url: URL) async -> Data? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            DiscoverNetworkLog.cache("cover memory hit \(DiscoverNetworkClientLogLabel.url(url))")
            return cached as Data
        }

        let fileURL = fileURL(for: url)
        if let data = try? Data(contentsOf: fileURL) {
            cache.setObject(data as NSData, forKey: key, cost: data.count)
            DiscoverNetworkLog.cache("cover disk hit \(DiscoverNetworkClientLogLabel.url(url))")
            return data
        }

        DiscoverNetworkLog.cache("cover miss \(DiscoverNetworkClientLogLabel.url(url))")
        do {
            let data = try await networkClient.data(for: url, kind: .image, timeout: 8)
            cache.setObject(data as NSData, forKey: key, cost: data.count)
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: [.atomic])
            return data
        } catch is CancellationError {
            DiscoverNetworkLog.throttle("cover cancelled \(DiscoverNetworkClientLogLabel.url(url))")
            return nil
        } catch {
            return nil
        }
    }

    private func fileURL(for url: URL) -> URL {
        directoryURL.appendingPathComponent("\(url.absoluteString.discoverStableHexDigest).cover", isDirectory: false)
    }
}

private actor DiscoverConcurrencyLimiter {
    private let limit: Int
    private var activeCount = 0

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func tryAcquire() -> Bool {
        guard activeCount < limit else {
            return false
        }
        activeCount += 1
        return true
    }

    func release() {
        activeCount = max(activeCount - 1, 0)
    }
}

private actor DiscoverKeyedConcurrencyLimiter {
    private let limit: Int
    private var activeCounts: [String: Int] = [:]

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func tryAcquire(key: String) -> Bool {
        let activeCount = activeCounts[key, default: 0]
        guard activeCount < limit else {
            return false
        }
        activeCounts[key] = activeCount + 1
        return true
    }

    func release(key: String) {
        let activeCount = activeCounts[key, default: 0]
        if activeCount <= 1 {
            activeCounts.removeValue(forKey: key)
        } else {
            activeCounts[key] = activeCount - 1
        }
    }
}

private actor DiscoverRequestCooldownStore {
    private let duration: TimeInterval
    private var retryAfterByURL: [URL: Date] = [:]

    init(duration: TimeInterval) {
        self.duration = max(duration, 0)
    }

    func check(url: URL) throws {
        guard let retryAfter = retryAfterByURL[url] else {
            return
        }
        if retryAfter > Date() {
            DiscoverNetworkLog.throttle("cooldown \(DiscoverNetworkClientLogLabel.url(url))")
            throw DiscoverServiceError.unavailable
        }
        retryAfterByURL.removeValue(forKey: url)
    }

    func recordFailure(url: URL) {
        retryAfterByURL[url] = Date().addingTimeInterval(duration)
        DiscoverNetworkLog.throttle("cooldown set \(DiscoverNetworkClientLogLabel.url(url))")
    }

    func recordSuccess(url: URL) {
        retryAfterByURL.removeValue(forKey: url)
    }
}

private enum DiscoverNetworkClientLogLabel {
    static func url(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }
}

private struct DiscoverNetworkTimeoutError: Error {}

private extension String {
    var discoverStableHexDigest: String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    var discoverCacheLogLabel: String {
        let value = replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.count <= 80 ? value : String(value.prefix(77)) + "..."
    }
}
