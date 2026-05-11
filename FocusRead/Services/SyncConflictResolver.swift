import Foundation

struct SyncMergeDecision: Equatable, Sendable {
    var entity: String
    var id: String
    var message: String
}

struct SyncMergeResult<Value: Equatable>: Equatable {
    var value: Value
    var decisions: [SyncMergeDecision]
}

enum SyncConflictResolver {
    static func mergeSnapshots(
        local: CloudSyncSnapshot,
        cloud: CloudSyncSnapshot,
        now: Date = Date()
    ) -> SyncMergeResult<CloudSyncSnapshot> {
        let deletedLibraryItems = mergeDeletedLibraryItems(
            local: local.deletedLibraryItems,
            cloud: cloud.deletedLibraryItems
        )
        let library = mergeLibraryItems(
            local: local.libraryItems,
            cloud: cloud.libraryItems,
            deleted: deletedLibraryItems.value
        )
        let stats = mergeReadingStats(local: local.readingStats, cloud: cloud.readingStats)
        let settings = mergeSettings(local: local.settings, cloud: cloud.settings)
        let recaps = mergeAIRecaps(local: local.aiRecaps, cloud: cloud.aiRecaps)
        let migrationState = mergeMigrationState(local: local.migrationState, cloud: cloud.migrationState, now: now)

        return SyncMergeResult(
            value: CloudSyncSnapshot(
                libraryItems: library.value,
                deletedLibraryItems: deletedLibraryItems.value,
                readingStats: stats.value,
                settings: settings.value,
                aiRecaps: recaps.value,
                migrationState: migrationState.value,
                generatedAt: now
            ),
            decisions: library.decisions + deletedLibraryItems.decisions + stats.decisions + settings.decisions + recaps.decisions + migrationState.decisions
        )
    }

    static func mergeLibraryItems(
        local: [SyncedSavedRead],
        cloud: [SyncedSavedRead],
        deleted: [SyncedDeletedLibraryItem] = []
    ) -> SyncMergeResult<[SyncedSavedRead]> {
        var merged: [SyncedSavedRead] = []
        var decisions: [SyncMergeDecision] = []
        var indexByFingerprint: [String: Int] = [:]
        let tombstonesByID = Dictionary(
            deleted.map { ($0.id, $0) },
            uniquingKeysWith: { first, second in first.deletedAt >= second.deletedAt ? first : second }
        )
        let tombstonesByFingerprint = Dictionary(
            deleted.compactMap { tombstone in tombstone.contentFingerprint.map { ($0, tombstone) } },
            uniquingKeysWith: { first, second in first.deletedAt >= second.deletedAt ? first : second }
        )

        func appendOrMerge(_ item: SyncedSavedRead, source: String) {
            if let existingIndex = merged.firstIndex(where: { $0.id == item.id }) {
                let result = mergeSavedRead(local: merged[existingIndex], cloud: item)
                merged[existingIndex] = result.value
                decisions.append(contentsOf: result.decisions)
                return
            }

            if let existingIndex = indexByFingerprint[item.contentFingerprint] {
                let existing = merged[existingIndex]
                let result: SyncMergeResult<SyncedSavedRead>
                if existing.fileSync?.localRelativePath != nil || source == "cloud" {
                    result = mergeSavedRead(local: existing, cloud: item)
                } else {
                    result = mergeSavedRead(local: item, cloud: existing)
                }
                merged[existingIndex] = result.value
                decisions.append(contentsOf: result.decisions)
                decisions.append(SyncMergeDecision(
                    entity: "library",
                    id: item.id.uuidString,
                    message: "Merged duplicate library metadata with matching content fingerprint."
                ))
                return
            }

            merged.append(item)
            indexByFingerprint[item.contentFingerprint] = merged.count - 1
        }

        local.forEach { appendOrMerge($0, source: "local") }
        cloud.forEach { appendOrMerge($0, source: "cloud") }

        merged = merged.filter { item in
            guard let tombstone = tombstonesByID[item.id] ?? tombstonesByFingerprint[item.contentFingerprint],
                  tombstone.deletedAt >= item.updatedAt else {
                return true
            }
            decisions.append(SyncMergeDecision(
                entity: "library",
                id: item.id.uuidString,
                message: "Kept library deletion tombstone newer than item metadata."
            ))
            return false
        }

        merged.sort {
            if $0.isFavorite != $1.isFavorite {
                return $0.isFavorite && !$1.isFavorite
            }
            return $0.lastOpenedAt > $1.lastOpenedAt
        }
        return SyncMergeResult(value: merged, decisions: decisions)
    }

