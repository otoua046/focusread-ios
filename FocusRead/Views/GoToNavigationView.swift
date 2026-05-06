import SwiftUI

struct GoToNavigationView: View {
    @StateObject private var viewModel: GoToViewModel
    @Environment(\.dismiss) private var dismiss

    init(readerViewModel: ReaderViewModel) {
        _viewModel = StateObject(wrappedValue: GoToViewModel(reader: readerViewModel))
    }

    var body: some View {
        NavigationStack {
            List {
                searchSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            viewModel.cancelSearch()
        }
    }

    private var searchSection: some View {
        Section("Search Word") {
            TextField("Find words", text: Binding(
                get: { viewModel.searchQuery },
                set: { viewModel.updateSearchQuery($0) }
            ))
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)

            if viewModel.isSearching {
                HStack {
                    ProgressView()
                    Text("Searching...")
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.vertical, 8)
            } else if viewModel.showNoSearchResults {
                Text("No matches found")
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.searchResults) { result in
                    Button {
                        viewModel.jumpToSearchResult(result)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Word \(result.index)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)

                            Text(highlightedSnippet(for: result))
                                .font(.body)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func highlightedSnippet(for result: ReaderSearchResult) -> AttributedString {
        var snippet = AttributedString()

        for (index, part) in result.snippetParts.enumerated() {
            if index > 0 {
                snippet += AttributedString(" ")
            }

            var text = AttributedString(part.text)
            if part.isMatch {
                text.backgroundColor = AppTheme.searchHighlightBackground
                text.foregroundColor = AppTheme.searchHighlightForeground
            } else {
                text.foregroundColor = AppTheme.primaryText
            }
            snippet += text
        }

        return snippet
    }
}
