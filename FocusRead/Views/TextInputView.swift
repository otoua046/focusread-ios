import SwiftUI
import UIKit

struct TextInputView: View {
    @ObservedObject var viewModel: InputViewModel
    let onStart: () -> Void
    let onStartImportedDocument: (ImportedDocument) -> Void
    @StateObject private var documentImportViewModel = DocumentImportViewModel()
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack {
                    mainContent
                }
                .frame(minHeight: proxy.size.height, alignment: .top)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(
                FocusReadBackground()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditorFocused = false
                    }
            )
            .sheet(isPresented: $documentImportViewModel.isImportSheetPresented) {
                DocumentImportView(viewModel: documentImportViewModel) { document in
                    documentImportViewModel.dismissImport()
                    onStartImportedDocument(document)
                }
            }
            .sheet(isPresented: $documentImportViewModel.isCameraCapturePresented) {
                CameraCaptureView(
                    onCapture: documentImportViewModel.handleCameraCapture,
                    onCancel: documentImportViewModel.handleImagePickerCancellation,
                    onFailure: documentImportViewModel.handleImagePickerFailure
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $documentImportViewModel.isPhotoLibraryPickerPresented) {
                PhotoLibraryPicker(
                    selectionLimit: 0,
                    onImagesPicked: documentImportViewModel.handlePhotoLibrarySelection,
                    onCancel: documentImportViewModel.handleImagePickerCancellation,
                    onFailure: documentImportViewModel.handleImagePickerFailure
                )
            }
            .fileImporter(
                isPresented: $documentImportViewModel.isFileImporterPresented,
                allowedContentTypes: DocumentPickerService.allowedContentTypes
            ) { result in
                documentImportViewModel.handleFileImporterResult(result)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isEditorFocused = false
                    }
                }
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 24) {
            header
            editor
            actions
            aiCleanupFooter
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }

    private var header: some View {
        VStack(spacing: 14) {
            FocusReadPageHeader(title: "Home")
                .padding(.bottom, 2)

            Text("Read faster with less motion.")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("Paste text, set a calm pace, and read one centered word at a time.")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topTrailing) {
            TextEditor(text: $viewModel.text)
                .font(.body)
                .focused($isEditorFocused)
                .scrollContentBackground(.hidden)
                .padding(16)
                .frame(minHeight: 280)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if viewModel.text.isEmpty {
                        Text("Paste anything worth reading...")
                            .foregroundStyle(AppTheme.tertiaryText)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 24)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                if viewModel.text.isEmpty || isEditorFocused {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.controlBackground, in: Circle())
                            .overlay {
                                Circle().strokeBorder(AppTheme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Paste")
                }

                if !viewModel.text.isEmpty {
                    Button {
                        viewModel.text = ""
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppTheme.controlForeground)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.controlBackground, in: Circle())
                            .overlay {
                                Circle().strokeBorder(AppTheme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear text")
                }
            }
            .padding(12)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                onStart()
            } label: {
                Label("Start Reading", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryButtonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.primaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(!viewModel.canStart)
            .opacity(viewModel.canStart ? 1 : 0.45)

            Menu {
                ForEach(ImportSource.allCases) { source in
                    Button {
                        isEditorFocused = false
                        documentImportViewModel.presentImportSource(source)
                    } label: {
                        Label(source.title, systemImage: source.systemImageName)
                    }
                }
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
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
    }

    @ViewBuilder
    private var aiCleanupFooter: some View {
        if SmartCleanupAvailability.isAICleanupAvailable {
            Text("AI Cleanup available on this device")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 4)
        }
    }

    private func pasteFromClipboard() {
        if let string = UIPasteboard.general.string, !string.isEmpty {
            viewModel.text = string
        }
    }
}

struct FocusReadBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                AppTheme.background,
                AppTheme.cardBackground,
                AppTheme.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
