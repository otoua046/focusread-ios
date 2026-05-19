import SwiftUI
import UIKit

struct DiscoverView: View {
    @ObservedObject var store: LocalReadingHistoryStore
    @StateObject private var viewModel: DiscoverViewModel
    let onResume: (SavedRead) -> Void
    let onAddImportedDocument: (ImportedDocument) -> SavedRead?
    let onReadImportedDocument: (ImportedDocument) -> Void

    @State private var hasScrolledUnderTop = false
    @State private var selectedBook: DiscoverBook?
    @AppStorage(FocusReadOnboardingSettingsKey.selectedReadingInterests) private var selectedInterestsRawValue = ""
    @AppStorage(FocusReadOnboardingSettingsKey.selectedReadingGoals) private var selectedGoalsRawValue = ""
    @AppStorage(FocusReadOnboardingSettingsKey.selectedReadingGoal) private var selectedGoalRawValue = FocusReadReadingGoal.research.rawValue
    @AppStorage(ReaderBehaviorSettingsKey.defaultWPM) private var defaultWPM = ReadingSession.defaultWPM
    @AppStorage(AppLanguageStorageKey.selectedLanguage) private var selectedLanguageRawValue = AppLanguage.systemDefault.rawValue
    @Environment(\.focusReadTheme) private var theme

    private let scrollCoordinateSpaceName = "discoverScroll"

    init(
        store: LocalReadingHistoryStore,
        onResume: @escaping (SavedRead) -> Void,
        onAddImportedDocument: @escaping (ImportedDocument) -> SavedRead?,
        onReadImportedDocument: @escaping (ImportedDocument) -> Void
    ) {
        self.store = store
        self.onResume = onResume
        self.onAddImportedDocument = onAddImportedDocument
        self.onReadImportedDocument = onReadImportedDocument
        _viewModel = StateObject(wrappedValue: DiscoverViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    FocusReadScrollTopTracker(coordinateSpaceName: scrollCoordinateSpaceName)

                    VStack(alignment: .leading, spacing: 20) {
                        FocusReadPageHeader(title: "Discover")
                        searchBar
                        content
                    }
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, DiscoverShelfChrome.pageHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
                }
            }
            .coordinateSpace(name: scrollCoordinateSpaceName)
            .onPreferenceChange(FocusReadScrollOffsetPreferenceKey.self) { offset in
                hasScrolledUnderTop = offset < -1
            }
            .navigationBarHidden(true)
            .background(FocusReadBackground())
            .focusReadTopSafeAreaMaterial(isElevated: hasScrolledUnderTop)
        }
        .focusReadLocalizationRefresh()
        .task {
            await viewModel.loadCuratedIfNeeded()
        }
        .task(id: viewModel.searchText) {
            await viewModel.searchAfterDelay()
        }
        .onAppear {
            viewModel.reloadPersonalization()
        }
        .onChange(of: selectedInterestsRawValue) { _, _ in viewModel.reloadPersonalization() }
        .onChange(of: selectedGoalsRawValue) { _, _ in viewModel.reloadPersonalization() }
        .onChange(of: selectedGoalRawValue) { _, _ in viewModel.reloadPersonalization() }
        .onChange(of: defaultWPM) { _, _ in viewModel.reloadPersonalization() }
        .onChange(of: selectedLanguageRawValue) { _, _ in viewModel.reloadPersonalization() }
        .onChange(of: store.savedReads) { _, _ in
            viewModel.refreshSavedLookup()
        }
        .fullScreenCover(item: $selectedBook) { book in
            BookDetailView(
                book: book,
                viewModel: viewModel,
                onAction: handleAction(_:for:),
                onOpenBook: openBook
            )
            .id(book.stableID)
        }
    }

    private var searchBar: some View {
        NativeSearchBarView(text: $viewModel.searchText, placeholder: "Search books")
            .frame(height: 40)
            .padding(.horizontal, -8)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isShowingSearchResults {
            searchResults
        } else if viewModel.sections.isEmpty && (viewModel.isLoadingSections || !viewModel.hasAttemptedCuratedLoad) {
            DiscoverShelfSkeleton(layout: .editorialHero)
        } else if viewModel.sections.isEmpty {
            calmState(
                systemImage: "book.closed",
                title: "Discover is quiet right now",
                detail: viewModel.message ?? "Try again in a moment."
            )
        } else {
            curatedSections
        }
    }

    private var curatedSections: some View {
        LazyVStack(alignment: .leading, spacing: 32) {
            ForEach(Array(viewModel.sections.enumerated()), id: \.element.id) { index, section in
                DiscoverShelfView(
                    id: section.id,
                    title: section.title,
                    books: section.books,
                    layout: section.layout,
                    treatment: section.treatment,
                    position: index,
                    onOpen: openBook,
                    onVisible: hydrateVisibleBook,
                    onPrefetch: {
                        await viewModel.loadMoreBooksIfNeeded(forSectionID: section.id)
                    }
                )
            }

            if let message = viewModel.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("Results")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.accent)
                }
            }

            if viewModel.searchResults.isEmpty && viewModel.isSearching {
                DiscoverSearchSkeletonGrid()
            } else if viewModel.searchResults.isEmpty {
                calmState(
                    systemImage: "magnifyingglass",
                    title: "No books found",
                    detail: viewModel.message ?? "Try a title, author, or subject."
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.searchResults) { book in
                        DiscoverSearchBookRow(
                            book: book,
                            onOpen: { openBook(book) }
                        )
                        .task(id: book.stableID) {
                            await hydrateVisibleBook(book)
                        }
                    }
                }
            }
        }
    }

    private func calmState(systemImage: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 54, height: 54)
                .background(theme.controlBackground, in: Circle())

            Text(title)
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            Text(detail)
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(22)
    }

    private func handleAction(_ action: DiscoverAction, for book: DiscoverBook) {
        Task {
            let outcome = await viewModel.perform(action, for: book)
            switch outcome {
            case .none:
                break
            case .openExisting(let read):
                onResume(read)
            case .imported(let document):
                switch action {
                case .add:
                    if onAddImportedDocument(document) != nil {
                        viewModel.markAdded(book)
                    } else {
                        viewModel.markImportFailed(book)
                    }
                case .read:
                    onReadImportedDocument(document)
                }
            }
        }
    }

    private func openBook(_ book: DiscoverBook) {
        selectedBook = viewModel.currentBook(matching: book) ?? book
        Task {
            await viewModel.hydrateIfNeeded(book)
            guard !Task.isCancelled,
                  selectedBook?.stableID == book.stableID,
                  let hydratedBook = viewModel.currentBook(matching: book) else {
                return
            }
            selectedBook = hydratedBook
        }
    }

    private func hydrateVisibleBook(_ book: DiscoverBook) async {
        await viewModel.hydrateIfNeeded(book)
    }

}

