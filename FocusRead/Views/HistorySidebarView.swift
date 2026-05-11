import SwiftUI
import UIKit

struct LibraryView: View {
    @ObservedObject var store: LocalReadingHistoryStore
    @ObservedObject var readingStatsStore: LocalReadingStatsStore
    @ObservedObject var recapStore: LocalAIRecapStore
    let showsAIRecapEntryPoint: Bool
    @StateObject private var viewModel: LibraryViewModel
    @StateObject private var documentImportViewModel = DocumentImportViewModel()
    let onResume: (SavedRead) -> Void
    let onReadCompleted: (SavedRead) -> Void
    let onStartImportedDocument: (ImportedDocument) -> Void
    let onOpenRecapRSVP: (SavedRead, AIRecap) -> Void
    @State private var renameTarget: SavedRead?
    @State private var deleteTarget: SavedRead?
    @State private var aiRecapTarget: SavedRead?
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeleteSelectedConfirmationPresented = false

    @AppStorage("library_view_mode") private var viewMode: LibraryViewMode = .grid
    @AppStorage("library_sort_mode") private var sortMode: LibrarySortMode = .recent
    @State private var isSelectMode = false
    @State private var selection = Set<UUID>()
    @State private var hasScrolledUnderTop = false
    @Environment(\.focusReadTheme) private var theme

    private let scrollCoordinateSpaceName = "libraryScroll"

