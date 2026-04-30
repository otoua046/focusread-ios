import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct SmartCleanupService: Sendable {
    func clean(
        _ document: ImportedDocument,
        mode: SmartCleanupMode,
        progress: @escaping DocumentImportProgressHandler
    ) async -> ImportedDocument {
        let effectiveMode = SmartCleanupAvailability.effectiveMode(for: mode)

        guard effectiveMode != .off else {
            return document.withCleanup(
                displayTitle: document.displayTitle,
                sections: document.sections,
                cleanupMode: .off,
                cleanupChunks: []
            )
        }

        await progress(DocumentImportProgress(
            message: "Preparing readable text...",
            completedUnitCount: nil,
            totalUnitCount: nil
        ))

        let repeatedLineKeys = repeatedFormattingLineKeys(in: document.sections)
        let deterministicSections = document.sections.map { section in
            section.withText(Self.deterministicTextCleanup(section.text, repeatedLineKeys: repeatedLineKeys))
        }
        let deterministicTitle = Self.deterministicDisplayTitle(from: document.fileName)

        let sections = Self.sectionsWithUpdatedWordRanges(deterministicSections, sourceType: document.sourceType)
        let chunks = effectiveMode == .ai ? Self.cleanupChunks(originalSections: document.sections, smartSections: sections, sourceType: document.sourceType) : []

        return document.withCleanup(
            displayTitle: deterministicTitle,
            sections: sections,
            cleanupMode: effectiveMode,
            cleanupChunks: chunks
        )
    }

    static func deterministicDisplayTitle(from fileName: String) -> String {
        let baseName = (fileName as NSString).deletingPathExtension
        var title = baseName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")

        let patterns = [
            #"(?i)\b(scanned|scan|ocr|copy|final|draft|revised|version|ver|rev)\s*\d*\b"#,
            #"(?i)\b(img|image|document|doc)\s*\d{2,}\b"#,
            #"\b\d{4}[\s_-]?\d{2}[\s_-]?\d{2}\b"#,
            #"\b\d{8,}\b"#,
            #"\(\s*\)"#,
            #"\[\s*\]"#
        ]

        for pattern in patterns {
            title = title.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }

        title = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            return baseName.isEmpty ? fileName : baseName
        }

        return title.localizedCapitalized
    }

    static func deterministicTextCleanup(_ text: String, repeatedLineKeys: Set<String> = []) -> String {
        let normalized = text
            .replacingOccurrences(of: "\u{00ad}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(
                of: #"([A-Za-z])-\n([a-z])"#,
                with: "$1$2",
                options: .regularExpression
            )

        let lines = normalized.components(separatedBy: "\n")
        let cleanedLines = lines.compactMap { line -> String? in
            var cleaned = line
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleaned.isEmpty else {
                return ""
            }

            if isFormattingGarbageLine(cleaned) {
                return nil
            }

            if repeatedLineKeys.contains(lineKey(cleaned)) {
                return nil
            }

            cleaned = cleaned
                .replacingOccurrences(of: #"([A-Za-z])\s+([’'])\s+([A-Za-z])"#, with: "$1$2$3", options: .regularExpression)
                .replacingOccurrences(of: #"([A-Za-z])\s+([,.;:!?])"#, with: "$1$2", options: .regularExpression)

            return cleaned
        }

        var output: [String] = []
        var previousWasBlank = false

        for line in cleanedLines {
            if line.isEmpty {
                if !previousWasBlank, !output.isEmpty {
                    output.append("")
                }
                previousWasBlank = true
            } else {
                output.append(line)
                previousWasBlank = false
            }
        }

        return output.joined(separator: "\n").focusReadNormalizedDocumentText
    }

    func foundationModelTitle(for fileName: String, fallback: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationModelSmartCleanup.cleanTitle(fileName, fallback: fallback)
        }
        #endif

        return nil
    }

    func foundationModelTextCleanup(for text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 120, trimmed.count <= 16_000 else {
            return nil
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationModelSmartCleanup.cleanText(trimmed)
        }
        #endif

        return nil
    }

    private func repeatedFormattingLineKeys(in sections: [ImportedDocumentSection]) -> Set<String> {
        guard sections.count >= 3 else { return [] }

        var counts: [String: Int] = [:]
        for section in sections {
            let keys = Set(section.text.components(separatedBy: .newlines).compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 3, trimmed.count <= 80 else { return nil }
                guard !Self.isFormattingGarbageLine(trimmed) else { return nil }
                return Self.lineKey(trimmed)
            })

            for key in keys {
                counts[key, default: 0] += 1
            }
        }

        let threshold = max(3, Int((Double(sections.count) * 0.4).rounded(.up)))
        return Set(counts.compactMap { key, count in
            count >= threshold ? key : nil
        })
    }

    private static func isFormattingGarbageLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^\d+$"#,
            #"(?i)^page\s+\d+(\s+of\s+\d+)?$"#,
            #"(?i)^scanned\s+with\s+.+"#,
            #"(?i)^generated\s+by\s+.+"#,
            #"^[\W_]{3,}$"#
        ]

        return patterns.contains { pattern in
            trimmed.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func lineKey(_ line: String) -> String {
        line
            .lowercased()
            .replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isSafeTextCleanup(original: String, cleaned: String) -> Bool {
        let normalizedOriginal = textForValidation(original)
        let normalizedCleaned = textForValidation(cleaned)
        guard !normalizedCleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        guard !containsSummaryLanguage(normalizedCleaned) else {
            return false
        }

        let originalWords = wordCount(normalizedOriginal)
        let cleanedWords = wordCount(normalizedCleaned)
        guard originalWords > 0, cleanedWords > 0 else { return false }

        let ratio = Double(cleanedWords) / Double(originalWords)
        guard ratio >= 0.85, ratio <= 1.15 else {
            return false
        }

        let originalSentences = sentenceEndingCount(normalizedOriginal)
        let cleanedSentences = sentenceEndingCount(normalizedCleaned)
        guard originalSentences == 0 || abs(originalSentences - cleanedSentences) <= max(3, originalSentences / 5) else {
            return false
        }

        guard lexicalOverlapRatio(original: normalizedOriginal, cleaned: normalizedCleaned) >= 0.62 else {
            return false
        }

        return true
    }

    static func cleanupChunks(
        originalSections: [ImportedDocumentSection],
        smartSections: [ImportedDocumentSection],
        sourceType: DocumentSourceType
    ) -> [DocumentCleanupChunk] {
        let originalByIndex = Dictionary(uniqueKeysWithValues: originalSections.map { ($0.index, $0) })

        switch sourceType {
        case .pdf, .image:
            return pdfCleanupChunks(originalByIndex: originalByIndex, smartSections: smartSections)
        case .epub:
            return smartSections.flatMap { section in
                cleanupChunks(for: section, originalText: originalByIndex[section.index]?.text ?? section.text, targetWordCount: 3_000)
            }
        case .txt:
            return smartSections.flatMap { section in
                cleanupChunks(for: section, originalText: originalByIndex[section.index]?.text ?? section.text, targetWordCount: 3_000)
            }
        }
    }

    static func pdfSectionTexts(from cleanedText: String, sectionIndices: [Int]) -> [Int: String]? {
        var output: [Int: String] = [:]

        for (offset, sectionIndex) in sectionIndices.enumerated() {
            let startMarker = pdfMarker(for: sectionIndex)
            let endMarker = offset + 1 < sectionIndices.count ? pdfMarker(for: sectionIndices[offset + 1]) : nil
            guard let startRange = cleanedText.range(of: startMarker) else {
                return nil
            }

            let bodyStart = startRange.upperBound
            let bodyEnd: String.Index
            if let endMarker, let endRange = cleanedText.range(of: endMarker, range: bodyStart..<cleanedText.endIndex) {
                bodyEnd = endRange.lowerBound
            } else if endMarker == nil {
                bodyEnd = cleanedText.endIndex
            } else {
                return nil
            }

            let pageText = cleanedText[bodyStart..<bodyEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pageText.isEmpty else {
                return nil
            }
            output[sectionIndex] = String(pageText)
        }

        return output
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private static func sentenceEndingCount(_ text: String) -> Int {
        text.reduce(0) { count, character in
            ".?!".contains(character) ? count + 1 : count
        }
    }

    private static func sectionsWithUpdatedWordRanges(
        _ sections: [ImportedDocumentSection],
        sourceType: DocumentSourceType
    ) -> [ImportedDocumentSection] {
        guard sourceType == .epub else {
            return sections
        }

        var nextWordIndex = 0
        return sections.map { section in
            let wordCount = wordCount(section.text)
            let wordRange = nextWordIndex..<(nextWordIndex + wordCount)
            nextWordIndex += wordCount
            return section.withWordRange(wordRange)
        }
    }

    private static func pdfCleanupChunks(
        originalByIndex: [Int: ImportedDocumentSection],
        smartSections: [ImportedDocumentSection]
    ) -> [DocumentCleanupChunk] {
        let maxPagesPerChunk = 8
        let maxWordsPerChunk = 3_500
        var chunks: [DocumentCleanupChunk] = []
        var pendingSections: [ImportedDocumentSection] = []
        var pendingWordCount = 0
        var nextWordIndex = 0

        func appendPending() {
            guard !pendingSections.isEmpty else { return }
            let sectionIndices = pendingSections.map(\.index)
            let smartText = pendingSections
                .map { "\(pdfMarker(for: $0.index))\n\($0.text)" }
                .joined(separator: "\n\n")
            let originalText = pendingSections
                .map { section in
                    "\(pdfMarker(for: section.index))\n\(originalByIndex[section.index]?.text ?? section.text)"
                }
                .joined(separator: "\n\n")
            let pageNumbers = pendingSections.compactMap(\.pageNumber)
            let sourcePageRange = pageNumbers.min().flatMap { lower in
                pageNumbers.max().map { lower...$0 }
            }
            let wordRange = nextWordIndex..<(nextWordIndex + pendingWordCount)
            nextWordIndex += pendingWordCount

            chunks.append(DocumentCleanupChunk(
                id: UUID(),
                sectionIndex: sectionIndices[0],
                sectionIndices: sectionIndices,
                wordRange: wordRange,
                sourcePageRange: sourcePageRange,
                chapterNumber: nil,
                chapterTitle: nil,
                originalText: originalText,
                smartCleanedText: smartText,
                aiCleanedText: nil,
                status: .pending
            ))
            pendingSections = []
            pendingWordCount = 0
        }

        for section in smartSections {
            let sectionWordCount = wordCount(section.text)
            if !pendingSections.isEmpty,
               (pendingSections.count >= maxPagesPerChunk || pendingWordCount + sectionWordCount > maxWordsPerChunk) {
                appendPending()
            }

            pendingSections.append(section)
            pendingWordCount += sectionWordCount
        }

        appendPending()
        return chunks
    }

    private static func cleanupChunks(
        for section: ImportedDocumentSection,
        originalText: String,
        targetWordCount: Int
    ) -> [DocumentCleanupChunk] {
        let smartParts = splitText(section.text, targetWordCount: targetWordCount)
        let originalParts = splitText(originalText, targetWordCount: targetWordCount)
        var chunks: [DocumentCleanupChunk] = []
        var nextWordIndex = section.wordRange?.lowerBound ?? 0

        for (index, smartPart) in smartParts.enumerated() {
            let partWordCount = wordCount(smartPart)
            let wordRange = nextWordIndex..<(nextWordIndex + partWordCount)
            nextWordIndex += partWordCount
            chunks.append(DocumentCleanupChunk(
                id: UUID(),
                sectionIndex: section.index,
                sectionIndices: [section.index],
                wordRange: wordRange,
                sourcePageRange: section.pageNumber.map { $0...$0 },
                chapterNumber: section.chapterNumber,
                chapterTitle: section.chapterTitle,
                originalText: originalParts.indices.contains(index) ? originalParts[index] : smartPart,
                smartCleanedText: smartPart,
                aiCleanedText: nil,
                status: .pending
            ))
        }

        return chunks
    }

    private static func splitText(_ text: String, targetWordCount: Int) -> [String] {
        let words = text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        guard words.count > targetWordCount else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }

        var parts: [String] = []
        var index = 0
        while index < words.count {
            let end = min(index + targetWordCount, words.count)
            parts.append(words[index..<end].joined(separator: " "))
            index = end
        }
        return parts
    }

    private static func pdfMarker(for sectionIndex: Int) -> String {
        "<<<FOCUSREAD_SECTION_\(sectionIndex)>>>"
    }

    private static func textForValidation(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"<<<FOCUSREAD_SECTION_\d+>>>"#, with: " ", options: .regularExpression)
            .focusReadNormalizedDocumentText
    }

    private static func containsSummaryLanguage(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let phrases = [
            "in summary",
            "to summarize",
            "summary:",
            "this passage",
            "this document",
            "the text discusses",
            "the author explains",
            "overall,"
        ]

        return phrases.contains { lowered.contains($0) }
    }

    private static func lexicalOverlapRatio(original: String, cleaned: String) -> Double {
        let originalWords = significantWords(in: original)
        let cleanedWords = significantWords(in: cleaned)
        guard originalWords.count >= 40, cleanedWords.count >= 40 else {
            return 1
        }

        let sharedCount = originalWords.intersection(cleanedWords).count
        return Double(sharedCount) / Double(min(originalWords.count, cleanedWords.count))
    }

    private static func significantWords(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "the", "and", "that", "with", "for", "you", "are", "was", "were", "this", "from", "have", "has", "had",
            "not", "but", "his", "her", "she", "him", "they", "them", "their", "there", "then", "than", "into", "out"
        ]

        return Set(text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0) }
        )
    }
}

