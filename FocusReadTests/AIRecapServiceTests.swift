import XCTest
@testable import FocusRead

final class AIRecapServiceTests: XCTestCase {
    func testRecentEligibleSessionsUsesOnlyRangedSessionsForBook() {
        let readID = UUID()
        let otherReadID = UUID()
        let extractor = AIRecapSourceExtractor(minimumInputWordCount: 1)
        let events = [
            event(readID: readID, endedAt: date("2026-05-01T10:00:00Z"), range: 0..<100),
            event(readID: readID, endedAt: date("2026-05-04T10:00:00Z"), range: 100..<200),
            event(readID: readID, endedAt: date("2026-05-03T10:00:00Z"), range: nil),
            event(readID: otherReadID, endedAt: date("2026-05-05T10:00:00Z"), range: 0..<100),
            event(readID: readID, endedAt: date("2026-05-02T10:00:00Z"), range: 200..<300)
        ]

        let eligible = extractor.recentEligibleSessions(for: readID, from: events)

        XCTAssertEqual(eligible.map(\.endedAt), [
            date("2026-05-04T10:00:00Z"),
            date("2026-05-02T10:00:00Z"),
            date("2026-05-01T10:00:00Z")
        ])
    }

    func testRecentEligibleSessionsRecoversOnlyMostRecentRangeLessSessionForSavedRead() {
        var read = makeRead(wordCount: 200)
        read.currentWordIndex = 120
        let extractor = AIRecapSourceExtractor(minimumInputWordCount: 1)
        let olderMissingRange = event(readID: read.id, endedAt: date("2026-05-01T10:00:00Z"), range: nil)
        let ranged = event(readID: read.id, endedAt: date("2026-05-02T10:00:00Z"), range: 50..<80)
        let newestMissingRange = event(readID: read.id, endedAt: date("2026-05-03T10:00:00Z"), range: nil)

        let eligible = extractor.recentEligibleSessions(for: read, from: [
            olderMissingRange,
            ranged,
            newestMissingRange
        ])

        XCTAssertEqual(eligible.map(\.id), [
            newestMissingRange.id,
            ranged.id
        ])
    }

    func testSourceExtractionUsesSessionRangeAndCapsLongInput() throws {
        let read = makeRead(wordCount: 120)
        let extractor = AIRecapSourceExtractor(maximumInputWordCount: 20, minimumInputWordCount: 1)
        let session = event(readID: read.id, range: 10..<80)

        let source = try extractor.source(for: read, sessionEvent: session)

        XCTAssertEqual(source.sourceStartWordIndex, 60)
        XCTAssertEqual(source.sourceEndWordIndex, 80)
        XCTAssertEqual(source.wordCount, 20)
        XCTAssertTrue(source.isCapped)
        XCTAssertTrue(source.text.hasPrefix("word60 word61"))
        XCTAssertTrue(source.text.hasSuffix("word79"))
    }

    func testSourceExtractionRecoversRangeLessSessionFromSavedProgress() throws {
        var read = makeRead(wordCount: 200)
        read.currentWordIndex = 120
        let extractor = AIRecapSourceExtractor(maximumInputWordCount: 100, minimumInputWordCount: 1)
        let session = event(readID: read.id, range: nil)

        let source = try extractor.source(for: read, sessionEvent: session)

        XCTAssertEqual(source.sourceStartWordIndex, 70)
        XCTAssertEqual(source.sourceEndWordIndex, 120)
        XCTAssertEqual(source.wordCount, 50)
        XCTAssertTrue(source.text.hasPrefix("word70 word71"))
        XCTAssertTrue(source.text.hasSuffix("word119"))
    }

    func testSourceExtractionRejectsVeryShortSessionText() {
        let read = makeRead(wordCount: 10)
        let extractor = AIRecapSourceExtractor(maximumInputWordCount: 20, minimumInputWordCount: 8)
        let session = event(readID: read.id, range: 2..<5)

        XCTAssertThrowsError(try extractor.source(for: read, sessionEvent: session)) { error in
            XCTAssertEqual(error as? AIRecapGenerationError, .notEnoughText)
        }
    }