    init(
        store: LocalReadingHistoryStore,
        readingStatsStore: LocalReadingStatsStore,
        recapStore: LocalAIRecapStore,
        showsAIRecapEntryPoint: Bool,
        onResume: @escaping (SavedRead) -> Void,
        onReadCompleted: @escaping (SavedRead) -> Void = { _ in },
        onStartImportedDocument: @escaping (ImportedDocument) -> Void,
        onOpenRecapRSVP: @escaping (SavedRead, AIRecap) -> Void
    ) {
        self.store = store
        self.readingStatsStore = readingStatsStore
        self.recapStore = recapStore
        self.showsAIRecapEntryPoint = showsAIRecapEntryPoint
        self.onResume = onResume
        self.onReadCompleted = onReadCompleted
        self.onStartImportedDocument = onStartImportedDocument
        self.onOpenRecapRSVP = onOpenRecapRSVP
        _viewModel = StateObject(wrappedValue: LibraryViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    FocusReadScrollTopTracker(coordinateSpaceName: scrollCoordinateSpaceName)

                    mainContent
                }
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
            }
            .coordinateSpace(name: scrollCoordinateSpaceName)
            .onPreferenceChange(FocusReadScrollOffsetPreferenceKey.self) { offset in
                hasScrolledUnderTop = offset < -1
            }
            .navigationBarHidden(true)
            .background(FocusReadBackground())
            .focusReadTopSafeAreaMaterial(isElevated: hasScrolledUnderTop)
            .documentImportFlow(
                viewModel: documentImportViewModel,
                onStartImportedDocument: onStartImportedDocument
            )
            .task(id: store.savedReads.map(\.id)) {
                await reconcileThumbnails()
            }
            .onAppear {
                viewModel.sortMode = sortMode
            }
            .onChange(of: viewModel.sortMode) {
                sortMode = viewModel.sortMode
            }
            .onChange(of: viewModel.searchText) {
                selection.removeAll()
            }
            .sheet(item: $renameTarget) { read in
                RenameReadSheet(
                    initialTitle: read.displayTitle,
                    onCancel: {
                        renameTarget = nil
                    },
                    onSave: { title in
                        rename(read, to: title)
                        renameTarget = nil
                    }
                )
                .presentationDetents([.height(210)])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $aiRecapTarget) { read in
                AIRecapView(
                    read: read,
                    readingStatsStore: readingStatsStore,
                    recapStore: recapStore,
                    onOpenRSVP: { recap in
                        aiRecapTarget = nil
                        onOpenRecapRSVP(read, recap)
                    }
                )
            }
            .confirmationDialog(
                L10n.string(.libraryDeleteReadTitle),
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible,
                presenting: deleteTarget
            ) { read in
                Button(.commonDelete, role: .destructive) {
                    delete(read)
                }

                Button(.commonCancel, role: .cancel) {}
            } message: { _ in
                Text(.libraryDeleteReadMessage)
            }
            .alert(
                selection.count == store.savedReads.count ? L10n.string(.libraryDeleteAllTitle) : L10n.string(.libraryDeleteSelectedTitle),
                isPresented: $isDeleteSelectedConfirmationPresented
            ) {
                Button(.commonCancel, role: .cancel) {}
                Button(.commonDelete, role: .destructive) {
                    let selectedIds = selection
                    deleteTarget = nil
                    selection.removeAll()
                    isSelectMode = false
                    
                    for id in selectedIds {
                        if let read = store.savedReads.first(where: { $0.id == id }) {
                            delete(read)
                        }
                    }
                }
            } message: {
                Text(.libraryDeleteSelectedMessage)
            }
        }
        .focusReadLocalizationRefresh()
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerRow

            if !viewModel.isLibraryEmpty || !viewModel.searchText.isEmpty {
                searchBar
            }

            if viewModel.isLibraryEmpty {
                emptyState
            } else if viewModel.reads.isEmpty && !viewModel.searchText.isEmpty {
                noSearchResultsState
            } else {
                if isSelectMode {
                    selectionToolbar
                }

                if viewMode == .grid {
                    LibraryGridView(
                        reads: viewModel.reads,
                        isSelectMode: isSelectMode,
                        selection: $selection,
                        onResume: onResume,
                        onMarkFinished: markFinished(_:),
                        onRename: { read in
                            renameTarget = read
                        },
                        showsAIRecapEntryPoint: showsAIRecapEntryPoint,
                        onAIRecap: { read in
                            aiRecapTarget = read
                        },
                        onDelete: { read in
                            deleteTarget = read
                            isDeleteConfirmationPresented = true
                        }
                    )
                } else {
                    LibraryListView(
                        reads: viewModel.reads,
                        isSelectMode: isSelectMode,
                        selection: $selection,
                        onResume: onResume,
                        onMarkFinished: markFinished(_:),
                        onRename: { read in
                            renameTarget = read
                        },
                        showsAIRecapEntryPoint: showsAIRecapEntryPoint,
                        onAIRecap: { read in
                            aiRecapTarget = read
                        },
                        onDelete: { read in
                            deleteTarget = read
                            isDeleteConfirmationPresented = true
                        }
                    )
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            FocusReadPageHeader(titleKey: .libraryTitle)
            Spacer()
            if isSelectMode {
                Button(.commonDone) {
                    isSelectMode = false
                    selection.removeAll()
                }
                .font(.headline)
                .foregroundStyle(theme.primaryText)
                .padding(.top, 4)
            } else {
                HStack(spacing: 8) {
                    ImportSourceMenu(
                        viewModel: documentImportViewModel,
                        onSourceSelected: {}
                    ) {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                            .frame(width: 44, height: 44)
                            .background(theme.controlBackground.opacity(0.8), in: Circle())
                    }
                    .accessibilityLabel(L10n.string(.libraryImportAccessibility))

                    LibraryControlsMenu(
                        viewMode: $viewMode,
                        sortMode: $viewModel.sortMode,
                        onSelectMode: {
                            isSelectMode = true
                        }
                    )
                }
                .padding(.top, 4)
            }
        }
    }

    private var searchBar: some View {
        NativeSearchBarView(text: $viewModel.searchText, placeholder: L10n.string(.librarySearchPlaceholder))
            .frame(height: 40)
            .padding(.horizontal, -8)
    }

    private var selectionToolbar: some View {
        HStack {
            let allSelected = selection.count == viewModel.reads.count && !viewModel.reads.isEmpty
            Button(allSelected ? L10n.string(.libraryDeselectAll) : L10n.string(.librarySelectAll)) {
                if allSelected {
                    selection.removeAll()
                } else {
                    selection = Set(viewModel.reads.map(\.id))
                }
            }
            .font(.subheadline.weight(.semibold))

            Spacer()

            Text(L10n.format(.librarySelectedCountFormat, selection.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
            
            Spacer()
            
            Button(role: .destructive) {
                isDeleteSelectedConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
                    .font(.headline)
                    .foregroundStyle(selection.isEmpty ? theme.secondaryText.opacity(0.5) : theme.destructive)
            }
            .disabled(selection.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 56, height: 56)
                .background(theme.controlBackground, in: Circle())

            Text(.libraryEmpty)
                .font(.headline)
                .foregroundStyle(theme.primaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(.vertical, 28)
    }

    private var noSearchResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 54, height: 54)
                .background(theme.controlBackground, in: Circle())

            Text(.libraryNoResults)
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            Text(.libraryNoResultsSuggestion)
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(24)
    }

    private func markFinished(_ read: SavedRead) {
        var updated = read
        updated.currentWordIndex = max(updated.totalWordCount - 1, 0)
        updated.progressPercent = 100
        updated.updatedAt = Date()
        updated.lastOpenedAt = Date()
        store.save(updated)
        onReadCompleted(updated)
    }

    private func rename(_ read: SavedRead, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = read
        updated.displayTitle = trimmed
        updated.updatedAt = Date()
        store.save(updated)
    }

    private func delete(_ read: SavedRead) {
        recapStore.deleteRecaps(for: read.id)
        store.delete(read)
    }

    private func reconcileThumbnails() async {
        for read in store.savedReads where read.thumbnailPath == nil {
            let updatedRead = await ThumbnailGeneratorService.shared.attachThumbnail(
                to: read,
                previewImageData: nil
            )
            guard updatedRead.thumbnailPath != read.thumbnailPath else { continue }
            await MainActor.run {
                if var latestRead = store.read(withID: read.id) {
                    latestRead.thumbnailPath = updatedRead.thumbnailPath
                    store.save(latestRead)
                }
            }
        }
    }
}

private enum LibraryCoverLayout {
    static let gridMinimumWidth: CGFloat = 156
    static let gridMaximumWidth: CGFloat = 220
    static let gridAspectRatio: CGFloat = 0.72
    static let listWidth: CGFloat = 50
    static let listHeight: CGFloat = 70
}

struct LibraryGridView: View {
    let reads: [SavedRead]
    let isSelectMode: Bool
    @Binding var selection: Set<UUID>
    let onResume: (SavedRead) -> Void
    let onMarkFinished: (SavedRead) -> Void
    let onRename: (SavedRead) -> Void
    let showsAIRecapEntryPoint: Bool
    let onAIRecap: (SavedRead) -> Void
    let onDelete: (SavedRead) -> Void

    private let columns = [
        GridItem(
            .adaptive(
                minimum: LibraryCoverLayout.gridMinimumWidth,
                maximum: LibraryCoverLayout.gridMaximumWidth
            ),
            spacing: 18,
            alignment: .top
        )
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(reads) { read in
                LibraryBookCard(
                    read: read,
                    isSelectMode: isSelectMode,
                    isSelected: selection.contains(read.id),
                    onToggleSelect: {
                        if selection.contains(read.id) {
                            selection.remove(read.id)
                        } else {
                            selection.insert(read.id)
                        }
                    },
                    onResume: { onResume(read) },
                    onMarkFinished: { onMarkFinished(read) },
                    onRename: { onRename(read) },
                    showsAIRecapEntryPoint: showsAIRecapEntryPoint,
                    onAIRecap: { onAIRecap(read) },
                    onDelete: { onDelete(read) }
                )
            }
        }
    }
}