enum SmartCleanupAvailability {
    static var isAICleanupAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif

        return false
    }

    static var defaultMode: SmartCleanupMode {
        isAICleanupAvailable ? .ai : .smart
    }

    static var availableModes: [SmartCleanupMode] {
        if isAICleanupAvailable {
            return [.off, .smart, .ai]
        }

        return [.off, .smart]
    }

    static func effectiveMode(savedRawValue: String) -> SmartCleanupMode {
        let savedMode = SmartCleanupMode(rawValue: savedRawValue)
        return effectiveMode(for: savedMode ?? migratedMode(from: savedRawValue) ?? defaultMode)
    }

    static func effectiveMode(for mode: SmartCleanupMode) -> SmartCleanupMode {
        if mode == .ai, !isAICleanupAvailable {
            return .smart
        }

        return mode
    }

    private static func migratedMode(from rawValue: String) -> SmartCleanupMode? {
        rawValue == "light" ? .smart : nil
    }
}

private extension ImportedDocumentSection {
    func withText(_ text: String) -> ImportedDocumentSection {
        ImportedDocumentSection(
            index: index,
            text: text,
            pageNumber: pageNumber,
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            wordRange: wordRange,
            epubNavigationLevel: epubNavigationLevel,
            epubSectionRole: epubSectionRole,
            epubStructureSource: epubStructureSource,
            epubStructureConfidence: epubStructureConfidence
        )
    }

