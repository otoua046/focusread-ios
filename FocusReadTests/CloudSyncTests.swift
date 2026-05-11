import XCTest
@testable import FocusRead

final class CloudSyncTests: XCTestCase {
    func testExistingLocalDataMigrationRunsOnceForSameSnapshot() {
        let read = syncedRead(
            id: UUID(),
            title: "Local Book",
            updatedAt: date("2026-05-01T10:00:00Z"),
            progress: 12
        )
        let snapshot = CloudSyncSnapshot(
            libraryItems: [read],
            deletedLibraryItems: [],
            readingStats: nil,
            settings: SyncedAppSettings(values: [
                SyncedSettingValue(
                    key: TypographySettingsKey.fontFamily,
                    value: ReaderFontFamily.serif.rawValue,
                    kind: .string,
                    updatedAt: date("2026-05-01T10:00:00Z")
                )
            ], updatedAt: date("2026-05-01T10:00:00Z")),
            aiRecaps: [],
            deletedAIRecaps: [],
            migrationState: CloudSyncMigrationState(),
            generatedAt: date("2026-05-01T10:00:00Z")
        )

        let first = LocalToCloudMigrationService.prepareMigration(
            localSnapshot: snapshot,
            cloudState: CloudSyncMigrationState(),
            now: date("2026-05-01T11:00:00Z")
        )
        let second = LocalToCloudMigrationService.prepareMigration(
            localSnapshot: snapshot,
            cloudState: first.snapshot.migrationState,
            now: date("2026-05-01T12:00:00Z")
        )

        XCTAssertTrue(first.didMigrate)
        XCTAssertFalse(second.didMigrate)
        XCTAssertEqual(first.snapshot.migrationState.migratedReadIDs, [read.id])
        XCTAssertEqual(first.snapshot.migrationState.migratedSettingKeys, [TypographySettingsKey.fontFamily])
    }

    func testCloudDataMergesWithLocalDataWithoutDuplicatingMatchingDocuments() {
        let id = UUID()
        let local = syncedRead(
            id: id,
            title: "User Title",
            updatedAt: date("2026-05-03T10:00:00Z"),
            progress: 35
        )
        var cloud = syncedRead(
            id: UUID(),
            title: "Original Title",
            updatedAt: date("2026-05-02T10:00:00Z"),
            progress: 50
        )
        cloud.contentFingerprint = local.contentFingerprint

        let result = SyncConflictResolver.mergeLibraryItems(local: [local], cloud: [cloud])

        XCTAssertEqual(result.value.count, 1)
        XCTAssertEqual(result.value.first?.displayTitle, "User Title")
        XCTAssertEqual(result.value.first?.progressPercent, 50)
        XCTAssertTrue(result.decisions.contains { $0.message.contains("matching content fingerprint") })
    }

    func testNewerLibraryDeletionTombstoneRemovesCloudItem() {
        let read = syncedRead(
            id: UUID(),
            title: "Deleted Book",
            updatedAt: date("2026-05-02T10:00:00Z"),
            progress: 10
        )
        let tombstone = SyncedDeletedLibraryItem(
            id: read.id,
            contentFingerprint: read.contentFingerprint,
            deletedAt: date("2026-05-03T10:00:00Z")
        )

        let result = SyncConflictResolver.mergeLibraryItems(local: [], cloud: [read], deleted: [tombstone])

        XCTAssertTrue(result.value.isEmpty)
        XCTAssertTrue(result.decisions.contains { $0.message.contains("deletion tombstone") })
    }

    func testOlderLibraryDeletionTombstoneDoesNotRemoveNewerItem() {
        let read = syncedRead(
            id: UUID(),
            title: "Reimported Book",
            updatedAt: date("2026-05-04T10:00:00Z"),
            progress: 10
        )
        let tombstone = SyncedDeletedLibraryItem(
            id: read.id,
            contentFingerprint: read.contentFingerprint,
            deletedAt: date("2026-05-03T10:00:00Z")
        )

        let result = SyncConflictResolver.mergeLibraryItems(local: [read], cloud: [], deleted: [tombstone])

        XCTAssertEqual(result.value.map(\.id), [read.id])
    }

    func testNewerAIRecapDeletionTombstoneRemovesCloudRecap() {
        let recap = aiRecap(
            id: UUID(),
            readID: UUID(),
            sessionID: UUID(),
            createdAt: date("2026-05-06T10:00:00Z")
        )
        let tombstone = SyncedDeletedAIRecap(
            recapID: recap.id,
            readID: recap.readID,
            sessionID: recap.sessionID,
            deletedAt: date("2026-05-06T11:00:00Z")
        )

        let result = SyncConflictResolver.mergeAIRecaps(local: [], cloud: [recap], deleted: [tombstone])

        XCTAssertTrue(result.value.isEmpty)
        XCTAssertTrue(result.decisions.contains { $0.message.contains("AI recap deletion tombstone") })
    }

