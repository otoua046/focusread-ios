import SwiftUI
import UIKit

struct TextInputView: View {
    @ObservedObject var viewModel: InputViewModel
    let onStart: () -> Void
    let onStartImportedDocument: (ImportedDocument) -> Void
    @StateObject private var documentImportViewModel = DocumentImportViewModel()
    @State private var showingTypographySettings = false
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                FocusReadBackground()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditorFocused = false
                    }

                VStack(spacing: 22) {
                    header
                    editor
                    actions
                    aiCleanupFooter
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTypographySettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .foregroundStyle(AppTheme.controlForeground)
                            .background(AppTheme.controlBackground, in: Circle())
                            .overlay {
                                Circle().strokeBorder(AppTheme.border, lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("Typography settings")
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isEditorFocused = false
                    }
                }
            }
            .sheet(isPresented: $showingTypographySettings) {
                TypographySettingsView()
            }
            .sheet(isPresented: $documentImportViewModel.isImportSheetPresented) {
                DocumentImportView(viewModel: documentImportViewModel) { document in
                    documentImportViewModel.dismissImport()
                    onStartImportedDocument(document)
                }
            }
            .fileImporter(
                isPresented: $documentImportViewModel.isFileImporterPresented,
                allowedContentTypes: DocumentPickerService.allowedContentTypes
            ) { result in
                documentImportViewModel.handleFileImporterResult(result)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
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
        .padding(.top, 24)
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

            Button {
                isEditorFocused = false
                documentImportViewModel.presentFilePicker()
            } label: {
                Label("Import File", systemImage: "doc.badge.plus")
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
