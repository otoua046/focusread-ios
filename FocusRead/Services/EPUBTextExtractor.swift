import Foundation
import UIKit
import ZIPFoundation

struct EPUBTextExtractor: DocumentTextExtractor {
    func extractText(
        from file: ImportedFile,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument {
        await progress(DocumentImportProgress(
            message: "Opening EPUB...",
            completedUnitCount: nil,
            totalUnitCount: nil
        ))

        do {
            let archive = try Archive(url: file.localURL, accessMode: .read)
            let containerData = try data(for: "META-INF/container.xml", in: archive)
            let opfPath = try ContainerXMLParser.parse(containerData)
            let opfData = try data(for: opfPath, in: archive)
            let package = try EPUBPackageParser.parse(opfData, opfPath: opfPath)
            let previewImageData = coverPreviewData(for: package, archive: archive)

            let spineItems = package.readableSpineItems()
            guard !spineItems.isEmpty else {
                throw DocumentImportError.epubContentsNotFound
            }

            let navigationEntries = EPUBNavigationParser.parse(
                package: package,
                archive: archive,
                dataProvider: { path in try? data(for: path, in: archive) }
            )

            var documents: [EPUBContentDocument] = []
            for (index, item) in spineItems.enumerated() {
                try Task.checkCancellation()
                await progress(DocumentImportProgress(
                    message: "Extracting EPUB section \(index + 1) of \(spineItems.count)...",
                    completedUnitCount: nil,
                    totalUnitCount: nil
                ))

                guard let chapterData = try? data(for: item.path, in: archive) else {
                    continue
                }

                let parseResult = EPUBXHTMLParser.parse(chapterData)
                let document = EPUBContentDocument(
                    spineItem: item,
                    blocks: parseResult.blocks,
                    linkDensity: parseResult.linkDensity
                )

                guard !EPUBStructureBuilder.shouldSkip(document) else {
                    continue
                }

                documents.append(document)
            }

            let sections = EPUBStructureBuilder.sections(
                from: documents,
                navigationEntries: navigationEntries
            )
            let text = sections.map(\.text).joined(separator: "\n\n").focusReadNormalizedDocumentText
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentImportError.epubNoReadableText
            }

            return ImportedDocument(
                fileName: file.fileName,
                displayTitle: package.metadataTitle,
                author: package.metadataAuthor,
                sourceType: .epub,
                sections: sections,
                previewImageData: previewImageData
            )
        } catch let error as DocumentImportError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DocumentImportError.epubExtractionFailed
        }
    }

    private func data(for path: String, in archive: Archive) throws -> Data {
        for candidate in path.archivePathCandidates {
            guard let entry = archive[candidate] else {
                continue
            }

            var data = Data()
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            return data
        }

        throw DocumentImportError.epubContentsNotFound
    }

    private func coverPreviewData(for package: EPUBPackage, archive: Archive) -> Data? {
        if let coverItemID = package.coverItemID,
           let coverItem = package.manifest[coverItemID],
           coverItem.isImage {
            let path = resolveArchivePath(baseDirectory: package.opfDirectory, href: coverItem.href)
            if let data = try? data(for: path, in: archive),
               UIImage(data: data) != nil {
                return data
            }
        }

        if let coverItem = package.manifest.values.first(where: { $0.isCoverImage }) {
            let path = resolveArchivePath(baseDirectory: package.opfDirectory, href: coverItem.href)
            if let data = try? data(for: path, in: archive),
               UIImage(data: data) != nil {
                return data
            }
        }

        return nil
    }
}

private enum EPUBStructureBuilder {
    private static let fallbackChunkWordCount = 3_000
    private static let minimumNavigationSectionWordCount = 80
    private static let maximumSaneSectionWordCount = 9_000

