import SwiftUI

struct RootView: View {
    @StateObject private var inputViewModel = InputViewModel()
    @StateObject private var readingHistoryStore = LocalReadingHistoryStore()
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
                TextInputView(
                    viewModel: inputViewModel,
                    historyStore: readingHistoryStore
                ) {
                    startReading()
                } onStartImportedDocument: { document in
                    startReading(importedDocument: document)
                } onResumeSavedRead: { read in
                    resume(read)
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: readerViewModel == nil)
    }

    private func startReading() {
        let tokens = tokenizer.tokenize(inputViewModel.text)
        guard !tokens.isEmpty else { return }
        let session = ReadingSession(
            tokens: tokens,
            document: .pastedText(),
            wordsPerMinute: defaultWPM
        )
        let savedRead = SavedReadMapper.makeSavedRead(from: inputViewModel.text, tokens: tokens)
        readingHistoryStore.save(savedRead)
        readerViewModel = ReaderViewModel(
            session: session,
            readingHistoryStore: readingHistoryStore,
            savedReadID: savedRead.id
        )
    }

    private func startReading(importedDocument: ImportedDocument) {
        let tokens = tokenizer.tokenize(importedDocument)
        guard !tokens.isEmpty else { return }
        let session = ReadingSession(
            tokens: tokens,
            document: ReadingDocument(importedDocument: importedDocument),
            wordsPerMinute: defaultWPM
        )
        let savedRead = SavedReadMapper.makeSavedRead(from: importedDocument, tokens: tokens)
        readingHistoryStore.save(savedRead)
        readerViewModel = ReaderViewModel(
            session: session,
            importedDocument: importedDocument,
            readingHistoryStore: readingHistoryStore,
            savedReadID: savedRead.id
        )
    }

    private func resume(_ read: SavedRead) {
        let importedDocument = SavedReadMapper.importedDocument(from: read)
        let tokens = importedDocument.map(tokenizer.tokenize) ?? tokenizer.tokenize(SavedReadMapper.text(from: read))
        guard !tokens.isEmpty else { return }

        var updatedRead = read
        updatedRead.lastOpenedAt = Date()
        updatedRead.updatedAt = updatedRead.lastOpenedAt
        updatedRead.readingStats.sessionsCount += 1
        readingHistoryStore.save(updatedRead)

        let session = ReadingSession(
            tokens: tokens,
            document: importedDocument.map(ReadingDocument.init(importedDocument:))
                ?? SavedReadMapper.readingDocument(from: updatedRead),
            currentIndex: updatedRead.currentWordIndex,
            wordsPerMinute: defaultWPM
        )
        readerViewModel = ReaderViewModel(
            session: session,
            importedDocument: importedDocument,
            readingHistoryStore: readingHistoryStore,
            savedReadID: updatedRead.id
        )
    }
}
