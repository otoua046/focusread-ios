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

    func testContentFingerprintIncludesDocumentText() {
        let first = savedRead(
            id: UUID(),
            title: "Same Title",
            updatedAt: date("2026-05-03T10:00:00Z"),
            progress: 0,
            sectionText: "The first document has its own words."
        )
        let second = savedRead(
            id: UUID(),
            title: "Same Title",
            updatedAt: date("2026-05-03T10:00:00Z"),
            progress: 0,
            sectionText: "A totally different document has different words."
        )

        XCTAssertNotEqual(SyncedSavedRead.contentFingerprint(for: first), SyncedSavedRead.contentFingerprint(for: second))
    }

    func testContentFingerprintIgnoresMutableMetadata() {
        let original = savedRead(
            id: UUID(),
            title: "Original Title",
            updatedAt: date("2026-05-03T10:00:00Z"),
            progress: 0,
            sectionText: "The same document text should define identity."
        )
        var renamed = original
        renamed.displayTitle = "Renamed on another device"
        renamed.originalFileName = "different-file-name.txt"
        renamed.authorName = "Different Author"
        renamed.author = "Different Author"
        renamed.sourceType = .txt

        XCTAssertEqual(SyncedSavedRead.contentFingerprint(for: original), SyncedSavedRead.contentFingerprint(for: renamed))
    }

    func testMetadataOnlySnapshotReusesStoredContentFingerprint() {
        let original = savedRead(
            id: UUID(),
            title: "Downloaded Elsewhere",
            updatedAt: date("2026-05-03T10:00:00Z"),
            progress: 0,
            sectionText: "The original document text defines reconciliation identity."
        )
        let originalFingerprint = SyncedSavedRead.contentFingerprint(for: original)
        var metadataOnly = original
        metadataOnly.sections[0].text = ""
        metadataOnly.cloudSync = SavedReadCloudSyncMetadata(
            isMetadataOnly: true,
            fileSyncState: .metadataOnly,
            contentFingerprint: originalFingerprint,
            migratedAt: date("2026-05-03T11:00:00Z")
        )

        let syncedRead = SyncedSavedRead(read: metadataOnly)

        XCTAssertEqual(syncedRead.contentFingerprint, originalFingerprint)
        XCTAssertEqual(syncedRead.fileSync?.contentFingerprint, originalFingerprint)
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

    func testCloudKitAIRecapDeletionTombstoneMatchesReplacementSessionRecap() {
        let readID = UUID()
        let sessionID = UUID()
        let deletedRecapID = UUID()
        let replacementRecap = aiRecap(
            id: UUID(),
            readID: readID,
            sessionID: sessionID,
            createdAt: date("2026-05-06T10:00:00Z")
        )
        let tombstone = SyncedDeletedAIRecap(
            recapID: deletedRecapID,
            readID: readID,
            sessionID: sessionID,
            deletedAt: date("2026-05-06T11:00:00Z")
        )

        XCTAssertTrue(DefaultCloudKitService.isAIRecap(replacementRecap, deletedBy: [tombstone]))
        XCTAssertEqual(DefaultCloudKitService.deletedAIRecapRecordNames(for: [tombstone]), ["recap-\(deletedRecapID.uuidString)"])
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
        XCTAssertEqual(setting.updatedAt, Date(timeIntervalSince1970: 0))
    }

    @MainActor
    func testUntouchedDefaultSettingDoesNotOverrideCloudValue() throws {
        let suiteName = "FocusReadCloudSyncSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = SyncSettingsStore(userDefaults: defaults)
        let cloudDate = date("2026-05-07T09:00:00Z")

        XCTAssertFalse(store.refreshTrackedSettings(now: date("2026-05-07T10:00:00Z")))
        let local = store.snapshot(now: date("2026-05-07T11:00:00Z"))
        let cloud = SyncedAppSettings(values: [
            SyncedSettingValue(
                key: TypographySettingsKey.fontSize,
                value: "72.0",
                kind: .double,
                updatedAt: cloudDate
            )
        ], updatedAt: cloudDate)

        let merged = try XCTUnwrap(SyncConflictResolver.mergeSettings(local: local, cloud: cloud).value)
        let setting = try XCTUnwrap(merged.values.first { $0.key == TypographySettingsKey.fontSize })
        XCTAssertEqual(setting.value, "72.0")
        XCTAssertEqual(setting.updatedAt, cloudDate)
    }

    func testDemoSavedReadReusesExistingDemoItem() {
        let text = "FocusRead demo text."
        let tokens = [token("FocusRead", index: 0), token("demo", index: 1)]
        let firstDate = date("2026-05-07T10:00:00Z")
        let secondDate = date("2026-05-07T11:00:00Z")
        var existing = SavedReadMapper.makeDemoSavedRead(
            from: text,
            tokens: tokens,
            title: "FocusRead Demo",
            existingReads: [],
            now: firstDate
        )
        existing.id = UUID()
        existing.readingStats = SavedReadStats(totalTimeRead: 120, sessionsCount: 3)
        existing.isFavorite = true

        let next = SavedReadMapper.makeDemoSavedRead(
            from: text,
            tokens: tokens,
            title: "Localized Demo",
            existingReads: [existing],
            now: secondDate
        )

        XCTAssertEqual(next.id, existing.id)
        XCTAssertEqual(next.createdAt, firstDate)
        XCTAssertEqual(next.displayTitle, "Localized Demo")
        XCTAssertEqual(next.readingStats.totalTimeRead, 120)
        XCTAssertEqual(next.readingStats.sessionsCount, 4)
        XCTAssertTrue(next.isFavorite)
        XCTAssertEqual(next.currentWordIndex, 0)
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
    func testManagerDoesNotRetryNonRetryableUnavailableICloud() async throws {
        let suiteName = "FocusReadCloudSyncTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let cloudKitService = NonRetryingUnavailableCloudKitService()
        let manager = CloudSyncManager(
            cloudKitService: cloudKitService,
            userDefaults: defaults,
            retryDelayNanoseconds: 10_000_000,
            maxAutomaticRetryAttempts: 3
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
        try await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(cloudKitService.availabilityCallCount, 1)
        XCTAssertEqual(manager.status.kind, .unavailable)
        manager.isSyncEnabled = false
    }

    @MainActor
    func testManagerSerializesQueuedSyncRuns() async throws {
        let suiteName = "FocusReadCloudSyncTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let cloudKitService = OverlapTrackingCloudKitService()
        let manager = CloudSyncManager(
            cloudKitService: cloudKitService,
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
        try await Task.sleep(for: .milliseconds(25))
        manager.syncNow()

        for _ in 0..<60 where cloudKitService.stats.saveCount < 2 {
            try await Task.sleep(for: .milliseconds(50))
        }
        manager.isSyncEnabled = false

        XCTAssertEqual(cloudKitService.stats.saveCount, 2)
        XCTAssertEqual(cloudKitService.stats.maxConcurrentSaves, 1)
    }

    @MainActor
    func testManagerRetriesAfterTransientUnavailable() async throws {
        let suiteName = "FocusReadCloudSyncTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let cloudKitService = TransientUnavailableCloudKitService(unavailableResponses: 1)
        let manager = CloudSyncManager(
            cloudKitService: cloudKitService,
            userDefaults: defaults,
            retryDelayNanoseconds: 20_000_000,
            maxAutomaticRetryAttempts: 2
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

        for _ in 0..<40 where cloudKitService.saveCount == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        for _ in 0..<20 where manager.status.kind != .synced {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(cloudKitService.availabilityCallCount, 2)
        XCTAssertEqual(cloudKitService.saveCount, 1)
        XCTAssertEqual(manager.status.kind, .synced)
        manager.isSyncEnabled = false
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
        var syncedCloudRead = SyncedSavedRead(read: cloudRead)
        syncedCloudRead.contentFingerprint = SyncedSavedRead.contentFingerprint(for: localRead)
        store.applySyncMergedReads([syncedCloudRead])

        XCTAssertEqual(store.savedReads.count, 1)
        XCTAssertEqual(store.savedReads.first?.sections.first?.text, localRead.sections.first?.text)
        XCTAssertFalse(store.savedReads.first?.cloudSync?.isMetadataOnly ?? true)
    }

    @MainActor
    func testApplyingFingerprintMatchedCloudMetadataMigratesLocalFiles() throws {
        let directory = temporaryDirectory()
        let store = LocalReadingHistoryStore(storageDirectory: directory)
        var localRead = savedRead(
            id: UUID(),
            title: "Book",
            updatedAt: date("2026-05-06T10:00:00Z"),
            progress: 20,
            sectionText: "Local document text with a thumbnail."
        )
        localRead.thumbnailPath = "SavedReads/\(localRead.id.uuidString)/thumbnail.jpg"
        store.save(localRead, durability: .immediate)
        let localFolder = directory
            .appendingPathComponent("SavedReads", isDirectory: true)
            .appendingPathComponent(localRead.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
        try Data("thumbnail".utf8).write(to: localFolder.appendingPathComponent("thumbnail.jpg"))

        let cloudRead = savedRead(
            id: UUID(),
            title: localRead.displayTitle,
            updatedAt: date("2026-05-06T11:00:00Z"),
            progress: 40,
            sectionText: ""
        )
        var syncedCloudRead = SyncedSavedRead(read: cloudRead)
        syncedCloudRead.contentFingerprint = SyncedSavedRead.contentFingerprint(for: localRead)
        store.applySyncMergedReads([syncedCloudRead])

        let mergedRead = try XCTUnwrap(store.savedReads.first)
        let mergedFolder = directory
            .appendingPathComponent("SavedReads", isDirectory: true)
            .appendingPathComponent(mergedRead.id.uuidString, isDirectory: true)
        XCTAssertEqual(mergedRead.id, cloudRead.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localFolder.path))
        XCTAssertEqual(try Data(contentsOf: mergedFolder.appendingPathComponent("thumbnail.jpg")), Data("thumbnail".utf8))
        XCTAssertEqual(mergedRead.thumbnailPath, "SavedReads/\(mergedRead.id.uuidString)/thumbnail.jpg")
    }

    @MainActor
    func testSyncSnapshotItemsPreservesExistingMigratedAt() {
        let store = LocalReadingHistoryStore(storageDirectory: temporaryDirectory())
        var read = savedRead(
            id: UUID(),
            title: "Stable Snapshot",
            updatedAt: date("2026-05-06T10:00:00Z"),
            progress: 20
        )
        let migratedAt = date("2026-05-06T11:00:00Z")
        read.cloudSync = SavedReadCloudSyncMetadata(
            isMetadataOnly: false,
            fileSyncState: .uploaded,
            contentFingerprint: SyncedSavedRead.contentFingerprint(for: read),
            migratedAt: migratedAt
        )
        store.save(read, durability: .immediate)

        let firstSnapshot = store.syncSnapshotItems(now: date("2026-05-06T12:00:00Z"))
        let secondSnapshot = store.syncSnapshotItems(now: date("2026-05-06T13:00:00Z"))

        XCTAssertEqual(firstSnapshot.first?.fileSync?.lastValidatedAt, migratedAt)
        XCTAssertEqual(secondSnapshot.first?.fileSync?.lastValidatedAt, migratedAt)
        XCTAssertEqual(firstSnapshot, secondSnapshot)
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

    private func token(_ text: String, index: Int) -> ReadingToken {
        ReadingToken(
            id: index,
            text: text,
            rawText: text,
            globalWordIndex: index,
            sourcePageNumber: nil,
            sourceChapterNumber: nil,
            sourceChapterTitle: nil,
            sourceSectionIndex: nil,
            pauseKind: .none,
            sentenceIndex: 0,
            containsNumber: false
        )
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

@MainActor
private final class NonRetryingUnavailableCloudKitService: CloudKitServing {
    private var availabilityCalls = 0

    nonisolated var allowsAutomaticUnavailableRetry: Bool { false }

    var availabilityCallCount: Int {
        availabilityCalls
    }

    func availability() async -> CloudSyncAvailability {
        availabilityCalls += 1
        return .unavailable("iCloud unavailable in tests.")
    }

    func fetchSnapshot() async throws -> CloudSyncSnapshot {
        XCTFail("Unavailable iCloud should not fetch snapshots.")
        return .empty()
    }

    func saveSnapshot(_ snapshot: CloudSyncSnapshot) async throws {
        XCTFail("Unavailable iCloud should not save snapshots.")
    }
}

@MainActor
private final class OverlapTrackingCloudKitService: CloudKitServing {
    struct Stats {
        var saveCount: Int
        var maxConcurrentSaves: Int
    }

    private var activeSaves = 0
    private var saveCount = 0
    private var maxConcurrentSaves = 0

    var stats: Stats {
        Stats(saveCount: saveCount, maxConcurrentSaves: maxConcurrentSaves)
    }

    func availability() async -> CloudSyncAvailability {
        .available
    }

    func fetchSnapshot() async throws -> CloudSyncSnapshot {
        .empty()
    }

    func saveSnapshot(_ snapshot: CloudSyncSnapshot) async throws {
        activeSaves += 1
        saveCount += 1
        maxConcurrentSaves = max(maxConcurrentSaves, activeSaves)

        try? await Task.sleep(for: .milliseconds(150))

        activeSaves -= 1
    }
}

@MainActor
private final class TransientUnavailableCloudKitService: CloudKitServing {
    private let unavailableResponses: Int
    private var availabilityCalls = 0
    private var saves = 0

    init(unavailableResponses: Int) {
        self.unavailableResponses = unavailableResponses
    }

    var availabilityCallCount: Int {
        availabilityCalls
    }

    var saveCount: Int {
        saves
    }

    func availability() async -> CloudSyncAvailability {
        availabilityCalls += 1
        let shouldReturnUnavailable = availabilityCalls <= unavailableResponses
        return shouldReturnUnavailable ? .unavailable("iCloud is temporarily unavailable.") : .available
    }

    func fetchSnapshot() async throws -> CloudSyncSnapshot {
        .empty()
    }

    func saveSnapshot(_ snapshot: CloudSyncSnapshot) async throws {
        saves += 1
    }
}