    static func shouldSkip(_ document: EPUBContentDocument) -> Bool {
        guard document.wordCount >= 8 else {
            return true
        }

        let titleText = [
            document.firstHeadingTitle,
            document.spineItem.manifestItem.title,
            document.filenameTitle
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let combined = [
            document.spineItem.path.lowercased(),
            document.spineItem.manifestItem.id.lowercased(),
            document.spineItem.manifestItem.properties.lowercased(),
            titleText
        ].joined(separator: " ")

        if combined.contains("cover") {
            return true
        }

        if combined.contains("toc") || combined.contains("contents") || combined.contains("nav") {
            return document.wordCount < 500 || document.linkDensity > 0.35
        }

        if combined.contains("titlepage") || combined.contains("title page") {
            return document.wordCount < 120
        }

        if isAdministrativeTitle(titleText) || isAdministrativePath(document.spineItem.path) {
            return document.wordCount < 500
        }

        if document.linkDensity > 0.55 && document.wordCount < 800 {
            return true
        }

        return document.wordCount < 20 && document.bestDeterministicTitle == nil
    }

    static func sections(
        from documents: [EPUBContentDocument],
        navigationEntries: [EPUBNavigationEntry]
    ) -> [ImportedDocumentSection] {
        guard !documents.isEmpty else {
            return []
        }

        let placedBlocks = placedBlocks(from: documents)
        guard !placedBlocks.isEmpty else {
            return []
        }

        let documentByPath = Dictionary(uniqueKeysWithValues: documents.map { ($0.spineItem.path, $0) })
        let quality = EPUBStructureQuality.score(
            navigationEntries: navigationEntries,
            documents: documents,
            placedBlocks: placedBlocks
        )

        var candidates: [EPUBBoundaryCandidate] = []
        if quality.band != .low {
            candidates = navigationBoundaryCandidates(
                navigationEntries,
                documentByPath: documentByPath,
                placedBlocks: placedBlocks
            )
        }

        if candidates.isEmpty {
            candidates = headingBoundaryCandidates(documents, placedBlocks: placedBlocks)
        }

        if candidates.isEmpty {
            candidates = spineBoundaryCandidates(documents, placedBlocks: placedBlocks)
        }

        if candidates.count <= 1, placedBlocks.reduce(0, { $0 + $1.block.wordCount }) > maximumSaneSectionWordCount {
            candidates = chunkBoundaryCandidates(placedBlocks)
        }

        if candidates.first?.globalBlockIndex != placedBlocks[0].globalBlockIndex {
            candidates.insert(EPUBBoundaryCandidate(
                globalBlockIndex: placedBlocks[0].globalBlockIndex,
                title: documents.first?.bestDeterministicTitle ?? "Section 1",
                level: nil,
                role: documents.first.map { role(for: $0.bestDeterministicTitle, path: $0.spineItem.path) } ?? .body,
                source: .spine
            ), at: 0)
        }

        let normalizedCandidates = normalizedBoundaryCandidates(
            candidates,
            placedBlocks: placedBlocks
        )

        return buildSections(
            from: placedBlocks,
            candidates: normalizedCandidates,
            structureQuality: quality
        )
    }

    private static func placedBlocks(from documents: [EPUBContentDocument]) -> [EPUBPlacedBlock] {
        var placedBlocks: [EPUBPlacedBlock] = []
        var nextGlobalBlockIndex = 0

        for document in documents {
            for block in document.blocks where block.wordCount > 0 {
                placedBlocks.append(EPUBPlacedBlock(
                    globalBlockIndex: nextGlobalBlockIndex,
                    document: document,
                    block: block
                ))
                nextGlobalBlockIndex += 1
            }
        }

        return placedBlocks
    }

    private static func navigationBoundaryCandidates(
        _ entries: [EPUBNavigationEntry],
        documentByPath: [String: EPUBContentDocument],
        placedBlocks: [EPUBPlacedBlock]
    ) -> [EPUBBoundaryCandidate] {
        guard !entries.isEmpty else { return [] }

        var output: [EPUBBoundaryCandidate] = []
        for entry in entries {
            guard let document = documentByPath[entry.path] else {
                continue
            }

            let level = entry.level
            if level > 2, document.wordCount < maximumSaneSectionWordCount {
                continue
            }

            guard let blockIndex = blockIndex(for: entry, in: document, placedBlocks: placedBlocks) else {
                continue
            }

            let documentStartIndex = firstBlockIndex(for: document, in: placedBlocks) ?? blockIndex
            let title = cleanedNavigationTitle(entry.title)
                ?? document.headingTitle(near: blockIndex - documentStartIndex)
                ?? document.bestDeterministicTitle
                ?? "Section \(output.count + 1)"

            output.append(EPUBBoundaryCandidate(
                globalBlockIndex: blockIndex,
                title: title,
                level: level,
                role: role(for: title, path: document.spineItem.path),
                source: .navigation
            ))
        }

        return output
    }

    private static func headingBoundaryCandidates(
        _ documents: [EPUBContentDocument],
        placedBlocks: [EPUBPlacedBlock]
    ) -> [EPUBBoundaryCandidate] {
        var output: [EPUBBoundaryCandidate] = []
        for document in documents {
            for block in document.blocks {
                guard let headingLevel = block.headingLevel,
                      headingLevel <= 2,
                      let title = cleanedNavigationTitle(block.headingText),
                      let globalIndex = globalBlockIndex(for: document, localBlockIndex: block.index, placedBlocks: placedBlocks) else {
                    continue
                }

                output.append(EPUBBoundaryCandidate(
                    globalBlockIndex: globalIndex,
                    title: title,
                    level: headingLevel,
                    role: role(for: title, path: document.spineItem.path),
                    source: .heading
                ))
            }
        }

        return output
    }

    private static func spineBoundaryCandidates(
        _ documents: [EPUBContentDocument],
        placedBlocks: [EPUBPlacedBlock]
    ) -> [EPUBBoundaryCandidate] {
        documents.compactMap { document in
            guard let globalIndex = firstBlockIndex(for: document, in: placedBlocks) else {
                return nil
            }

            let title = document.bestDeterministicTitle ?? "Section \(document.spineItem.spineIndex + 1)"
            return EPUBBoundaryCandidate(
                globalBlockIndex: globalIndex,
                title: title,
                level: nil,
                role: role(for: title, path: document.spineItem.path),
                source: .spine
            )
        }
    }

    private static func chunkBoundaryCandidates(_ placedBlocks: [EPUBPlacedBlock]) -> [EPUBBoundaryCandidate] {
        var output: [EPUBBoundaryCandidate] = []
        var pendingWords = 0

        for placedBlock in placedBlocks {
            if output.isEmpty || pendingWords >= fallbackChunkWordCount {
                output.append(EPUBBoundaryCandidate(
                    globalBlockIndex: placedBlock.globalBlockIndex,
                    title: placedBlock.document.bestDeterministicTitle ?? "Section \(output.count + 1)",
                    level: nil,
                    role: .body,
                    source: .chunk
                ))
                pendingWords = 0
            }

            pendingWords += placedBlock.block.wordCount
        }

        return output
    }

    private static func normalizedBoundaryCandidates(
        _ candidates: [EPUBBoundaryCandidate],
        placedBlocks: [EPUBPlacedBlock]
    ) -> [EPUBBoundaryCandidate] {
        let validBlockIndices = Set(placedBlocks.map(\.globalBlockIndex))
        var byIndex: [Int: EPUBBoundaryCandidate] = [:]

        for candidate in candidates.sorted(by: { lhs, rhs in
            if lhs.globalBlockIndex == rhs.globalBlockIndex {
                return lhs.priority > rhs.priority
            }
            return lhs.globalBlockIndex < rhs.globalBlockIndex
        }) where validBlockIndices.contains(candidate.globalBlockIndex) {
            if let existing = byIndex[candidate.globalBlockIndex] {
                byIndex[candidate.globalBlockIndex] = mergedBoundary(existing, with: candidate)
            } else {
                byIndex[candidate.globalBlockIndex] = candidate
            }
        }

        var sorted = byIndex.values.sorted { $0.globalBlockIndex < $1.globalBlockIndex }
        sorted = coalescingParentPlaceholders(sorted, placedBlocks: placedBlocks)
        return sorted
    }

    private static func mergedBoundary(
        _ existing: EPUBBoundaryCandidate,
        with candidate: EPUBBoundaryCandidate
    ) -> EPUBBoundaryCandidate {
        if candidate.priority > existing.priority {
            return candidate
        }

        if isPlaceholderTitle(existing.title), !isPlaceholderTitle(candidate.title) {
            return EPUBBoundaryCandidate(
                globalBlockIndex: existing.globalBlockIndex,
                title: candidate.title,
                level: min(existing.level ?? candidate.level ?? 1, candidate.level ?? existing.level ?? 1),
                role: candidate.role,
                source: existing.source
            )
        }

        return existing
    }

    private static func coalescingParentPlaceholders(
        _ candidates: [EPUBBoundaryCandidate],
        placedBlocks: [EPUBPlacedBlock]
    ) -> [EPUBBoundaryCandidate] {
        guard candidates.count > 1 else { return candidates }

        var output: [EPUBBoundaryCandidate] = []
        var index = 0
        while index < candidates.count {
            let current = candidates[index]
            if index + 1 < candidates.count {
                let next = candidates[index + 1]
                let distance = wordsBetween(
                    startGlobalBlockIndex: current.globalBlockIndex,
                    endGlobalBlockIndex: next.globalBlockIndex,
                    placedBlocks: placedBlocks
                )

                if current.source == .navigation,
                   next.source == .navigation,
                   (next.level ?? 1) > (current.level ?? 1),
                   isPlaceholderTitle(current.title),
                   distance <= minimumNavigationSectionWordCount {
                    output.append(EPUBBoundaryCandidate(
                        globalBlockIndex: current.globalBlockIndex,
                        title: next.title,
                        level: current.level,
                        role: role(for: next.title, path: blockPath(at: current.globalBlockIndex, placedBlocks: placedBlocks)),
                        source: .navigation
                    ))
                    index += 2
                    continue
                }
            }

            output.append(current)
            index += 1
        }

        return output
    }

    private static func buildSections(
        from placedBlocks: [EPUBPlacedBlock],
        candidates: [EPUBBoundaryCandidate],
        structureQuality: EPUBStructureQuality
    ) -> [ImportedDocumentSection] {
        guard !candidates.isEmpty else { return [] }

        var sections: [ImportedDocumentSection] = []
        var nextWordIndex = 0

        for (candidateOffset, candidate) in candidates.enumerated() {
            let startIndex = candidate.globalBlockIndex
            let endIndex = candidateOffset + 1 < candidates.count
                ? candidates[candidateOffset + 1].globalBlockIndex
                : (placedBlocks.last?.globalBlockIndex ?? startIndex) + 1

            let sectionBlocks = placedBlocks.filter {
                $0.globalBlockIndex >= startIndex && $0.globalBlockIndex < endIndex
            }
            let text = sectionBlocks.map(\.block.text)
                .joined(separator: "\n\n")
                .focusReadNormalizedDocumentText
            let wordCount = wordCount(text)
            guard wordCount > 0 else {
                continue
            }

            let wordRange = nextWordIndex..<(nextWordIndex + wordCount)
            nextWordIndex += wordCount

            let title = cleanedNavigationTitle(candidate.title)
                ?? sectionBlocks.first?.document.bestDeterministicTitle
                ?? "Section \(sections.count + 1)"

            sections.append(ImportedDocumentSection(
                index: sections.count,
                text: text,
                pageNumber: nil,
                chapterNumber: sections.count + 1,
                chapterTitle: title,
                wordRange: wordRange,
                epubNavigationLevel: candidate.level,
                epubSectionRole: candidate.role,
                epubStructureSource: candidate.source,
                epubStructureConfidence: structureQuality.score
            ))
        }

        return sections
    }

    private static func blockIndex(
        for entry: EPUBNavigationEntry,
        in document: EPUBContentDocument,
        placedBlocks: [EPUBPlacedBlock]
    ) -> Int? {
        let localBlockIndex: Int
        if let fragment = entry.fragment?.removingPercentEncoding, !fragment.isEmpty,
           let anchoredBlock = document.blocks.first(where: { $0.anchorIDs.contains(fragment) }) {
            localBlockIndex = anchoredBlock.index
        } else {
            localBlockIndex = document.blocks.first?.index ?? 0
        }

        return globalBlockIndex(for: document, localBlockIndex: localBlockIndex, placedBlocks: placedBlocks)
    }

    private static func firstBlockIndex(
        for document: EPUBContentDocument,
        in placedBlocks: [EPUBPlacedBlock]
    ) -> Int? {
        placedBlocks.first { $0.document.spineItem.path == document.spineItem.path }?.globalBlockIndex
    }

    private static func globalBlockIndex(
        for document: EPUBContentDocument,
        localBlockIndex: Int,
        placedBlocks: [EPUBPlacedBlock]
    ) -> Int? {
        placedBlocks.first {
            $0.document.spineItem.path == document.spineItem.path && $0.block.index == localBlockIndex
        }?.globalBlockIndex
    }

    private static func wordsBetween(
        startGlobalBlockIndex: Int,
        endGlobalBlockIndex: Int,
        placedBlocks: [EPUBPlacedBlock]
    ) -> Int {
        placedBlocks
            .filter { $0.globalBlockIndex >= startGlobalBlockIndex && $0.globalBlockIndex < endGlobalBlockIndex }
            .reduce(0) { $0 + $1.block.wordCount }
    }

    private static func blockPath(at globalBlockIndex: Int, placedBlocks: [EPUBPlacedBlock]) -> String {
        placedBlocks.first { $0.globalBlockIndex == globalBlockIndex }?.document.spineItem.path ?? ""
    }

    static func cleanedNavigationTitle(_ title: String?) -> String? {
        guard var title else { return nil }
        title = title
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`")))

        guard !title.isEmpty else { return nil }

        if title.count > 80 {
            title = String(title.prefix(77)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }

        return title
    }

    static func cleanedFilenameTitle(_ title: String?) -> String? {
        guard var title else { return nil }
        title = title.components(separatedBy: "#").first ?? title
        title = title.components(separatedBy: "/").last ?? title
        title = (title as NSString).deletingPathExtension
        title = title
            .replacingOccurrences(of: #"([A-Za-z])(\d)"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d)([A-Za-z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"[_\-.]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`")))

        guard !title.isEmpty, title.count <= 80 else { return nil }

        let lower = title.lowercased()
        if lower.range(of: #"^id\s+id\s+\d+$"#, options: .regularExpression) != nil {
            return nil
        }
        if lower.range(of: #"^(x?html|body|content|section|chapter)\s*\d*$"#, options: .regularExpression) != nil {
            return nil
        }
        if isAdministrativeTitle(lower) {
            return nil
        }

        return title.localizedCapitalized
    }

    private static func role(for title: String?, path: String) -> EPUBSectionRole {
        let lower = [title?.lowercased(), path.lowercased()]
            .compactMap { $0 }
            .joined(separator: " ")

        if lower.contains("appendix") {
            return .appendix
        }
        if lower.contains("bibliography") || lower.contains("notes") || lower.contains("index") {
            return .reference
        }
        if lower.contains("acknowledg") || lower.contains("copyright") || lower.contains("colophon") {
            return .backMatter
        }
        if lower.contains("preface") || lower.contains("introduction") || lower.contains("prologue") || lower.contains("foreword") {
            return .frontMatter
        }
        if lower.range(of: #"(^|\b)part\b"#, options: .regularExpression) != nil {
            return .part
        }
        if lower.range(of: #"(^|\b)(chapter|ch\.?)\s*([ivxlcdm]+|\d+)\b"#, options: .regularExpression) != nil ||
            lower.range(of: #"(^|\b)[ivxlcdm]{1,8}\b"#, options: .regularExpression) != nil ||
            lower.range(of: #"(^|\b)\d{1,3}\b"#, options: .regularExpression) != nil {
            return .chapter
        }

        return .body
    }

    private static func isPlaceholderTitle(_ title: String) -> Bool {
        let lower = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.range(of: #"^(chapter\s*)?\d{1,4}$"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"^[ivxlcdm]{1,8}$"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"^id\s+id\s+\d+$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func isAdministrativePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("copyright") ||
            lower.contains("uncopyright") ||
            lower.contains("colophon") ||
            lower.contains("imprint")
    }

    private static func isAdministrativeTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("copyright") ||
            lower.contains("uncopyright") ||
            lower.contains("colophon") ||
            lower.contains("imprint")
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

private struct EPUBStructureQuality {
    enum Band {
        case high
        case medium
        case low
    }

    let score: Double

    var band: Band {
        if score >= 0.80 {
            return .high
        }
        if score >= 0.55 {
            return .medium
        }
        return .low
    }

    static func score(
        navigationEntries: [EPUBNavigationEntry],
        documents: [EPUBContentDocument],
        placedBlocks: [EPUBPlacedBlock]
    ) -> EPUBStructureQuality {
        let readablePaths = Set(documents.map(\.spineItem.path))
        let validNavigationEntries = navigationEntries.filter { readablePaths.contains($0.path) }
        let linkValidity = navigationEntries.isEmpty ? 0 : Double(validNavigationEntries.count) / Double(navigationEntries.count)
        let coverage = documents.isEmpty ? 0 : Double(Set(validNavigationEntries.map(\.path)).count) / Double(documents.count)

        let pathOrder = Dictionary(uniqueKeysWithValues: documents.enumerated().map { ($0.element.spineItem.path, $0.offset) })
        let orderValues = validNavigationEntries.compactMap { pathOrder[$0.path] }
        let inversions = zip(orderValues, orderValues.dropFirst()).filter { $1 < $0 }.count
        let orderScore = orderValues.count <= 1
            ? (validNavigationEntries.isEmpty ? 0 : 1)
            : max(0, 1 - (Double(inversions) / Double(orderValues.count - 1)))

        let headingCoverage = documents.isEmpty
            ? 0
            : Double(documents.filter { $0.firstHeadingTitle != nil }.count) / Double(documents.count)

        let proposedSections = max(1, validNavigationEntries.isEmpty ? documents.count : validNavigationEntries.count)
        let totalWordCount = placedBlocks.reduce(0) { $0 + $1.block.wordCount }
        let averageWords = Double(totalWordCount) / Double(proposedSections)
        let sectionSizeSanity = averageWords >= 250 && averageWords <= 9_000 ? 1.0 : 0.0

        let score = (0.35 * linkValidity) +
            (0.25 * min(coverage, 1)) +
            (0.20 * orderScore) +
            (0.10 * headingCoverage) +
            (0.10 * sectionSizeSanity)

        return EPUBStructureQuality(score: min(max(score, 0), 1))
    }
}

private struct EPUBBoundaryCandidate {
    let globalBlockIndex: Int
    let title: String
    let level: Int?
    let role: EPUBSectionRole
    let source: EPUBStructureSource

    var priority: Int {
        switch source {
        case .navigation:
            return 4
        case .heading:
            return 3
        case .spine:
            return 2
        case .chunk:
            return 1
        }
    }
}

private struct EPUBPlacedBlock {
    let globalBlockIndex: Int
    let document: EPUBContentDocument
    let block: EPUBTextBlock
}

private struct EPUBPackage {
    let opfPath: String
    let opfDirectory: String
    let metadataTitle: String?
    let metadataAuthor: String?
    let coverItemID: String?
    let manifest: [String: ManifestItem]
    let spine: [String]
    let spineTOCID: String?

    func readableSpineItems() -> [EPUBSpineItem] {
        spine.enumerated().compactMap { spineIndex, manifestID -> EPUBSpineItem? in
            guard let manifestItem = manifest[manifestID],
                  manifestItem.isReadableContent else {
                return nil
            }

            return EPUBSpineItem(
                spineIndex: spineIndex,
                path: resolveArchivePath(baseDirectory: opfDirectory, href: manifestItem.href),
                manifestItem: manifestItem
            )
        }
    }
}

private struct ManifestItem {
    let id: String
    let href: String
    let mediaType: String
    let properties: String
    let title: String?

    var isReadableContent: Bool {
        let normalizedMediaType = mediaType.lowercased()
        guard normalizedMediaType == "application/xhtml+xml" ||
              normalizedMediaType == "text/html" else {
            return false
        }

        return !propertyValues.contains("nav")
    }

    var isNavigationDocument: Bool {
        propertyValues.contains("nav")
    }

    var isCoverImage: Bool {
        propertyValues.contains("cover-image")
    }

    var isImage: Bool {
        mediaType.lowercased().hasPrefix("image/")
    }

    var isNCX: Bool {
        mediaType.lowercased() == "application/x-dtbncx+xml"
    }

    private var propertyValues: Set<String> {
        Set(properties
            .lowercased()
            .split { $0 == " " || $0 == "\t" || $0 == "\n" }
            .map(String.init))
    }
}

private struct EPUBSpineItem {
    let spineIndex: Int
    let path: String
    let manifestItem: ManifestItem
}

private struct EPUBNavigationEntry {
    let title: String
    let href: String
    let path: String
    let fragment: String?
    let level: Int
    let source: EPUBNavigationSource
}

private enum EPUBNavigationSource {
    case nav
    case ncx
}

private struct EPUBContentDocument {
    let spineItem: EPUBSpineItem
    let blocks: [EPUBTextBlock]
    let linkDensity: Double

    var wordCount: Int {
        blocks.reduce(0) { $0 + $1.wordCount }
    }

    var firstHeadingTitle: String? {
        blocks.lazy.compactMap(\.headingText).first
    }

    var filenameTitle: String? {
        EPUBStructureBuilder.cleanedFilenameTitle(spineItem.path)
    }

    var bestDeterministicTitle: String? {
        blocks.lazy
            .compactMap(\.headingText)
            .compactMap(EPUBStructureBuilder.cleanedNavigationTitle)
            .first
            ?? EPUBStructureBuilder.cleanedNavigationTitle(spineItem.manifestItem.title)
            ?? filenameTitle
    }

    func headingTitle(near localBlockIndex: Int) -> String? {
        if blocks.indices.contains(localBlockIndex),
           let heading = blocks[localBlockIndex].headingText {
            return EPUBStructureBuilder.cleanedNavigationTitle(heading)
        }

        return blocks
            .dropFirst(max(localBlockIndex, 0))
            .prefix(4)
            .compactMap(\.headingText)
            .compactMap(EPUBStructureBuilder.cleanedNavigationTitle)
            .first
    }
}

private struct EPUBTextBlock {
    let index: Int
    let text: String
    let anchorIDs: Set<String>
    let headingLevel: Int?
    let headingText: String?

    var wordCount: Int {
        EPUBStructureBuilder.wordCount(text)
    }
}

private enum EPUBPackageParser {
    static func parse(_ data: Data, opfPath: String) throws -> EPUBPackage {
        let delegate = OPFXMLParser(opfPath: opfPath)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(),
              !delegate.manifest.isEmpty,
              !delegate.spine.isEmpty else {
            throw DocumentImportError.epubContentsNotFound
        }

        return EPUBPackage(
            opfPath: opfPath,
            opfDirectory: opfPath.deletingLastPathComponent,
            metadataTitle: EPUBStructureBuilder.cleanedNavigationTitle(delegate.metadataTitle),
            metadataAuthor: EPUBStructureBuilder.cleanedNavigationTitle(delegate.metadataAuthor),
            coverItemID: delegate.coverItemID,
            manifest: delegate.manifest,
            spine: delegate.spine,
            spineTOCID: delegate.spineTOCID
        )
    }
}

private enum EPUBNavigationParser {
    static func parse(
        package: EPUBPackage,
        archive: Archive,
        dataProvider: (String) -> Data?
    ) -> [EPUBNavigationEntry] {
        let navEntries = package.manifest.values
            .filter(\.isNavigationDocument)
            .flatMap { item -> [EPUBNavigationEntry] in
                let path = resolveArchivePath(baseDirectory: package.opfDirectory, href: item.href)
                guard let data = dataProvider(path) else { return [] }
                return XHTMLNavigationParser.parse(
                    data,
                    navPath: path,
                    requiresTOCNav: true
                )
            }

        if !navEntries.isEmpty {
            return navEntries
        }

        var ncxItems: [ManifestItem] = []
        if let spineTOCID = package.spineTOCID,
           let tocItem = package.manifest[spineTOCID] {
            ncxItems.append(tocItem)
        }
        ncxItems.append(contentsOf: package.manifest.values.filter { item in
            item.isNCX && !ncxItems.contains(where: { $0.id == item.id })
        })

        return ncxItems.flatMap { item -> [EPUBNavigationEntry] in
            let path = resolveArchivePath(baseDirectory: package.opfDirectory, href: item.href)
            guard let data = dataProvider(path) else { return [] }
            return NCXNavigationParser.parse(data, ncxPath: path)
        }
    }
}

private enum EPUBXHTMLParser {
    private static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "dd", "div", "dl",
        "dt", "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5",
        "h6", "header", "li", "main", "ol", "p", "pre", "section", "table",
        "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
    ]

    private static let skippedElementNames: Set<String> = [
        "audio", "head", "metadata", "nav", "script", "style", "svg", "video"
    ]

    static func parse(_ data: Data) -> EPUBXHTMLParseResult {
        let delegate = EPUBXHTMLParserDelegate(
            blockElements: blockElements,
            skippedElementNames: skippedElementNames
        )
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            return fallbackParse(data)
        }

        delegate.finish()
        return EPUBXHTMLParseResult(
            blocks: delegate.blocks,
            linkDensity: delegate.linkDensity
        )
    }

    private static func fallbackParse(_ data: Data) -> EPUBXHTMLParseResult {
        guard var text = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .isoLatin1) else {
            return EPUBXHTMLParseResult(blocks: [], linkDensity: 0)
        }

        text = text
            .replacingOccurrences(of: #"<(script|style|nav)[\s\S]*?</\1>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</(p|div|section|h[1-6]|li)>"#, with: "\n\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"&nbsp;"#, with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: #"&amp;"#, with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: #"&lt;"#, with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: #"&gt;"#, with: ">", options: .caseInsensitive)
            .focusReadNormalizedDocumentText

        guard !text.isEmpty else {
            return EPUBXHTMLParseResult(blocks: [], linkDensity: 0)
        }

        return EPUBXHTMLParseResult(
            blocks: [
                EPUBTextBlock(
                    index: 0,
                    text: text,
                    anchorIDs: [],
                    headingLevel: nil,
                    headingText: nil
                )
            ],
            linkDensity: 0
        )
    }
}

private struct EPUBXHTMLParseResult {
    let blocks: [EPUBTextBlock]
    let linkDensity: Double
}

private final class EPUBXHTMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var blocks: [EPUBTextBlock] = []
    private let blockElements: Set<String>
    private let skippedElementNames: Set<String>
    private var skipDepth = 0
    private var linkDepth = 0
    private var linkedCharacterCount = 0
    private var totalCharacterCount = 0
    private var activeIDStack: [String?] = []
    private var currentBlockText = ""
    private var currentBlockAnchorIDs: Set<String> = []
    private var currentHeadingLevel: Int?
    private var currentHeadingText = ""

    init(blockElements: Set<String>, skippedElementNames: Set<String>) {
        self.blockElements = blockElements
        self.skippedElementNames = skippedElementNames
    }

    var linkDensity: Double {
        guard totalCharacterCount > 0 else { return 0 }
        return Double(linkedCharacterCount) / Double(totalCharacterCount)
    }

    func finish() {
        flushBlock()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.xmlLocalName

        if skipDepth > 0 || skippedElementNames.contains(element) {
            skipDepth += 1
            activeIDStack.append(nil)
            return
        }

        let id = attributeDict["id"] ?? attributeDict["xml:id"]
        activeIDStack.append(id)

        if element == "a" {
            linkDepth += 1
            if let id {
                currentBlockAnchorIDs.insert(id)
            }
        }

        if blockElements.contains(element) {
            flushBlock()
            currentBlockAnchorIDs.formUnion(activeIDStack.compactMap { $0 })
        }

        if element == "br" {
            appendText("\n")
        }

        if let level = headingLevel(for: element) {
            flushBlock()
            currentHeadingLevel = level
            currentHeadingText = ""
            currentBlockAnchorIDs.formUnion(activeIDStack.compactMap { $0 })
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.xmlLocalName

        if skipDepth > 0 {
            skipDepth -= 1
            _ = activeIDStack.popLast()
            return
        }

        if element == "a", linkDepth > 0 {
            linkDepth -= 1
        }

        if headingLevel(for: element) != nil {
            currentHeadingText = currentHeadingText
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            flushBlock()
            currentHeadingLevel = nil
            currentHeadingText = ""
        } else if blockElements.contains(element) {
            flushBlock()
        }

        _ = activeIDStack.popLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skipDepth == 0 else { return }
        appendText(string)
    }

    private func appendText(_ string: String) {
        let collapsed = string
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        guard !collapsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let countedCharacters = collapsed.trimmingCharacters(in: .whitespacesAndNewlines).count
        totalCharacterCount += countedCharacters
        if linkDepth > 0 {
            linkedCharacterCount += countedCharacters
        }

        if currentHeadingLevel != nil {
            if !currentHeadingText.isEmpty {
                currentHeadingText.append(" ")
            }
            currentHeadingText.append(collapsed.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let last = currentBlockText.last,
           !last.isWhitespace,
           let first = collapsed.first,
           !first.isWhitespace {
            currentBlockText.append(" ")
        }

        currentBlockText.append(collapsed)
    }

    private func flushBlock() {
        let text = currentBlockText.focusReadNormalizedDocumentText
        if !text.isEmpty {
            blocks.append(EPUBTextBlock(
                index: blocks.count,
                text: text,
                anchorIDs: currentBlockAnchorIDs,
                headingLevel: currentHeadingLevel,
                headingText: currentHeadingLevel == nil ? nil : currentHeadingText
            ))
        }

        currentBlockText = ""
        currentBlockAnchorIDs = []
    }

    private func headingLevel(for element: String) -> Int? {
        guard element.count == 2,
              element.first == "h",
              let digit = element.last?.wholeNumberValue,
              (1...6).contains(digit) else {
            return nil
        }

        return digit
    }
}

private final class ContainerXMLParser: NSObject, XMLParserDelegate {
    private var rootfilePath: String?

    static func parse(_ data: Data) throws -> String {
        let delegate = ContainerXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(),
              let rootfilePath = delegate.rootfilePath,
              !rootfilePath.isEmpty else {
            throw DocumentImportError.invalidEPUB
        }

        return rootfilePath.normalizedArchivePath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.xmlLocalName == "rootfile", rootfilePath == nil else {
            return
        }

        rootfilePath = attributeDict["full-path"]
    }
}

private final class OPFXMLParser: NSObject, XMLParserDelegate {
    let opfPath: String
    var manifest: [String: ManifestItem] = [:]
    var spine: [String] = []
    var spineTOCID: String?
    var coverItemID: String?
    var metadataTitle: String?
    var metadataAuthor: String?
    private var capturingTitle = false
    private var capturingAuthor = false
    private var titleText = ""
    private var authorText = ""

    init(opfPath: String) {
        self.opfPath = opfPath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.xmlLocalName {
        case "title":
            if metadataTitle == nil {
                capturingTitle = true
                titleText = ""
            }
        case "creator":
            if metadataAuthor == nil {
                capturingAuthor = true
                authorText = ""
            }
        case "meta":
            if coverItemID == nil,
               attributeDict["name"]?.lowercased() == "cover" {
                coverItemID = attributeDict["content"]
            }
        case "item":
            guard let id = attributeDict["id"],
                  let href = attributeDict["href"],
                  let mediaType = attributeDict["media-type"] else {
                return
            }

            manifest[id] = ManifestItem(
                id: id,
                href: href,
                mediaType: mediaType,
                properties: attributeDict["properties"] ?? "",
                title: attributeDict["title"] ?? attributeDict["opf:title"]
            )
        case "spine":
            spineTOCID = attributeDict["toc"]
        case "itemref":
            if attributeDict["linear"]?.lowercased() == "no" {
                return
            }

            guard let idref = attributeDict["idref"] else {
                return
            }

            spine.append(idref)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingTitle {
            titleText.append(string)
        } else if capturingAuthor {
            authorText.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName.xmlLocalName {
        case "title":
            guard capturingTitle else { return }
            let title = cleanedMetadataText(titleText)
            if !title.isEmpty {
                metadataTitle = title
            }
            capturingTitle = false
            titleText = ""
        case "creator":
            guard capturingAuthor else { return }
            let creator = cleanedMetadataText(authorText)
            if !creator.isEmpty {
                metadataAuthor = creator
            }
            capturingAuthor = false
            authorText = ""
        default:
            return
        }
    }

    private func cleanedMetadataText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class XHTMLNavigationParser: NSObject, XMLParserDelegate {
    private let navPath: String
    private let requiresTOCNav: Bool
    private var entries: [EPUBNavigationEntry] = []
    private var navDepth = 0
    private var skippedNavDepth = 0
    private var listDepth = 0
    private var currentHref: String?
    private var currentLevel = 1
    private var currentText = ""

    init(navPath: String, requiresTOCNav: Bool) {
        self.navPath = navPath
        self.requiresTOCNav = requiresTOCNav
    }

    static func parse(_ data: Data, navPath: String, requiresTOCNav: Bool) -> [EPUBNavigationEntry] {
        let delegate = XHTMLNavigationParser(navPath: navPath, requiresTOCNav: requiresTOCNav)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            return []
        }
        return delegate.entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.xmlLocalName

        if skippedNavDepth > 0 {
            skippedNavDepth += 1
            return
        }

        if element == "nav" {
            if navDepth > 0 {
                navDepth += 1
                return
            }

            let navType = [
                attributeDict["type"],
                attributeDict["epub:type"],
                attributeDict["ops:type"]
            ]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")

            if !requiresTOCNav || navType.contains("toc") || navType.isEmpty {
                navDepth = 1
            } else {
                skippedNavDepth = 1
            }
            return
        }

        guard navDepth > 0 || !requiresTOCNav else {
            return
        }

        if element == "ol" || element == "ul" {
            listDepth += 1
        } else if element == "a", let href = attributeDict["href"] {
            currentHref = href
            currentLevel = max(listDepth, 1)
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentHref != nil {
            currentText.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.xmlLocalName

        if skippedNavDepth > 0 {
            skippedNavDepth -= 1
            return
        }

        if element == "a", let href = currentHref {
            let title = currentText
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                entries.append(EPUBNavigationEntry(
                    title: title,
                    href: href,
                    path: resolveArchivePath(baseDirectory: navPath.deletingLastPathComponent, href: href),
                    fragment: href.hrefFragment,
                    level: currentLevel,
                    source: .nav
                ))
            }
            currentHref = nil
            currentText = ""
        } else if element == "ol" || element == "ul" {
            listDepth = max(listDepth - 1, 0)
        } else if element == "nav", navDepth > 0 {
            navDepth -= 1
        }
    }
}

private final class NCXNavigationParser: NSObject, XMLParserDelegate {
    private struct NavPoint {
        var label = ""
        var src: String?
        let level: Int
    }

    private let ncxPath: String
    private var stack: [NavPoint] = []
    private var entries: [EPUBNavigationEntry] = []
    private var capturingText = false
    private var textBuffer = ""

    init(ncxPath: String) {
        self.ncxPath = ncxPath
    }

    static func parse(_ data: Data, ncxPath: String) -> [EPUBNavigationEntry] {
        let delegate = NCXNavigationParser(ncxPath: ncxPath)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            return []
        }
        return delegate.entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.xmlLocalName {
        case "navpoint":
            stack.append(NavPoint(level: stack.count + 1))
        case "text":
            guard !stack.isEmpty else { return }
            capturingText = true
            textBuffer = ""
        case "content":
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].src = attributeDict["src"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingText {
            textBuffer.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName.xmlLocalName {
        case "text":
            if capturingText, !stack.isEmpty {
                stack[stack.count - 1].label = textBuffer
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            capturingText = false
            textBuffer = ""
        case "navpoint":
            guard let point = stack.popLast(),
                  let src = point.src,
                  !point.label.isEmpty else {
                return
            }

            entries.append(EPUBNavigationEntry(
                title: point.label,
                href: src,
                path: resolveArchivePath(baseDirectory: ncxPath.deletingLastPathComponent, href: src),
                fragment: src.hrefFragment,
                level: point.level,
                source: .ncx
            ))
        default:
            break
        }
    }
}

private func resolveArchivePath(baseDirectory: String, href: String) -> String {
    let hrefWithoutFragment = href.components(separatedBy: "#").first ?? href
    let decodedHref = hrefWithoutFragment.removingPercentEncoding ?? hrefWithoutFragment

    let combined: String
    if baseDirectory.isEmpty {
        combined = decodedHref
    } else {
        combined = baseDirectory + "/" + decodedHref
    }

    return combined.normalizedArchivePath
}

private extension String {
    var deletingLastPathComponent: String {
        let components = split(separator: "/", omittingEmptySubsequences: true)
        guard components.count > 1 else {
            return ""
        }

        return components.dropLast().joined(separator: "/")
    }

    var normalizedArchivePath: String {
        let parts = split(separator: "/", omittingEmptySubsequences: false)
        var normalized: [Substring] = []

        for part in parts {
            if part.isEmpty || part == "." {
                continue
            }

            if part == ".." {
                if !normalized.isEmpty {
                    normalized.removeLast()
                }
            } else {
                normalized.append(part)
            }
        }

        return normalized.joined(separator: "/")
    }

    var archivePathCandidates: [String] {
        let normalized = normalizedArchivePath
        let decoded = removingPercentEncoding?.normalizedArchivePath

        if let decoded, decoded != normalized {
            return [normalized, decoded]
        }

        return [normalized]
    }

    var xmlLocalName: String {
        lowercased().split(separator: ":").last.map(String.init) ?? lowercased()
    }

    var hrefFragment: String? {
        guard let fragment = split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first else {
            return nil
        }

        let raw = String(fragment)
        return raw.removingPercentEncoding ?? raw
    }
}
