import re

with open("FocusRead/Views/HistorySidebarView.swift", "r") as f:
    content = f.read()

new_content = content.replace(
    '''    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FocusReadPageHeader(title: "Library")

                if store.savedReads.isEmpty {
                    emptyState
                } else {
                    LibraryGridView(
                        reads: store.savedReads,
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
            }''',
    '''    @AppStorage("library_view_mode") private var viewMode: LibraryViewMode = .grid
    @AppStorage("library_sort_mode") private var sortMode: LibrarySortMode = .recent
    @State private var isSelectMode = false
    @State private var selection = Set<UUID>()

    private var sortedReads: [SavedRead] {
        var sorted = store.savedReads
        switch sortMode {
        case .recent:
            sorted.sort {
                if $0.lastOpenedAt != $1.lastOpenedAt {
                    return $0.lastOpenedAt > $1.lastOpenedAt
                } else if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.createdAt > $1.createdAt
            }
        case .title:
            sorted.sort {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .author:
            sorted.sort {
                let author1 = $0.author ?? ""
                let author2 = $1.author ?? ""
                if author1.isEmpty && !author2.isEmpty { return false }
                if !author1.isEmpty && author2.isEmpty { return true }
                if author1.isEmpty && author2.isEmpty {
                    return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                if author1.localizedCaseInsensitiveCompare(author2) == .orderedSame {
                    return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                return author1.localizedCaseInsensitiveCompare(author2) == .orderedAscending
            }
        case .manual:
            sorted.sort {
                let s1 = $0.manualSortIndex ?? Int.max
                let s2 = $1.manualSortIndex ?? Int.max
                if s1 == s2 {
                    return $0.createdAt > $1.createdAt
                }
                return s1 < s2
            }
        }
        return sorted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                            sortMode: $sortMode,
                            onSelectMode: {
                                isSelectMode = true
                            }
                        )
                        .padding(.top, 4)
                    }
                }

                if store.savedReads.isEmpty {
                    emptyState
                } else {
                    if isSelectMode {
                        HStack {
                            Text("\(selection.count) Selected")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                            Spacer()
                            Button(role: .destructive) {
                                let selectedIds = selection
                                deleteTarget = nil
                                selection.removeAll()
                                isSelectMode = false
                                for id in selectedIds {
                                    if let read = store.read(withID: id) {
                                        delete(read)
                                    }
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.headline)
                                    .foregroundStyle(selection.isEmpty ? AppTheme.secondaryText.opacity(0.5) : .red)
                            }
                            .disabled(selection.isEmpty)
                        }
                    }

                    if viewMode == .grid {
                        LibraryGridView(
                            reads: sortedReads,
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
                            reads: sortedReads,
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
            }'''
)

new_content = new_content.replace(
    '''struct LibraryGridView: View {
    let reads: [SavedRead]
    let onResume: (SavedRead) -> Void
    let onMarkFinished: (SavedRead) -> Void
    let onRename: (SavedRead) -> Void
    let onDelete: (SavedRead) -> Void''',
    '''struct LibraryGridView: View {
    let reads: [SavedRead]
    let isSelectMode: Bool
    @Binding var selection: Set<UUID>
    let onResume: (SavedRead) -> Void
    let onMarkFinished: (SavedRead) -> Void
    let onRename: (SavedRead) -> Void
    let onDelete: (SavedRead) -> Void'''
)

new_content = new_content.replace(
    '''        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(reads) { read in
                LibraryBookCard(
                    read: read,
                    onResume: { onResume(read) },
                    onMarkFinished: { onMarkFinished(read) },
                    onRename: { onRename(read) },
                    onDelete: { onDelete(read) }
                )
            }
        }''',
    '''        LazyVGrid(columns: columns, spacing: 22) {
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
        }'''
)

new_content = new_content.replace(
    '''struct LibraryBookCard: View {
    let read: SavedRead
    let onResume: () -> Void
    let onMarkFinished: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void''',
    '''struct LibraryBookCard: View {
    let read: SavedRead
    let isSelectMode: Bool
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onResume: () -> Void
    let onMarkFinished: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void'''
)

new_content = new_content.replace(
    '''        VStack(alignment: .leading, spacing: 10) {
            Button(action: onResume) {
                coverView
            }
            .buttonStyle(.plain)''',
    '''        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                if isSelectMode {
                    onToggleSelect()
                } else {
                    onResume()
                }
            }) {
                coverView
            }
            .buttonStyle(.plain)'''
)

new_content = new_content.replace(
    '''        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14),
            radius: 12,
            x: 0,
            y: 6
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))''',
    '''        .aspectRatio(0.72, contentMode: .fit)
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
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))'''
)


new_components = """
enum LibraryViewMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }
}

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case recent
    case title
    case author
    case manual

    var id: String { rawValue }
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
                Button {
                    viewMode = .grid
                } label: {
                    HStack {
                        Text("Grid")
                        Spacer()
                        if viewMode == .grid {
                            Image(systemName: "checkmark")
                        }
                    }
                    // For the icon, use Label if preferred, but Menu supports systemImage correctly:
                }
                // Overriding to standard Label for checkmark + icon
                Button(action: { viewMode = .grid }) {
                    Label("Grid", systemImage: viewMode == .grid ? "checkmark" : "square.grid.2x2")
                }
                Button(action: { viewMode = .list }) {
                    Label("List", systemImage: viewMode == .list ? "checkmark" : "list.bullet")
                }
            }

            Section("Sort By") {
                Button(action: { sortMode = .recent }) {
                    Label("Recent", systemImage: sortMode == .recent ? "checkmark" : "clock")
                }
                Button(action: { sortMode = .title }) {
                    Label("Title", systemImage: sortMode == .title ? "checkmark" : "textformat")
                }
                Button(action: { sortMode = .author }) {
                    Label("Author", systemImage: sortMode == .author ? "checkmark" : "person")
                }
                Button(action: { sortMode = .manual }) {
                    Label("Manual", systemImage: sortMode == .manual ? "checkmark" : "line.3.horizontal")
                }
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

struct LibraryListView: View {
    let reads: [SavedRead]
    let isSelectMode: Bool
    @Binding var selection: Set<UUID>
    let onResume: (SavedRead) -> Void
    let onMarkFinished: (SavedRead) -> Void
    let onRename: (SavedRead) -> Void
    let onDelete: (SavedRead) -> Void

    var body: some View {
        VStack(spacing: 16) {
            ForEach(reads) { read in
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(read.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)

                    if let author = read.author, !author.isEmpty {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: read.sourceType.systemImageName)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("\(Int(read.progressPercent.rounded()))%")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
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
            .padding(12)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            }
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
"""

new_content = new_content + "\\n" + new_components

with open("FocusRead/Views/HistorySidebarView.swift", "w") as f:
    f.write(new_content)
