import Foundation

enum BookSource: String, Codable, Sendable {
    case projectGutenberg
    case openLibrary

    var displayName: String {
        switch self {
        case .projectGutenberg:
            "Project Gutenberg"
        case .openLibrary:
            "Open Library"
        }
    }

    var availabilityLabel: String {
        switch self {
        case .projectGutenberg:
            "Public domain"
        case .openLibrary:
            "Public scan"
        }
    }
}

enum DiscoverDownloadFormat: String, Codable, Sendable {
    case epub
    case pdf
    case plainText

    var fileExtension: String {
        switch self {
        case .epub:
            "epub"
        case .pdf:
            "pdf"
        case .plainText:
            "txt"
        }
    }

    var priority: Int {
        switch self {
        case .epub:
            0
        case .pdf:
            1
        case .plainText:
            2
        }
    }
}

enum DiscoverDownloadLocation: Hashable, Codable, Sendable {
    case direct(URL)
    case internetArchive(identifier: String)
}

struct DiscoverAvailability: Hashable, Codable, Sendable {
    let preferredFormat: DiscoverDownloadFormat
    let location: DiscoverDownloadLocation
    let localFileName: String
}

struct DiscoverBook: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let source: BookSource
    let sourceID: String
    let title: String
    let author: String?
    let coverURL: URL?
    let subjects: [String]
    let availability: DiscoverAvailability?
    let webURL: URL?
    let languageCode: String?
    let pageCount: Int?
    let description: String?
    let firstPublishYear: Int?
    let downloadCount: Int?
    let ratingAverage: Double?
    let ratingCount: Int?
    let editionCount: Int?

    var isReadable: Bool {
        availability != nil
    }

    var duplicateFileName: String? {
        availability?.localFileName
    }

    var externalSourceID: String {
        "\(source.rawValue):\(sourceID)"
    }

    var stableID: String {
        externalSourceID
    }

    var titleAuthorFingerprint: String {
        [
            title.discoverCanonicalTitleComponent,
            author?.discoverCanonicalAuthorComponent ?? ""
        ].joined(separator: "|")
    }

    var primaryCategory: String? {
        cleanedSubjects
            .first
    }

    var cleanedSubjects: [String] {
        Array(subjects.compactMap(Self.cleanSubject).prefix(6))
    }

    var cleanLanguageName: String? {
        guard let languageCode, !languageCode.isEmpty else { return nil }
        return Locale.current.localizedString(forLanguageCode: languageCode)
            ?? Locale(identifier: languageCode).localizedString(forLanguageCode: languageCode)
    }

    var shareText: String {
        var lines = [title]
        if let author, !author.isEmpty {
            lines.append("by \(author)")
        }
        lines.append("Ready to read in FocusRead")
        return lines.joined(separator: "\n")
    }

    var storefrontScore: Int {
        var score = 0

        if coverURL != nil {
            score += 18
        } else {
            score -= 34
        }

        score += coverSourceQualityScore

        if let ratingAverage {
            score += Int((min(max(ratingAverage, 0), 5) / 5) * 14)
        }
        if let ratingCount {
            score += min(10, Int(log10(Double(max(ratingCount, 1)))) * 3)
        }
        if let editionCount {
            score += min(8, Int(log10(Double(max(editionCount, 1)))) * 3)
        }
        if let pageCount, pageCount > 0 {
            score += 4
        }
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 4
        }
        if let downloadCount {
            score += min(8, Int(log10(Double(max(downloadCount, 1)))) * 2)
        }

        switch source {
        case .openLibrary:
            score += 14
        case .projectGutenberg:
            score -= isLikelyGeneratedGutenbergCover ? 18 : 8
        }

        return min(max(score, 0), 100)
    }

    var coverQualityScore: Int {
        guard let coverURL else { return 8 }
        let url = coverURL.absoluteString.lowercased()

        if Self.hasWeakCoverURLToken(url) {
            return 6
        }

        if url.contains("covers.openlibrary.org") {
            var score = 50
            if url.contains("-l.") {
                score += 28
            } else if url.contains("-m.") {
                score += 12
            } else if url.contains("-s.") {
                score -= 22
            }
            return Self.clampedCoverQuality(score)
        }

        if isLikelyGeneratedGutenbergCover {
            return 16
        }

        var score = 36
        if url.contains("gutenberg.org/cache/epub") {
            score += 6
        }
        if url.contains("cover") {
            score += 5
        }
        if Self.hasStrongCoverURLToken(url) {
            score += 12
        }
        if Self.hasSmallCoverURLToken(url) {
            score -= 16
        }
        if source == .openLibrary {
            score += 8
        }
        return Self.clampedCoverQuality(score)
    }

    var coverPresentationBoost: Int {
        min(24, coverQualityScore / 3)
    }

    var visualClusterKey: String {
        guard let coverURL else { return "missing-cover" }
        let url = coverURL.absoluteString.lowercased()

        if isLikelyGeneratedGutenbergCover {
            return "gutenberg-generated-template"
        }
        if url.contains("covers.openlibrary.org") {
            return "openlibrary-\(sourceID.stableDiscoverBucket(count: 7))"
        }
        return "\(source.rawValue)-\(coverURL.host ?? "cover")-\(sourceID.stableDiscoverBucket(count: 7))"
    }

    private var coverSourceQualityScore: Int {
        guard let coverURL else { return 0 }
        let url = coverURL.absoluteString.lowercased()

        if url.contains("covers.openlibrary.org") {
            if url.contains("-l.") { return 34 }
            if url.contains("-m.") { return 26 }
            if url.contains("-s.") { return 10 }
            return 22
        }

        if url.contains("gutenberg.org/cache/epub") {
            if isLikelyGeneratedGutenbergCover { return 6 }
            return 12
        }

        return 18
    }

    private var isLikelyGeneratedGutenbergCover: Bool {
        guard source == .projectGutenberg, let coverURL else { return false }
        let url = coverURL.absoluteString.lowercased()
        return url.contains("gutenberg.org/cache/epub")
            && url.contains("/pg")
            && url.contains(".cover.")
    }

    var hasLikelyGeneratedCover: Bool {
        isLikelyGeneratedGutenbergCover
    }

    private static func hasWeakCoverURLToken(_ url: String) -> Bool {
        [
            "placeholder",
            "no-cover",
            "nocover",
            "no_image",
            "noimage",
            "defaultcover",
            "blank"
        ].contains { url.contains($0) }
    }

    private static func hasStrongCoverURLToken(_ url: String) -> Bool {
        url.range(
            of: "(large|original|hires|highres|full|xl|[0-9]{3,4}x[0-9]{3,4})",
            options: .regularExpression
        ) != nil
    }

    private static func hasSmallCoverURLToken(_ url: String) -> Bool {
        url.range(
            of: "(small|thumb|thumbnail|[1-9][0-9]x[1-9][0-9])",
            options: .regularExpression
        ) != nil
    }

    private static func clampedCoverQuality(_ score: Int) -> Int {
        min(max(score, 0), 100)
    }

    private static func cleanSubject(_ subject: String) -> String? {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        let ignoredTokens = [
            "accessible book",
            "protected daisy",
            "bibliography",
            "indexes",
            "project gutenberg",
            "electronic books"
        ]
        guard !ignoredTokens.contains(where: lowercased.contains) else { return nil }

        let components = trimmed
            .components(separatedBy: "--")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let candidate = components.first(where: { !$0.localizedCaseInsensitiveContains("fiction") })
            ?? components.first
            ?? trimmed
        guard candidate.count <= 36 else { return nil }
        return candidate
    }
}