    func withWordRange(_ wordRange: Range<Int>?) -> ImportedDocumentSection {
        ImportedDocumentSection(
            index: index,
            text: text,
            pageNumber: pageNumber,
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            wordRange: wordRange,
            epubNavigationLevel: epubNavigationLevel,
            epubSectionRole: epubSectionRole,
            epubStructureSource: epubStructureSource,
            epubStructureConfidence: epubStructureConfidence
        )
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private enum FoundationModelSmartCleanup {
    static func cleanTitle(_ fileName: String, fallback: String) async -> String? {
        guard SystemLanguageModel.default.isAvailable else {
            return nil
        }

        let instructions = """
        You clean document filenames for display on this device.
        Return only a short title.
        Remove extensions, underscores, scan labels, dates, version noise, and device file prefixes.
        Do not add facts, infer missing content, summarize, or change meaning.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: "Filename: \(fileName)\nDeterministic fallback title: \(fallback)")
            return sanitizedTitle(response.content, fallback: fallback)
        } catch {
            return nil
        }
    }

    static func cleanText(_ text: String) async -> String? {
        guard SystemLanguageModel.default.isAvailable else {
            return nil
        }

        let instructions = """
        You lightly clean OCR/imported document text on this device.
        Return only the cleaned text.
        Allowed changes: remove OCR artifacts, repeated headers or footers, broken spacing, line-break hyphenation, page-number noise, and obvious formatting garbage.
        Forbidden changes: summarizing, paraphrasing, rewriting style, changing wording, adding content, removing meaningful content, or altering meaning.
        If unsure, return the input unchanged.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func sanitizedTitle(_ title: String, fallback: String) -> String? {
        let cleaned = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`")))

        guard !cleaned.isEmpty, cleaned.count <= 90 else {
            return nil
        }

        let lowered = cleaned.lowercased()
        guard !lowered.contains("summary"), !lowered.contains("unknown") else {
            return nil
        }

        return cleaned
    }
}
#endif
