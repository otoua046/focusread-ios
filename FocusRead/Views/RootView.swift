import SwiftUI

struct RootView: View {
    private enum MainTab: Hashable, CaseIterable {
        case home
        case library
        case stats
        case settings

        var title: String {
            switch self {
            case .home:
                return "Home"
            case .library:
                return "Library"
            case .stats:
                return "My Stats"
            case .settings:
                return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .home:
                return "house"
            case .library:
                return "books.vertical"
            case .stats:
                return "chart.bar"
            case .settings:
                return "gearshape"
            }
        }
    }

    @StateObject private var inputViewModel = InputViewModel()
    @StateObject private var readingHistoryStore = LocalReadingHistoryStore()
    @StateObject private var readingStatsStore = LocalReadingStatsStore()
    @StateObject private var documentOpenInViewModel = DocumentImportViewModel()
    @State private var readerViewModel: ReaderViewModel?
    @State private var selectedTab: MainTab = .home
    @AppStorage(ReaderBehaviorSettingsKey.defaultWPM) private var defaultWPM: Int = ReadingSession.defaultWPM
    private let tokenizer = TextTokenizer()

    var body: some View {
        Group {
            if let readerViewModel {
                ReaderView(viewModel: readerViewModel) {
                    readerViewModel.cleanup()
                    self.readerViewModel = nil
                }
                .environmentObject(readingStatsStore)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                TabView(selection: $selectedTab) {
                    TextInputView(
                        viewModel: inputViewModel
                    ) {
                        startReading()
                    } onStartImportedDocument: { document in
                        startReading(importedDocument: document)
                    }
                    .tabItem {
                        Label(MainTab.home.title, systemImage: MainTab.home.systemImage)
                    }
                    .tag(MainTab.home)

                    LibraryView(
                        store: readingHistoryStore,
                        onResume: { read in
                            resume(read)
                        },
                        onReadCompleted: { read in
                            readingStatsStore.markReadCompleted(readID: read.id, completedAt: read.updatedAt)
                        },
                        onStartImportedDocument: { document in
                            startReading(importedDocument: document)
                        }
                    )
                    .tabItem {
                        Label(MainTab.library.title, systemImage: MainTab.library.systemImage)
                    }
                    .tag(MainTab.library)

                    StatsView(
                        statsStore: readingStatsStore,
                        readingHistoryStore: readingHistoryStore
                    )
                    .tabItem {
                        Label(MainTab.stats.title, systemImage: MainTab.stats.systemImage)
                    }
                    .tag(MainTab.stats)

                    TypographySettingsView(
                        readingStatsStore: readingStatsStore,
                        showsDismissButton: false,
                        showsPageHeader: true
                    )
                    .tabItem {
                        Label(MainTab.settings.title, systemImage: MainTab.settings.systemImage)
                    }
                    .tag(MainTab.settings)
                }
                .tint(AppTheme.primaryText)
                .tabViewStyle(.tabBarOnly)
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: readerViewModel == nil)
        .documentImportFlow(
            viewModel: documentOpenInViewModel,
            onStartImportedDocument: { document in
                startReading(importedDocument: document)
            }
        )
        .onOpenURL { url in
            readerViewModel?.cleanup()
            readerViewModel = nil
            selectedTab = .library
            documentOpenInViewModel.importDocument(from: url)
        }
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
        attachThumbnail(for: savedRead, previewImageData: nil)
        readerViewModel = ReaderViewModel(
            session: session,
            readingHistoryStore: readingHistoryStore,
            readingStatsStore: readingStatsStore,
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
        attachThumbnail(for: savedRead, previewImageData: importedDocument.previewImageData)
        readerViewModel = ReaderViewModel(
            session: session,
            importedDocument: importedDocument,
            readingHistoryStore: readingHistoryStore,
            readingStatsStore: readingStatsStore,
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
            readingStatsStore: readingStatsStore,
            savedReadID: updatedRead.id
        )
    }

    private func attachThumbnail(for read: SavedRead, previewImageData: Data?) {
        Task {
            let updatedRead = await ThumbnailGeneratorService.shared.attachThumbnail(
                to: read,
                previewImageData: previewImageData
            )

            guard updatedRead.thumbnailPath != read.thumbnailPath else {
                return
            }

            await MainActor.run {
                if var latestRead = readingHistoryStore.read(withID: read.id) {
                    latestRead.thumbnailPath = updatedRead.thumbnailPath
                    readingHistoryStore.save(latestRead, durability: .immediate)
                }
            }
        }
    }
}
