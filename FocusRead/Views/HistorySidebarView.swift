import SwiftUI
import UIKit

struct LibraryView: View {
    @ObservedObject var store: LocalReadingHistoryStore
    @StateObject private var viewModel: LibraryViewModel
    let onResume: (SavedRead) -> Void
    
    @State private var renameTarget: SavedRead?
    @State private var deleteTarget: SavedRead?
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeleteSelectedConfirmationPresented = false

    @AppStorage("library_view_mode") private var viewMode: LibraryViewMode = .grid
    @AppStorage("library_sort_mode") private var sortMode: LibrarySortMode = .recent
    @State private var isSelectMode = false
    @State private var selection = Set<UUID>()
    @Environment(\.colorScheme) private var colorScheme

    init(store: LocalReadingHistoryStore, onResume: @escaping (SavedRead) -> Void) {
        self.store = store
        self.onResume = onResume
        _viewModel = StateObject(wrappedValue: LibraryViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                mainContent
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
            }
            .navigationBarHidden(true)
            .background(FocusReadBackground())
            .task(id: store.savedReads.map(\.id)) {
                await reconcileThumbnails()
            }
            .onAppear {
                viewModel.sortMode = sortMode
            }
            .onChange(of: viewModel.sortMode) {
                sortMode = viewModel.sortMode
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
            .confirmationDialog(
                "Delete this read?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible,
                presenting: deleteTarget
            ) { read in
                Button("Delete", role: .destructive) {
                    delete(read)
                }

                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes the read and its local thumbnail.")
            }
            .alert(
                selection.count == store.savedReads.count ? "Delete all reads from Library?" : "Delete selected reads?",
                isPresented: $isDeleteSelectedConfirmationPresented
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
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
                Text("This removes saved reads and local files from this device. This cannot be undone.")
            }
        }
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
            FocusReadPageHeader(title: "Library")
            Spacer()
            if isSelectMode {
                Button("Done") {
                    isSelectMode = false
                    selection.removeAll()
                }
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
                .padding(.top, 4)
            } else {
                LibraryControlsMenu(
                    viewMode: $viewMode,
                    sortMode: $viewModel.sortMode,
                    onSelectMode: {
                        isSelectMode = true
                    }
                )
                .padding(.top, 4)
            }
        }
    }

    private var searchBar: some View {
        NativeSearchBarView(text: $viewModel.searchText, placeholder: "Search books or authors")
            .frame(height: 40)
            .padding(.horizontal, -8)
    }

    private var selectionToolbar: some View {
        HStack {
            let allSelected = selection.count == viewModel.reads.count && !viewModel.reads.isEmpty
            Button(allSelected ? "Deselect All" : "Select All") {
                if allSelected {
                    selection.removeAll()
                } else {
                    selection = Set(viewModel.reads.map(\.id))
                }
            }
            .font(.subheadline.weight(.semibold))

            Spacer()

            Text("\(selection.count) Selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            
            Spacer()
            
            Button(role: .destructive) {
                isDeleteSelectedConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
                    .font(.headline)
                    .foregroundStyle(selection.isEmpty ? AppTheme.secondaryText.opacity(0.5) : .red)
            }
            .disabled(selection.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 56, height: 56)
                .background(AppTheme.controlBackground, in: Circle())

            Text("No reads yet.")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(.vertical, 28)
    }

    private var noSearchResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 54, height: 54)
                .background(AppTheme.controlBackground, in: Circle())

            Text("No results")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Text("Try a different title or author")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
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

struct LibraryGridView: View {
    let reads: [SavedRead]
    let isSelectMode: Bool
    @Binding var selection: Set<UUID>
    let onResume: (SavedRead) -> Void
    let onMarkFinished: (SavedRead) -> Void
    let onRename: (SavedRead) -> Void
    let onDelete: (SavedRead) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 220), spacing: 18, alignment: .top)
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
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
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
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(read.progressPercent.rounded()))%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer(minLength: 8)

                LibraryItemMenu(
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
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.controlBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.24), lineWidth: 1)
                }

            if let thumbnailData, let thumbnailImage = UIImage(data: thumbnailData) {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderView
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if isSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.blue : Color.white)
                    .background(Circle().fill(isSelected ? Color.white : Color.black.opacity(0.4)))
                    .padding(8)
            }
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14),
            radius: 12,
            x: 0,
            y: 6
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: read.sourceType.systemImageName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))

            Text(read.sourceType.libraryLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(uiColor: placeholderTopColor),
                    Color(uiColor: placeholderBottomColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var placeholderTopColor: UIColor {
        switch read.sourceType {
        case .epub:
            return UIColor(red: 0.20, green: 0.29, blue: 0.52, alpha: 1)
        case .pdf:
            return UIColor(red: 0.44, green: 0.20, blue: 0.16, alpha: 1)
        case .image:
            return UIColor(red: 0.14, green: 0.38, blue: 0.34, alpha: 1)
        case .txt:
            return UIColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1)
        case .pastedText:
            return UIColor(red: 0.23, green: 0.19, blue: 0.15, alpha: 1)
        }
    }

    private var placeholderBottomColor: UIColor {
        switch read.sourceType {
        case .epub:
            return UIColor(red: 0.52, green: 0.61, blue: 0.89, alpha: 1)
        case .pdf:
            return UIColor(red: 0.79, green: 0.48, blue: 0.34, alpha: 1)
        case .image:
            return UIColor(red: 0.43, green: 0.68, blue: 0.63, alpha: 1)
        case .txt:
            return UIColor(red: 0.50, green: 0.56, blue: 0.68, alpha: 1)
        case .pastedText:
            return UIColor(red: 0.65, green: 0.52, blue: 0.39, alpha: 1)
        }
    }

    private func loadThumbnail() async {
        thumbnailData = await ThumbnailGeneratorService.shared.thumbnailData(for: read)
    }
}

