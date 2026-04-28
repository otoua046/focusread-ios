import Foundation

actor RSVPReadingEngine {
    typealias AdvanceHandler = @MainActor @Sendable () -> Bool
    typealias SessionProvider = @MainActor @Sendable () -> ReadingSession

    private var task: Task<Void, Never>?

    func start(sessionProvider: @escaping SessionProvider, advance: @escaping AdvanceHandler) {
        stop()
        task = Task {
            while !Task.isCancelled {
                let session = await sessionProvider()
                guard let token = session.currentToken else {
                    break
                }

                let delay = Self.delay(for: token, wpm: session.wordsPerMinute)
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

    static func delay(for token: ReadingToken, wpm: Int) -> Double {
        let base = 60.0 / Double(ReadingSession.clampWPM(wpm))
        var multiplier = 1.0

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

        if token.isLongWord {
            multiplier += min(Double(token.text.count - 8) * 0.05, 0.35)
        }
        if token.containsNumber {
            multiplier += 0.25
        }

        return base * multiplier
    }
}
