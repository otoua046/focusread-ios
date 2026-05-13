import Foundation

enum SavedReadMapper {
    static let demoReadID = UUID(uuidString: "8F7B7F6C-7F37-4F65-9B43-5D9B6C0E52D1")!

    static func makeSavedRead(
        from text: String,
        tokens: [ReadingToken],
        cleanupMode: SmartCleanupMode = .off,
        now: Date = Date()
    ) -> SavedRead {
        SavedRead(
            id: UUID(),
            displayTitle: title(forPastedText: text),
            originalFileName: nil,
            sourceType: .pastedText,
            languageCode: nil,
            thumbnailPath: nil,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now,
            totalWordCount: tokens.count,
            currentWordIndex: 0,
            progressPercent: progressPercent(currentIndex: 0, stepSize: 1, totalWordCount: tokens.count),
            currentPage: nil,
            totalPages: nil,
            currentChapter: nil,
            totalChapters: nil,
            sections: [
                SavedReadSection(
                    index: 0,
                    title: nil,
                    text: text.focusReadNormalizedDocumentText,
                    pageNumber: nil,
                    chapterNumber: nil,
                    wordRange: nil,
                    epubNavigationLevel: nil,
                    epubSectionRole: .body,
                    epubStructureSource: nil,
                    epubStructureConfidence: nil
                )
            ],
            cleanupModeUsed: cleanupMode.rawValue,
            isFavorite: false,
            readingStats: SavedReadStats(totalTimeRead: 0, sessionsCount: 1),
            author: nil,
            manualSortIndex: nil
        )
    }

    static func makeDemoSavedRead(
        from text: String,
        tokens: [ReadingToken],
        title: String,
        existingReads: [SavedRead],
        now: Date = Date()
    ) -> SavedRead {
        var savedRead = makeSavedRead(from: text, tokens: tokens, now: now)
        savedRead.id = Self.demoReadID
        savedRead.displayTitle = title
        savedRead.originalFileName = title
        savedRead.sourceType = .txt

        guard let existing = existingReads.first(where: { isDemoRead($0, matching: text) }) else {
            return savedRead
        }

        savedRead.id = existing.id
        savedRead.createdAt = existing.createdAt
        savedRead.isFavorite = existing.isFavorite
        savedRead.manualSortIndex = existing.manualSortIndex
        savedRead.cloudSync = existing.cloudSync
        savedRead.readingStats = existing.readingStats
        savedRead.readingStats.sessionsCount += 1
        return savedRead
    }

    static func isDemoRead(_ read: SavedRead, matching text: String) -> Bool {
        read.id == Self.demoReadID
            || (
                read.sourceType == .txt
                    && read.documentText.focusReadNormalizedDocumentText == text.focusReadNormalizedDocumentText
            )
    }

    static func makeSavedRead(
        from document: ImportedDocument,
        tokens: [ReadingToken],
        now: Date = Date()
    ) -> SavedRead {
        let sections = savedSections(from: document)
        return SavedRead(
            id: UUID(),
            displayTitle: document.displayTitle,
            originalFileName: document.fileName,
            sourceType: savedSourceType(from: document.sourceType),
            languageCode: document.languageCode,
            thumbnailPath: nil,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now,
            totalWordCount: tokens.count,
            currentWordIndex: 0,
            progressPercent: progressPercent(currentIndex: 0, stepSize: 1, totalWordCount: tokens.count),
            currentPage: nil,
            totalPages: totalPages(in: sections),
            currentChapter: nil,
            totalChapters: totalChapters(in: sections),
            sections: sections,
            cleanupModeUsed: document.cleanupMode.rawValue,
            isFavorite: false,
            readingStats: SavedReadStats(totalTimeRead: 0, sessionsCount: 1),
            author: document.author,
            manualSortIndex: nil
        )
    }

    static func updating(_ read: SavedRead, from session: ReadingSession, now: Date = Date()) -> SavedRead {
        var updated = read
        updated.sourceType = savedSourceType(from: session.document.sourceType)
        updated.updatedAt = now
        updated.lastOpenedAt = now
        updated.totalWordCount = session.tokens.count
        updated.currentWordIndex = session.currentIndex
        updated.progressPercent = session.isAtEnd ? 100 : progressPercent(
            currentIndex: session.currentIndex,
            stepSize: session.stepSize,
            totalWordCount: session.tokens.count
        )
        updated.currentPage = session.currentToken?.sourcePageNumber
        updated.currentChapter = session.currentToken?.sourceChapterNumber
        updated.totalPages = totalPages(in: updated.sections)
        updated.totalChapters = totalChapters(in: updated.sections)
        return updated
    }