struct LibraryBookCard: View {
    let read: SavedRead
    let isSelectMode: Bool
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onResume: () -> Void
    let onMarkFinished: () -> Void
    let onRename: () -> Void
    let showsAIRecapEntryPoint: Bool
    let onAIRecap: () -> Void
    let onDelete: () -> Void

    @Environment(\.focusReadTheme) private var theme
    @State private var thumbnailData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                if isSelectMode {
                    onToggleSelect()
                } else {
                    onResume()
                }
            }) {
                coverView
            }
            .buttonStyle(.plain)

            Text(read.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(read.progressPercent.rounded()))%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.secondaryText)

                Spacer(minLength: 8)

                LibraryItemMenu(
                    showsAIRecapEntryPoint: showsAIRecapEntryPoint,
                    onAIRecap: onAIRecap,
                    onMarkFinished: onMarkFinished,
                    onRename: onRename,
                    onDelete: onDelete
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: read.thumbnailPath ?? read.id.uuidString) {
            await loadThumbnail()
        }
    }

    private var coverView: some View {
        LibraryCoverThumbnail(
            read: read,
            thumbnailData: thumbnailData,
            imageCornerRadius: 6,
            placeholderCornerRadius: 14,
            placeholderIconSize: 26,
            showsPlaceholderLabel: true
        )
        .aspectRatio(LibraryCoverLayout.gridAspectRatio, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            if isSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? theme.coverSelectionForeground : theme.coverUnselectedForeground)
                    .background(Circle().fill(isSelected ? theme.coverSelectionBackground : theme.coverUnselectedBackground))
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    private func loadThumbnail() async {
        thumbnailData = await ThumbnailGeneratorService.shared.thumbnailData(for: read)
    }
}