private struct DiscoverShelfView: View {
    let id: String
    let title: String
    let books: [DiscoverBook]
    let layout: DiscoverShelfLayout
    let treatment: DiscoverSectionTreatment?
    let position: Int
    let onOpen: (DiscoverBook) -> Void
    let onVisible: (DiscoverBook) async -> Void
    let onPrefetch: () async -> Void

    @Environment(\.focusReadTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if sectionTreatment == .framed {
                shelfBody
                    .padding(.horizontal, isRegularWidth ? 22 : 18)
                    .padding(.vertical, isRegularWidth ? 22 : 20)
                    .background {
                        softBackdrop
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(softBackdropStroke, lineWidth: 0.6)
                    }
                    .shadow(color: softBackdropShadow, radius: 14, x: 0, y: 8)
            } else {
                shelfBody
            }
        }
    }

    private var shelfBody: some View {
        VStack(alignment: .leading, spacing: layout.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(layout.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let editorialSubtitle {
                    Text(editorialSubtitle)
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            shelfContent
        }
    }

    @ViewBuilder
    private var shelfContent: some View {
        switch layout {
        case .classicRow:
            classicRow
        case .compactGrid:
            compactGrid
        case .editorialHero:
            editorialHeroShelf
        }
    }

    private var classicRow: some View {
        let metrics = DiscoverBookCardMetrics.classicRow(isRegularWidth: isRegularWidth)

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: metrics.spacing) {
                ForEach(books) { book in
                    DiscoverBookCard(
                        book: book,
                        metrics: metrics,
                        onOpen: { onOpen(book) }
                    )
                    .task(id: book.stableID) {
                        await hydrateAndPrefetchIfNeeded(appearing: book)
                    }
                }
                paginationSentinel(height: metrics.cellHeight)
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, DiscoverShelfChrome.scrollContentInset, for: .scrollContent)
        .padding(.horizontal, -DiscoverShelfChrome.pageHorizontalPadding)
    }

    private var compactGrid: some View {
        let metrics = DiscoverBookCardMetrics.compactGrid(isRegularWidth: isRegularWidth)
        let rows = [
            GridItem(.fixed(metrics.cellHeight), spacing: 14, alignment: .top),
            GridItem(.fixed(metrics.cellHeight), spacing: 14, alignment: .top)
        ]

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, alignment: .top, spacing: metrics.spacing) {
                ForEach(books) { book in
                    DiscoverBookCard(
                        book: book,
                        metrics: metrics,
                        onOpen: { onOpen(book) }
                    )
                    .task(id: book.stableID) {
                        await hydrateAndPrefetchIfNeeded(appearing: book)
                    }
                }
                paginationSentinel(height: metrics.cellHeight)
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, scrollContentInset, for: .scrollContent)
        .padding(.horizontal, scrollHorizontalPadding)
    }

    private var editorialHeroShelf: some View {
        let heroMetrics = DiscoverBookCardMetrics.editorialHero(isRegularWidth: isRegularWidth)
        let supportMetrics = DiscoverBookCardMetrics.editorialSupport(isRegularWidth: isRegularWidth)
        let groups = DiscoverEditorialComposer.groups(from: books)

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: isRegularWidth ? 26 : 20) {
                ForEach(groups) { group in
                    Group {
                        switch group.kind {
                        case .hero(let heroTrailing):
                            DiscoverEditorialHeroCluster(
                                books: group.books,
                                heroMetrics: heroMetrics,
                                supportMetrics: supportMetrics,
                                heroTrailing: heroTrailing,
                                onOpen: onOpen
                            )
                        case .quad:
                            DiscoverEditorialQuadCluster(
                                books: group.books,
                                metrics: supportMetrics,
                                onOpen: onOpen
                            )
                        }
                    }
                    .task(id: group.id) {
                        for book in group.books {
                            await onVisible(book)
                        }
                        await prefetchIfNeeded(appearing: group, in: groups)
                    }
                }
                paginationSentinel(height: max(heroMetrics.cellHeight, supportMetrics.cellHeight * 2 + 14))
            }
            .padding(.vertical, 6)
        }
        .contentMargins(.horizontal, scrollContentInset, for: .scrollContent)
        .padding(.horizontal, scrollHorizontalPadding)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private func hydrateAndPrefetchIfNeeded(appearing book: DiscoverBook) async {
        await onVisible(book)
        await prefetchIfNeeded(appearing: book)
    }

    private func prefetchIfNeeded(appearing book: DiscoverBook) async {
        guard let index = books.firstIndex(where: { $0.stableID == book.stableID }) else { return }
        let triggerIndex = max(books.count - layout.prefetchThreshold, 0)
        let isNearEnd = index >= triggerIndex
        discoverDebugLog(
            "Discover pagination visibility event=visible-item shelf=\(id) title=\(title.discoverIdentityComponent) layout=\(layout.rawValue) visibleIndex=\(index) itemCount=\(books.count) threshold=\(layout.prefetchThreshold) nearEnd=\(isNearEnd) book=\(book.stableID) reason=\(isNearEnd ? "trigger" : "not-near-end")"
        )
        if isNearEnd {
            await onPrefetch()
        }
    }

    private func prefetchIfNeeded(appearing group: DiscoverEditorialGroup, in groups: [DiscoverEditorialGroup]) async {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let triggerIndex = max(groups.count - 2, 0)
        let isNearEnd = index >= triggerIndex
        discoverDebugLog(
            "Discover pagination visibility event=visible-group shelf=\(id) title=\(title.discoverIdentityComponent) layout=\(layout.rawValue) groupIndex=\(index) groupCount=\(groups.count) threshold=2 nearEnd=\(isNearEnd) reason=\(isNearEnd ? "trigger" : "not-near-end")"
        )
        if isNearEnd {
            await onPrefetch()
        }
    }

    private func paginationSentinel(height: CGFloat) -> some View {
        Color.clear
            .frame(width: 1, height: height)
            .accessibilityHidden(true)
            .task(id: books.count) {
                discoverDebugLog(
                    "Discover pagination visibility event=end-sentinel shelf=\(id) title=\(title.discoverIdentityComponent) layout=\(layout.rawValue) itemCount=\(books.count) nearEnd=true reason=trigger"
                )
                await onPrefetch()
            }
    }

    private var usesSoftBackdrop: Bool {
        sectionTreatment == .framed
    }

    private var sectionTreatment: DiscoverSectionTreatment {
        if let treatment {
            return treatment
        }

        switch id {
        case "featured-for-you", "based-on-preferences", "fiction-literature", "ideas-productivity":
            return .framed
        case "popular-classics", "quick-under-two-hours", "public-domain-essentials":
            return .open
        default:
            break
        }

        switch layout {
        case .editorialHero:
            return .framed
        case .compactGrid:
            return position.isMultiple(of: 3) && books.count >= 8 ? .framed : .open
        case .classicRow:
            return .open
        }
    }

    private var softBackdrop: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(softBackdropBase)
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(theme.accent.opacity(softBackdropAccentOpacity))
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(theme.colorScheme == .dark ? 0.035 : 0.18),
                        Color.white.opacity(0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
    }

    private var softBackdropBase: Color {
        if theme.colorScheme == .dark {
            switch id {
            case "based-on-preferences":
                return theme.controlBackground.opacity(0.62)
            case "fiction-literature", "featured-for-you":
                return theme.cardBackground.opacity(0.58)
            default:
                return theme.secondaryBackground.opacity(0.62)
            }
        }

        switch id {
        case "based-on-preferences":
            return theme.controlBackground.opacity(0.58)
        case "fiction-literature", "featured-for-you":
            return theme.secondaryBackground.opacity(0.74)
        default:
            return theme.secondaryBackground.opacity(0.68)
        }
    }

    private var softBackdropAccentOpacity: Double {
        switch id {
        case "based-on-preferences":
            theme.colorScheme == .dark ? 0.055 : 0.025
        case "fiction-literature", "featured-for-you":
            theme.colorScheme == .dark ? 0.045 : 0.018
        default:
            theme.colorScheme == .dark ? 0.04 : 0.018
        }
    }

    private var softBackdropStroke: Color {
        if theme.colorScheme == .dark {
            return theme.border.opacity(0.12)
        }
        return theme.border.opacity(0.10)
    }

    private var softBackdropShadow: Color {
        if theme.colorScheme == .dark {
            return Color.clear
        }
        return theme.subtleShadow.opacity(0.30)
    }

    private var scrollContentInset: CGFloat {
        usesSoftBackdrop ? 0 : DiscoverShelfChrome.scrollContentInset
    }

    private var scrollHorizontalPadding: CGFloat {
        usesSoftBackdrop ? 0 : -DiscoverShelfChrome.pageHorizontalPadding
    }

    private var editorialSubtitle: String? {
        switch title {
        case "Start Reading Now":
            "A balanced table of strong covers and readable classics."
        case "Featured for You":
            "Picked from your reading goals with visual variety in mind."
        case "Based on Your Preferences":
            "Personal matches, arranged to avoid lookalike rows."
        case "Popular Classics":
            "Enduring books with stronger storefront presence."
        case "Short Reads", "Quick Reads Under 2 Hours":
            "Compact works that still look worth opening."
        case "Philosophy & Focus":
            "Reflective reads with quieter visual rhythm."
        case "Fiction & Literature":
            "Canonical fiction with a more varied shelf."
        case "Ideas & Productivity":
            "Essays and practical ideas selected for focus sessions."
        case "Public Domain Essentials":
            "Readable classics filtered for a cleaner first impression."
        default:
            nil
        }
    }
}

