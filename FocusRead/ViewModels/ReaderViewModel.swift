import Foundation
import Combine
import UIKit

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var session: ReadingSession
    private let engine: RSVPReadingEngine
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private var behaviorSettings: ReaderBehaviorSettings

    @Published var isPlaying = false
    @Published var controlsVisible = true

    init(session: ReadingSession, engine: RSVPReadingEngine = RSVPReadingEngine()) {
        self.session = session
        self.engine = engine
        self.behaviorSettings = Self.storedBehaviorSettings()
        haptics.prepare()
    }

    var currentWord: String {
        session.currentToken?.text ?? ""
    }

    var wordsPerMinute: Int {
        get { session.wordsPerMinute }
        set { setWPM(newValue, haptic: false) }
    }

    var progress: Double {
        session.progress
    }

    var progressLabel: String {
        guard !session.tokens.isEmpty else { return "0 / 0" }
        return "\(session.currentIndex + 1) / \(session.tokens.count)"
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !session.tokens.isEmpty else { return }
        if session.isAtEnd {
            session.currentIndex = 0
        }
        isPlaying = true
        controlsVisible = false
        triggerHaptic(intensity: 0.75)

        Task {
            await engine.start(
                sessionProvider: { [weak self] in
                    self?.session ?? ReadingSession(tokens: [])
                },
                behaviorProvider: { [weak self] in
                    self?.behaviorSettings ?? .default
                },
                advance: { [weak self] in
                    guard let self else { return false }
                    return self.advanceFromEngine()
                }
            )
        }
    }

    func pause(showControls: Bool = true) {
        guard isPlaying else {
            controlsVisible = showControls
            return
        }
        isPlaying = false
        controlsVisible = showControls
        triggerHaptic(intensity: 0.55)
        Task { await engine.stop() }
    }

    func rewindWord() {
        pause(showControls: true)
        withAnimationStateChange {
            session.rewindWord()
        }
        triggerHaptic(intensity: 0.45)
    }

    func skipWord() {
        pause(showControls: true)
        withAnimationStateChange {
            session.skipWord()
        }
        triggerHaptic(intensity: 0.35)
    }

    func rewindSentence() {
        pause(showControls: true)
        withAnimationStateChange {
            session.rewindSentence()
        }
        triggerHaptic(intensity: 0.7)
    }

    func adjustSpeed(by delta: Int) {
        setWPM(session.wordsPerMinute + delta, haptic: true)
    }

    func setWPM(_ value: Int, haptic: Bool = true) {
        let previous = session.wordsPerMinute
        session.setWPM(value)
        if haptic, previous != session.wordsPerMinute {
            triggerHaptic(intensity: 0.35)
        }
    }

    func revealControls() {
        controlsVisible = true
    }

    func updateBehaviorSettings(_ settings: ReaderBehaviorSettings) {
        behaviorSettings = settings
    }

    func cleanup() {
        Task { await engine.stop() }
    }

    private func advanceFromEngine() -> Bool {
        guard isPlaying else { return false }
        if session.isAtEnd {
            isPlaying = false
            controlsVisible = true
            return false
        }

        session.advance()
        return true
    }

    private func withAnimationStateChange(_ change: () -> Void) {
        change()
    }

    private func triggerHaptic(intensity: CGFloat) {
        guard UserDefaults.standard.object(forKey: ReaderBehaviorSettingsKey.hapticsEnabled) as? Bool ?? true else {
            return
        }
        haptics.impactOccurred(intensity: intensity)
        haptics.prepare()
    }

    private static func storedBehaviorSettings() -> ReaderBehaviorSettings {
        let defaults = UserDefaults.standard
        let punctuationPauses = defaults.object(forKey: ReaderBehaviorSettingsKey.punctuationPausesEnabled) as? Bool ?? true
        let rawLongWordMode = defaults.string(forKey: ReaderBehaviorSettingsKey.longWordDelayMode) ?? LongWordDelayMode.moderate.rawValue

        return ReaderBehaviorSettings(
            punctuationPausesEnabled: punctuationPauses,
            longWordDelayMode: LongWordDelayMode(rawValue: rawLongWordMode) ?? .moderate
        )
    }
}
