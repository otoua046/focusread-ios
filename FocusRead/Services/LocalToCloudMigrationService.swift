import Foundation
import OSLog

struct CloudSyncMigrationResult: Equatable, Sendable {
    var snapshot: CloudSyncSnapshot
    var didMigrate: Bool
    var logEntries: [CloudSyncMigrationLogEntry]
}

enum LocalToCloudMigrationService {
    private static let logger = Logger(subsystem: "FocusRead", category: "LocalToCloudMigration")

    static func prepareMigration(
        localSnapshot: CloudSyncSnapshot,
        cloudState: CloudSyncMigrationState,
        now: Date = Date()
    ) -> CloudSyncMigrationResult {
        let signature = localSignature(for: localSnapshot)
        guard cloudState.localSnapshotSignature != signature else {
            logger.debug("Skipping iCloud migration; local signature already migrated.")
            return CloudSyncMigrationResult(snapshot: localSnapshot, didMigrate: false, logEntries: [])
        }

        var state = cloudState
        state.migratedReadIDs = Set(state.migratedReadIDs)
            .union(localSnapshot.libraryItems.map(\.id))
            .sorted { $0.uuidString < $1.uuidString }
        state.migratedSettingKeys = Set(state.migratedSettingKeys)
            .union(localSnapshot.settings?.values.map(\.key) ?? [])
            .sorted()
        state.migratedRecapIDs = Set(state.migratedRecapIDs)
            .union(localSnapshot.aiRecaps.map(\.id))
            .sorted { $0.uuidString < $1.uuidString }
        if localSnapshot.readingStats != nil {
            state.migratedStatsAt = now
        }
        state.lastMigrationRunAt = now
        state.localSnapshotSignature = signature

        let entries = migrationLogEntries(for: localSnapshot, now: now)
        state.logEntries = Array((state.logEntries + entries).suffix(40))

        var snapshot = localSnapshot
        snapshot.migrationState = state

        logger.info("Prepared iCloud migration with \(localSnapshot.libraryItems.count) library items, \(localSnapshot.aiRecaps.count) recaps.")
        return CloudSyncMigrationResult(snapshot: snapshot, didMigrate: true, logEntries: entries)
    }

    static func localSignature(for snapshot: CloudSyncSnapshot) -> String {
        [
            snapshot.libraryItems.map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }.sorted().joined(separator: "|"),
            snapshot.readingStats.map { "\($0.updatedAt.timeIntervalSince1970):\($0.sessionEvents.count):\($0.completedReadIDs.count)" } ?? "no-stats",
            snapshot.settings?.values.map { "\($0.key):\($0.updatedAt.timeIntervalSince1970)" }.sorted().joined(separator: "|") ?? "no-settings",
            snapshot.aiRecaps.map { "\($0.id.uuidString):\($0.createdAt.timeIntervalSince1970)" }.sorted().joined(separator: "|")
        ]
        .joined(separator: "#")
    }

    private static func migrationLogEntries(
        for snapshot: CloudSyncSnapshot,
        now: Date
    ) -> [CloudSyncMigrationLogEntry] {
        [
            CloudSyncMigrationLogEntry(
                id: UUID(),
                createdAt: now,
                message: "Migrated \(snapshot.libraryItems.count) library metadata records without uploading document text or files."
            ),
            CloudSyncMigrationLogEntry(
                id: UUID(),
                createdAt: now,
                message: "Migrated settings: \(snapshot.settings?.values.count ?? 0), stats events: \(snapshot.readingStats?.sessionEvents.count ?? 0), AI recaps: \(snapshot.aiRecaps.count)."
            )
        ]
    }
}
