import SwiftUI

struct DocumentImportView: View {
    @ObservedObject var viewModel: DocumentImportViewModel
    let onStartReading: (ImportedDocument) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                FocusReadBackground()

                Group {
                    switch viewModel.state {
                    case .idle:
                        EmptyView()
                    case .loading(let progress):
                        loadingView(progress)
                    case .preview(let document):
                        previewView(document)
                    case .failed(let error):
                        errorView(error)
                    }
                }
                .padding(22)
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.dismissImport()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close import")
                }
            }
        }
    }

    private func loadingView(_ progress: DocumentImportProgress) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.circular)
                .tint(AppTheme.primaryText)

            Text(progress.message)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            if let detail = progress.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewView(_ document: ImportedDocument) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label(document.displayTitle, systemImage: document.sourceType.previewSystemImageName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)

                Text("\(document.estimatedWordCount) words • \(document.sourceType.label)")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            ScrollView {
                Text(document.previewText)
                    .font(.body)
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .frame(maxHeight: 320)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            }

            Spacer(minLength: 0)

            Button {
                onStartReading(document)
            } label: {
                Label("Start Reading", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryButtonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.primaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Button {
                viewModel.chooseAnotherFile()
            } label: {
                Label("Choose Another File", systemImage: "folder")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func errorView(_ error: DocumentImportError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 64, height: 64)
                .background(AppTheme.controlBackground, in: Circle())
                .overlay {
                    Circle().strokeBorder(AppTheme.border, lineWidth: 1)
                }

            Text(error.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            Text(error.message)
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            VStack(spacing: 10) {
                if viewModel.canRetry {
                    Button {
                        viewModel.retryImport()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryButtonForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(AppTheme.primaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }

                Button {
                    viewModel.chooseAnotherFile()
                } label: {
                    Label("Choose Another File", systemImage: "folder")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(AppTheme.border, lineWidth: 1)
                        }
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension DocumentSourceType {
    var previewSystemImageName: String {
        switch self {
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