    func testServiceGeneratesRecapWithInjectedLocalModel() async throws {
        let read = makeRead(wordCount: 80)
        let generatedAt = date("2026-05-07T12:00:00Z")
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(maximumInputWordCount: 50, minimumInputWordCount: 1),
            model: FakeRecapModel(output: "A concise on-device recap."),
            dateProvider: { generatedAt }
        )
        let session = event(
            readID: read.id,
            endedAt: date("2026-05-07T10:10:00Z"),
            range: 5..<45
        )

        let recap = try await service.generateRecap(for: read, sessionEvent: session)

        XCTAssertEqual(recap.readID, read.id)
        XCTAssertEqual(recap.sessionID, session.id)
        XCTAssertEqual(recap.sourceStartWordIndex, 5)
        XCTAssertEqual(recap.sourceEndWordIndex, 45)
        XCTAssertEqual(recap.generatedText, "A concise on-device recap.")
        XCTAssertEqual(recap.createdAt, generatedAt)
        XCTAssertEqual(recap.inputWordCount, 40)
        XCTAssertEqual(recap.modelName, "Fake Local Model")
    }

    func testServiceRejectsUnavailableLocalModel() async {
        let read = makeRead(wordCount: 80)
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 1),
            model: FakeRecapModel(isAvailable: false, output: "")
        )

        do {
            _ = try await service.generateRecap(for: read, sessionEvent: event(readID: read.id, range: 0..<20))
            XCTFail("Expected localAIUnavailable")
        } catch {
            XCTAssertEqual(error as? AIRecapGenerationError, .localAIUnavailable)
        }
    }

    func testEnglishSourceGeneratesEnglishRecap() async throws {
        let read = makeRead(text: englishText(wordCount: 280))
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: LanguageAwareFakeRecapModel()
        )

        let recap = try await service.generateRecap(for: read, sessionEvent: event(readID: read.id, range: 0..<280))

        XCTAssertEqual(recap.generatedText, "This is an English recap.")
        XCTAssertEqual(recap.sourceLanguageCode, "en")
        XCTAssertEqual(recap.sourceLanguageName, "English")
    }

    func testFrenchSourceGeneratesFrenchRecap() async throws {
        let read = makeRead(text: frenchText(wordCount: 280))
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: LanguageAwareFakeRecapModel()
        )

        let recap = try await service.generateRecap(for: read, sessionEvent: event(readID: read.id, range: 0..<280))

        XCTAssertEqual(recap.generatedText, "Ceci est un résumé en français.")
        XCTAssertEqual(recap.sourceLanguageCode, "fr")
        XCTAssertEqual(recap.sourceLanguageName, "French")
    }

    func testCleanFrenchSevenHundredWordSampleGeneratesFrenchRecap() async throws {
        let read = makeRead(text: frenchText(wordCount: 700))
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: LanguageAwareFakeRecapModel()
        )

        let recap = try await service.generateRecap(for: read, sessionEvent: event(readID: read.id, range: 0..<700))

        XCTAssertEqual(recap.generatedText, "Ceci est un résumé en français.")
        XCTAssertEqual(recap.sourceLanguageCode, "fr")
        XCTAssertEqual(recap.inputWordCount, 700)
    }

    func testShortFrenchSourceGeneratesFrenchRecapWhenAllowed() async throws {
        let read = makeRead(text: frenchText(wordCount: 100))
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 1),
            model: LanguageAwareFakeRecapModel()
        )

        let recap = try await service.generateRecap(for: read, sessionEvent: event(readID: read.id, range: 0..<100))

        XCTAssertEqual(recap.generatedText, "Ceci est un résumé en français.")
        XCTAssertEqual(recap.sourceLanguageCode, "fr")
    }

    func testMetadataLanguagePreferredWhenReliable() throws {
        var read = makeRead(text: englishText(wordCount: 280))
        read.languageCode = "fr"
        let extractor = AIRecapSourceExtractor(minimumInputWordCount: 250)

        let source = try extractor.source(for: read, sessionEvent: event(readID: read.id, range: 0..<280))

        XCTAssertEqual(source.detectedLanguage?.code, "fr")
        XCTAssertEqual(source.detectedLanguage?.source, .metadata)
    }

    func testFrenchEPUBSourceTextIsCleanedAndPreservesAccents() throws {
        let read = makeImportedRead(
            text: dirtyFrenchEPUBText(wordCount: 700),
            sourceType: .epub,
            languageCode: "fr"
        )
        let extractor = AIRecapSourceExtractor(minimumInputWordCount: 250)
        let source = try extractor.source(for: read, sessionEvent: event(readID: read.id, range: 0..<read.totalWordCount))

        XCTAssertEqual(source.detectedLanguage?.code, "fr")
        XCTAssertEqual(source.documentSourceType, .epub)
        XCTAssertGreaterThan(source.rawTextLength, source.cleanedTextLength)
        XCTAssertFalse(source.text.contains("<p>"))
        XCTAssertFalse(source.text.contains("</em>"))
        XCTAssertFalse(source.text.contains("&eacute;"))
        XCTAssertFalse(source.text.contains("\u{200B}"))
        XCTAssertTrue(source.text.contains("Élise"))
        XCTAssertTrue(source.text.contains("mémoire"))
        XCTAssertTrue(source.text.contains("œuvre"))
        XCTAssertTrue(source.text.contains("garçon"))
    }

    func testMalformedMarkupControlCharactersAreCleanedBeforeRecapInput() throws {
        let text = """
        <?xml version="1.0"?><html><body><script>ignore()</script><!-- remove -->
        <p>Chapter 3\u{0000} begins with clear prose&nbsp;about knowledge.</p>
        <p>It keeps accents like Émilie, François, garçon, and œuvre.\u{200B}</p>
        </body></html>
        """
        let read = makeImportedRead(text: repeatedWords([text], count: 260), sourceType: .epub, languageCode: "en")
        let source = try AIRecapSourceExtractor(minimumInputWordCount: 1)
            .source(for: read, sessionEvent: event(readID: read.id, range: 0..<read.totalWordCount))

        XCTAssertFalse(source.text.contains("<script>"))
        XCTAssertFalse(source.text.contains("ignore()"))
        XCTAssertFalse(source.text.contains("<!--"))
        XCTAssertFalse(source.text.contains("&nbsp;"))
        XCTAssertFalse(source.text.contains("\u{0000}"))
        XCTAssertFalse(source.text.contains("\u{200B}"))
        XCTAssertTrue(source.text.contains("Émilie"))
        XCTAssertTrue(source.text.contains("œuvre"))
        XCTAssertGreaterThan(source.longestParagraphLength, 0)
        XCTAssertGreaterThan(source.estimatedTokenCount, 0)
    }

    func testFrenchEPUBSevenHundredWordLogicalSessionGeneratesRecap() async throws {
        let read = makeImportedRead(
            text: dirtyFrenchEPUBText(wordCount: 700),
            sourceType: .epub,
            languageCode: "fr"
        )
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: LanguageAwareFakeRecapModel()
        )

        let recap = try await service.generateRecap(
            for: read,
            sessionEvent: event(readID: read.id, range: 0..<read.totalWordCount)
        )

        XCTAssertEqual(recap.generatedText, "Ceci est un résumé en français.")
        XCTAssertEqual(recap.sourceLanguageCode, "fr")
        XCTAssertEqual(recap.inputWordCount, 700)
    }

    func testFrenchUnsupportedByLocalModelFailsWithSpecificError() async {
        let read = makeImportedRead(
            text: frenchText(wordCount: 700),
            sourceType: .epub,
            languageCode: "fr"
        )
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: LanguageSupportFakeRecapModel(unsupportedLanguageCodes: ["fr"])
        )

        do {
            _ = try await service.generateRecap(for: read, sessionEvent: event(readID: read.id, range: 0..<700))
            XCTFail("Expected unsupportedLanguage")
        } catch {
            XCTAssertEqual(error as? AIRecapGenerationError, .unsupportedLanguage)
        }
    }

    func testRussellChapterThreeStyleEPUBInputUsesCharacterAndTokenSafetyBudget() async throws {
        let read = makeImportedRead(
            text: russellChapterThreeStylePublicDomainText(wordCount: 2_800),
            sourceType: .epub,
            languageCode: "en"
        )
        let recorder = RecapModelAttemptRecorder()
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: RecordingRecapModel(recorder: recorder, output: "Russell weighs idealism against common sense.")
        )

        let recap = try await service.generateRecap(
            for: read,
            sessionEvent: event(readID: read.id, range: 0..<read.totalWordCount)
        )
        let attempts = await recorder.attempts

        XCTAssertEqual(recap.generatedText, "Russell weighs idealism against common sense.")
        XCTAssertEqual(attempts.count, 1)
        XCTAssertLessThanOrEqual(attempts[0].wordCount, 2_800)
        XCTAssertLessThanOrEqual(attempts[0].characterCount, 12_000)
        XCTAssertLessThanOrEqual(attempts[0].estimatedTokenCount, 2_650)
        XCTAssertEqual(attempts[0].documentSourceType, .epub)
    }

    func testDenseLongParagraphInputIsWindowedBelowModelSafetyCaps() async throws {
        let longWords = (0..<3_000).map { "extraordinarilyelongatedphilosophicalterm\($0)" }.joined(separator: " ")
        let read = makeImportedRead(text: longWords, sourceType: .epub, languageCode: "en")
        let recorder = RecapModelAttemptRecorder()
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: RecordingRecapModel(recorder: recorder, output: "A compact recap.")
        )

        _ = try await service.generateRecap(
            for: read,
            sessionEvent: event(readID: read.id, range: 0..<read.totalWordCount)
        )
        let attempts = await recorder.attempts

        XCTAssertEqual(attempts.count, 1)
        XCTAssertLessThan(attempts[0].wordCount, 3_000)
        XCTAssertLessThanOrEqual(attempts[0].characterCount, 12_000)
        XCTAssertLessThanOrEqual(attempts[0].estimatedTokenCount, 2_650)
        XCTAssertGreaterThan(attempts[0].averageWordLength, 20)
        XCTAssertGreaterThan(attempts[0].longestParagraphLength, 8_000)
    }

    func testGenerationFailureRetriesOnceWithSmallerRecentWindow() async throws {
        let read = makeImportedRead(
            text: russellChapterThreeStylePublicDomainText(wordCount: 2_800),
            sourceType: .epub,
            languageCode: "en"
        )
        let recorder = RecapModelAttemptRecorder()
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: FailFirstThenSucceedRecapModel(recorder: recorder)
        )

        let recap = try await service.generateRecap(
            for: read,
            sessionEvent: event(readID: read.id, range: 0..<read.totalWordCount)
        )
        let attempts = await recorder.attempts

        XCTAssertEqual(recap.generatedText, "Fallback recap succeeded.")
        XCTAssertEqual(attempts.count, 2)
        XCTAssertLessThan(attempts[1].wordCount, attempts[0].wordCount)
        XCTAssertLessThanOrEqual(attempts[1].wordCount, 1_800)
        XCTAssertLessThanOrEqual(attempts[1].characterCount, 7_500)
        XCTAssertLessThanOrEqual(attempts[1].estimatedTokenCount, 1_750)
    }

    func testGenerationFailureDoesNotRetryEndlessly() async {
        let read = makeImportedRead(
            text: russellChapterThreeStylePublicDomainText(wordCount: 2_800),
            sourceType: .epub,
            languageCode: "en"
        )
        let recorder = RecapModelAttemptRecorder()
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
            model: AlwaysFailingRecapModel(recorder: recorder)
        )

        do {
            _ = try await service.generateRecap(
                for: read,
                sessionEvent: event(readID: read.id, range: 0..<read.totalWordCount)
            )
            XCTFail("Expected generationFailed")
        } catch {
            let attempts = await recorder.attempts
            XCTAssertEqual(error as? AIRecapGenerationError, .generationFailed)
            XCTAssertEqual(attempts.count, 2)
        }
    }

    @MainActor
    func testFailedRegenerationPreservesExistingRecap() async {
        let read = makeRead(wordCount: 800)
        let session = event(readID: read.id, range: 0..<600)
        let existing = AIRecap(
            readID: read.id,
            sessionID: session.id,
            sessionStartedAt: session.startedAt,
            sessionEndedAt: session.endedAt,
            sourceStartWordIndex: 0,
            sourceEndWordIndex: 600,
            generatedText: "Existing valid recap.",
            inputWordCount: 600,
            outputWordCount: 3,
            modelName: "Fake Local Model",
            modelVersion: "test"
        )
        let statsStore = MockReadingStatsStore(sessionEvents: [session])
        let recapStore = MockAIRecapStore(recaps: [existing])
        let viewModel = AIRecapViewModel(
            read: read,
            readingStatsStore: statsStore,
            recapStore: recapStore,
            service: AIRecapService(
                extractor: AIRecapSourceExtractor(minimumInputWordCount: 250),
                model: AlwaysFailingRecapModel(recorder: RecapModelAttemptRecorder())
            ),
            isAIRecapsEnabledProvider: { true }
        )

        guard let item = viewModel.items.first else {
            XCTFail("Expected an eligible recap session")
            return
        }

        viewModel.generate(for: item, regenerate: true)
        await waitForGenerationToFinish(viewModel)

        XCTAssertEqual(recapStore.recaps(for: read.id), [existing])
        XCTAssertEqual(recapStore.savedRecaps, [])
        XCTAssertEqual(viewModel.errorMessage, L10n.string(.aiRecapGenerationFailed))
    }

    func testFrenchPromptUsesSimpleInstructionWithoutRedetection() throws {
        let read = makeRead(text: frenchText(wordCount: 280))
        let source = try AIRecapSourceExtractor(minimumInputWordCount: 250)
            .source(for: read, sessionEvent: event(readID: read.id, range: 0..<280))

        let prompt = AIRecapPromptBuilder.makePrompt(for: source, outputWordLimit: 500)

        XCTAssertTrue(prompt.instructions.contains("Summarize the following reading session in French."))
        XCTAssertFalse(prompt.instructions.localizedCaseInsensitiveContains("detect"))
        XCTAssertFalse(prompt.logDescription.contains(source.text))
        XCTAssertTrue(prompt.logDescription.contains("[omitted"))
    }

    func testPausePlayAfterTenSecondsMergesIntoSameLogicalRecapSession() {
        let read = makeRead(wordCount: 400)
        let first = event(readID: read.id, startedAt: date("2026-05-07T10:00:00Z"), endedAt: date("2026-05-07T10:02:00Z"), range: 0..<180)
        let second = event(readID: read.id, startedAt: date("2026-05-07T10:02:10Z"), endedAt: date("2026-05-07T10:04:00Z"), range: 180..<360)

        let sessions = AIRecapSourceExtractor(minimumInputWordCount: 250).recentEligibleSessions(for: read, from: [first, second])

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sourceWordRange, 0..<360)
    }

    func testPausePlayAfterFiveMinutesMergesIntoSameLogicalRecapSession() {
        let read = makeRead(wordCount: 500)
        let first = event(readID: read.id, startedAt: date("2026-05-07T10:00:00Z"), endedAt: date("2026-05-07T10:05:00Z"), range: 0..<200)
        let second = event(readID: read.id, startedAt: date("2026-05-07T10:10:00Z"), endedAt: date("2026-05-07T10:15:00Z"), range: 200..<420)

        let sessions = AIRecapSourceExtractor(minimumInputWordCount: 250).recentEligibleSessions(for: read, from: [first, second])

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sourceWordRange, 0..<420)
    }

    func testNearbySessionsFromDistantSourceRangesDoNotMerge() {
        let read = makeRead(wordCount: 1_000)
        let first = event(readID: read.id, startedAt: date("2026-05-07T10:00:00Z"), endedAt: date("2026-05-07T10:05:00Z"), range: 0..<120)
        let second = event(readID: read.id, startedAt: date("2026-05-07T10:10:00Z"), endedAt: date("2026-05-07T10:15:00Z"), range: 900..<980)

        let sessions = AIRecapSourceExtractor(minimumInputWordCount: 1).recentEligibleSessions(for: read, from: [first, second])

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.sourceWordRange), [900..<980, 0..<120])
    }

    func testReturnAfterThirtyOneMinutesStartsNewLogicalRecapSession() {
        let read = makeRead(wordCount: 700)
        let first = event(readID: read.id, startedAt: date("2026-05-07T10:00:00Z"), endedAt: date("2026-05-07T10:10:00Z"), range: 0..<300)
        let second = event(readID: read.id, startedAt: date("2026-05-07T10:41:00Z"), endedAt: date("2026-05-07T10:50:00Z"), range: 300..<620)

        let sessions = AIRecapSourceExtractor(minimumInputWordCount: 250).recentEligibleSessions(for: read, from: [first, second])

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.sourceWordRange), [300..<620, 0..<300])
    }

    func testMultipleShortSegmentsWithinThirtyMinutesMergeIntoEligibleSession() {
        let read = makeRead(wordCount: 400)
        let segments = [
            event(readID: read.id, startedAt: date("2026-05-07T10:00:00Z"), endedAt: date("2026-05-07T10:01:00Z"), range: 0..<90),
            event(readID: read.id, startedAt: date("2026-05-07T10:06:00Z"), endedAt: date("2026-05-07T10:07:00Z"), range: 90..<180),
            event(readID: read.id, startedAt: date("2026-05-07T10:12:00Z"), endedAt: date("2026-05-07T10:13:00Z"), range: 180..<270)
        ]

        let sessions = AIRecapSourceExtractor(minimumInputWordCount: 250).recentEligibleSessions(for: read, from: segments)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sourceWordRange, 0..<270)
    }

    func testMergedLogicalSessionIDChangesWhenNewEventsExtendSession() {
        let read = makeRead(wordCount: 500)
        let first = event(readID: read.id, startedAt: date("2026-05-07T10:00:00Z"), endedAt: date("2026-05-07T10:05:00Z"), range: 0..<180)
        let second = event(readID: read.id, startedAt: date("2026-05-07T10:10:00Z"), endedAt: date("2026-05-07T10:15:00Z"), range: 180..<320)
        let extractor = AIRecapSourceExtractor(minimumInputWordCount: 1)

        let originalSession = extractor.recentEligibleSessions(for: read, from: [first])
        let extendedSession = extractor.recentEligibleSessions(for: read, from: [first, second])
        let recalculatedExtendedSession = extractor.recentEligibleSessions(for: read, from: [first, second])

        XCTAssertEqual(originalSession.count, 1)
        XCTAssertEqual(originalSession[0].id, first.id)
        XCTAssertEqual(extendedSession.count, 1)
        XCTAssertEqual(extendedSession[0].sourceWordRange, 0..<320)
        XCTAssertNotEqual(extendedSession[0].id, first.id)
        XCTAssertEqual(extendedSession[0].id, recalculatedExtendedSession[0].id)
    }

    func testOneWordSessionIsNotRecapable() {
        let read = makeRead(wordCount: 300)
        let session = event(readID: read.id, range: 0..<1)

        let sessions = AIRecapSourceExtractor().recentEligibleSessions(for: read, from: [session])

        XCTAssertEqual(sessions, [])
    }

    func testOneHundredWordSessionIsNotRecapable() {
        let read = makeRead(wordCount: 300)
        let session = event(readID: read.id, range: 0..<100)

        let sessions = AIRecapSourceExtractor().recentEligibleSessions(for: read, from: [session])

        XCTAssertEqual(sessions, [])
    }

    func testTwoHundredFiftyWordSessionIsRecapable() {
        let read = makeRead(wordCount: 300)
        let session = event(readID: read.id, range: 0..<250)

        let sessions = AIRecapSourceExtractor().recentEligibleSessions(for: read, from: [session])

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sourceWordRange, 0..<250)
    }

    func testSixThousandWordSessionCapsToMostRecentFiveThousandWords() throws {
        let read = makeRead(wordCount: 6_200)
        let extractor = AIRecapSourceExtractor()

        let source = try extractor.source(for: read, sessionEvent: event(readID: read.id, range: 0..<6_000))

        XCTAssertEqual(source.sourceStartWordIndex, 1_000)
        XCTAssertEqual(source.sourceEndWordIndex, 6_000)
        XCTAssertEqual(source.sourceWordCountBeforeCap, 6_000)
        XCTAssertEqual(source.wordCount, 5_000)
        XCTAssertTrue(source.isCapped)
        XCTAssertTrue(source.text.hasPrefix("word1000 word1001"))
        XCTAssertTrue(source.text.hasSuffix("word5999"))
    }

    private func makeRead(wordCount: Int) -> SavedRead {
        let text = (0..<wordCount).map { "word\($0)" }.joined(separator: " ")
        return makeRead(text: text)
    }

    private func makeRead(text: String) -> SavedRead {
        let tokens = TextTokenizer().tokenize(text)
        return SavedReadMapper.makeSavedRead(from: text, tokens: tokens, now: date("2026-05-07T09:00:00Z"))
    }

    private func makeImportedRead(
        text: String,
        sourceType: DocumentSourceType,
        languageCode: String?
    ) -> SavedRead {
        let document = ImportedDocument(
            fileName: "french.epub",
            displayTitle: "Livre français",
            author: "Autrice",
            text: text,
            sourceType: sourceType,
            languageCode: languageCode
        )
        let tokens = TextTokenizer().tokenize(document)
        return SavedReadMapper.makeSavedRead(from: document, tokens: tokens, now: date("2026-05-07T09:00:00Z"))
    }

    private func event(
        readID: UUID,
        endedAt: Date = Date(),
        range: Range<Int>?
    ) -> ReadingSessionEvent {
        event(
            readID: readID,
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            range: range
        )
    }

    private func event(
        readID: UUID,
        startedAt: Date,
        endedAt: Date,
        range: Range<Int>?
    ) -> ReadingSessionEvent {
        ReadingSessionEvent(
            readID: readID,
            startedAt: startedAt,
            endedAt: endedAt,
            wordsRead: range.map { $0.count } ?? 50,
            averageWPM: 300,
            sourceStartWordIndex: range?.lowerBound,
            sourceEndWordIndex: range?.upperBound
        )
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private func englishText(wordCount: Int) -> String {
        repeatedWords(["the", "reader", "follows", "a", "clear", "English", "chapter", "about", "memory", "and", "attention"], count: wordCount)
    }

    private func frenchText(wordCount: Int) -> String {
        repeatedWords(["le", "lecteur", "suit", "un", "chapitre", "français", "sur", "la", "mémoire", "et", "l’attention", "où", "Élise", "écrit", "à", "François", "une", "œuvre", "claire", "pour", "le", "garçon"], count: wordCount)
    }

    private func dirtyFrenchEPUBText(wordCount: Int) -> String {
        repeatedWords([
            "<p>Élise",
            "décrit",
            "la",
            "mémoire",
            "d’un",
            "garçon</p>",
            "<em>&eacute;tonné</em>",
            "par",
            "l’œuvre",
            "à",
            "côté",
            "du",
            "marché\u{200B}",
            "et",
            "François",
            "écoute",
            "sans",
            "bruit.",
            "Le",
            "cœur",
            "reste",
            "clair"
        ], count: wordCount)
    }

    private func russellChapterThreeStylePublicDomainText(wordCount: Int) -> String {
        let bodyWords = """
        <section><h1>Chapter III. The Nature of Matter</h1>
        In considering the problems of philosophy, Bertrand Russell asks whether the table that seems so familiar is known directly, or whether its colour, hardness, and shape are appearances related to our senses. The argument proceeds carefully through sense-data, belief, matter, idealism, and the stubborn habit of common sense. It is public-domain prose with long clauses, semicolons, and XHTML wrappers that should not confuse the recap input budget.
        </section>
        """.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        return """
        *** START OF THE PROJECT GUTENBERG EBOOK THE PROBLEMS OF PHILOSOPHY ***
        \(repeatedWords(bodyWords, count: wordCount))
        """
    }

    private func repeatedWords(_ words: [String], count: Int) -> String {
        (0..<count).map { words[$0 % words.count] }.joined(separator: " ")
    }

    @MainActor
    private func waitForGenerationToFinish(_ viewModel: AIRecapViewModel) async {
        for _ in 0..<500 where viewModel.isGenerating {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        await Task.yield()
    }
}

private struct FakeRecapModel: AIRecapModelGenerating {
    var isAvailable = true
    var output: String
    var modelName: String { "Fake Local Model" }
    var modelVersion: String { "test" }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        output
    }
}