    func testOlderAIRecapDeletionTombstoneDoesNotRemoveNewerRecap() {
        let recap = aiRecap(
            id: UUID(),
            readID: UUID(),
            sessionID: UUID(),
            createdAt: date("2026-05-06T11:00:00Z")
        )
        let tombstone = SyncedDeletedAIRecap(
            recapID: recap.id,
            readID: recap.readID,
            sessionID: recap.sessionID,
            deletedAt: date("2026-05-06T10:00:00Z")
        )

        let result = SyncConflictResolver.mergeAIRecaps(local: [recap], cloud: [], deleted: [tombstone])

        XCTAssertEqual(result.value.map(\.id), [recap.id])
    }

    func testOlderCloudSettingDoesNotOverwriteNewerLocalSetting() throws {
        let key = TypographySettingsKey.fontSize
        let local = SyncedAppSettings(values: [
            SyncedSettingValue(
                key: key,
                value: "72",
                kind: .double,
                updatedAt: date("2026-05-04T10:00:00Z")
            )
        ], updatedAt: date("2026-05-04T10:00:00Z"))
        let cloud = SyncedAppSettings(values: [
            SyncedSettingValue(
                key: key,
                value: "44",
                kind: .double,
                updatedAt: date("2026-05-03T10:00:00Z")
            )
        ], updatedAt: date("2026-05-03T10:00:00Z"))

        let merged = try XCTUnwrap(SyncConflictResolver.mergeSettings(local: local, cloud: cloud).value)

        XCTAssertEqual(merged.values.first?.value, "72")
    }

    func testDailyStatsMergeAddsSameDayCounters() throws {
        let day = date("2026-05-08T00:00:00Z")
        let completedReadID = UUID()
        let local = SyncedReadingStats(
            dailyGoalWords: 1_000,
            dailyStats: [
                DailyReadingStats(
                    date: day,
                    wordsRead: 400,
                    readingSeconds: 120,
                    sessionsCount: 1,
                    completedBooksCount: 0
                )
            ],
            sessionEvents: [],
            completedReadIDs: [],
            updatedAt: date("2026-05-08T10:00:00Z")
        )
        let cloud = SyncedReadingStats(
            dailyGoalWords: 1_000,
            dailyStats: [
                DailyReadingStats(
                    date: day,
                    wordsRead: 600,
                    readingSeconds: 180,
                    sessionsCount: 2,
                    completedBooksCount: 1
                )
            ],
            sessionEvents: [],
            completedReadIDs: [completedReadID],
            updatedAt: date("2026-05-08T11:00:00Z")
        )

        let merged = try XCTUnwrap(SyncConflictResolver.mergeReadingStats(local: local, cloud: cloud).value)
        let mergedDay = try XCTUnwrap(merged.dailyStats.first)

        XCTAssertEqual(mergedDay.wordsRead, 1_000)
        XCTAssertEqual(mergedDay.readingSeconds, 300)
        XCTAssertEqual(mergedDay.sessionsCount, 3)
        XCTAssertEqual(mergedDay.completedBooksCount, 1)
    }

    @MainActor
    func testTrackedSettingTimestampRefreshesWhenLocalValueChanges() throws {
        let suiteName = "FocusReadCloudSyncSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = SyncSettingsStore(userDefaults: defaults)
        let initialDate = date("2026-05-07T10:00:00Z")
        let changedDate = date("2026-05-07T11:00:00Z")

        XCTAssertFalse(store.refreshTrackedSettings(now: initialDate))
        defaults.set(72.0, forKey: TypographySettingsKey.fontSize)

        XCTAssertTrue(store.refreshTrackedSettings(now: changedDate))
        let setting = try XCTUnwrap(store.snapshot(now: changedDate).values.first { $0.key == TypographySettingsKey.fontSize })
        XCTAssertEqual(setting.value, "72.0")
        XCTAssertEqual(setting.updatedAt, changedDate)
    }

    @MainActor
    func testSyncBookkeepingDefaultsDoNotRefreshSettingTimestamps() throws {
        let suiteName = "FocusReadCloudSyncSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = SyncSettingsStore(userDefaults: defaults)
        let initialDate = date("2026-05-07T10:00:00Z")
        let bookkeepingDate = date("2026-05-07T11:00:00Z")

        XCTAssertFalse(store.refreshTrackedSettings(now: initialDate))
        defaults.set(bookkeepingDate, forKey: CloudSyncSettingsKey.lastSyncedAt)

        XCTAssertFalse(store.refreshTrackedSettings(now: bookkeepingDate))
        let setting = try XCTUnwrap(store.snapshot(now: bookkeepingDate).values.first { $0.key == TypographySettingsKey.fontSize })
        XCTAssertEqual(setting.updatedAt, initialDate)
    }

