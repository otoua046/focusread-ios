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
            .navigationTitle(L10n.key(.importTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.dismissImport()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.focusReadIconControl(tone: .regular, visualSize: 36, tapTargetSize: 44))
                    .accessibilityLabel(L10n.string(.importCloseAccessibility))
                }
            }
        }
        .focusReadThemeRefresh()
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

                Text(L10n.format(.importDocumentDetailFormat, document.estimatedWordCount, document.sourceType.label))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(document.previewText)
                        .font(.body)
                        .foregroundStyle(AppTheme.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxWidth: .infinity)
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
                Label(.importStartReading, systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.focusReadProminentAction())

            Button {
                viewModel.chooseAnotherFile()
            } label: {
                Label(.importChooseAnotherFile, systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.focusReadSecondaryAction(font: .subheadline.weight(.medium)))
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
                        Label(.commonRetry, systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.focusReadProminentAction())
                }

                Button {
                    viewModel.chooseAnotherFile()
                } label: {
                    Label(.importChooseAnotherFile, systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.focusReadSecondaryAction(font: .subheadline.weight(.medium)))
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ImportSourceMenu<MenuLabel: View>: View {
    @ObservedObject var viewModel: DocumentImportViewModel
    let onSourceSelected: () -> Void
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            ForEach(ImportSource.allCases) { source in
                Button {
                    onSourceSelected()
                    viewModel.presentImportSource(source)
                } label: {
                    Label(source.title, systemImage: source.systemImageName)
                }
            }
        } label: {
            label()
        }
    }
}

struct QuickReadEditorSheet: View {
    let onCancel: () -> Void
    let onStartReading: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.focusReadTheme) private var theme
    @FocusState private var isTextFocused: Bool
    @State private var title = ""
    @State private var text = ""

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTitle: String? {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string(.quickReadTitlePlaceholder), text: $title)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(theme.primaryText)
                } header: {
                    Text(.quickReadTitleSection)
                }
                .listRowBackground(theme.cardBackground)

                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .focused($isTextFocused)
                            .font(.body)
                            .foregroundStyle(theme.primaryText)
                            .lineSpacing(3)
                            .frame(minHeight: 320)
                            .scrollContentBackground(.hidden)

                        if text.isEmpty {
                            Text(.quickReadTextPlaceholder)
                                .font(.body)
                                .foregroundStyle(theme.secondaryText)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                } header: {
                    Text(.quickReadTextSection)
                } footer: {
                    PasteButton(payloadType: String.self) { strings in
                        guard let pastedText = strings.first else { return }
                        text = pastedText
                    }
                    .accessibilityLabel(L10n.string(.quickReadPaste))
                }
                .listRowBackground(theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(FocusReadBackground())
            .navigationTitle(L10n.key(.quickReadTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.commonCancel) {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(.quickReadStartReading) {
                        onStartReading(trimmedText, trimmedTitle)
                        dismiss()
                    }
                    .disabled(trimmedText.isEmpty)
                }
            }
        }
        .presentationCornerRadius(22)
        .task {
            isTextFocused = true
        }
    }
}

private struct DocumentImportFlowModifier: ViewModifier {
    @ObservedObject var viewModel: DocumentImportViewModel
    let onStartImportedDocument: (ImportedDocument) -> Void
    let onStartQuickRead: (String, String?) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $viewModel.isImportSheetPresented) {
                DocumentImportView(viewModel: viewModel) { document in
                    viewModel.dismissImport()
                    onStartImportedDocument(document)
                }
            }
            .sheet(isPresented: $viewModel.isQuickReadEditorPresented) {
                QuickReadEditorSheet(
                    onCancel: {
                        viewModel.isQuickReadEditorPresented = false
                    },
                    onStartReading: { text, title in
                        viewModel.isQuickReadEditorPresented = false
                        onStartQuickRead(text, title)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.isCameraCapturePresented) {
                CameraCaptureView(
                    onCapture: viewModel.handleCameraCapture,
                    onCancel: viewModel.handleImagePickerCancellation,
                    onFailure: viewModel.handleImagePickerFailure
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $viewModel.isPhotoLibraryPickerPresented) {
                PhotoLibraryPicker(
                    selectionLimit: 0,
                    onImagesPicked: viewModel.handlePhotoLibrarySelection,
                    onCancel: viewModel.handleImagePickerCancellation,
                    onFailure: viewModel.handleImagePickerFailure
                )
            }
            .fileImporter(
                isPresented: $viewModel.isFileImporterPresented,
                allowedContentTypes: DocumentPickerService.allowedContentTypes
            ) { result in
                viewModel.handleFileImporterResult(result)
            }
    }
}

extension View {
    func documentImportFlow(
        viewModel: DocumentImportViewModel,
        onStartImportedDocument: @escaping (ImportedDocument) -> Void,
        onStartQuickRead: @escaping (String, String?) -> Void
    ) -> some View {
        modifier(DocumentImportFlowModifier(
            viewModel: viewModel,
            onStartImportedDocument: onStartImportedDocument,
            onStartQuickRead: onStartQuickRead
        ))
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
