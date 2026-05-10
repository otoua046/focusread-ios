import Combine
import Foundation
import OSLog

@MainActor
final class CloudSyncManager: ObservableObject {
    @Published private(set) var status: SyncStatus
    @Published var isSyncEnabled: Bool {
        didSet {
            userDefaults.set(isSyncEnabled, forKey: CloudSyncSettingsKey.isEnabled)
            if isSyncEnabled {
                scheduleSync(reason: "enabled")
            } else {
                status = .off
            }
        }
    }

    private weak var readingHistoryStore: LocalReadingHistoryStore?
    private weak var readingStatsStore: LocalReadingStatsStore?
    private weak var recapStore: LocalAIRecapStore?
    private let cloudKitService: CloudKitServing
    private let settingsStore: SyncSettingsStore
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "FocusRead", category: "CloudSync")
    private var syncTask: Task<Void, Never>?
    private var scheduledTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var isConfigured = false
    private var isApplyingRemoteSnapshot = false

    init(
        cloudKitService: CloudKitServing = CloudKitServiceFactory.makeDefaultService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.cloudKitService = cloudKitService
        self.userDefaults = userDefaults
        self.settingsStore = SyncSettingsStore(userDefaults: userDefaults)
        self.isSyncEnabled = userDefaults.object(forKey: CloudSyncSettingsKey.isEnabled) as? Bool ?? true
        self.status = SyncStatus(
            kind: (userDefaults.object(forKey: CloudSyncSettingsKey.isEnabled) as? Bool ?? true) ? .unavailable : .off,
            lastSyncedAt: userDefaults.object(forKey: CloudSyncSettingsKey.lastSyncedAt) as? Date,
            message: nil
        )
    }

    func configure(
        readingHistoryStore: LocalReadingHistoryStore,
        readingStatsStore: LocalReadingStatsStore,
        recapStore: LocalAIRecapStore
    ) {
        guard !isConfigured else { return }
        isConfigured = true
        self.readingHistoryStore = readingHistoryStore
        self.readingStatsStore = readingStatsStore
        self.recapStore = recapStore

        readingHistoryStore.$savedReads
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSync(reason: "library changed")
            }
            .store(in: &cancellables)

        readingStatsStore.$snapshot
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSync(reason: "stats changed")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard !isApplyingRemoteSnapshot else { return }
                guard settingsStore.refreshTrackedSettings() else { return }
                scheduleSync(reason: "settings changed")
            }
            .store(in: &cancellables)

        settingsStore.refreshTrackedSettings()
        scheduleSync(reason: "startup")
    }

    func syncNow() {
        scheduledTask?.cancel()
        runSync(reason: "manual")
    }

    func scheduleSync(reason: String) {
        guard isSyncEnabled, !isApplyingRemoteSnapshot else { return }
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                self?.runSync(reason: reason)
            }
        }
    }

    private func runSync(reason: String) {
        guard isSyncEnabled else {
            status = .off
            return
        }

        syncTask?.cancel()
        syncTask = Task { [weak self] in
            await self?.performSync(reason: reason)
        }
    }

    private func performSync(reason: String) async {
        guard let readingHistoryStore, let readingStatsStore, let recapStore else { return }

        status = SyncStatus(kind: .syncing, lastSyncedAt: status.lastSyncedAt, message: nil)
        logger.info("Starting iCloud sync: \(reason, privacy: .public)")

        switch await cloudKitService.availability() {
        case .available:
            break
        case .unavailable(let message):
            status = SyncStatus(kind: .unavailable, lastSyncedAt: status.lastSyncedAt, message: message)
            logger.info("iCloud sync unavailable: \(message, privacy: .public)")
            return
        }

        do {
            let now = Date()
            settingsStore.refreshTrackedSettings(now: now)
            let localSnapshot = makeLocalSnapshot(
                readingHistoryStore: readingHistoryStore,
                readingStatsStore: readingStatsStore,
                recapStore: recapStore,
                now: now
            )
            let cloudSnapshot = try await cloudKitService.fetchSnapshot()
            let migration = LocalToCloudMigrationService.prepareMigration(
                localSnapshot: localSnapshot,
                cloudState: cloudSnapshot.migrationState,
                now: now
            )
            let merged = SyncConflictResolver.mergeSnapshots(
                local: migration.snapshot,
                cloud: cloudSnapshot,
                now: now
            )

            isApplyingRemoteSnapshot = true
            applyMergedSnapshot(
                merged.value,
                readingHistoryStore: readingHistoryStore,
                readingStatsStore: readingStatsStore,
                recapStore: recapStore
            )
            isApplyingRemoteSnapshot = false

            try await cloudKitService.saveSnapshot(merged.value)

            writeSyncBookkeeping {
                userDefaults.set(now, forKey: CloudSyncSettingsKey.lastSyncedAt)
            }
            status = SyncStatus(kind: .synced, lastSyncedAt: now, message: nil)
            logDecisions(migration.logEntries + merged.decisions.map {
                CloudSyncMigrationLogEntry(id: UUID(), createdAt: now, message: "\($0.entity)/\($0.id): \($0.message)")
            })
        } catch {
            isApplyingRemoteSnapshot = false
            status = SyncStatus(kind: .error, lastSyncedAt: status.lastSyncedAt, message: error.localizedDescription)
            logger.error("iCloud sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeLocalSnapshot(
        readingHistoryStore: LocalReadingHistoryStore,
        readingStatsStore: LocalReadingStatsStore,
        recapStore: LocalAIRecapStore,
        now: Date
    ) -> CloudSyncSnapshot {
        let readIDs = readingHistoryStore.savedReads.map(\.id)
        return CloudSyncSnapshot(
            libraryItems: readingHistoryStore.syncSnapshotItems(now: now),
            readingStats: readingStatsStore.syncSnapshot(updatedAt: now),
            settings: settingsStore.snapshot(now: now),
            aiRecaps: recapStore.syncSnapshotRecaps(for: readIDs),
            migrationState: CloudSyncMigrationState(),
            generatedAt: now
        )
    }

    private func applyMergedSnapshot(
        _ snapshot: CloudSyncSnapshot,
        readingHistoryStore: LocalReadingHistoryStore,
        readingStatsStore: LocalReadingStatsStore,
        recapStore: LocalAIRecapStore
    ) {
        readingHistoryStore.applySyncMergedReads(snapshot.libraryItems)
        if let readingStats = snapshot.readingStats {
            readingStatsStore.applySyncMergedStats(readingStats)
        }
        if let settings = snapshot.settings {
            settingsStore.apply(settings)
        }
        recapStore.applySyncMergedRecaps(snapshot.aiRecaps)
    }

    private func logDecisions(_ entries: [CloudSyncMigrationLogEntry]) {
        entries.forEach { entry in
            logger.info("\(entry.message, privacy: .public)")
        }
    }

    private func writeSyncBookkeeping(_ updates: () -> Void) {
        isApplyingRemoteSnapshot = true
        updates()
        isApplyingRemoteSnapshot = false
    }
}

@MainActor
struct SyncSettingsStore {
    private struct Definition {
        var key: String
        var kind: SyncedSettingValueKind
        var defaultValue: String
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func snapshot(now: Date = Date()) -> SyncedAppSettings {
        let values = Self.definitions.map { definition in
            SyncedSettingValue(
                key: definition.key,
                value: storedString(for: definition),
                kind: definition.kind,
                updatedAt: settingUpdatedAt(for: definition.key) ?? now
            )
        }
        return SyncedAppSettings(values: values, updatedAt: values.map(\.updatedAt).max() ?? now)
    }

    func apply(_ settings: SyncedAppSettings) {
        for value in settings.values {
            let localUpdatedAt = settingUpdatedAt(for: value.key) ?? .distantPast
            guard value.updatedAt >= localUpdatedAt else { continue }
            apply(value)
            setSettingUpdatedAt(value.updatedAt, for: value.key)
            setKnownValue(value.value, for: value.key)
        }
    }

    @discardableResult
    func refreshTrackedSettings(now: Date = Date()) -> Bool {
        var didChange = false
        for definition in Self.definitions {
            let currentValue = storedString(for: definition)
            if userDefaults.object(forKey: updatedAtKey(for: definition.key)) == nil {
                setSettingUpdatedAt(now, for: definition.key)
            }

            guard let knownValue = knownValue(for: definition.key) else {
                setKnownValue(currentValue, for: definition.key)
                continue
            }

            guard knownValue != currentValue else { continue }
            setSettingUpdatedAt(now, for: definition.key)
            setKnownValue(currentValue, for: definition.key)
            didChange = true
        }
        return didChange
    }

    private func storedString(for definition: Definition) -> String {
        switch definition.kind {
        case .string:
            return userDefaults.string(forKey: definition.key) ?? definition.defaultValue
        case .integer:
            guard userDefaults.object(forKey: definition.key) != nil else { return definition.defaultValue }
            return String(userDefaults.integer(forKey: definition.key))
        case .double:
            guard userDefaults.object(forKey: definition.key) != nil else { return definition.defaultValue }
            return String(userDefaults.double(forKey: definition.key))
        case .bool:
            guard userDefaults.object(forKey: definition.key) != nil else { return definition.defaultValue }
            return userDefaults.bool(forKey: definition.key) ? "true" : "false"
        }
    }

    private func apply(_ value: SyncedSettingValue) {
        switch value.kind {
        case .string:
            userDefaults.set(value.value, forKey: value.key)
            if value.key == FocusReadThemeStorageKey.selectedThemeID {
                FocusReadThemeManager.shared.selectedThemeID = value.value
            }
        case .integer:
            userDefaults.set(Int(value.value) ?? 0, forKey: value.key)
        case .double:
            userDefaults.set(Double(value.value) ?? 0, forKey: value.key)
        case .bool:
            userDefaults.set(value.value == "true", forKey: value.key)
        }
    }

    private func settingUpdatedAt(for key: String) -> Date? {
        userDefaults.object(forKey: updatedAtKey(for: key)) as? Date
    }

    private func setSettingUpdatedAt(_ date: Date, for key: String) {
        userDefaults.set(date, forKey: updatedAtKey(for: key))
    }

    private func updatedAtKey(for key: String) -> String {
        CloudSyncSettingsKey.settingsUpdatedAtPrefix + key
    }

    private func knownValue(for key: String) -> String? {
        userDefaults.string(forKey: knownValueKey(for: key))
    }

    private func setKnownValue(_ value: String, for key: String) {
        userDefaults.set(value, forKey: knownValueKey(for: key))
    }

    private func knownValueKey(for key: String) -> String {
        CloudSyncSettingsKey.settingsKnownValuePrefix + key
    }

    private static let definitions: [Definition] = [
        Definition(key: TypographySettingsKey.fontFamily, kind: .string, defaultValue: ReaderFontFamily.serif.rawValue),
        Definition(key: TypographySettingsKey.fontSize, kind: .double, defaultValue: String(FontStyle.defaultSize)),
        Definition(key: TypographySettingsKey.fontWeight, kind: .string, defaultValue: ReaderFontWeight.regular.rawValue),
        Definition(key: TypographySettingsKey.isItalic, kind: .bool, defaultValue: "false"),
        Definition(key: TypographySettingsKey.textColor, kind: .string, defaultValue: ReaderTextColor.primary.rawValue),
        Definition(key: TypographySettingsKey.appearance, kind: .string, defaultValue: AppAppearance.system.rawValue),
        Definition(key: ReaderBehaviorSettingsKey.defaultWPM, kind: .integer, defaultValue: String(ReadingSession.defaultWPM)),
        Definition(key: ReaderBehaviorSettingsKey.hapticsEnabled, kind: .bool, defaultValue: "true"),
        Definition(key: ReaderBehaviorSettingsKey.reverseWPMDialDirection, kind: .bool, defaultValue: "false"),
        Definition(key: ReaderBehaviorSettingsKey.punctuationPausesEnabled, kind: .bool, defaultValue: "true"),
        Definition(key: ReaderBehaviorSettingsKey.longWordDelayMode, kind: .string, defaultValue: LongWordDelayMode.moderate.rawValue),
        Definition(key: ReaderBehaviorSettingsKey.smartCleanupMode, kind: .string, defaultValue: SmartCleanupAvailability.defaultMode.rawValue),
        Definition(key: ReaderBehaviorSettingsKey.anchorLetterEnabled, kind: .bool, defaultValue: "true"),
        Definition(key: ReaderBehaviorSettingsKey.displayMode, kind: .string, defaultValue: ReaderDisplayMode.oneWord.rawValue),
        Definition(key: AIRecapSettingsKey.isEnabled, kind: .bool, defaultValue: "true"),
        Definition(key: AppLanguageStorageKey.selectedLanguage, kind: .string, defaultValue: AppLanguage.systemDefault.rawValue),
        Definition(key: FocusReadThemeStorageKey.selectedThemeID, kind: .string, defaultValue: FocusReadThemeCatalog.defaultTheme.id),
        Definition(key: "library_view_mode", kind: .string, defaultValue: LibraryViewMode.grid.rawValue),
        Definition(key: "library_sort_mode", kind: .string, defaultValue: LibrarySortMode.recent.rawValue)
    ]
}