private struct DiscoverEditorialHeroCluster: View {
    let books: [DiscoverBook]
    let heroMetrics: DiscoverBookCardMetrics
    let supportMetrics: DiscoverBookCardMetrics
    let heroTrailing: Bool
    let onOpen: (DiscoverBook) -> Void

    private var heroBook: DiscoverBook? {
        books.first
    }

    private var supportingBooks: [DiscoverBook] {
        Array(books.dropFirst().prefix(4))
    }

    var body: some View {
        if let heroBook {
            HStack(alignment: .top, spacing: 14) {
                if !heroTrailing {
                    heroCard(heroBook)
                }

                supportGrid

                if heroTrailing {
                    heroCard(heroBook)
                }
            }
        }
    }

    private func heroCard(_ book: DiscoverBook) -> some View {
        DiscoverBookCard(
            book: book,
            metrics: heroMetrics,
            onOpen: { onOpen(book) }
        )
    }

    private var supportGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.fixed(supportMetrics.cardWidth), spacing: 10, alignment: .top),
                GridItem(.fixed(supportMetrics.cardWidth), spacing: 10, alignment: .top)
            ],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(supportingBooks) { book in
                DiscoverBookCard(
                    book: book,
                    metrics: supportMetrics,
                    onOpen: { onOpen(book) }
                )
            }
        }
        .frame(width: supportMetrics.cardWidth * 2 + 10, alignment: .topLeading)
    }
}