    @MainActor
    func testStatsSnapshotDoesNotAdvanceTimestampWithoutLocalStatsChange() {
        var now = date("2026-05-08T10:00:00Z")
        let store = LocalReadingStatsStore(
            storageDirectory: temporaryDirectory(),
            now: { now }
        )
        store.record(ReadingSessionEvent(
            readID: UUID(),
            startedAt: date("2026-05-08T09:45:00Z"),
            endedAt: date("2026-05-08T10:00:00Z"),
            wordsRead: 500,
            averageWPM: 250
        ))
        let firstSnapshot = store.syncSnapshot()

        now = date("2026-05-08T11:00:00Z")
        let secondSnapshot = store.syncSnapshot()
        store.updateDailyGoalWords(2_000)
        let thirdSnapshot = store.syncSnapshot()

        XCTAssertEqual(firstSnapshot.updatedAt, date("2026-05-08T10:00:00Z"))
        XCTAssertEqual(secondSnapshot.updatedAt, firstSnapshot.updatedAt)
        XCTAssertEqual(thirdSnapshot.updatedAt, date("2026-05-08T11:00:00Z"))
    }

    func testReadingProgressKeepsFurthestMeaningfulProgress() {
        let local = syncedRead(
            id: UUID(),
            updatedAt: date("2026-05-05T10:00:00Z"),
            progress: 40,
            currentWordIndex: 400
        )
        let cloud = syncedRead(
            id: local.id,
            updatedAt: date("2026-05-05T11:00:00Z"),
            progress: 30,
            currentWordIndex: 300
        )

        let merged = SyncConflictResolver.mergeSavedRead(local: local, cloud: cloud).value

        XCTAssertEqual(merged.progressPercent, 40)
        XCTAssertEqual(merged.currentWordIndex, 400)
    }

    func testReadingProgressAllowsClearIntentionalReset() {
        let local = syncedRead(
            id: UUID(),
            updatedAt: date("2026-05-05T10:00:00Z"),
            progress: 60,
            currentWordIndex: 600
        )
        let cloud = syncedRead(
            id: local.id,
            updatedAt: date("2026-05-05T11:00:00Z"),
            progress: 0,
            currentWordIndex: 0
        )

        let merged = SyncConflictResolver.mergeSavedRead(local: local, cloud: cloud).value

        XCTAssertEqual(merged.progressPercent, 0)
        XCTAssertEqual(merged.currentWordIndex, 0)
    }

    @MainActor
    func testManagerKeepsAppUsableWhenICloudUnavailable() async {
        let suiteName = "FocusReadCloudSyncTests-\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let manager = CloudSyncManager(
            cloudKitService: UnavailableCloudKitService(),
            userDefaults: defaults
        )
        let historyStore = LocalReadingHistoryStore(storageDirectory: temporaryDirectory())
        let statsStore = LocalReadingStatsStore(storageDirectory: temporaryDirectory())
        let recapStore = LocalAIRecapStore(storageDirectory: temporaryDirectory())

        manager.configure(
            readingHistoryStore: historyStore,
            readingStatsStore: statsStore,
            recapStore: recapStore
        )
        manager.syncNow()
        for _ in 0..<20 where manager.status.kind != .unavailable {
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(manager.status.kind, .unavailable)
        XCTAssertTrue(manager.isSyncEnabled)
    }

    @MainActor
    func testApplyingFingerprintMatchedCloudMetadataPreservesLocalDocumentText() {
        let store = LocalReadingHistoryStore(storageDirectory: temporaryDirectory())
        let localRead = savedRead(
            id: UUID(),
            title: "Book",
            updatedAt: date("2026-05-06T10:00:00Z"),
            progress: 20,
            sectionText: "Local document text that must stay on device."
        )
        store.save(localRead, durability: .immediate)

        let cloudRead = savedRead(
            id: UUID(),
            title: localRead.displayTitle,
            updatedAt: date("2026-05-06T11:00:00Z"),
            progress: 40,
            sectionText: ""
        )
        store.applySyncMergedReads([SyncedSavedRead(read: cloudRead)])

        XCTAssertEqual(store.savedReads.count, 1)
        XCTAssertEqual(store.savedReads.first?.sections.first?.text, localRead.sections.first?.text)
        XCTAssertFalse(store.savedReads.first?.cloudSync?.isMetadataOnly ?? true)
    }