    static func savedSections(from document: ImportedDocument) -> [SavedReadSection] {
        document.sections.map(savedSection)
    }

    static func importedDocument(from read: SavedRead) -> ImportedDocument? {
        let sourceType: DocumentSourceType
        switch read.sourceType {
        case .txt:
            sourceType = .txt
        case .pdf:
            sourceType = .pdf
        case .epub:
            sourceType = .epub
        case .image:
            sourceType = .image
        case .pastedText:
            return nil
        }

        return ImportedDocument(
            fileName: read.originalFileName ?? read.displayTitle,
            displayTitle: read.displayTitle,
            author: read.author,
            sourceType: sourceType,
            languageCode: read.languageCode,
            sections: read.sections.map(importedSection),
            cleanupMode: SmartCleanupMode(rawValue: read.cleanupModeUsed) ?? .off
        )
    }

    static func readingDocument(from read: SavedRead) -> ReadingDocument {
        ReadingDocument(
            id: read.id,
            title: read.displayTitle,
            fileName: read.originalFileName,
            sourceType: readingSourceType(from: read.sourceType),
            sections: read.sections.map(readingSection)
        )
    }

    static func text(from read: SavedRead) -> String {
        read.documentText.focusReadNormalizedDocumentText
    }

    private static func title(forPastedText text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? L10n.string(.readerPastedText)
        return String(firstLine.prefix(64))
    }

    private static func savedSection(_ section: ImportedDocumentSection) -> SavedReadSection {
        SavedReadSection(
            index: section.index,
            title: section.chapterTitle,
            text: section.text,
            pageNumber: section.pageNumber,
            chapterNumber: section.chapterNumber,
            wordRange: section.wordRange.map(SavedReadWordRange.init),
            epubNavigationLevel: section.epubNavigationLevel,
            epubSectionRole: section.epubSectionRole,
            epubStructureSource: section.epubStructureSource,
            epubStructureConfidence: section.epubStructureConfidence
        )
    }

    private static func importedSection(_ section: SavedReadSection) -> ImportedDocumentSection {
        ImportedDocumentSection(
            index: section.index,
            text: section.text,
            pageNumber: section.pageNumber,
            chapterNumber: section.chapterNumber,
            chapterTitle: section.title,
            wordRange: section.wordRange?.range,
            epubNavigationLevel: section.epubNavigationLevel,
            epubSectionRole: section.epubSectionRole,
            epubStructureSource: section.epubStructureSource,
            epubStructureConfidence: section.epubStructureConfidence
        )
    }

    private static func readingSection(_ section: SavedReadSection) -> ReadingDocumentSection {
        ReadingDocumentSection(
            index: section.index,
            title: section.title,
            pageNumber: section.pageNumber,
            chapterNumber: section.chapterNumber,
            wordRange: section.wordRange?.range,
            epubNavigationLevel: section.epubNavigationLevel,
            epubSectionRole: section.epubSectionRole,
            epubStructureSource: section.epubStructureSource,
            epubStructureConfidence: section.epubStructureConfidence
        )
    }

    private static func savedSourceType(from sourceType: DocumentSourceType) -> SavedReadSourceType {
        switch sourceType {
        case .txt:
            .txt
        case .pdf:
            .pdf
        case .epub:
            .epub
        case .image:
            .image
        }
    }

    private static func savedSourceType(from sourceType: ReadingDocumentSourceType) -> SavedReadSourceType {
        switch sourceType {
        case .pastedText:
            .pastedText
        case .txt:
            .txt
        case .pdf:
            .pdf
        case .epub:
            .epub
        case .image:
            .image
        }
    }

    private static func readingSourceType(from sourceType: SavedReadSourceType) -> ReadingDocumentSourceType {
        switch sourceType {
        case .pastedText:
            .pastedText
        case .txt:
            .txt
        case .pdf:
            .pdf
        case .epub:
            .epub
        case .image:
            .image
        }
    }

    private static func progressPercent(currentIndex: Int, stepSize: Int, totalWordCount: Int) -> Double {
        guard totalWordCount > 0 else { return 0 }
        let readCount = min(currentIndex + stepSize, totalWordCount)
        return min(max(Double(readCount) / Double(totalWordCount) * 100, 0), 100)
    }

    private static func totalPages(in sections: [SavedReadSection]) -> Int? {
        sections.compactMap(\.pageNumber).max()
    }

    private static func totalChapters(in sections: [SavedReadSection]) -> Int? {
        let chapterNumbers = sections.compactMap(\.chapterNumber)
        if let maxChapter = chapterNumbers.max() {
            return maxChapter
        }
        let chapterSections = sections.filter { $0.epubSectionRole == .chapter }
        return chapterSections.isEmpty ? nil : chapterSections.count
    }
}
