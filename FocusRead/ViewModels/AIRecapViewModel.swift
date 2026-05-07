import Foundation

struct AIRecapSessionItem: Identifiable, Equatable {
    var id: UUID { session.id }

    let session: AIRecapSession
    let recap: AIRecap?
    let isMostRecent: Bool
}

@MainActor
final class AIRecapViewModel: ObservableObject {
    @Published private(set) var items: [AIRecapSessionItem] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var generatingSessionID: UUID?
    @Published private(set) var hasOnlyTooShortSessions = false
    @Published var errorMessage: String?

    let read: SavedRead
    private let readingStatsStore: ReadingStatsStore
    private let recapStore: AIRecapStore
    private let service: AIRecapService
    private let isAIRecapsEnabledProvider: () -> Bool
    private var generationTask: Task<Void, Never>?

    init(
        read: SavedRead,
        readingStatsStore: ReadingStatsStore,
        recapStore: AIRecapStore,
        service: AIRecapService = AIRecapService(),
        isAIRecapsEnabledProvider: (() -> Bool)? = nil
    ) {
        self.read = read
        self.readingStatsStore = readingStatsStore
        self.recapStore = recapStore
        self.service = service
        self.isAIRecapsEnabledProvider = isAIRecapsEnabledProvider ?? {
            AIRecapSettings.isEnabled(localAIAvailable: service.isAvailable)
        }
        refresh()
    }

    deinit {
        generationTask?.cancel()
    }

    var isLocalAIAvailable: Bool {
        service.isAvailable
    }

    var isAIRecapsEnabled: Bool {
        isAIRecapsEnabledProvider()
    }

    var hasEligibleSessions: Bool {
        !items.isEmpty
    }

    var hasExistingRecaps: Bool {
        items.contains { $0.recap != nil }
    }

    func refresh() {
        guard isAIRecapsEnabled else {
            items = []
            hasOnlyTooShortSessions = false
            return
        }

        let logicalSessions = service.extractor.logicalSessions(
            for: read,
            from: readingStatsStore.sessionEvents
        )
        let eligibleSessions = logicalSessions
            .filter { $0.sourceWordRange.count >= service.extractor.minimumInputWordCount }
            .sorted { $0.endedAt > $1.endedAt }
            .prefix(3)
            .map { $0 }
        hasOnlyTooShortSessions = !logicalSessions.isEmpty && eligibleSessions.isEmpty
        let recapsBySessionID = Dictionary(
            uniqueKeysWithValues: recapStore.recaps(for: read.id).map { ($0.sessionID, $0) }
        )

        items = eligibleSessions.enumerated().map { index, session in
            AIRecapSessionItem(
                session: session,
                recap: recapsBySessionID[session.id],
                isMostRecent: index == 0
            )
        }
    }

    func generate(for item: AIRecapSessionItem, regenerate: Bool = false) {
        guard !isGenerating else { return }
        guard isAIRecapsEnabled else {
            errorMessage = AIRecapSettings.disabledMessage
            return
        }
        guard item.isMostRecent || item.recap != nil else { return }
        guard regenerate || item.recap == nil else { return }
        guard service.isAvailable else {
            errorMessage = Self.message(for: AIRecapGenerationError.localAIUnavailable)
            return
        }

        errorMessage = nil
        isGenerating = true
        generatingSessionID = item.session.id
        let read = read
        let session = item.session
        let service = service

        generationTask = Task { [weak self, read, session, service] in
            do {
                let recap = try await service.generateRecap(for: read, recapSession: session)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.recapStore.save(recap)
                    self.finishGeneration()
                    self.refresh()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.finishGeneration()
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.errorMessage = Self.message(for: error)
                    self.finishGeneration()
                }
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        finishGeneration()
    }

    private func finishGeneration() {
        isGenerating = false
        generatingSessionID = nil
        generationTask = nil
    }

    private static func message(for error: Error) -> String {
        switch error as? AIRecapGenerationError {
        case .localAIUnavailable:
            return "AI Recap requires on-device Apple Intelligence support."
        case .noEligibleSession:
            return "No recent reading session is available for recap yet."
        case .sourceUnavailable:
            return "Couldn’t find enough saved text for this session."
        case .notEnoughText:
            return "This reading session is too short to summarize."
        case .generationFailed, nil:
            return "Couldn’t generate recap. Try again."
        }
    }
}
