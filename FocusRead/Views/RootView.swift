import SwiftUI

struct RootView: View {
    private enum MainTab: Hashable, CaseIterable {
        case discover
        case library
        case stats
        case settings

        var titleKey: L10n.Key {
            switch self {
            case .discover:
                return .tabDiscover
            case .library:
                return .tabLibrary
            case .stats:
                return .tabStats
            case .settings:
                return .tabSettings
            }
        }

        var systemImage: String {
            switch self {
            case .discover:
                return "sparkles"
            case .library:
                return "books.vertical"
            case .stats:
                return "chart.bar"
            case .settings:
                return "gearshape"
            }
        }
    }

    @StateObject private var readingHistoryStore = LocalReadingHistoryStore()
    @StateObject private var readingStatsStore = LocalReadingStatsStore()
    @StateObject private var recapStore = LocalAIRecapStore()
    @StateObject private var cloudSyncManager = CloudSyncManager()
    @StateObject private var documentOpenInViewModel = DocumentImportViewModel()
    @State private var readerViewModel: ReaderViewModel?
    @State private var selectedTab: MainTab = .discover
    @State private var isReplayingOnboarding = false
    @AppStorage(FocusReadOnboardingSettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage(ReaderBehaviorSettingsKey.defaultWPM) private var defaultWPM: Int = ReadingSession.defaultWPM
    @AppStorage(AIRecapSettingsKey.isEnabled) private var aiRecapsEnabledPreference: Bool = AIRecapSettings.defaultEnabled()
    @Environment(\.focusReadTheme) private var theme
    private let tokenizer = TextTokenizer()
    private let aiRecapCapabilityService = AIRecapService()

    var body: some View {
        Group {
            if let readerViewModel {
                ReaderView(viewModel: readerViewModel) {
                    readerViewModel.cleanup()
                    self.readerViewModel = nil
                } onOpenRecapRSVP: { read, recap in
                    readerViewModel.cleanup()
                    startRecapRSVP(for: read, recap: recap)
                }
                .environmentObject(readingStatsStore)
                .environmentObject(cloudSyncManager)
                .environmentObject(recapStore)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if !hasCompletedOnboarding {
                FocusReadOnboardingView(
                    mode: .firstLaunch,
                    onComplete: completeOnboarding
                )
                .environmentObject(cloudSyncManager)
                .environmentObject(recapStore)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                TabView(selection: $selectedTab) {
                    DiscoverView(
                        store: readingHistoryStore,
                        onResume: { read in
                            resume(read)
                        },
                        onAddImportedDocument: { document in
                            addImportedDocumentToLibrary(document)
                        },
                        onReadImportedDocument: { document in
                            startReading(importedDocument: document)
                        }
                    )
                    .tabItem {
                        Label(MainTab.discover.titleKey, systemImage: MainTab.discover.systemImage)
                    }
                    .tag(MainTab.discover)

                    LibraryView(
                        store: readingHistoryStore,
                        readingStatsStore: readingStatsStore,
                        recapStore: recapStore,
                        showsAIRecapEntryPoint: showsAIRecapEntryPoints,
                        onResume: { read in
                            resume(read)
                        },
                        onReadCompleted: { read in
                            readingStatsStore.markReadCompleted(readID: read.id, completedAt: read.updatedAt)
                        },
                        onStartImportedDocument: { document in
                            startReading(importedDocument: document)
                        },
                        onStartQuickRead: { text, title in
                            startQuickRead(text: text, title: title)
                        },
                        onOpenRecapRSVP: { read, recap in
                            startRecapRSVP(for: read, recap: recap)
                        }
                    )
                    .tabItem {
                        Label(MainTab.library.titleKey, systemImage: MainTab.library.systemImage)
                    }
                    .tag(MainTab.library)

                    StatsView(
                        statsStore: readingStatsStore,
                        readingHistoryStore: readingHistoryStore
                    )
                    .tabItem {
                        Label(MainTab.stats.titleKey, systemImage: MainTab.stats.systemImage)
                    }
                    .tag(MainTab.stats)

                    TypographySettingsView(
                        readingStatsStore: readingStatsStore,
                        showsDismissButton: false,
                        showsPageHeader: true,
                        onReplayOnboarding: {
                            isReplayingOnboarding = true
                        }
                    )
                    .environmentObject(cloudSyncManager)
                    .tabItem {
                        Label(MainTab.settings.titleKey, systemImage: MainTab.settings.systemImage)
                    }
                    .tag(MainTab.settings)
                }
                .tint(theme.accent)
                .tabViewStyle(.tabBarOnly)
                .background(FocusReadTabBarUpdater().frame(width: 0, height: 0))
                .transition(.opacity)
            }
        }
        .focusReadLocalizationRefresh()
        .animation(.smooth(duration: 0.35), value: readerViewModel == nil)
        .documentImportFlow(
            viewModel: documentOpenInViewModel,
            onStartImportedDocument: { document in
                startReading(importedDocument: document)
            },
            onStartQuickRead: { text, title in
                startQuickRead(text: text, title: title)
            }
        )
        .fullScreenCover(isPresented: $isReplayingOnboarding) {
            FocusReadOnboardingView(
                mode: .replay,
                onComplete: completeOnboarding
            )
            .environmentObject(readingStatsStore)
            .environmentObject(cloudSyncManager)
            .environmentObject(recapStore)
        }
        .onOpenURL { url in
            if !hasCompletedOnboarding {
                hasCompletedOnboarding = true
            }
            readerViewModel?.cleanup()
            readerViewModel = nil
            selectedTab = .library
            documentOpenInViewModel.importDocument(from: url)
        }
        .onAppear {
            cloudSyncManager.configure(
                readingHistoryStore: readingHistoryStore,
                readingStatsStore: readingStatsStore,
                recapStore: recapStore
            )
            markOnboardingCompleteForExistingLibraryIfNeeded()
        }
        .onChange(of: readingHistoryStore.savedReads) { _, _ in
            markOnboardingCompleteForExistingLibraryIfNeeded()
        }
    }

    private var showsAIRecapEntryPoints: Bool {
        _ = aiRecapsEnabledPreference
        return AIRecapSettings.shouldShowEntryPoints(
            localAIAvailable: aiRecapCapabilityService.isAvailable
        )
    }

    private func startDemoReading() {
        let sampleText = FocusReadOnboardingSample.passage
        let tokens = tokenizer.tokenize(sampleText)
        guard !tokens.isEmpty else { return }
        let document = ReadingDocument(
            title: FocusReadOnboardingSample.title,
            fileName: FocusReadOnboardingSample.title,
            sourceType: .txt,
            sections: [
                ReadingDocumentSection(
                    index: 0,
                    title: nil,
                    pageNumber: nil,
                    chapterNumber: nil,
                    wordRange: nil
                )
            ]
        )
        let session = ReadingSession(
            tokens: tokens,
            document: document,
            wordsPerMinute: defaultWPM
        )
        let savedRead = SavedReadMapper.makeDemoSavedRead(
            from: sampleText,
            tokens: tokens,
            title: FocusReadOnboardingSample.title,
            existingReads: readingHistoryStore.savedReads
        )
        readingHistoryStore.save(savedRead)

        readerViewModel = ReaderViewModel(
            session: session,
            readingHistoryStore: readingHistoryStore,
            readingStatsStore: readingStatsStore,
            savedReadID: savedRead.id
        )
    }

    private func completeOnboarding(_ action: FocusReadOnboardingCompletionAction) {
        let wasReplaying = isReplayingOnboarding
        if !hasCompletedOnboarding {
            hasCompletedOnboarding = true
        }
        isReplayingOnboarding = false

        switch action {
        case .showLibrary:
            if !wasReplaying {
                selectedTab = .library
            }
        case .importBook:
            selectedTab = .library
            Task { @MainActor in
                documentOpenInViewModel.presentFilePicker()
            }
        case .trySampleText:
            selectedTab = .library
            startDemoReading()
        }
    }

    private func markOnboardingCompleteForExistingLibraryIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        guard !readingHistoryStore.savedReads.isEmpty || FocusReadOnboardingMigration.hasExistingInstallSignal(
            hasPersistedReadingHistory: readingHistoryStore.hasPersistedReadingHistory
        ) else { return }
        hasCompletedOnboarding = true
    }

    private func startReading(importedDocument: ImportedDocument) {
        if let existingRead = existingDiscoverRead(for: importedDocument) {
            resume(existingRead)
            return
        }

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

    private func startQuickRead(text: String, title: String?) {
        let normalizedText = text.focusReadNormalizedDocumentText
        let tokens = tokenizer.tokenize(normalizedText)
        guard !tokens.isEmpty else { return }

        let savedRead = SavedReadMapper.makeSavedRead(
            from: normalizedText,
            tokens: tokens,
            providedTitle: title
        )
        readingHistoryStore.save(savedRead)

        let session = ReadingSession(
            tokens: tokens,
            document: SavedReadMapper.readingDocument(from: savedRead),
            wordsPerMinute: defaultWPM
        )
        readerViewModel = ReaderViewModel(
            session: session,
            readingHistoryStore: readingHistoryStore,
            readingStatsStore: readingStatsStore,
            savedReadID: savedRead.id
        )
    }

    @discardableResult
    private func addImportedDocumentToLibrary(_ importedDocument: ImportedDocument) -> SavedRead? {
        if let existingRead = existingDiscoverRead(for: importedDocument) {
            updateExistingRead(existingRead, with: importedDocument)
            return existingRead
        }

        let tokens = tokenizer.tokenize(importedDocument)
        guard !tokens.isEmpty else { return nil }

        let savedRead = SavedReadMapper.makeSavedRead(from: importedDocument, tokens: tokens)
        readingHistoryStore.save(savedRead)
        attachThumbnail(for: savedRead, previewImageData: importedDocument.previewImageData)
        return savedRead
    }

    private func existingDiscoverRead(for importedDocument: ImportedDocument) -> SavedRead? {
        DiscoverImportDeduper.existingRead(
            for: importedDocument,
            in: readingHistoryStore.savedReads
        )
    }

    private func updateExistingRead(_ existingRead: SavedRead, with importedDocument: ImportedDocument) {
        var updatedRead = existingRead
        var didUpdate = false

        if updatedRead.externalSourceID == nil, let externalSourceID = importedDocument.externalSourceID {
            updatedRead.externalSourceID = externalSourceID
            didUpdate = true
        }

        let cleanTitle = importedDocument.displayTitle.discoverCleanBookTitle
        if !cleanTitle.isEmpty,
           (updatedRead.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || updatedRead.displayTitle.discoverIdentityComponent == (updatedRead.originalFileName ?? "").discoverIdentityComponent
                || (
                    updatedRead.displayTitle.discoverCanonicalTitleComponent == cleanTitle.discoverCanonicalTitleComponent
                    && cleanTitle.count < updatedRead.displayTitle.count
                )) {
            updatedRead.displayTitle = cleanTitle
            didUpdate = true
        }

        if let cleanAuthor = importedDocument.author?.discoverCleanAuthorName.nilIfBlank,
           updatedRead.author?.discoverCleanAuthorName.nilIfBlank == nil {
            updatedRead.author = cleanAuthor
            updatedRead.authorName = cleanAuthor
            didUpdate = true
        }

        if didUpdate {
            updatedRead.updatedAt = Date()
            readingHistoryStore.save(updatedRead, durability: .immediate)
        }

        if importedDocument.previewImageData != nil {
            attachThumbnail(for: updatedRead, previewImageData: importedDocument.previewImageData, forceSave: true)
        }
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

    private func startRecapRSVP(for read: SavedRead, recap: AIRecap) {
        guard showsAIRecapEntryPoints else { return }

        let tokens = tokenizer.tokenize(recap.generatedText)
        guard !tokens.isEmpty else { return }

        let document = ReadingDocument(
            id: recap.id,
            title: L10n.string(.aiRecapTitle),
            fileName: read.displayTitle,
            sourceType: .pastedText,
            sections: [
                ReadingDocumentSection(
                    index: 0,
                    title: L10n.string(.aiRecapTitle),
                    pageNumber: nil,
                    chapterNumber: nil,
                    wordRange: nil
                )
            ]
        )
        let session = ReadingSession(
            tokens: tokens,
            document: document,
            wordsPerMinute: defaultWPM
        )
        readerViewModel = ReaderViewModel(
            session: session,
            displayContext: .aiRecap(bookTitle: read.displayTitle)
        )
    }

    private func attachThumbnail(for read: SavedRead, previewImageData: Data?, forceSave: Bool = false) {
        Task {
            let updatedRead = await ThumbnailGeneratorService.shared.attachThumbnail(
                to: read,
                previewImageData: previewImageData
            )
            let thumbnailDidChange = updatedRead.thumbnailPath != read.thumbnailPath

            guard thumbnailDidChange else {
                return
            }

            await MainActor.run {
                if var latestRead = readingHistoryStore.read(withID: read.id) {
                    latestRead.thumbnailPath = updatedRead.thumbnailPath
                    if forceSave {
                        latestRead.updatedAt = Date()
                    }
                    readingHistoryStore.save(latestRead, durability: .immediate)
                }
            }
        }
    }
}

enum DiscoverImportDeduper {
    static func existingRead(for importedDocument: ImportedDocument, in reads: [SavedRead]) -> SavedRead? {
        reads.first { read in
            if let externalSourceID = importedDocument.externalSourceID,
               read.externalSourceID == externalSourceID {
                return true
            }
            if read.originalFileName == importedDocument.fileName {
                return discoverTitleMatches(read, importedDocument: importedDocument)
                    && discoverAuthorsAreCompatible(read, importedDocument: importedDocument)
            }
            guard importedDocument.externalSourceID != nil else { return false }
            return discoverTitleMatches(read, importedDocument: importedDocument)
                && discoverAuthorMatches(read, importedDocument: importedDocument)
        }
    }

    private static func discoverTitleMatches(_ read: SavedRead, importedDocument: ImportedDocument) -> Bool {
        let readTitle = read.displayTitle.discoverIdentityComponent
        let importedTitle = importedDocument.displayTitle.discoverIdentityComponent
        return !readTitle.isEmpty && readTitle == importedTitle
    }

    private static func discoverAuthorMatches(_ read: SavedRead, importedDocument: ImportedDocument) -> Bool {
        let readAuthor = (read.author ?? read.authorName ?? "").discoverIdentityComponent
        let importedAuthor = (importedDocument.author ?? "").discoverIdentityComponent
        return !readAuthor.isEmpty && readAuthor == importedAuthor
    }

    private static func discoverAuthorsAreCompatible(_ read: SavedRead, importedDocument: ImportedDocument) -> Bool {
        let readAuthor = (read.author ?? read.authorName ?? "").discoverIdentityComponent
        let importedAuthor = (importedDocument.author ?? "").discoverIdentityComponent
        return readAuthor.isEmpty || importedAuthor.isEmpty || readAuthor == importedAuthor
    }
}