    @MainActor
    func testApplyingSyncMergedReadsRemovesFilesForDroppedLocalReads() throws {
        let directory = temporaryDirectory()
        let store = LocalReadingHistoryStore(storageDirectory: directory)
        let localRead = savedRead(
            id: UUID(),
            title: "Deleted elsewhere",
            updatedAt: date("2026-05-09T10:00:00Z"),
            progress: 20
        )
        store.save(localRead, durability: .immediate)
        let readFolder = directory
            .appendingPathComponent("SavedReads", isDirectory: true)
            .appendingPathComponent(localRead.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: readFolder, withIntermediateDirectories: true)
        try Data("thumbnail".utf8).write(to: readFolder.appendingPathComponent("thumbnail.jpg"))

        store.applySyncMergedReads([])

        XCTAssertTrue(store.savedReads.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: readFolder.path))
    }

    @MainActor
    func testAIRecapStoreRecordsDeletionTombstoneAndAppliesRemoteDeletion() {
        let store = LocalAIRecapStore(storageDirectory: temporaryDirectory())
        let recap = aiRecap(
            id: UUID(),
            readID: UUID(),
            sessionID: UUID(),
            createdAt: date("2026-05-07T10:00:00Z")
        )
        store.save(recap)

        store.deleteRecap(sessionID: recap.sessionID, for: recap.readID)

        XCTAssertTrue(store.recaps(for: recap.readID).isEmpty)
        XCTAssertEqual(store.syncDeletedAIRecaps().first?.recapID, recap.id)

        let remoteStore = LocalAIRecapStore(storageDirectory: temporaryDirectory())
        remoteStore.save(recap)
        remoteStore.applySyncMergedDeletedAIRecaps(store.syncDeletedAIRecaps())
        remoteStore.applySyncMergedRecaps([], deletedRecaps: store.syncDeletedAIRecaps())

        XCTAssertTrue(remoteStore.recaps(for: recap.readID).isEmpty)
    }

    private func syncedRead(
        id: UUID,
        title: String = "Book",
        updatedAt: Date,
        progress: Double,
        currentWordIndex: Int? = nil
    ) -> SyncedSavedRead {
        var read = savedRead(
            id: id,
            title: title,
            updatedAt: updatedAt,
            progress: progress,
            currentWordIndex: currentWordIndex
        )
        read.cloudSync = .localDocumentAvailable
        return SyncedSavedRead(read: read, migratedAt: updatedAt)
    }

    private func savedRead(
        id: UUID,
        title: String = "Book",
        updatedAt: Date,
        progress: Double,
        currentWordIndex: Int? = nil,
        sectionText: String = "Local text"
    ) -> SavedRead {
        SavedRead(
            id: id,
            displayTitle: title,
            authorName: "Author",
            originalFileName: "book.epub",
            sourceType: .epub,
            languageCode: "en",
            thumbnailPath: nil,
            createdAt: date("2026-05-01T09:00:00Z"),
            updatedAt: updatedAt,
            lastOpenedAt: updatedAt,
            totalWordCount: 1_000,
            currentWordIndex: currentWordIndex ?? Int(progress * 10),
            progressPercent: progress,
            currentPage: nil,
            totalPages: nil,
            currentChapter: nil,
            totalChapters: nil,
            sections: [
                SavedReadSection(
                    index: 0,
                    title: "Chapter",
                    text: sectionText,
                    pageNumber: nil,
                    chapterNumber: 1,
                    wordRange: nil,
                    epubNavigationLevel: nil,
                    epubSectionRole: .body,
                    epubStructureSource: nil,
                    epubStructureConfidence: nil
                )
            ],
            cleanupModeUsed: SmartCleanupMode.smart.rawValue,
            isFavorite: false,
            readingStats: .empty,
            author: "Author",
            manualSortIndex: nil
        )
    }

    private func aiRecap(
        id: UUID,
        readID: UUID,
        sessionID: UUID,
        createdAt: Date
    ) -> AIRecap {
        AIRecap(
            id: id,
            readID: readID,
            sessionID: sessionID,
            sessionStartedAt: createdAt.addingTimeInterval(-900),
            sessionEndedAt: createdAt,
            sourceStartWordIndex: 0,
            sourceEndWordIndex: 500,
            generatedText: "A concise recap.",
            createdAt: createdAt,
            inputWordCount: 500,
            outputWordCount: 20,
            sourceLanguageCode: "en",
            sourceLanguageName: "English",
            modelName: "TestModel",
            modelVersion: "1"
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusReadCloudSyncTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}

private final class UnavailableCloudKitService: CloudKitServing {
    func availability() async -> CloudSyncAvailability {
        .unavailable("iCloud unavailable in tests.")
    }

    func fetchSnapshot() async throws -> CloudSyncSnapshot {
        XCTFail("Unavailable iCloud should not fetch snapshots.")
        return .empty()
    }

    func saveSnapshot(_ snapshot: CloudSyncSnapshot) async throws {
        XCTFail("Unavailable iCloud should not save snapshots.")
    }
}