private struct DiscoverEditorialQuadCluster: View {
    let books: [DiscoverBook]
    let metrics: DiscoverBookCardMetrics
    let onOpen: (DiscoverBook) -> Void

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.fixed(metrics.cardWidth), spacing: 10, alignment: .top),
                GridItem(.fixed(metrics.cardWidth), spacing: 10, alignment: .top)
            ],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(books) { book in
                DiscoverBookCard(
                    book: book,
                    metrics: metrics,
                    onOpen: { onOpen(book) }
                )
            }
        }
        .frame(width: metrics.cardWidth * 2 + 10, alignment: .topLeading)
    }
}

private struct DiscoverBookCard: View {
    let book: DiscoverBook
    let metrics: DiscoverBookCardMetrics
    let onOpen: () -> Void

    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: metrics.textSpacing) {
                DiscoverCoverView(book: book, contentMode: .fit)
                    .frame(width: metrics.coverSize.width, height: metrics.coverSize.height)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if metrics.showsTitle {
                    Text(book.title)
                        .font(metrics.titleFont)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(metrics.titleLineLimit)
                        .frame(width: metrics.cardWidth, height: metrics.titleHeight, alignment: .topLeading)

                    if metrics.showsAuthor {
                        if let author = book.author, !author.isEmpty {
                            Text(author)
                                .font(metrics.authorFont)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                                .frame(width: metrics.cardWidth, height: metrics.authorHeight, alignment: .topLeading)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .frame(width: metrics.cardWidth, alignment: .topLeading)
    }

    private var accessibilityLabel: String {
        if let author = book.author, !author.isEmpty {
            return "\(book.title), \(author)"
        }
        return book.title
    }
}

private extension DiscoverShelfLayout {
    var prefetchThreshold: Int {
        switch self {
        case .classicRow:
            return 4
        case .compactGrid:
            return 8
        case .editorialHero:
            return 10
        }
    }

    var headerSpacing: CGFloat {
        switch self {
        case .editorialHero:
            14
        case .classicRow, .compactGrid:
            12
        }
    }

    var sectionTitleFont: Font {
        switch self {
        case .editorialHero:
            .system(.title2, design: .serif).weight(.semibold)
        case .classicRow, .compactGrid:
            .system(.title3, design: .serif).weight(.semibold)
        }
    }
}

private struct DiscoverEditorialGroup: Identifiable {
    enum Kind {
        case hero(heroTrailing: Bool)
        case quad
    }

    let id: String
    let books: [DiscoverBook]
    let kind: Kind
}

private enum DiscoverEditorialComposer {
    static func groups(from books: [DiscoverBook]) -> [DiscoverEditorialGroup] {
        let balancedBooks = orderedForEditorialBalance(books)
        guard !balancedBooks.isEmpty else { return [] }

        var groups: [DiscoverEditorialGroup] = []
        var cursor = 0

        while cursor < balancedBooks.count {
            let remaining = balancedBooks.count - cursor

            if remaining >= 5, remaining != 8 {
                let slice = Array(balancedBooks[cursor..<cursor + 5])
                let books = heroBalanced(slice)
                groups.append(
                    DiscoverEditorialGroup(
                        id: books.map(\.stableID).joined(separator: "-"),
                        books: books,
                        kind: .hero(heroTrailing: groups.count.isMultiple(of: 2) == false)
                    )
                )
                cursor += 5
            } else if remaining >= 4 {
                let slice = Array(balancedBooks[cursor..<cursor + 4])
                groups.append(
                    DiscoverEditorialGroup(
                        id: slice.map(\.stableID).joined(separator: "-"),
                        books: slice,
                        kind: .quad
                    )
                )
                cursor += 4
            } else {
                break
            }
        }

        if groups.isEmpty, balancedBooks.count >= 3 {
            let slice = Array(balancedBooks.prefix(3))
            let books = heroBalanced(slice)
            groups.append(
                DiscoverEditorialGroup(
                    id: books.map(\.stableID).joined(separator: "-"),
                    books: books,
                    kind: .hero(heroTrailing: false)
                )
            )
        }

        return groups
    }

    private static func orderedForEditorialBalance(_ books: [DiscoverBook]) -> [DiscoverBook] {
        var seen = Set<String>()
        var result: [DiscoverBook] = []

        for book in books where book.isReadable {
            guard !seen.contains(book.titleAuthorFingerprint) else { continue }
            seen.insert(book.titleAuthorFingerprint)
            result.append(book)
        }

        return result
    }

    private static func heroBalanced(_ books: [DiscoverBook]) -> [DiscoverBook] {
        guard let hero = books.max(by: { lhs, rhs in
            if lhs.coverQualityScore != rhs.coverQualityScore {
                return lhs.coverQualityScore < rhs.coverQualityScore
            }
            return lhs.storefrontScore < rhs.storefrontScore
        }) else {
            return books
        }

        let supportingBooks = books.filter { $0.stableID != hero.stableID }
        return [hero] + supportingBooks
    }
}

private struct DiscoverBookCardMetrics {
    let cardWidth: CGFloat
    let coverSize: CGSize
    let spacing: CGFloat
    let showsTitle: Bool
    let titleLineLimit: Int
    let titleHeight: CGFloat
    let authorHeight: CGFloat
    let showsAuthor: Bool
    let titleFont: Font
    let authorFont: Font
    let textSpacing: CGFloat

    var cellHeight: CGFloat {
        if showsTitle {
            return coverSize.height + textSpacing + titleHeight + (showsAuthor ? authorHeight : 0)
        }
        return coverSize.height
    }

    static func classicRow(isRegularWidth: Bool) -> DiscoverBookCardMetrics {
        DiscoverBookCardMetrics(
            cardWidth: isRegularWidth ? 136 : 126,
            coverSize: CGSize(width: isRegularWidth ? 136 : 126, height: isRegularWidth ? 203 : 188),
            spacing: isRegularWidth ? 18 : 16,
            showsTitle: true,
            titleLineLimit: 2,
            titleHeight: 38,
            authorHeight: 16,
            showsAuthor: true,
            titleFont: .caption.weight(.semibold),
            authorFont: .caption2,
            textSpacing: 7
        )
    }

    static func compactGrid(isRegularWidth: Bool) -> DiscoverBookCardMetrics {
        DiscoverBookCardMetrics(
            cardWidth: isRegularWidth ? 102 : 92,
            coverSize: CGSize(width: isRegularWidth ? 102 : 92, height: isRegularWidth ? 153 : 138),
            spacing: isRegularWidth ? 16 : 14,
            showsTitle: false,
            titleLineLimit: 2,
            titleHeight: 0,
            authorHeight: 0,
            showsAuthor: false,
            titleFont: .caption.weight(.semibold),
            authorFont: .caption2,
            textSpacing: 7
        )
    }

    static func editorialHero(isRegularWidth: Bool) -> DiscoverBookCardMetrics {
        DiscoverBookCardMetrics(
            cardWidth: isRegularWidth ? 174 : 138,
            coverSize: CGSize(width: isRegularWidth ? 174 : 138, height: isRegularWidth ? 260 : 206),
            spacing: isRegularWidth ? 20 : 16,
            showsTitle: false,
            titleLineLimit: 2,
            titleHeight: 0,
            authorHeight: 0,
            showsAuthor: false,
            titleFont: .subheadline.weight(.semibold),
            authorFont: .caption,
            textSpacing: 8
        )
    }

    static func editorialSupport(isRegularWidth: Bool) -> DiscoverBookCardMetrics {
        DiscoverBookCardMetrics(
            cardWidth: isRegularWidth ? 84 : 65,
            coverSize: CGSize(width: isRegularWidth ? 84 : 65, height: isRegularWidth ? 124 : 97),
            spacing: isRegularWidth ? 12 : 10,
            showsTitle: false,
            titleLineLimit: 2,
            titleHeight: 0,
            authorHeight: 0,
            showsAuthor: false,
            titleFont: .caption2.weight(.semibold),
            authorFont: .caption2,
            textSpacing: 6
        )
    }

    static let search = DiscoverBookCardMetrics(
        cardWidth: 96,
        coverSize: CGSize(width: 96, height: 144),
        spacing: 14,
        showsTitle: true,
        titleLineLimit: 2,
        titleHeight: 34,
        authorHeight: 15,
        showsAuthor: true,
        titleFont: .caption.weight(.semibold),
        authorFont: .caption2,
        textSpacing: 7
    )
}

private struct DiscoverSearchBookRow: View {
    let book: DiscoverBook
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 14) {
                DiscoverCoverView(book: book, contentMode: .fit)
                    .frame(width: 58, height: 86)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let author = book.author, !author.isEmpty {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        if let category = book.primaryCategory {
                            Text(category)
                        }

                        Text(formatOrAvailabilityLabel)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.top, 34)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(theme.cardBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme.border.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        if let author = book.author, !author.isEmpty {
            return "\(book.title), \(author)"
        }
        return book.title
    }

    private var formatOrAvailabilityLabel: String {
        switch book.availability?.preferredFormat {
        case .epub:
            return "EPUB"
        case .pdf:
            return "PDF"
        case .plainText:
            return "Plain text"
        case .none:
            return "Ready to read"
        }
    }

    @Environment(\.focusReadTheme) private var theme
}

private struct DiscoverCoverView: View {
    let book: DiscoverBook
    let contentMode: ContentMode

    @State private var coverImage: UIImage?
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.controlBackground)

            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(
            color: theme.colorScheme == .dark ? theme.deepOverlayShadow : theme.overlayShadow,
            radius: 12,
            x: 0,
            y: 7
        )
        .task(id: book.coverURL) {
            await loadCover()
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    theme.coverPlaceholderTop.opacity(0.92),
                    theme.coverPlaceholderBottom.opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "book.closed")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.coverText)

            VStack(spacing: 5) {
                Spacer()

                Text(book.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.coverText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)

                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(theme.coverText.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadCover() async {
        guard let coverURL = book.coverURL else {
            coverImage = nil
            return
        }

        if await loadImage(from: coverURL) {
            return
        }
        guard let fallbackCoverURL else {
            return
        }
        _ = await loadImage(from: fallbackCoverURL)
    }

    private func loadImage(from url: URL) async -> Bool {
        if let data = await DiscoverCoverImageCache.shared.imageData(for: url),
           let image = UIImage(data: data),
           !Task.isCancelled {
            coverImage = image
            return true
        }
        return false
    }

    private var fallbackCoverURL: URL? {
        guard book.source == .projectGutenberg,
              let coverURL = book.coverURL,
              coverURL.host?.localizedCaseInsensitiveContains("covers.openlibrary.org") == true,
              !book.sourceID.isEmpty else {
            return nil
        }
        return URL(string: "https://www.gutenberg.org/cache/epub/\(book.sourceID)/pg\(book.sourceID).cover.medium.jpg")
    }
}

private struct BookDetailView: View {
    let book: DiscoverBook
    @ObservedObject var viewModel: DiscoverViewModel
    let onAction: (DiscoverAction, DiscoverBook) -> Void
    let onOpenBook: (DiscoverBook) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.focusReadTheme) private var theme
    @State private var recommendations: [DiscoverBook] = []
    @State private var isLoadingRecommendations = true

    private let coverSize = CGSize(width: 168, height: 252)

    private var actionState: DiscoverBookActionState {
        viewModel.actionState(for: book)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DiscoverCoverView(book: book, contentMode: .fit)
                        .frame(width: coverSize.width, height: coverSize.height)
                        .shadow(
                            color: theme.colorScheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.18),
                            radius: 22,
                            x: 0,
                            y: 16
                        )
                        .accessibilityLabel(Text(coverAccessibilityLabel))
                        .padding(.top, 6)

                    heroDetailCard

                    if !infoItems.isEmpty {
                        infoStrip
                    }

                    detailSection(title: "Why It Belongs Here", text: whyItBelongsHere, serifTitle: true)

                    if isLoadingRecommendations {
                        BookDetailMoreLikeThisSkeleton()
                    } else if !recommendations.isEmpty {
                        BookDetailMoreLikeThisSection(
                            books: recommendations,
                            onOpen: onOpenBook
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(bookDetailBackground)
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) {
                floatingControls
            }
            .task(id: recommendationTaskID) {
                await loadRecommendations()
            }
        }
    }

    private var recommendationTaskID: String {
        [
            book.stableID,
            viewModel.sections.map { "\($0.id):\($0.books.count)" }.joined(separator: ","),
            viewModel.searchResults.map(\.stableID).joined(separator: ",")
        ].joined(separator: "|")
    }

    @MainActor
    private func loadRecommendations() async {
        isLoadingRecommendations = true
        await Task.yield()

        let recommendationBook = viewModel.currentBook(matching: book) ?? book
        let relatedBooks = viewModel.relatedBooks(for: recommendationBook, limit: 10)
        guard !Task.isCancelled else { return }

        discoverDebugLog(
            "Discover recommendations event=detail-loaded source=\(recommendationBook.stableID) final=\(relatedBooks.count)"
        )
        withAnimation(.easeOut(duration: 0.18)) {
            recommendations = relatedBooks
            isLoadingRecommendations = false
        }
    }

    private var floatingControls: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                floatingControlIcon("xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))

            Spacer()

            ShareLink(item: book.shareText) {
                floatingControlIcon("square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Share book"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private func floatingControlIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.primaryText)
            .frame(width: 42, height: 42)
            .background(theme.cardBackground.opacity(0.88), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(theme.border.opacity(0.18), lineWidth: 1)
            }
            .shadow(
                color: theme.colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.10),
                radius: 14,
                x: 0,
                y: 8
            )
    }

    private var heroDetailCard: some View {
        VStack(spacing: 12) {
            Text(book.title)
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            if let author = cleanAuthor {
                Text(author)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }

            Text(shortDescription)
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, cleanAuthor == nil ? 0 : 2)

            if !metadataChips.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        metadataChipRow
                    }

                    VStack(spacing: 8) {
                        metadataChipRow
                    }
                }
                .padding(.top, 2)
            }

            if book.isReadable {
                actionRow
                    .padding(.top, 6)
            } else {
                Text("This book is not available to read here right now.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(theme.cardBackground.opacity(0.54), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.border.opacity(0.12), lineWidth: 1)
        }
    }

    private var metadataChipRow: some View {
        ForEach(metadataChips) { chip in
            Text(chip.value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.cardBackground.opacity(0.62), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(theme.border.opacity(0.14), lineWidth: 1)
                }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            readButton
                .layoutPriority(1)
            addButton
        }
        .frame(maxWidth: .infinity)
    }

    private var readButton: some View {
        Button {
            guard !actionState.isWorking else { return }
            onAction(.read, book)
        } label: {
            actionLabel(
                title: actionState.isAdded ? "Resume" : "Read",
                systemImage: "book.fill",
                isWorking: actionState.isWorkingOn(.read),
                foregroundStyle: Color(uiColor: theme.palette.primaryButtonForeground)
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(Color(uiColor: theme.palette.primaryButtonBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(actionState.isWorking && !actionState.isWorkingOn(.read) ? 0.68 : 1)
        }
        .buttonStyle(.plain)
        .disabled(actionState.isWorking)
        .accessibilityLabel(Text(actionState.isAdded ? "Resume book" : "Read book"))
    }

    private var addButton: some View {
        Button {
            guard !actionState.isAdded, !actionState.isWorking else { return }
            onAction(.add, book)
        } label: {
            compactActionLabel(
                title: actionState.isAdded ? "Added" : "Add",
                systemImage: actionState.isAdded ? "checkmark" : "plus",
                isWorking: actionState.isWorkingOn(.add)
            )
            .frame(minWidth: 92)
            .frame(minHeight: 56)
            .background(theme.controlBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.border.opacity(0.18), lineWidth: 1)
            }
            .opacity(actionState.isAdded || (actionState.isWorking && !actionState.isWorkingOn(.add)) ? 0.70 : 1)
        }
        .buttonStyle(.plain)
        .disabled(actionState.isAdded || actionState.isWorking)
        .accessibilityLabel(Text(actionState.isAdded ? "Added to Library" : "Add to Library"))
    }

    private func actionLabel(
        title: String,
        systemImage: String,
        isWorking: Bool,
        foregroundStyle: Color
    ) -> some View {
        HStack(spacing: 9) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .tint(foregroundStyle)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
            }

            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(foregroundStyle)
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private func compactActionLabel(
        title: String,
        systemImage: String,
        isWorking: Bool
    ) -> some View {
        VStack(spacing: 4) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.primaryText)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .foregroundStyle(theme.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var infoStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 118), spacing: 12, alignment: .top)],
            alignment: .center,
            spacing: 12
        ) {
            ForEach(infoItems) { item in
                VStack(spacing: 4) {
                    Text(item.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)

                    Text(item.value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(theme.cardBackground.opacity(0.56), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.border.opacity(0.14), lineWidth: 1)
        }
    }

    private func detailSection(title: String, text: String, serifTitle: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(serifTitle ? .system(.headline, design: .serif).weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(theme.primaryText)

            Text(text)
                .font(.body)
                .foregroundStyle(theme.secondaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bookDetailBackground: some View {
        ZStack {
            FocusReadBackground()

            LinearGradient(
                colors: [
                    theme.accent.opacity(theme.colorScheme == .dark ? 0.14 : 0.11),
                    theme.secondaryBackground.opacity(theme.colorScheme == .dark ? 0.48 : 0.70),
                    theme.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var cleanAuthor: String? {
        guard let author = book.author?.trimmingCharacters(in: .whitespacesAndNewlines),
              !author.isEmpty else {
            return nil
        }
        return author
    }

    private var shortDescription: String {
        guard let rawDescription = book.description else {
            return fallbackDescription
        }
        let description = rawDescription
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return fallbackDescription }

        let summary = firstSentences(from: description, limit: 2)
        return capped(summary.isEmpty ? description : summary, at: 300)
    }

    private var fallbackDescription: String {
        "A public-domain classic ready for focused reading."
    }

    private var whyItBelongsHere: String {
        if let pageCount = book.pageCount, pageCount > 0, pageCount <= 180 {
            return "A compact read that fits naturally into focused sessions. It is easy to start, pause, and return to later."
        }

        return "A timeless classic that works well for focused reading sessions. Its clear structure makes it easy to start and return to later."
    }

    private var metadataChips: [BookDetailMetadataItem] {
        [
            preferredFormatLabel.map { BookDetailMetadataItem(label: "Format", value: $0) },
            BookDetailMetadataItem(label: "Status", value: "Ready to read"),
            languageDisplayName.map { BookDetailMetadataItem(label: "Language", value: $0) }
        ].compactMap(\.self)
    }

    private var infoItems: [BookDetailMetadataItem] {
        [
            preferredFormatLabel.map { BookDetailMetadataItem(label: "Format", value: $0) },
            publishedYear.map { BookDetailMetadataItem(label: "Published", value: $0) },
            languageDisplayName.map { BookDetailMetadataItem(label: "Language", value: $0) }
        ].compactMap(\.self)
    }

    private var preferredFormatLabel: String? {
        guard let preferredFormat = book.availability?.preferredFormat else { return nil }
        switch preferredFormat {
        case .epub:
            return "EPUB"
        case .pdf:
            return "PDF"
        case .plainText:
            return "Plain text"
        }
    }

    private var languageDisplayName: String? {
        guard let languageCode = book.languageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !languageCode.isEmpty else {
            return nil
        }

        let knownLanguages = [
            "en": "English",
            "eng": "English",
            "fr": "French",
            "fre": "French",
            "fra": "French",
            "de": "German",
            "ger": "German",
            "deu": "German",
            "es": "Spanish",
            "spa": "Spanish",
            "it": "Italian",
            "ita": "Italian",
            "pt": "Portuguese",
            "por": "Portuguese",
            "ja": "Japanese",
            "jpn": "Japanese",
            "ko": "Korean",
            "kor": "Korean",
            "zh": "Chinese",
            "chi": "Chinese",
            "zho": "Chinese"
        ]

        if let knownLanguage = knownLanguages[languageCode] {
            return knownLanguage
        }

        guard languageCode.count == 2,
              let localizedName = Locale.current.localizedString(forLanguageCode: languageCode)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              isCleanLanguageName(localizedName, sourceCode: languageCode) else {
            return nil
        }
        return localizedName
    }

    private func isCleanLanguageName(_ value: String, sourceCode: String) -> Bool {
        guard !value.isEmpty, value.count <= 24 else { return false }
        guard value.range(of: "[0-9_/:]", options: .regularExpression) == nil else { return false }
        guard !value.localizedCaseInsensitiveContains(sourceCode) || value.count > sourceCode.count else { return false }
        return true
    }

    private var publishedYear: String? {
        guard let year = book.firstPublishYear, year > 0 else { return nil }
        return "\(year)"
    }

    private var coverAccessibilityLabel: String {
        if let cleanAuthor {
            return "Cover of \(book.title) by \(cleanAuthor)"
        }
        return "Cover of \(book.title)"
    }

    private func firstSentences(from value: String, limit: Int) -> String {
        let sentenceTerminators = CharacterSet(charactersIn: ".!?")
        var sentences: [String] = []
        var current = ""

        for character in value {
            current.append(character)
            if String(character).rangeOfCharacter(from: sentenceTerminators) != nil {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                current = ""
                if sentences.count == limit {
                    break
                }
            }
        }

        return sentences.joined(separator: " ")
    }

    private func capped(_ value: String, at limit: Int) -> String {
        guard value.count > limit else { return value }
        let endIndex = value.index(value.startIndex, offsetBy: limit)
        let prefix = value[..<endIndex]
        if let lastSpace = prefix.lastIndex(where: { $0 == " " }) {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

private struct BookDetailMetadataItem: Identifiable {
    let label: String
    let value: String

    var id: String {
        "\(label)-\(value)"
    }
}

private struct BookDetailMoreLikeThisSection: View {
    let books: [DiscoverBook]
    let onOpen: (DiscoverBook) -> Void

    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("More Like This")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(books) { book in
                        BookDetailRecommendationCard(book: book) {
                            onOpen(book)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}

private struct BookDetailRecommendationCard: View {
    let book: DiscoverBook
    let onOpen: () -> Void

    @Environment(\.focusReadTheme) private var theme

    private let cardWidth: CGFloat = 112
    private let coverSize = CGSize(width: 112, height: 168)

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                DiscoverCoverView(book: book, contentMode: .fit)
                    .frame(width: coverSize.width, height: coverSize.height)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(book.title)
                    .font(.system(.caption, design: .serif).weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: cardWidth, height: 34, alignment: .topLeading)

                if let author = cleanAuthor {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .frame(width: cardWidth, height: 15, alignment: .topLeading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: cardWidth, alignment: .topLeading)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var cleanAuthor: String? {
        guard let author = book.author?.trimmingCharacters(in: .whitespacesAndNewlines),
              !author.isEmpty else {
            return nil
        }
        return author
    }

    private var accessibilityLabel: String {
        if let cleanAuthor {
            return "\(book.title), \(cleanAuthor)"
        }
        return book.title
    }
}

private struct BookDetailMoreLikeThisSkeleton: View {
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.controlBackground.opacity(0.78))
                .frame(width: 146, height: 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.controlBackground.opacity(0.82))
                                .frame(width: 112, height: 168)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(theme.controlBackground.opacity(0.72))
                                .frame(width: 96, height: 14)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(theme.controlBackground.opacity(0.58))
                                .frame(width: 72, height: 12)
                        }
                        .frame(width: 112, alignment: .topLeading)
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .transition(.opacity)
    }
}

private struct DiscoverShelfSkeleton: View {
    let layout: DiscoverShelfLayout
    @Environment(\.focusReadTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.controlBackground.opacity(0.8))
                .frame(width: 178, height: 24)

            switch layout {
            case .classicRow:
                skeletonRow(metrics: .classicRow(isRegularWidth: isRegularWidth), count: 5)
            case .compactGrid:
                skeletonGrid(metrics: .compactGrid(isRegularWidth: isRegularWidth))
            case .editorialHero:
                skeletonHero
            }
        }
        .redacted(reason: .placeholder)
    }

    private func skeletonRow(metrics: DiscoverBookCardMetrics, count: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: metrics.spacing) {
                ForEach(0..<count, id: \.self) { _ in
                    DiscoverSkeletonCard(metrics: metrics)
                }
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, DiscoverShelfChrome.scrollContentInset, for: .scrollContent)
        .padding(.horizontal, -DiscoverShelfChrome.pageHorizontalPadding)
    }

    private func skeletonGrid(metrics: DiscoverBookCardMetrics) -> some View {
        let rows = [
            GridItem(.fixed(metrics.cellHeight), spacing: 14, alignment: .top),
            GridItem(.fixed(metrics.cellHeight), spacing: 14, alignment: .top)
        ]

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, alignment: .top, spacing: metrics.spacing) {
                ForEach(0..<8, id: \.self) { _ in
                    DiscoverSkeletonCard(metrics: metrics)
                }
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, DiscoverShelfChrome.scrollContentInset, for: .scrollContent)
        .padding(.horizontal, -DiscoverShelfChrome.pageHorizontalPadding)
    }

    private var skeletonHero: some View {
        let heroMetrics = DiscoverBookCardMetrics.editorialHero(isRegularWidth: isRegularWidth)
        let supportMetrics = DiscoverBookCardMetrics.editorialSupport(isRegularWidth: isRegularWidth)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                DiscoverSkeletonCard(metrics: heroMetrics)

                LazyVGrid(
                    columns: [
                        GridItem(.fixed(supportMetrics.cardWidth), spacing: 10, alignment: .top),
                        GridItem(.fixed(supportMetrics.cardWidth), spacing: 10, alignment: .top)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(0..<4, id: \.self) { _ in
                        DiscoverSkeletonCard(metrics: supportMetrics)
                    }
                }
                .frame(width: supportMetrics.cardWidth * 2 + 10, alignment: .topLeading)
                .padding(.top, 2)
            }
            .padding(.vertical, 6)
        }
        .contentMargins(.horizontal, DiscoverShelfChrome.scrollContentInset, for: .scrollContent)
        .padding(.horizontal, -DiscoverShelfChrome.pageHorizontalPadding)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }
}

private enum DiscoverShelfChrome {
    static let pageHorizontalPadding: CGFloat = 22
    static let scrollContentInset: CGFloat = pageHorizontalPadding
}

private struct DiscoverSearchSkeletonGrid: View {
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96, maximum: 122), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 20
        ) {
            ForEach(0..<8, id: \.self) { _ in
                DiscoverSkeletonCard(metrics: .search)
            }
        }
        .redacted(reason: .placeholder)
    }
}

private struct DiscoverSkeletonCard: View {
    let metrics: DiscoverBookCardMetrics
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(theme.controlBackground.opacity(0.82))
            .frame(width: metrics.coverSize.width, height: metrics.coverSize.height)
            .frame(width: metrics.cardWidth, alignment: .topLeading)
    }
}