    static func mergeDeletedLibraryItems(
        local: [SyncedDeletedLibraryItem],
        cloud: [SyncedDeletedLibraryItem]
    ) -> SyncMergeResult<[SyncedDeletedLibraryItem]> {
        var byID: [UUID: SyncedDeletedLibraryItem] = [:]
        var decisions: [SyncMergeDecision] = []

        for tombstone in local + cloud {
            if let existing = byID[tombstone.id] {
                byID[tombstone.id] = existing.deletedAt >= tombstone.deletedAt ? existing : tombstone
                decisions.append(SyncMergeDecision(
                    entity: "libraryDeletion",
                    id: tombstone.id.uuidString,
                    message: "Merged duplicate library deletion tombstone."
                ))
            } else {
                byID[tombstone.id] = tombstone
            }
        }

        return SyncMergeResult(
            value: byID.values.sorted { $0.deletedAt > $1.deletedAt },
            decisions: decisions
        )
    }

    static func mergeSavedRead(local: SyncedSavedRead, cloud: SyncedSavedRead) -> SyncMergeResult<SyncedSavedRead> {
        var decisions: [SyncMergeDecision] = []
        var base = local.updatedAt >= cloud.updatedAt ? local : cloud
        let progress = preferredProgress(local: local, cloud: cloud)

        base.currentWordIndex = progress.currentWordIndex
        base.progressPercent = progress.progressPercent
        base.currentPage = progress.currentPage
        base.currentChapter = progress.currentChapter
        base.lastOpenedAt = max(local.lastOpenedAt, cloud.lastOpenedAt)
        base.readingStats = SavedReadStats(
            totalTimeRead: max(local.readingStats.totalTimeRead, cloud.readingStats.totalTimeRead),
            sessionsCount: max(local.readingStats.sessionsCount, cloud.readingStats.sessionsCount)
        )
        base.fileSync = preferredFileSync(local: local.fileSync, cloud: cloud.fileSync)

        if progress.source != "newest" {
            decisions.append(SyncMergeDecision(
                entity: "readingProgress",
                id: local.id.uuidString,
                message: "Kept \(progress.source) progress during merge."
            ))
        }

        return SyncMergeResult(value: base, decisions: decisions)
    }

    static func mergeReadingStats(
        local: SyncedReadingStats?,
        cloud: SyncedReadingStats?
    ) -> SyncMergeResult<SyncedReadingStats?> {
        guard let local else { return SyncMergeResult(value: cloud, decisions: []) }
        guard let cloud else { return SyncMergeResult(value: local, decisions: []) }

        var decisions: [SyncMergeDecision] = []
        let events = Dictionary(
            (local.sessionEvents + cloud.sessionEvents).map { ($0.id, $0) },
            uniquingKeysWith: { first, second in first.endedAt >= second.endedAt ? first : second }
        )
        let completedReadIDs = Set(local.completedReadIDs).union(cloud.completedReadIDs)
        let dailyStats = mergeDailyStats(
            local: local.dailyStats,
            cloud: cloud.dailyStats,
            sessionEvents: Array(events.values),
            completedReadIDs: completedReadIDs
        )
        if events.count != local.sessionEvents.count || completedReadIDs.count != local.completedReadIDs.count {
            decisions.append(SyncMergeDecision(
                entity: "readingStats",
                id: "summary",
                message: "Merged reading stats by unique session IDs and completed read IDs."
            ))
        }

        return SyncMergeResult(
            value: SyncedReadingStats(
                dailyGoalWords: local.updatedAt >= cloud.updatedAt ? local.dailyGoalWords : cloud.dailyGoalWords,
                dailyStats: dailyStats,
                sessionEvents: events.values.sorted { $0.endedAt > $1.endedAt },
                completedReadIDs: completedReadIDs.sorted { $0.uuidString < $1.uuidString },
                updatedAt: max(local.updatedAt, cloud.updatedAt)
            ),
            decisions: decisions
        )
    }

