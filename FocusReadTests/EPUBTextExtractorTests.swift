import XCTest
@testable import FocusRead

final class EPUBTextExtractorTests: XCTestCase {
    func testMinimalEPUBUsesNavigationBoundariesAndSkipsCopyright() async throws {
        let document = try await extractFixture("minimal")

        XCTAssertEqual(document.sections.map(\.chapterTitle), ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(document.sections.map(\.epubStructureSource), [.navigation, .navigation])
        XCTAssertFalse(document.text.localizedCaseInsensitiveContains("Copyright"))
    }

    func testPrideAndPrejudiceKeepsRomanNumeralChaptersSeparate() async throws {
        let document = try await extractFixture("jane-austen_pride-and-prejudice")
        let titles = document.sections.compactMap(\.chapterTitle)

        XCTAssertEqual(document.sections.count, 61)
        XCTAssertEqual(titles.prefix(5), ["I", "II", "III", "IV", "V"])
        XCTAssertTrue(titles.contains("LXI"))
        XCTAssertEqual(Set(document.sections.map(\.epubStructureSource)), [.navigation])
    }

    func testAccessibleEPUBUsesNavLabelsInsteadOfGeneratedIDs() async throws {
        let document = try await extractFixture("accessible_epub_3")
        let titles = document.sections.compactMap(\.chapterTitle)

        XCTAssertGreaterThan(document.sections.count, 10)
        XCTAssertTrue(titles.contains("Preface"))
        XCTAssertTrue(titles.contains("The Digital Famine"))
        XCTAssertTrue(titles.contains("A Solid Foundation: Structure and Semantics"))
        XCTAssertFalse(titles.contains { $0.localizedCaseInsensitiveContains("Id Id") })
    }

    func testCorruptGutenbergFixtureFailsAsEPUBExtractionFailure() async {
        do {
            _ = try await extractFixture("pg1342-images-3")
            XCTFail("Expected corrupt EPUB fixture to fail")
        } catch let error as DocumentImportError {
            XCTAssertEqual(error, .epubExtractionFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func extractFixture(_ name: String) async throws -> ImportedDocument {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "epub"))
        let file = ImportedFile(
            localURL: url,
            fileName: url.lastPathComponent,
            fileExtension: "epub"
        )

        return try await EPUBTextExtractor().extractText(from: file) { _ in }
    }
}
