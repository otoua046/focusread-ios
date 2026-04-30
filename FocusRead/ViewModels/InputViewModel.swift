import Foundation
import Combine

@MainActor
final class InputViewModel: ObservableObject {
    @Published var text = sampleText

    var canStart: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func useSampleText() {
        text = Self.sampleText
    }

    static let sampleText = """
    FocusRead is built around a simple idea: when your eyes stay still, your attention has fewer places to leak.

    Paste an essay, a product brief, or a long message. Set a pace that feels slightly faster than comfortable, then let the words arrive one at a time. Commas breathe. Sentences pause. Longer words get a fraction more time.

    The result is not a race. It is a calm, focused reading rhythm that helps you move through text with less friction and more intent.
    """
}