enum DiscoverShelfLayout: String, Codable, Sendable {
    case classicRow
    case compactGrid
    case editorialHero
}

enum DiscoverSectionTreatment: String, Codable, Sendable {
    case framed
    case open
}

struct DiscoverSection: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let books: [DiscoverBook]
    let layout: DiscoverShelfLayout
    let treatment: DiscoverSectionTreatment?

    init(
        id: String,
        title: String,
        books: [DiscoverBook],
        layout: DiscoverShelfLayout = .classicRow,
        treatment: DiscoverSectionTreatment? = nil
    ) {
        self.id = id
        self.title = title
        self.books = books
        self.layout = layout
        self.treatment = treatment
    }
}

extension String {
    var discoverSafeFileComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "book" : collapsed
    }

    var discoverReadableFileComponent: String {
        let folded = folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return folded.discoverSafeFileComponent
    }

    var discoverIdentityComponent: String {
        let folded = folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let normalized = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }.joined()
        return normalized
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var discoverCanonicalTitleComponent: String {
        var value = discoverCleanBookTitle
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        value = value.replacingOccurrences(of: "&", with: " and ")
        return value.discoverIdentityComponent
    }

    var discoverCleanBookTitle: String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "\\[[^\\]]*\\]|\\([^\\)]*\\)", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\b\\d{3,4}\\s*(edition|ed\\.?|printing)?\\b$", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(
            of: "\\b(complete|unabridged|illustrated|annotated|revised|selected|collected)\\s+(edition|works?|texts?)\\b.*$",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        if let separatorRange = value.range(of: "\\s*[:;]\\s*", options: .regularExpression) {
            let prefix = value[..<separatorRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.count >= 3 {
                value = String(prefix)
            }
        }
        value = value.replacingOccurrences(
            of: "\\b(volume|vol|book|part)\\s+[ivxlcdm0-9]+\\b",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        return value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:")))
    }

    var discoverCanonicalAuthorComponent: String {
        discoverCleanAuthorName.discoverIdentityComponent
    }

    var discoverCleanAuthorName: String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "\\([^\\)]*\\)", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\b\\d{3,4}\\s*-\\s*\\d{0,4}\\b", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(
            of: "\\b(editor|ed\\.?|translator|trans\\.?|illustrator|illustrated by|compiler|contributor)\\b\\.?",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:")))

        let parts = value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.range(of: "^\\d", options: .regularExpression) == nil }
        if parts.count >= 2 {
            let familyName = parts[0]
            let givenNames = parts[1...].joined(separator: " ")
            value = "\(givenNames) \(familyName)"
        }

        return value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stableDiscoverBucket(count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash = 5381
        for scalar in unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
        let positiveHash = hash == Int.min ? 0 : abs(hash)
        return positiveHash % count
    }
}
