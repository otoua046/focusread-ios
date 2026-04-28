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
            let package = try OPFXMLParser.parse(opfData)

            let opfDirectory = opfPath.deletingLastPathComponent
            let chapterPaths = package.spine
                .compactMap { package.manifest[$0] }
                .filter(\.isReadableChapter)
                .map { resolveArchivePath(baseDirectory: opfDirectory, href: $0.href) }

            guard !chapterPaths.isEmpty else {
                throw DocumentImportError.epubContentsNotFound
            }

            var chapterTexts: [String] = []

            for (index, path) in chapterPaths.enumerated() {
                try Task.checkCancellation()
                await progress(DocumentImportProgress(
                    message: "Extracting EPUB chapter \(index + 1) of \(chapterPaths.count)...",
                    completedUnitCount: nil,
                    totalUnitCount: nil
                ))

                guard let chapterData = try? data(for: path, in: archive) else {
                    continue
                }

                let chapterText = extractReadableText(from: chapterData)
                    .focusReadNormalizedDocumentText

                if !chapterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chapterTexts.append(chapterText)
                }
            }

            let text = chapterTexts.joined(separator: "\n\n").focusReadNormalizedDocumentText
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentImportError.epubNoReadableText
            }

            return ImportedDocument(
                fileName: file.fileName,
                text: text,
                sourceType: .epub
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
        let candidates = path.archivePathCandidates

        for candidate in candidates {
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

    private func extractReadableText(from data: Data) -> String {
        if let parsedText = XHTMLTextParser.parse(data),
           !parsedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return parsedText
        }

        return attributedHTMLText(from: data)
    }

    private func attributedHTMLText(from data: Data) -> String {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attributed = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ) else {
            return ""
        }

        return attributed.string
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
}

private struct EPUBPackage {
    let manifest: [String: ManifestItem]
    let spine: [String]
}

private struct ManifestItem {
    let id: String
    let href: String
    let mediaType: String
    let properties: String

    var isReadableChapter: Bool {
        let normalizedMediaType = mediaType.lowercased()
        guard normalizedMediaType == "application/xhtml+xml" ||
              normalizedMediaType == "text/html" else {
            return false
        }

        let propertyValues = properties
            .lowercased()
            .split { $0 == " " || $0 == "\t" || $0 == "\n" }

        return !propertyValues.contains("nav")
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
    private var manifest: [String: ManifestItem] = [:]
    private var spine: [String] = []

    static func parse(_ data: Data) throws -> EPUBPackage {
        let delegate = OPFXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(),
              !delegate.manifest.isEmpty,
              !delegate.spine.isEmpty else {
            throw DocumentImportError.epubContentsNotFound
        }

        return EPUBPackage(manifest: delegate.manifest, spine: delegate.spine)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.xmlLocalName {
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
                properties: attributeDict["properties"] ?? ""
            )
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
}

private final class XHTMLTextParser: NSObject, XMLParserDelegate {
    private var output = ""
    private var skippedElements: [String] = []

    private let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "dd", "div", "dl",
        "dt", "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5",
        "h6", "header", "li", "main", "ol", "p", "pre", "section", "table",
        "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
    ]

    private let skippedElementNames: Set<String> = [
        "audio", "head", "metadata", "nav", "script", "style", "svg", "video"
    ]

    static func parse(_ data: Data) -> String? {
        let delegate = XHTMLTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            return nil
        }

        return delegate.output
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.xmlLocalName

        if skippedElementNames.contains(element) || !skippedElements.isEmpty {
            skippedElements.append(element)
            return
        }

        if element == "br" {
            appendLineBreak()
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.xmlLocalName

        if !skippedElements.isEmpty {
            _ = skippedElements.popLast()
            return
        }

        if blockElements.contains(element) {
            appendParagraphBreak()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skippedElements.isEmpty else {
            return
        }

        let collapsed = string
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        guard !collapsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if let last = output.last,
           !last.isWhitespace,
           let first = collapsed.first,
           !first.isWhitespace {
            output.append(" ")
        }

        output.append(collapsed)
    }

    private func appendLineBreak() {
        guard !output.hasSuffix("\n") else {
            return
        }

        output.append("\n")
    }

    private func appendParagraphBreak() {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            output = ""
            return
        }

        output = trimmed + "\n\n"
    }
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
}
