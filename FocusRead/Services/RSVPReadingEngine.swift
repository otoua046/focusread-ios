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
                let tokens = session.currentTokens
                guard !tokens.isEmpty else {
                    break
                }

                let behavior = await behaviorProvider()
                let delay = Self.delay(for: tokens, wpm: session.wordsPerMinute, behavior: behavior)
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
        for tokens: [ReadingToken],
        wpm: Int,
        behavior: ReaderBehaviorSettings = .default
    ) -> TimeInterval {
        guard !tokens.isEmpty else { return 0 }
        
        let base = 60.0 / Double(ReadingSession.clampWPM(wpm))
        var multiplier = Double(tokens.count)

        for token in tokens {
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
        }

        return base * multiplier
    }
    
    private static func pauseWeight(_ kind: ReadingToken.PauseKind) -> Int {
        switch kind {
        case .none: return 0
        case .minorPunctuation: return 1
        case .sentenceEnd: return 2
        case .paragraphBreak: return 3
        }
    }
}