private struct LanguageAwareFakeRecapModel: AIRecapModelGenerating {
    var isAvailable = true
    var modelName: String { "Fake Local Model" }
    var modelVersion: String { "test" }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        if source.detectedLanguage?.code == "fr" {
            return "Ceci est un résumé en français."
        }

        return "This is an English recap."
    }
}

private struct LanguageSupportFakeRecapModel: AIRecapModelGenerating {
    var isAvailable = true
    var unsupportedLanguageCodes: Set<String>
    var modelName: String { "Fake Local Model" }
    var modelVersion: String { "test" }
    var availabilityDebugDescription: String { "available supportedLanguages=en" }

    func supportsLanguage(_ code: String) -> Bool? {
        !unsupportedLanguageCodes.contains(code)
    }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        "This should not be generated."
    }
}

private struct RecapModelAttempt: Equatable, Sendable {
    let wordCount: Int
    let characterCount: Int
    let estimatedTokenCount: Int
    let averageWordLength: Double
    let longestParagraphLength: Int
    let documentSourceType: SavedReadSourceType
}

private actor RecapModelAttemptRecorder {
    private(set) var attempts: [RecapModelAttempt] = []

    func record(_ source: AIRecapSource) {
        attempts.append(RecapModelAttempt(
            wordCount: source.wordCount,
            characterCount: source.cleanedTextLength,
            estimatedTokenCount: source.estimatedTokenCount,
            averageWordLength: source.averageWordLength,
            longestParagraphLength: source.longestParagraphLength,
            documentSourceType: source.documentSourceType
        ))
    }
}

