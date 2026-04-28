import Foundation

struct ReadingToken: Identifiable, Equatable, Sendable {
    enum PauseKind: Equatable, Sendable {
        case none
        case minorPunctuation
        case sentenceEnd
        case paragraphBreak
    }

    let id: Int
    let text: String
    let rawText: String
    let pauseKind: PauseKind
    let sentenceIndex: Int
    let containsNumber: Bool

    var isLongWord: Bool {
        text.count >= 9
    }
}