    static func mergeSettings(
        local: SyncedAppSettings?,
        cloud: SyncedAppSettings?
    ) -> SyncMergeResult<SyncedAppSettings?> {
        guard let local else { return SyncMergeResult(value: cloud, decisions: []) }
        guard let cloud else { return SyncMergeResult(value: local, decisions: []) }

        var decisions: [SyncMergeDecision] = []
        let allKeys = Set(local.values.map(\.key)).union(cloud.values.map(\.key))
        let localByKey = Dictionary(local.values.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let cloudByKey = Dictionary(cloud.values.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        let values = allKeys.compactMap { key -> SyncedSettingValue? in
            guard let localValue = localByKey[key] else { return cloudByKey[key] }
            guard let cloudValue = cloudByKey[key] else { return localValue }
            let winner = localValue.updatedAt >= cloudValue.updatedAt ? localValue : cloudValue
            if winner != localValue {
                decisions.append(SyncMergeDecision(
                    entity: "settings",
                    id: key,
                    message: "Applied newer cloud setting."
                ))
            }
            return winner
        }
        .sorted { $0.key < $1.key }

        return SyncMergeResult(
            value: SyncedAppSettings(
                values: values,
                updatedAt: values.map(\.updatedAt).max() ?? max(local.updatedAt, cloud.updatedAt)
            ),
            decisions: decisions
        )
    }

    static func mergeAIRecaps(local: [AIRecap], cloud: [AIRecap]) -> SyncMergeResult<[AIRecap]> {
        let recapsByID = Dictionary(
            (local + cloud).map { ($0.id, $0) },
            uniquingKeysWith: { first, second in first.createdAt >= second.createdAt ? first : second }
        )
        let recaps = recapsByID.values.sorted {
            if $0.sessionEndedAt != $1.sessionEndedAt {
                return $0.sessionEndedAt > $1.sessionEndedAt
            }
            return $0.createdAt > $1.createdAt
        }
        return SyncMergeResult(value: recaps, decisions: [])
    }

    static func mergeMigrationState(
        local: CloudSyncMigrationState,
        cloud: CloudSyncMigrationState,
        now: Date
    ) -> SyncMergeResult<CloudSyncMigrationState> {
        var state = CloudSyncMigrationState(
            schemaVersion: max(local.schemaVersion, cloud.schemaVersion),
            migratedReadIDs: Set(local.migratedReadIDs).union(cloud.migratedReadIDs).sorted { $0.uuidString < $1.uuidString },
            migratedSettingKeys: Set(local.migratedSettingKeys).union(cloud.migratedSettingKeys).sorted(),
            migratedStatsAt: [local.migratedStatsAt, cloud.migratedStatsAt].compactMap { $0 }.max(),
            migratedRecapIDs: Set(local.migratedRecapIDs).union(cloud.migratedRecapIDs).sorted { $0.uuidString < $1.uuidString },
            lastMigrationRunAt: [local.lastMigrationRunAt, cloud.lastMigrationRunAt].compactMap { $0 }.max(),
            localSnapshotSignature: local.localSnapshotSignature ?? cloud.localSnapshotSignature,
            logEntries: Array((local.logEntries + cloud.logEntries).suffix(40))
        )
        if state.lastMigrationRunAt == nil {
            state.lastMigrationRunAt = now
        }
        return SyncMergeResult(value: state, decisions: [])
    }

    private static func preferredProgress(
        local: SyncedSavedRead,
        cloud: SyncedSavedRead
    ) -> (currentWordIndex: Int, progressPercent: Double, currentPage: Int?, currentChapter: Int?, source: String) {
        let newer = local.updatedAt >= cloud.updatedAt ? local : cloud
        let older = local.updatedAt >= cloud.updatedAt ? cloud : local
        let newerLooksLikeIntentionalReset = newer.currentWordIndex <= 1
            && newer.progressPercent <= 1
            && older.progressPercent >= 10
            && newer.updatedAt > older.updatedAt

        if newerLooksLikeIntentionalReset {
            return (newer.currentWordIndex, newer.progressPercent, newer.currentPage, newer.currentChapter, "intentional reset")
        }

        let furthest = local.progressPercent >= cloud.progressPercent ? local : cloud
        if furthest.id == newer.id && furthest.progressPercent == newer.progressPercent {
            return (furthest.currentWordIndex, furthest.progressPercent, furthest.currentPage, furthest.currentChapter, "newest")
        }
        return (furthest.currentWordIndex, furthest.progressPercent, furthest.currentPage, furthest.currentChapter, "furthest")
    }

    private static func preferredFileSync(
        local: CloudDocumentFileSyncDescriptor?,
        cloud: CloudDocumentFileSyncDescriptor?
    ) -> CloudDocumentFileSyncDescriptor? {
        if let local, local.localRelativePath != nil {
            return local
        }
        if let cloud, cloud.cloudAssetRecordName != nil {
            return cloud
        }
        return local ?? cloud
    }

    private static func mergeDailyStats(
        local: [DailyReadingStats],
        cloud: [DailyReadingStats],
        sessionEvents: [ReadingSessionEvent],
        completedReadIDs: Set<UUID>
    ) -> [DailyReadingStats] {
        let calendar = Calendar(identifier: .gregorian)
        let stats = local + cloud
        let groupedStats = Dictionary(grouping: stats) { calendar.startOfDay(for: $0.date) }
        let groupedEvents = Dictionary(grouping: sessionEvents) { calendar.startOfDay(for: $0.endedAt) }
        let dates = Set(groupedStats.keys).union(groupedEvents.keys)
        let merged: [DailyReadingStats] = dates.map { date in
            let statsForDay = groupedStats[date] ?? []
            let eventsForDay = groupedEvents[date] ?? []
            let completedBooksCount = mergedCompletedBooksCount(for: statsForDay)
            return DailyReadingStats(
                date: date,
                wordsRead: eventsForDay.isEmpty
                    ? mergedIntegerCounter(statsForDay.map(\.wordsRead))
                    : eventsForDay.reduce(0) { $0 + $1.wordsRead },
                readingSeconds: eventsForDay.isEmpty
                    ? mergedTimeCounter(statsForDay.map(\.readingSeconds))
                    : eventsForDay.reduce(0) { $0 + $1.readingSeconds },
                sessionsCount: eventsForDay.isEmpty
                    ? mergedIntegerCounter(statsForDay.map(\.sessionsCount))
                    : eventsForDay.count,
                completedBooksCount: completedBooksCount
            )
        }
        .sorted { $0.date > $1.date }

        return cappedCompletedBooks(merged, totalCompletedBooks: completedReadIDs.count)
    }

    private static func mergedIntegerCounter(_ values: [Int]) -> Int {
        let positiveValues = values.filter { $0 > 0 }
        guard Set(positiveValues).count != 1 else { return positiveValues.first ?? 0 }
        return positiveValues.reduce(0, +)
    }

    private static func mergedTimeCounter(_ values: [TimeInterval]) -> TimeInterval {
        let positiveValues = values.filter { $0 > 0 }
        guard Set(positiveValues).count != 1 else { return positiveValues.first ?? 0 }
        return positiveValues.reduce(0, +)
    }

    private static func mergedCompletedBooksCount(for stats: [DailyReadingStats]) -> Int {
        mergedIntegerCounter(stats.map(\.completedBooksCount))
    }

    private static func cappedCompletedBooks(
        _ dailyStats: [DailyReadingStats],
        totalCompletedBooks: Int
    ) -> [DailyReadingStats] {
        guard totalCompletedBooks > 0 else {
            return dailyStats.map {
                DailyReadingStats(
                    date: $0.date,
                    wordsRead: $0.wordsRead,
                    readingSeconds: $0.readingSeconds,
                    sessionsCount: $0.sessionsCount,
                    completedBooksCount: 0
                )
            }
        }

        var remaining = totalCompletedBooks
        return dailyStats.map { stat in
            let completedBooksCount = min(stat.completedBooksCount, remaining)
            remaining -= completedBooksCount
            return DailyReadingStats(
                date: stat.date,
                wordsRead: stat.wordsRead,
                readingSeconds: stat.readingSeconds,
                sessionsCount: stat.sessionsCount,
                completedBooksCount: completedBooksCount
            )
        }
    }
}
