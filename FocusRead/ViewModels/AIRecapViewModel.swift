import Foundation

struct AIRecapSessionItem: Identifiable, Equatable {
    var id: UUID { session.id }

    let session: ReadingSessionEvent
    let recap: AIRecap?
    let isMostRecent: Bool
}

@MainActor
final class AIRecapViewModel: ObservableObject {
    @Published private(set) var items: [AIRecapSessionItem] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var generatingSessionID: UUID?
    @Published var errorMessage: String?

    let read: SavedRead
    private let readingStatsStore: ReadingStatsStore
    private let recapStore: AIRecapStore
    private let service: AIRecapService
    private var generationTask: Task<Void, Never>?

    init(
        read: SavedRead,
        readingStatsStore: ReadingStatsStore,
        recapStore: AIRecapStore,
        service: AIRecapService = AIRecapService()
    ) {
        self.read = read
        self.readingStatsStore = readingStatsStore
        self.recapStore = recapStore
        self.service = service
        refresh()
    }

    deinit {
        generationTask?.cancel()
    }

    var isLocalAIAvailable: Bool {
        service.isAvailable
    }

    var hasEligibleSessions: Bool {
        !items.isEmpty
    }

    var hasExistingRecaps: Bool {
        items.contains { $0.recap != nil }
    }

    func refresh() {
        let eligibleSessions = service.extractor.recentEligibleSessions(
            for: read,
            from: readingStatsStore.sessionEvents,
            limit: 3
        )
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
                let recap = try await service.generateRecap(for: read, sessionEvent: session)
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
            return "This session is too short for a useful recap."
        case .generationFailed, nil:
            return "Couldn’t generate recap. Try again."
        }
    }
}
