import Foundation

@MainActor
protocol ReadingStatsStore: AnyObject {
    var snapshot: ReadingStatsSnapshot { get }
    var dailyStats: [DailyReadingStats] { get }
    var sessionEvents: [ReadingSessionEvent] { get }

    func record(_ event: ReadingSessionEvent)
    func markReadCompleted(readID: UUID, completedAt: Date)
    func updateDailyGoalWords(_ words: Int)
}

@MainActor
final class LocalReadingStatsStore: ObservableObject, ReadingStatsStore {
    @Published private(set) var snapshot: ReadingStatsSnapshot = .empty
    @Published private(set) var dailyStats: [DailyReadingStats] = []
    @Published private(set) var sessionEvents: [ReadingSessionEvent] = []

    private let fileManager: FileManager
    private let fileURL: URL
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private var completedReadIDs: Set<UUID> = []
    private var dailyGoalWords = ReadingStatsSnapshot.defaultDailyGoalWords
    private var persistenceSuspended = false

    init(
        fileManager: FileManager = .default,
        storageDirectory: URL? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = now

        let directory = storageDirectory ?? Self.defaultStorageDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("ReadingStats.json")

        load()
    }

    func record(_ event: ReadingSessionEvent) {
        guard event.wordsRead > 0 else { return }

        sessionEvents.append(event)
        upsertDailyStats(for: event)
        recomputeSnapshot()
        persist()
    }

    func markReadCompleted(readID: UUID, completedAt: Date = Date()) {
        guard completedReadIDs.insert(readID).inserted else { return }

        let day = calendar.startOfDay(for: completedAt)
        if let index = dailyStats.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            dailyStats[index].completedBooksCount += 1
        } else {
            dailyStats.append(DailyReadingStats(
                date: day,
                wordsRead: 0,
                readingSeconds: 0,
                sessionsCount: 0,
                completedBooksCount: 1
            ))
        }

        sortDailyStats()
        recomputeSnapshot()
        persist()
    }

    func updateDailyGoalWords(_ words: Int) {
        dailyGoalWords = min(max(words, 100), 100_000)
        recomputeSnapshot()
        persist()
    }

    func reconcileCompletedReads(from reads: [SavedRead]) {
        var didChange = false
        for read in reads where read.progressPercent >= 100 {
            guard completedReadIDs.insert(read.id).inserted else { continue }
            didChange = true

            let day = calendar.startOfDay(for: read.updatedAt)
            if let index = dailyStats.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                dailyStats[index].completedBooksCount += 1
            } else {
                dailyStats.append(DailyReadingStats(
                    date: day,
                    wordsRead: 0,
                    readingSeconds: 0,
                    sessionsCount: 0,
                    completedBooksCount: 1
                ))
            }
        }

        guard didChange else { return }
        sortDailyStats()
        recomputeSnapshot()
        persist()
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            recomputeSnapshot()
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try Data(contentsOf: fileURL)
            let payload = try decoder.decode(ReadingStatsPersistencePayload.self, from: data)
            dailyGoalWords = max(payload.dailyGoalWords, 1)
            dailyStats = payload.dailyStats
            sessionEvents = payload.sessionEvents
            completedReadIDs = Set(payload.completedReadIDs)
            sortDailyStats()
            recomputeSnapshot()
        } catch {
            quarantineUnreadableStatsFile(loadError: error)
            dailyGoalWords = ReadingStatsSnapshot.defaultDailyGoalWords
            dailyStats = []
            sessionEvents = []
            completedReadIDs = []
            recomputeSnapshot()
        }
    }

    private func upsertDailyStats(for event: ReadingSessionEvent) {
        let day = calendar.startOfDay(for: event.endedAt)
        if let index = dailyStats.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            dailyStats[index].wordsRead += event.wordsRead
            dailyStats[index].readingSeconds += event.readingSeconds
            dailyStats[index].sessionsCount += 1
        } else {
            dailyStats.append(DailyReadingStats(
                date: day,
                wordsRead: event.wordsRead,
                readingSeconds: event.readingSeconds,
                sessionsCount: 1,
                completedBooksCount: 0
            ))
        }
        sortDailyStats()
    }

    private func sortDailyStats() {
        dailyStats.sort { $0.date > $1.date }
    }

    private func recomputeSnapshot() {
        snapshot = ReadingStatsCalculator.snapshot(
            dailyStats: dailyStats,
            sessionEvents: sessionEvents,
            completedReadIDs: completedReadIDs,
            dailyGoalWords: dailyGoalWords,
            calendar: calendar,
            now: nowProvider()
        )
    }

    private func persist() {
        guard !persistenceSuspended else { return }

        let payload = ReadingStatsPersistencePayload(
            dailyGoalWords: dailyGoalWords,
            dailyStats: dailyStats,
            sessionEvents: sessionEvents,
            completedReadIDs: Array(completedReadIDs).sorted { $0.uuidString < $1.uuidString }
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to persist reading stats: \(error)")
        }
    }

    private func quarantineUnreadableStatsFile(loadError: Error) {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantineURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("ReadingStats-unreadable-\(timestamp).json")

        do {
            try fileManager.copyItem(at: fileURL, to: quarantineURL)
            try? fileManager.removeItem(at: fileURL)
        } catch {
            persistenceSuspended = true
            assertionFailure("Unable to quarantine unreadable reading stats: \(loadError); quarantine error: \(error)")
        }
    }

    private static func defaultStorageDirectory(fileManager: FileManager) -> URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return supportDirectory.appendingPathComponent("FocusRead", isDirectory: true)
    }
}

private struct ReadingStatsPersistencePayload: Codable {
    var dailyGoalWords: Int
    var dailyStats: [DailyReadingStats]
    var sessionEvents: [ReadingSessionEvent]
    var completedReadIDs: [UUID]
}
