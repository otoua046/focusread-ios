import Foundation
import PDFKit
import UIKit
import XCTest
@testable import FocusRead

enum PerformanceBenchmarkFixtures {
    static let repeatedParagraph = """
    FocusRead benchmarks should measure realistic reading text with punctuation, numbers like 1200, paragraph breaks,
    and enough variety to exercise pause classification, sentence tracking, and token indexing.

    A second paragraph keeps paragraph-break handling honest. The reader should advance predictably, reopen quickly,
    and avoid doing invisible work on the main thread.
    """

    static func text(wordCount: Int) -> String {
        let wordsPerParagraph = repeatedParagraph.split { $0.isWhitespace || $0.isNewline }.count
        let repetitions = max(1, Int(ceil(Double(wordCount) / Double(wordsPerParagraph))))
        return Array(repeating: repeatedParagraph, count: repetitions).joined(separator: "\n\n")
    }

    static func temporaryTextFile(wordCount: Int, fileName: String = "benchmark-large.txt") throws -> ImportedFile {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try text(wordCount: wordCount).write(to: url, atomically: true, encoding: .utf8)
        return ImportedFile(localURL: url, fileName: fileName, fileExtension: "txt")
    }

    static func temporaryPDF(pageCount: Int, wordsPerPage: Int, fileName: String = "benchmark-large.pdf") throws -> ImportedFile {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            let text = self.text(wordCount: wordsPerPage)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]
            for page in 0..<pageCount {
                context.beginPage()
                let heading = "Benchmark Page \(page + 1)\n\n"
                (heading + text).draw(
                    with: CGRect(x: 48, y: 48, width: 516, height: 696),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
            }
        }
        return ImportedFile(localURL: url, fileName: fileName, fileExtension: "pdf")
    }

    static func temporaryScannedPDF(pageCount: Int = 1, fileName: String = "benchmark-scanned.pdf") throws -> ImportedFile {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let imageRenderer = UIGraphicsImageRenderer(size: pageBounds.size)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        try pdfRenderer.writePDF(to: url) { context in
            for pageIndex in 0..<pageCount {
                let image = imageRenderer.image { imageContext in
                    UIColor.white.setFill()
                    imageContext.fill(pageBounds)

                    let text = """
                    Scanned benchmark page \(pageIndex + 1)

                    FocusRead should recognize text from image-only PDFs without blocking reader controls.
                    This fixture intentionally stores text as pixels, not selectable PDF text.
                    The benchmark measures OCR setup, page rendering, Vision recognition, and document assembly.
                    """
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 28, weight: .regular),
                        .foregroundColor: UIColor.black
                    ]
                    text.draw(
                        with: CGRect(x: 54, y: 72, width: 504, height: 620),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes,
                        context: nil
                    )
                }

                context.beginPage()
                image.draw(in: pageBounds)
            }
        }
        return ImportedFile(localURL: url, fileName: fileName, fileExtension: "pdf")
    }

    static func epubFixture(_ name: String, testCase: XCTestCase) throws -> ImportedFile {
        let url = try XCTUnwrap(Bundle(for: type(of: testCase)).url(forResource: name, withExtension: "epub"))
        return ImportedFile(localURL: url, fileName: url.lastPathComponent, fileExtension: "epub")
    }

    static func seededSavedReads(count: Int, wordsPerRead: Int = 180) -> [SavedRead] {
        let now = Date(timeIntervalSince1970: 1_779_000_000)
        return (0..<count).map { index in
            let title = "Benchmark Read \(String(format: "%04d", index))"
            let author = "Author \(index % 37)"
            let text = text(wordCount: wordsPerRead)
            let section = SavedReadSection(
                index: 0,
                title: nil,
                text: text,
                pageNumber: nil,
                chapterNumber: nil,
                wordRange: SavedReadWordRange(0..<wordsPerRead),
                epubNavigationLevel: nil,
                epubSectionRole: .body,
                epubStructureSource: nil,
                epubStructureConfidence: nil
            )

            return SavedRead(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                displayTitle: title,
                authorName: author,
                originalFileName: "benchmark-\(index).txt",
                externalSourceID: index.isMultiple(of: 3) ? "benchmark:\(index)" : nil,
                sourceType: index.isMultiple(of: 5) ? .epub : .txt,
                languageCode: "en",
                thumbnailPath: index.isMultiple(of: 4) ? "SavedReads/\(index)/thumbnail.jpg" : nil,
                createdAt: now.addingTimeInterval(TimeInterval(-index * 90)),
                updatedAt: now.addingTimeInterval(TimeInterval(-index * 60)),
                lastOpenedAt: now.addingTimeInterval(TimeInterval(-index * 30)),
                totalWordCount: wordsPerRead,
                currentWordIndex: index % max(wordsPerRead, 1),
                progressPercent: Double(index % 100) / 100.0,
                currentPage: nil,
                totalPages: nil,
                currentChapter: nil,
                totalChapters: nil,
                sections: [section],
                cleanupModeUsed: SmartCleanupMode.off.rawValue,
                isFavorite: index.isMultiple(of: 11),
                readingStats: .empty,
                author: author,
                manualSortIndex: index,
                cloudSync: nil
            )
        }
    }

    static func writeSavedReads(_ reads: [SavedRead]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusReadBenchmarks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(reads)
        try data.write(to: directory.appendingPathComponent("SavedReads.json"), options: .atomic)
        return directory
    }

    static func discoverBooks(count: Int) -> [DiscoverBook] {
        (0..<count).map { index in
            DiscoverBook(
                id: "benchmark-\(index)",
                source: index.isMultiple(of: 2) ? .projectGutenberg : .openLibrary,
                sourceID: "benchmark-\(index)",
                title: "Benchmark Discover Book \(index)",
                author: "Discover Author \(index % 41)",
                coverURL: URL(string: "https://covers.openlibrary.org/b/id/\(1000 + index)-L.jpg"),
                subjects: ["Fiction", "Benchmark", index.isMultiple(of: 3) ? "Philosophy" : "Adventure"],
                availability: DiscoverAvailability(
                    preferredFormat: index.isMultiple(of: 4) ? .pdf : .epub,
                    location: .direct(URL(string: "https://example.com/book-\(index).epub")!),
                    localFileName: "book-\(index).epub"
                ),
                webURL: URL(string: "https://example.com/book-\(index)"),
                languageCode: "en",
                pageCount: 80 + (index % 320),
                description: "Benchmark discover fixture book \(index).",
                firstPublishYear: 1900 + (index % 100),
                downloadCount: 1000 + index,
                ratingAverage: Double(30 + (index % 20)) / 10.0,
                ratingCount: 25 + index,
                editionCount: 1 + (index % 12)
            )
        }
    }

    static func discoverSections(sectionCount: Int, booksPerSection: Int) -> [DiscoverSection] {
        let books = discoverBooks(count: sectionCount * booksPerSection)
        return (0..<sectionCount).map { sectionIndex in
            let start = sectionIndex * booksPerSection
            return DiscoverSection(
                id: "benchmark-section-\(sectionIndex)",
                title: "Benchmark Section \(sectionIndex)",
                books: Array(books[start..<(start + booksPerSection)]),
                layout: sectionIndex.isMultiple(of: 3) ? .editorialHero : sectionIndex.isMultiple(of: 2) ? .compactGrid : .classicRow,
                treatment: sectionIndex.isMultiple(of: 2) ? .framed : .open
            )
        }
    }
}
