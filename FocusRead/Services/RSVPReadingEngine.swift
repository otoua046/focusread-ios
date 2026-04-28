import Foundation

actor RSVPReadingEngine {
    typealias AdvanceHandler = @MainActor @Sendable () -> Bool
    typealias SessionProvider = @MainActor @Sendable () -> ReadingSession
    typealias BehaviorProvider = @MainActor @Sendable () -> ReaderBehaviorSettings

    private var task: Task<Void, Never>?

    func start(
        sessionProvider: @escaping SessionProvider,
        behaviorProvider: @escaping BehaviorProvider,
        advance: @escaping AdvanceHandler
    ) {
        stop()
        task = Task {
            while !Task.isCancelled {
                let session = await sessionProvider()
                guard let token = session.currentToken else {
                    break
                }

                let behavior = await behaviorProvider()
                let delay = Self.delay(for: token, wpm: session.wordsPerMinute, behavior: behavior)
                try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
                guard !Task.isCancelled else { break }

                let shouldContinue = await advance()
                if !shouldContinue {
                    break
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    static func delay(
        for token: ReadingToken,
        wpm: Int,
        behavior: ReaderBehaviorSettings = .default
    ) -> TimeInterval {
        let base = 60.0 / Double(ReadingSession.clampWPM(wpm))
        var multiplier = 1.0

        if behavior.punctuationPausesEnabled {
            switch token.pauseKind {
            case .none:
                break
            case .minorPunctuation:
                multiplier += 0.45
            case .sentenceEnd:
                multiplier += 0.9
            case .paragraphBreak:
                multiplier += 1.35
            }
        }

        multiplier += behavior.longWordDelayMode.extraMultiplier(for: token)

        return base * multiplier
    }
}
