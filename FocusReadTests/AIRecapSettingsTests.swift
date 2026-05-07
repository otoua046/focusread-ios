import XCTest
@testable import FocusRead

final class AIRecapSettingsTests: XCTestCase {
    func testTogglePersistsAcrossLaunches() throws {
        let suiteName = "FocusReadAIRecapSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        XCTAssertTrue(AIRecapSettings.isEnabled(userDefaults: defaults, localAIAvailable: true))

        AIRecapSettings.setEnabled(false, userDefaults: defaults)
        let disabledDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertFalse(AIRecapSettings.isEnabled(userDefaults: disabledDefaults, localAIAvailable: true))

        AIRecapSettings.setEnabled(true, userDefaults: disabledDefaults)
        let enabledDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertTrue(AIRecapSettings.isEnabled(userDefaults: enabledDefaults, localAIAvailable: true))
    }

    func testUnavailableOrDisabledStateHidesEntryPoints() {
        XCTAssertTrue(AIRecapSettings.shouldShowEntryPoints(storedPreference: true, localAIAvailable: true))
        XCTAssertFalse(AIRecapSettings.shouldShowEntryPoints(storedPreference: false, localAIAvailable: true))
        XCTAssertFalse(AIRecapSettings.shouldShowEntryPoints(storedPreference: true, localAIAvailable: false))
    }

    @MainActor
    func testDisabledStateBlocksGeneration() async {
        let read = makeRead(wordCount: 120)
        let session = event(readID: read.id, range: 0..<80)
        let statsStore = ReadingStatsStoreProbe(sessionEvents: [session])
        let recapStore = LocalAIRecapStore(storageDirectory: temporaryDirectory())
        let service = AIRecapService(
            extractor: AIRecapSourceExtractor(minimumInputWordCount: 1),
            model: SettingsFakeRecapModel(output: "Generated recap.")
        )
        let viewModel = AIRecapViewModel(
            read: read,
            readingStatsStore: statsStore,
            recapStore: recapStore,
            service: service,
            isAIRecapsEnabledProvider: { false }
        )
        let item = AIRecapSessionItem(session: recapSession(from: session), recap: nil, isMostRecent: true)

        viewModel.generate(for: item)

        XCTAssertEqual(viewModel.errorMessage, AIRecapSettings.disabledMessage)
        XCTAssertEqual(recapStore.recaps(for: read.id), [])
    }

    @MainActor
    func testReenabledStateRestoresExistingRecapsWithoutDeletingData() {
        var isEnabled = false
        let read = makeRead(wordCount: 120)
        let session = event(readID: read.id, range: 0..<80)
        let statsStore = ReadingStatsStoreProbe(sessionEvents: [session])
        let recapStore = LocalAIRecapStore(storageDirectory: temporaryDirectory())
        let existingRecap = makeRecap(readID: read.id, sessionID: session.id, text: "Stored recap.")
        recapStore.save(existingRecap)

        let viewModel = AIRecapViewModel(
            read: read,
            readingStatsStore: statsStore,
            recapStore: recapStore,
            service: AIRecapService(
                extractor: AIRecapSourceExtractor(minimumInputWordCount: 1),
                model: SettingsFakeRecapModel(output: "Generated recap.")
            ),
            isAIRecapsEnabledProvider: { isEnabled }
        )

        XCTAssertEqual(viewModel.items, [])
        XCTAssertEqual(recapStore.recaps(for: read.id), [existingRecap])

        isEnabled = true
        viewModel.refresh()

        XCTAssertEqual(viewModel.items.map(\.recap), [existingRecap])
        XCTAssertEqual(recapStore.recaps(for: read.id), [existingRecap])
    }

    private func makeRead(wordCount: Int) -> SavedRead {
        let text = (0..<wordCount).map { "word\($0)" }.joined(separator: " ")
        let tokens = TextTokenizer().tokenize(text)
        return SavedReadMapper.makeSavedRead(from: text, tokens: tokens, now: date("2026-05-07T09:00:00Z"))
    }

    private func event(readID: UUID, range: Range<Int>) -> ReadingSessionEvent {
        ReadingSessionEvent(
            readID: readID,
            startedAt: date("2026-05-07T09:00:00Z"),
            endedAt: date("2026-05-07T09:10:00Z"),
            wordsRead: range.count,
            averageWPM: 300,
            sourceStartWordIndex: range.lowerBound,
            sourceEndWordIndex: range.upperBound
        )
    }

    private func recapSession(from event: ReadingSessionEvent) -> AIRecapSession {
        AIRecapSession(
            id: event.id,
            readID: event.readID,
            startedAt: event.startedAt,
            endedAt: event.endedAt,
            wordsRead: event.wordsRead,
            averageWPM: event.averageWPM,
            sourceStartWordIndex: event.sourceWordRange?.lowerBound ?? 0,
            sourceEndWordIndex: event.sourceWordRange?.upperBound ?? event.wordsRead,
            sourceEventIDs: [event.id]
        )
    }

    private func makeRecap(readID: UUID, sessionID: UUID, text: String) -> AIRecap {
        AIRecap(
            readID: readID,
            sessionID: sessionID,
            sessionStartedAt: date("2026-05-07T09:00:00Z"),
            sessionEndedAt: date("2026-05-07T09:10:00Z"),
            sourceStartWordIndex: 0,
            sourceEndWordIndex: 80,
            generatedText: text,
            createdAt: date("2026-05-07T09:11:00Z"),
            inputWordCount: 80,
            outputWordCount: text.split { $0.isWhitespace || $0.isNewline }.count,
            modelName: "Fake Local Model",
            modelVersion: "test"
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusReadAIRecapSettingsTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}

@MainActor
private final class ReadingStatsStoreProbe: ReadingStatsStore {
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

private struct SettingsFakeRecapModel: AIRecapModelGenerating {
    var isAvailable = true
    var output: String
    var modelName: String { "Fake Local Model" }
    var modelVersion: String { "test" }

    func generateRecap(from source: AIRecapSource, outputWordLimit: Int) async throws -> String {
        output
    }
}