private struct LibraryCoverThumbnail: View {
    let read: SavedRead
    let thumbnailData: Data?
    let imageCornerRadius: CGFloat
    let placeholderCornerRadius: CGFloat
    let placeholderIconSize: CGFloat
    let showsPlaceholderLabel: Bool

    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        ZStack {
            Color.clear

            if let thumbnailData, let thumbnailImage = UIImage(data: thumbnailData) {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .shadow(
                        color: theme.colorScheme == .dark ? theme.deepOverlayShadow : theme.overlayShadow,
                        radius: 12,
                        x: 0,
                        y: 6
                    )
            } else {
                placeholderView
                    .clipShape(RoundedRectangle(cornerRadius: placeholderCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: placeholderCornerRadius, style: .continuous)
                            .strokeBorder(theme.border.opacity(0.24), lineWidth: 1)
                    }
                    .shadow(
                        color: theme.colorScheme == .dark ? theme.deepOverlayShadow : theme.overlayShadow,
                        radius: 12,
                        x: 0,
                        y: 6
                    )
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: showsPlaceholderLabel ? 12 : 0) {
            Image(systemName: read.sourceType.systemImageName)
                .font(.system(size: placeholderIconSize, weight: .semibold))
                .foregroundStyle(theme.coverText)

            if showsPlaceholderLabel {
                Text(read.sourceType.libraryLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.coverSecondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    theme.coverPlaceholderTop,
                    theme.coverPlaceholderBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct LibraryItemMenu: View {
    let showsAIRecapEntryPoint: Bool
    let onAIRecap: () -> Void
    let onMarkFinished: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        Menu {
            if showsAIRecapEntryPoint {
                Button {
                    onAIRecap()
                } label: {
                    Label(.libraryAIRecap, systemImage: "sparkles")
                }
            }

            Button {
                onMarkFinished()
            } label: {
                Label(.libraryMarkFinished, systemImage: "checkmark.circle")
            }

            Button {
                onRename()
            } label: {
                Label(.libraryRename, systemImage: "textformat")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(.commonDelete, systemImage: "trash")
                    .foregroundStyle(theme.destructive)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 30, height: 30)
                .background(theme.controlBackground.opacity(0.75), in: Circle())
        }
        .menuStyle(.borderlessButton)
    }
}

struct RenameReadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.focusReadTheme) private var theme
    @State private var title: String

    let initialTitle: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    init(
        initialTitle: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.initialTitle = initialTitle
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string(.libraryReadTitlePlaceholder), text: $title)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(theme.primaryText)
                } header: {
                    Text(.libraryRenameTitleSection)
                }
                .listRowBackground(theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(FocusReadBackground())
            .navigationTitle(L10n.key(.libraryRename))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.commonCancel) {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(.commonSave) {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationCornerRadius(22)
    }
}

struct LibraryListView: View {
    let reads: [SavedRead]
    let isSelectMode: Bool
    @Binding var selection: Set<UUID>
    let onResume: (SavedRead) -> Void
    let onMarkFinished: (SavedRead) -> Void
    let onRename: (SavedRead) -> Void
    let showsAIRecapEntryPoint: Bool
    let onAIRecap: (SavedRead) -> Void
    let onDelete: (SavedRead) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(reads.enumerated()), id: \.element.id) { index, read in
                LibraryListRow(
                    read: read,
                    isSelectMode: isSelectMode,
                    isSelected: selection.contains(read.id),
                    onToggleSelect: {
                        if selection.contains(read.id) {
                            selection.remove(read.id)
                        } else {
                            selection.insert(read.id)
                        }
                    },
                    onResume: { onResume(read) },
                    onMarkFinished: { onMarkFinished(read) },
                    onRename: { onRename(read) },
                    showsAIRecapEntryPoint: showsAIRecapEntryPoint,
                    onAIRecap: { onAIRecap(read) },
                    onDelete: { onDelete(read) }
                )

                if index < reads.count - 1 {
                    Divider()
                        .padding(.leading, isSelectMode ? 96 : 64)
                        .opacity(0.6)
                }
            }
        }
    }
}