private enum RecapModelTestError: Error {
    case failed
}

private struct RecordingRecapModel: AIRecapModelGenerating {
    var isAvailable = true
    let recorder: RecapModelAttemptRecorder
    var output: String
    var modelName: String { "Recording Fake Model" }
    var modelVersion: String { "test" }
    var contextWindowTokenLimit: Int? { 4_096 }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        await recorder.record(source)
        return output
    }
}

private struct FailFirstThenSucceedRecapModel: AIRecapModelGenerating {
    var isAvailable = true
    let recorder: RecapModelAttemptRecorder
    var modelName: String { "Retry Fake Model" }
    var modelVersion: String { "test" }
    var contextWindowTokenLimit: Int? { 4_096 }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        await recorder.record(source)
        if await recorder.attempts.count == 1 {
            throw RecapModelTestError.failed
        }

        return "Fallback recap succeeded."
    }
}

private struct AlwaysFailingRecapModel: AIRecapModelGenerating {
    var isAvailable = true
    let recorder: RecapModelAttemptRecorder
    var modelName: String { "Failing Fake Model" }
    var modelVersion: String { "test" }
    var contextWindowTokenLimit: Int? { 4_096 }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        await recorder.record(source)
        throw RecapModelTestError.failed
    }
}

@MainActor
private final class MockReadingStatsStore: ReadingStatsStore {
    var snapshot: ReadingStatsSnapshot = .empty
    var dailyStats: [DailyReadingStats] = []
    var sessionEvents: [ReadingSessionEvent]

    init(sessionEvents: [ReadingSessionEvent]) {
        self.sessionEvents = sessionEvents
    }

    func record(_ event: ReadingSessionEvent) {
        sessionEvents.append(event)
    }

    func markReadCompleted(readID: UUID, completedAt: Date) {}

    func updateDailyGoalWords(_ words: Int) {}
}

@MainActor
private final class MockAIRecapStore: AIRecapStore {
    private var storedRecaps: [AIRecap]
    private(set) var savedRecaps: [AIRecap] = []

    init(recaps: [AIRecap]) {
        storedRecaps = recaps
    }

    func recaps(for readID: UUID) -> [AIRecap] {
        storedRecaps.filter { $0.readID == readID }
    }

    func save(_ recap: AIRecap) {
        savedRecaps.append(recap)
        storedRecaps.removeAll { $0.readID == recap.readID && $0.sessionID == recap.sessionID }
        storedRecaps.append(recap)
    }

    func deleteRecap(sessionID: UUID, for readID: UUID) {
        storedRecaps.removeAll { $0.readID == readID && $0.sessionID == sessionID }
    }

    func deleteRecaps(for readID: UUID) {
        storedRecaps.removeAll { $0.readID == readID }
    }
}