struct LibraryItemMenu: View {
    let onMarkFinished: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button {
                onMarkFinished()
            } label: {
                Label("Mark as Finished", systemImage: "checkmark.circle")
            }

            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "textformat")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 30, height: 30)
                .background(AppTheme.controlBackground.opacity(0.75), in: Circle())
        }
        .menuStyle(.borderlessButton)
    }
}

struct RenameReadSheet: View {
    @Environment(\.dismiss) private var dismiss
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
                Section("Title") {
                    TextField("Read title", text: $title)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
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
                        .foregroundStyle(isSelected ? Color.blue : AppTheme.secondaryText)
                }

                coverView
                    .frame(width: 50, height: 70)

                VStack(alignment: .leading, spacing: 2) {
                    Text(read.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)

                    if let author = read.author, !author.isEmpty {
                        Text(author)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: read.sourceType.systemImageName)
                        Text("\(Int(read.progressPercent.rounded()))%")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isSelectMode {
                    LibraryItemMenu(
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
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.controlBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.24), lineWidth: 1)
                }

            if let thumbnailData, let thumbnailImage = UIImage(data: thumbnailData) {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: read.sourceType.systemImageName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(uiColor: placeholderTopColor),
                                Color(uiColor: placeholderBottomColor)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholderTopColor: UIColor {
        switch read.sourceType {
        case .epub: return UIColor(red: 0.20, green: 0.29, blue: 0.52, alpha: 1)
        case .pdf: return UIColor(red: 0.44, green: 0.20, blue: 0.16, alpha: 1)
        case .image: return UIColor(red: 0.14, green: 0.38, blue: 0.34, alpha: 1)
        case .txt: return UIColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1)
        case .pastedText: return UIColor(red: 0.23, green: 0.19, blue: 0.15, alpha: 1)
        }
    }

    private var placeholderBottomColor: UIColor {
        switch read.sourceType {
        case .epub: return UIColor(red: 0.52, green: 0.61, blue: 0.89, alpha: 1)
        case .pdf: return UIColor(red: 0.79, green: 0.48, blue: 0.34, alpha: 1)
        case .image: return UIColor(red: 0.43, green: 0.68, blue: 0.63, alpha: 1)
        case .txt: return UIColor(red: 0.50, green: 0.56, blue: 0.68, alpha: 1)
        case .pastedText: return UIColor(red: 0.65, green: 0.52, blue: 0.39, alpha: 1)
        }
    }
}

struct LibraryControlsMenu: View {
    @Binding var viewMode: LibraryViewMode
    @Binding var sortMode: LibrarySortMode
    let onSelectMode: () -> Void

    var body: some View {
        Menu {
            Section {
                Button(action: onSelectMode) {
                    Label("Select", systemImage: "checkmark.circle")
                }
            }

            Section("View As") {
                Picker("View As", selection: $viewMode) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(LibraryViewMode.grid)
                    Label("List", systemImage: "list.bullet").tag(LibraryViewMode.list)
                }
                .pickerStyle(.inline)
            }

            Section("Sort By") {
                Picker("Sort By", selection: $sortMode) {
                    Label("Recent", systemImage: "clock").tag(LibrarySortMode.recent)
                    Label("Title", systemImage: "textformat").tag(LibrarySortMode.title)
                    Label("Author", systemImage: "person").tag(LibrarySortMode.author)
                    Label("Manual", systemImage: "line.3.horizontal").tag(LibrarySortMode.manual)
                }
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 44, height: 44)
                .background(AppTheme.controlBackground.opacity(0.8), in: Circle())
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
            "Pasted"
        case .txt:
            "Text"
        case .pdf:
            "PDF"
        case .epub:
            "EPUB"
        case .image:
            "Image"
        }
    }
}
