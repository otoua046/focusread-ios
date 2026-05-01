import SwiftUI

struct LibraryView: View {
    @ObservedObject var store: LocalReadingHistoryStore
    let onResume: (SavedRead) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FocusReadPageHeader(title: "Library")

                if store.savedReads.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(store.savedReads) { read in
                            HistoryItemRow(
                                read: read,
                                onResume: {
                                    onResume(read)
                                },
                                onToggleFavorite: {
                                    store.toggleFavorite(read)
                                },
                                onDelete: {
                                    store.delete(read)
                                }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background(FocusReadBackground())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 54, height: 54)
                .background(AppTheme.controlBackground, in: Circle())

            Text("No reads yet")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Text("Start something from Home and it will appear here for easy resuming.")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(24)
        .background(AppTheme.cardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(AppTheme.border.opacity(0.8), lineWidth: 1)
        }
    }
}

struct HistorySidebarView: View {
    @ObservedObject var store: LocalReadingHistoryStore
    @Binding var isPresented: Bool
    let isPersistent: Bool
    let onResume: (SavedRead) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.savedReads.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.savedReads) { read in
                            HistoryItemRow(
                                read: read,
                                onResume: {
                                    if !isPersistent {
                                        isPresented = false
                                    }
                                    onResume(read)
                                },
                                onToggleFavorite: {
                                    store.toggleFavorite(read)
                                },
                                onDelete: {
                                    store.delete(read)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.border.opacity(0.65))
                .frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Library")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Spacer()

            if !isPersistent {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.controlForeground)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close library")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 54, height: 54)
                .background(AppTheme.controlBackground, in: Circle())

            Text("No reads yet")
                .font(.callout.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct HistoryItemRow: View {
    let read: SavedRead
    let onResume: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onResume) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: read.sourceType.systemImageName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(read.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if read.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("\(Int(read.progressPercent.rounded()))%")
                        Text(read.lastOpenedAt, format: .relative(presentation: .named))
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)

                    ProgressView(value: read.progressPercent, total: 100)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.primaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(AppTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppTheme.border.opacity(0.8), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onToggleFavorite()
            } label: {
                Label(read.isFavorite ? "Unfavorite" : "Favorite", systemImage: read.isFavorite ? "star.slash" : "star")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onToggleFavorite()
            } label: {
                Label(read.isFavorite ? "Unfavorite" : "Favorite", systemImage: read.isFavorite ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
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
}