struct LibraryListRow: View {
    let read: SavedRead
    let isSelectMode: Bool
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onResume: () -> Void
    let onMarkFinished: () -> Void
    let onRename: () -> Void
    let showsAIRecapEntryPoint: Bool
    let onAIRecap: () -> Void
    let onDelete: () -> Void

    @Environment(\.focusReadTheme) private var theme
    @State private var thumbnailData: Data?

    var body: some View {
        Button(action: {
            if isSelectMode {
                onToggleSelect()
            } else {
                onResume()
            }
        }) {
            HStack(spacing: 14) {
                if isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
                }

                coverView
                    .frame(width: LibraryCoverLayout.listWidth, height: LibraryCoverLayout.listHeight)

                VStack(alignment: .leading, spacing: 2) {
                    Text(read.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)

                    if let author = read.author, !author.isEmpty {
                        Text(author)
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: read.sourceType.systemImageName)
                        Text("\(Int(read.progressPercent.rounded()))%")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isSelectMode {
                    LibraryItemMenu(
                        showsAIRecapEntryPoint: showsAIRecapEntryPoint,
                        onAIRecap: onAIRecap,
                        onMarkFinished: onMarkFinished,
                        onRename: onRename,
                        onDelete: onDelete
                    )
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: read.thumbnailPath ?? read.id.uuidString) {
            thumbnailData = await ThumbnailGeneratorService.shared.thumbnailData(for: read)
        }
    }

    private var coverView: some View {
        LibraryCoverThumbnail(
            read: read,
            thumbnailData: thumbnailData,
            imageCornerRadius: 3,
            placeholderCornerRadius: 8,
            placeholderIconSize: 16,
            showsPlaceholderLabel: false
        )
        .contentShape(Rectangle())
    }
}

struct LibraryControlsMenu: View {
    @Binding var viewMode: LibraryViewMode
    @Binding var sortMode: LibrarySortMode
    let onSelectMode: () -> Void
    @Environment(\.focusReadTheme) private var theme

    var body: some View {
        Menu {
            Section {
                Button(action: onSelectMode) {
                    Label(.librarySelect, systemImage: "checkmark.circle")
                }
            }

            Section {
                Picker(L10n.key(.libraryViewAs), selection: $viewMode) {
                    Label(.libraryGrid, systemImage: "square.grid.2x2").tag(LibraryViewMode.grid)
                    Label(.libraryList, systemImage: "list.bullet").tag(LibraryViewMode.list)
                }
                .pickerStyle(.inline)
            } header: {
                Text(.libraryViewAs)
            }

            Section {
                Picker(L10n.key(.librarySortBy), selection: $sortMode) {
                    Label(.librarySortRecent, systemImage: "clock").tag(LibrarySortMode.recent)
                    Label(.librarySortTitle, systemImage: "textformat").tag(LibrarySortMode.title)
                    Label(.librarySortAuthor, systemImage: "person").tag(LibrarySortMode.author)
                    Label(.librarySortManual, systemImage: "line.3.horizontal").tag(LibrarySortMode.manual)
                }
                .pickerStyle(.inline)
            } header: {
                Text(.librarySortBy)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundStyle(theme.primaryText)
                .frame(width: 44, height: 44)
                .background(theme.controlBackground.opacity(0.8), in: Circle())
        }
        .menuStyle(.borderlessButton)
    }
}

private extension SavedReadSourceType {
    var systemImageName: String {
        switch self {
        case .pastedText:
            "doc.on.clipboard"
        case .txt:
            "doc.plaintext"
        case .pdf:
            "doc.richtext"
        case .epub:
            "book"
        case .image:
            "text.viewfinder"
        }
    }

    var libraryLabel: String {
        switch self {
        case .pastedText:
            L10n.string(.librarySourcePasted)
        case .txt:
            L10n.string(.librarySourceText)
        case .pdf:
            "PDF"
        case .epub:
            "EPUB"
        case .image:
            L10n.string(.librarySourceImage)
        }
    }
}
