import CloudKit
import Foundation
import OSLog

enum CloudSyncAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

protocol CloudKitServing: AnyObject, Sendable {
    func availability() async -> CloudSyncAvailability
    func fetchSnapshot() async throws -> CloudSyncSnapshot
    func saveSnapshot(_ snapshot: CloudSyncSnapshot) async throws
}

enum CloudKitServiceFactory {
    static func makeDefaultService(bundle: Bundle = .main) -> CloudKitServing {
        // CKContainer must only be initialized by CloudKit-capable builds with valid entitlements.
        guard bundle.object(forInfoDictionaryKey: "FocusReadCloudKitEnabled") as? Bool == true else {
            return UnconfiguredCloudKitService()
        }
        return DefaultCloudKitService()
    }
}

final class UnconfiguredCloudKitService: CloudKitServing {
    func availability() async -> CloudSyncAvailability {
        .unavailable("iCloud Sync is not configured for this build.")
    }

    func fetchSnapshot() async throws -> CloudSyncSnapshot {
        CloudSyncSnapshot.empty()
    }

    func saveSnapshot(_ snapshot: CloudSyncSnapshot) async throws {}
}

final class DefaultCloudKitService: CloudKitServing, @unchecked Sendable {
    private enum RecordType {
        static let libraryItem = "FRLibraryItem"
        static let readingStats = "FRReadingStats"
        static let appSettings = "FRAppSettings"
        static let aiRecap = "FRAIRecap"
        static let migrationState = "FRMigrationState"
    }

    private enum Field {
        static let payload = "payload"
        static let updatedAt = "updatedAt"
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let logger = Logger(subsystem: "FocusRead", category: "CloudKitService")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(container: CKContainer = .default()) {
        self.container = container
        self.database = container.privateCloudDatabase
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func availability() async -> CloudSyncAvailability {
        await withCheckedContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(returning: .unavailable(error.localizedDescription))
                    return
                }

                switch status {
                case .available:
                    continuation.resume(returning: .available)
                case .noAccount:
                    continuation.resume(returning: .unavailable("Sign in to iCloud to sync FocusRead."))
                case .restricted:
                    continuation.resume(returning: .unavailable("iCloud is restricted on this device."))
                case .couldNotDetermine:
                    continuation.resume(returning: .unavailable("FocusRead could not determine iCloud account status."))
                case .temporarilyUnavailable:
                    continuation.resume(returning: .unavailable("iCloud is temporarily unavailable."))
                @unknown default:
                    continuation.resume(returning: .unavailable("iCloud is unavailable."))
                }
            }
        }
    }

    func fetchSnapshot() async throws -> CloudSyncSnapshot {
        let libraryRecords = try await fetchRecords(type: RecordType.libraryItem)
        let statsRecords = try await fetchRecords(type: RecordType.readingStats)
        let settingsRecords = try await fetchRecords(type: RecordType.appSettings)
        let recapRecords = try await fetchRecords(type: RecordType.aiRecap)
        let migrationRecords = try await fetchRecords(type: RecordType.migrationState)

        return CloudSyncSnapshot(
            libraryItems: try libraryRecords.compactMap { try decode(SyncedSavedRead.self, from: $0) },
            readingStats: try statsRecords.compactMap { try decode(SyncedReadingStats.self, from: $0) }.max { $0.updatedAt < $1.updatedAt },
            settings: try settingsRecords.compactMap { try decode(SyncedAppSettings.self, from: $0) }.max { $0.updatedAt < $1.updatedAt },
            aiRecaps: try recapRecords.compactMap { try decode(AIRecap.self, from: $0) },
            migrationState: try migrationRecords.compactMap { try decode(CloudSyncMigrationState.self, from: $0) }.first ?? CloudSyncMigrationState(),
            generatedAt: Date()
        )
    }

    func saveSnapshot(_ snapshot: CloudSyncSnapshot) async throws {
        for item in snapshot.libraryItems {
            try await save(item, recordType: RecordType.libraryItem, recordName: "read-\(item.id.uuidString)", updatedAt: item.updatedAt)
        }
        if let readingStats = snapshot.readingStats {
            try await save(readingStats, recordType: RecordType.readingStats, recordName: "reading-stats", updatedAt: readingStats.updatedAt)
        }
        if let settings = snapshot.settings {
            try await save(settings, recordType: RecordType.appSettings, recordName: "app-settings", updatedAt: settings.updatedAt)
        }
        for recap in snapshot.aiRecaps {
            try await save(recap, recordType: RecordType.aiRecap, recordName: "recap-\(recap.id.uuidString)", updatedAt: recap.createdAt)
        }
        try await save(
            snapshot.migrationState,
            recordType: RecordType.migrationState,
            recordName: "migration-state",
            updatedAt: snapshot.migrationState.lastMigrationRunAt ?? snapshot.generatedAt
        )
    }

    private func save<Value: Encodable>(
        _ value: Value,
        recordType: String,
        recordName: String,
        updatedAt: Date
    ) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await fetchRecord(recordID: recordID) ?? CKRecord(recordType: recordType, recordID: recordID)
        record[Field.payload] = try encoder.encode(value) as NSData
        record[Field.updatedAt] = updatedAt as NSDate
        _ = try await saveRecord(record)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from record: CKRecord) throws -> Value? {
        let payload = record[Field.payload]
        let data = (payload as? Data) ?? (payload as? NSData).map { $0 as Data }
        guard let data else {
            logger.error("CloudKit record \(record.recordID.recordName, privacy: .public) is missing payload data.")
            return nil
        }
        return try decoder.decode(type, from: data)
    }

    private func fetchRecords(type: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: Field.updatedAt, ascending: false)]
        var page = try await fetchRecordsPage(query: query)
        var records = page.records
        while let cursor = page.cursor {
            page = try await fetchRecordsPage(cursor: cursor)
            records.append(contentsOf: page.records)
        }
        return records
    }

    private func fetchRecordsPage(query: CKQuery) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            let operation = CKQueryOperation(query: query)
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    records.append(record)
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    continuation.resume(returning: (records, cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func fetchRecordsPage(cursor: CKQueryOperation.Cursor) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            let operation = CKQueryOperation(cursor: cursor)
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    records.append(record)
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    continuation.resume(returning: (records, cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func fetchRecord(recordID: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    continuation.resume(returning: nil)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: record)
            }
        }
    }

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: savedRecord ?? record)
            }
        }
    }
}
