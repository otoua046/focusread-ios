import SwiftUI

struct RootView: View {
    @StateObject private var inputViewModel = InputViewModel()
    @State private var readerViewModel: ReaderViewModel?
    @AppStorage(ReaderBehaviorSettingsKey.defaultWPM) private var defaultWPM: Int = ReadingSession.defaultWPM
    private let tokenizer = TextTokenizer()

    var body: some View {
        Group {
            if let readerViewModel {
                ReaderView(viewModel: readerViewModel) {
                    readerViewModel.cleanup()
                    self.readerViewModel = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                TextInputView(viewModel: inputViewModel) {
                    startReading()
                } onStartImportedDocument: { document in
                    inputViewModel.text = document.text
                    startReading()
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: readerViewModel == nil)
    }

    private func startReading() {
        let tokens = tokenizer.tokenize(inputViewModel.text)
        guard !tokens.isEmpty else { return }
        let session = ReadingSession(tokens: tokens, wordsPerMinute: defaultWPM)
        readerViewModel = ReaderViewModel(session: session)
    }
}
