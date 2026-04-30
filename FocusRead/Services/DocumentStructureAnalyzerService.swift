import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct DocumentStructureAnalyzerService: Sendable {
    private let minimumAcceptedConfidence = 0.70
    private let maximumExcerptCharacterCount = 8_000
    private let maximumExcerptWordCount = 1_500
    private let maximumRecentSummaryCount = 3
    private let maximumDetectedSectionCount = 80

    func analyze(
        chunk: DocumentCleanupChunk,
        structureState: DocumentStructureState,
        nearbyHeadingCandidates: [String]
    ) async -> ChunkStructureSummary? {
        let excerpt = Self.excerpt(from: chunk.smartCleanedText, wordLimit: maximumExcerptWordCount, characterLimit: maximumExcerptCharacterCount)
        guard excerpt.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count >= 20 else {
            return nil
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            guard let modelSummary = await FoundationModelDocumentStructureAnalyzer.analyze(
                chunk: chunk,
                excerpt: excerpt,
                recentSummaries: Array(structureState.recentChunkSummaries.suffix(maximumRecentSummaryCount)),
                outlineSummary: Self.outlineSummary(from: structureState)
            ) else {
                return nil
            }

            return validatedSummary(
                modelSummary,
                chunk: chunk,
                chunkText: chunk.smartCleanedText,
                nearbyHeadingCandidates: nearbyHeadingCandidates
            )
        }
        #endif

        return nil
    }

    func updatedState(
        byApplying summary: ChunkStructureSummary,
        to state: DocumentStructureState,
        chunk: DocumentCleanupChunk
    ) -> DocumentStructureState {
        var next = state
        next.recentChunkSummaries.append(summary)
        if next.recentChunkSummaries.count > maximumRecentSummaryCount {
            next.recentChunkSummaries = Array(next.recentChunkSummaries.suffix(maximumRecentSummaryCount))
        }

        if let label = acceptedLabel(from: summary),
           summary.startsNewSection,
           summary.confidence >= minimumAcceptedConfidence {
            next.detectedSections.append(DetectedDocumentSection(
                id: UUID(),
                chunkID: summary.chunkID,
                sectionIndex: chunk.sectionIndex,
                sourcePageRange: summary.sourcePageRange,
                chapterNumber: summary.chapterNumber,
                title: label,
                inferredSectionType: summary.inferredSectionType,
                confidence: summary.confidence
            ))
            if next.detectedSections.count > maximumDetectedSectionCount {
                next.detectedSections = Array(next.detectedSections.suffix(maximumDetectedSectionCount))
            }
        }

        if chunk.chapterNumber != nil {
            next.currentChapterNumber = chunk.chapterNumber
            next.currentChapterTitle = chunk.chapterTitle
        } else if summary.startsNewSection, let label = acceptedLabel(from: summary) {
            next.currentChapterTitle = label
        }

        next.confidence = next.recentChunkSummaries.isEmpty
            ? 0
            : next.recentChunkSummaries.map(\.confidence).reduce(0, +) / Double(next.recentChunkSummaries.count)
        return next
    }

    func acceptedLabel(from summary: ChunkStructureSummary?) -> String? {
        guard let summary, summary.confidence >= minimumAcceptedConfidence else {
            return nil
        }

        return Self.sanitizedLabel(summary.shortLabel)
            ?? Self.sanitizedLabel(summary.detectedHeading)
    }

    func deterministicHeadingCandidates(
        for chunk: DocumentCleanupChunk,
        in document: ImportedDocument?
    ) -> [String] {
        var candidates = Self.headingCandidates(in: chunk.smartCleanedText, edgeLineLimit: 12)

        guard let document else {
            return Self.unique(candidates)
        }

        let nearbyIndices = Set(chunk.sectionIndices.flatMap { [$0 - 1, $0, $0 + 1] })
        for section in document.sections where nearbyIndices.contains(section.index) {
            candidates.append(contentsOf: Self.headingCandidates(in: section.text, edgeLineLimit: 8))
            if let title = section.chapterTitle {
                candidates.append(title)
            }
        }

        return Self.unique(candidates.compactMap(Self.sanitizedLabel))
    }

    private func validatedSummary(
        _ modelSummary: ModelChunkStructureSummary,
        chunk: DocumentCleanupChunk,
        chunkText: String,
        nearbyHeadingCandidates: [String]
    ) -> ChunkStructureSummary? {
        let confidence = min(max(modelSummary.confidence ?? 0, 0), 1)
        guard confidence > 0 else {
            return nil
        }

        let detectedHeading = validatedHeading(
            modelSummary.detectedHeading,
            chunkText: chunkText,
            nearbyHeadingCandidates: nearbyHeadingCandidates
        )
        let shortLabel = validatedShortLabel(modelSummary.shortLabel, confidence: confidence)
        let evidence = validatedEvidence(
            modelSummary.evidence,
            chunkText: chunkText,
            nearbyHeadingCandidates: nearbyHeadingCandidates
        )
        let repairAction = validatedRepairAction(
            modelSummary.epubStructureRepairAction,
            evidence: evidence,
            confidence: confidence
        )

        guard detectedHeading != nil ||
                shortLabel != nil ||
                repairAction != nil ||
                modelSummary.startsNewSection == true ||
                modelSummary.continuationOfPrevious == true else {
            return nil
        }

        return ChunkStructureSummary(
            chunkID: chunk.id,
            sourcePageRange: chunk.sourcePageRange,
            chapterNumber: chunk.chapterNumber,
            detectedHeading: detectedHeading,
            inferredSectionType: Self.sanitizedSectionType(modelSummary.inferredSectionType),
            epubStructureRepairAction: repairAction,
            evidence: evidence,
            startsNewSection: modelSummary.startsNewSection ?? false,
            continuationOfPrevious: modelSummary.continuationOfPrevious ?? false,
            shortLabel: shortLabel,
            confidence: confidence
        )
    }

    private func validatedHeading(
        _ heading: String?,
        chunkText: String,
        nearbyHeadingCandidates: [String]
    ) -> String? {
        guard let heading = Self.sanitizedLabel(heading) else {
            return nil
        }

        let normalizedHeading = Self.normalizedComparableText(heading)
        guard !normalizedHeading.isEmpty else {
            return nil
        }

        let normalizedChunkText = Self.normalizedComparableText(chunkText)
        if normalizedChunkText.contains(normalizedHeading) {
            return heading
        }

        let candidateMatches = nearbyHeadingCandidates.contains { candidate in
            Self.normalizedComparableText(candidate) == normalizedHeading
        }
        return candidateMatches ? heading : nil
    }

    private func validatedShortLabel(_ label: String?, confidence: Double) -> String? {
        guard confidence >= minimumAcceptedConfidence,
              let label = Self.sanitizedLabel(label),
              !Self.containsSummaryLanguage(label) else {
            return nil
        }

        return label
    }

    private func validatedEvidence(
        _ evidence: String?,
        chunkText: String,
        nearbyHeadingCandidates: [String]
    ) -> String? {
        guard let evidence = Self.sanitizedLabel(evidence) else {
            return nil
        }

        let normalizedEvidence = Self.normalizedComparableText(evidence)
        guard !normalizedEvidence.isEmpty else {
            return nil
        }

        if Self.normalizedComparableText(chunkText).contains(normalizedEvidence) {
            return evidence
        }

        let candidateMatches = nearbyHeadingCandidates.contains { candidate in
            Self.normalizedComparableText(candidate).contains(normalizedEvidence) ||
                normalizedEvidence.contains(Self.normalizedComparableText(candidate))
        }
        return candidateMatches ? evidence : nil
    }

    private func validatedRepairAction(
        _ action: String?,
        evidence: String?,
        confidence: Double
    ) -> EPUBStructureRepairAction? {
        guard confidence >= minimumAcceptedConfidence,
              let action,
              let repairAction = EPUBStructureRepairAction(rawValue: action),
              evidence != nil || repairAction == .keep else {
            return nil
        }

        return repairAction
    }

    private static func excerpt(from text: String, wordLimit: Int, characterLimit: Int) -> String {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        let wordLimited = words.prefix(wordLimit).joined(separator: " ")
        if wordLimited.count <= characterLimit {
            return wordLimited
        }

        return String(wordLimited.prefix(characterLimit))
    }

    private static func outlineSummary(from state: DocumentStructureState) -> String {
        let labels = state.detectedSections
            .suffix(8)
            .map { section in
                if let pageRange = section.sourcePageRange {
                    return "pages \(pageRange.lowerBound)-\(pageRange.upperBound): \(section.title)"
                }
                if let chapterNumber = section.chapterNumber {
                    return "chapter \(chapterNumber): \(section.title)"
                }
                return section.title
            }

        guard !labels.isEmpty else {
            return "No accepted outline entries yet."
        }

        return labels.joined(separator: " | ")
    }

    private static func headingCandidates(in text: String, edgeLineLimit: Int) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let edgeLines = Array(lines.prefix(edgeLineLimit)) + Array(lines.suffix(edgeLineLimit))
        return edgeLines.compactMap { line in
            guard line.count >= 3, line.count <= 90 else { return nil }
            guard line.split(whereSeparator: { $0.isWhitespace }).count <= 12 else { return nil }
            guard line.range(of: #"[.!?]\s*$"#, options: .regularExpression) == nil else { return nil }
            guard line.range(of: #"^\d+$"#, options: .regularExpression) == nil else { return nil }
            return sanitizedLabel(line)
        }
    }

    private static func sanitizedLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let cleaned = label
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`")))

        guard !cleaned.isEmpty, cleaned.count <= 90 else {
            return nil
        }

        return cleaned
    }

    private static func sanitizedSectionType(_ type: String?) -> String? {
        guard let type = sanitizedLabel(type)?.lowercased(),
              type.count <= 40,
              !containsSummaryLanguage(type) else {
            return nil
        }

        return type
    }

    private static func containsSummaryLanguage(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let phrases = [
            "summary",
            "summarize",
            "this passage",
            "this document",
            "the text discusses",
            "the author explains",
            "overall"
        ]

        return phrases.contains { lowered.contains($0) }
    }

    private static func normalizedComparableText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for value in values {
            let key = normalizedComparableText(value)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(value)
        }
        return output
    }
}

private struct ModelChunkStructureSummary: Decodable, Sendable {
    let detectedHeading: String?
    let inferredSectionType: String?
    let epubStructureRepairAction: String?
    let evidence: String?
    let startsNewSection: Bool?
    let continuationOfPrevious: Bool?
    let shortLabel: String?
    let confidence: Double?
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private enum FoundationModelDocumentStructureAnalyzer {
    static func analyze(
        chunk: DocumentCleanupChunk,
        excerpt: String,
        recentSummaries: [ChunkStructureSummary],
        outlineSummary: String
    ) async -> ModelChunkStructureSummary? {
        let instructions = """
        You analyze document structure metadata for a reading app.
        Return strict JSON only with keys: detectedHeading, inferredSectionType, epubStructureRepairAction, evidence, startsNewSection, continuationOfPrevious, shortLabel, confidence.
        You may suggest cleaner labels, whether this chunk starts a section, whether it continues the previous section, likely section type, and an advisory EPUB repair action.
        epubStructureRepairAction must be one of: keep, mergeWithPrevious, splitAtEvidence.
        evidence must be exact nearby visible text supporting the label or advisory action.
        You must not rewrite document text, summarize content, invent chapters, reorder sections, remove sections, or add facts.
        detectedHeading must be text that appears in the chunk or is directly supported by a visible heading.
        shortLabel must be a short navigation label, not a summary.
        Advisory repair actions are metadata only; they do not change imported text or live reader boundaries.
        """

        let prompt = """
        Chunk ID: \(chunk.id.uuidString)
        Source page range: \(Self.pageRangeDescription(chunk.sourcePageRange))
        EPUB chapter number: \(chunk.chapterNumber.map(String.init) ?? "none")
        EPUB chapter title: \(chunk.chapterTitle ?? "none")

        Previous summaries:
        \(Self.recentSummaryDescription(recentSummaries))

        Current accepted outline:
        \(outlineSummary)

        Current chunk excerpt:
        \(excerpt)
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            guard let data = response.content.data(using: .utf8) else {
                return nil
            }

            return try JSONDecoder().decode(ModelChunkStructureSummary.self, from: data)
        } catch {
            return nil
        }
    }

    private static func pageRangeDescription(_ range: ClosedRange<Int>?) -> String {
        guard let range else { return "none" }
        if range.lowerBound == range.upperBound {
            return "\(range.lowerBound)"
        }
        return "\(range.lowerBound)-\(range.upperBound)"
    }

    private static func recentSummaryDescription(_ summaries: [ChunkStructureSummary]) -> String {
        guard !summaries.isEmpty else {
            return "none"
        }

        return summaries.map { summary in
            [
                "chunk=\(summary.chunkID.uuidString)",
                "heading=\(summary.detectedHeading ?? "none")",
                "type=\(summary.inferredSectionType ?? "none")",
                "repair=\(summary.epubStructureRepairAction?.rawValue ?? "none")",
                "evidence=\(summary.evidence ?? "none")",
                "startsNewSection=\(summary.startsNewSection)",
                "continues=\(summary.continuationOfPrevious)",
                "label=\(summary.shortLabel ?? "none")",
                "confidence=\(summary.confidence)"
            ].joined(separator: ", ")
        }.joined(separator: "\n")
    }
}
#endif
