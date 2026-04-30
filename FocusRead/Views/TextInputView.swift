import SwiftUI
import UIKit

struct TextInputView: View {
    @ObservedObject var viewModel: InputViewModel
    @ObservedObject var historyStore: LocalReadingHistoryStore
    let onStart: () -> Void
    let onStartImportedDocument: (ImportedDocument) -> Void
    let onResumeSavedRead: (SavedRead) -> Void
    @StateObject private var documentImportViewModel = DocumentImportViewModel()
    @State private var showingTypographySettings = false
    @State private var isHistoryPresented = false
    @State private var isHistorySidebarPersistent = false
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let sidebarIsPersistent = proxy.size.width >= 760

                ZStack(alignment: .leading) {
                    FocusReadBackground()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isEditorFocused = false
                        }

                    if sidebarIsPersistent {
                        HStack(spacing: 0) {
                            HistorySidebarView(
                                store: historyStore,
                                isPresented: $isHistoryPresented,
                                isPersistent: sidebarIsPersistent,
                                onResume: onResumeSavedRead
                            )
                            .frame(width: min(320, max(286, proxy.size.width * 0.36)))

                            mainContent
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        mainContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if isHistoryPresented {
                            HistorySidebarView(
                                store: historyStore,
                                isPresented: $isHistoryPresented,
                                isPersistent: false,
                                onResume: onResumeSavedRead
                            )
                            .frame(width: min(320, max(286, proxy.size.width * 0.82)))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .zIndex(2)
                        }
                    }

                    if isHistoryPresented && !sidebarIsPersistent {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()
                            .padding(.leading, min(320, max(286, proxy.size.width * 0.82)))
                            .onTapGesture {
                                isHistoryPresented = false
                            }
                            .transition(.opacity)
                            .zIndex(1)
                    }

                    if !sidebarIsPersistent && !isHistoryPresented {
                        historyEdgeHandle
                            .zIndex(3)
                    }
                }
                .animation(.smooth(duration: 0.28), value: isHistoryPresented)
                .animation(.smooth(duration: 0.28), value: sidebarIsPersistent)
                .onAppear {
                    updateHistorySidebarPersistence(sidebarIsPersistent)
                }
                .onChange(of: sidebarIsPersistent) { _, newValue in
                    updateHistorySidebarPersistence(newValue)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isHistorySidebarPersistent {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isHistoryPresented.toggle()
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .buttonStyle(.topReaderControl)
                        .accessibilityLabel(isHistoryPresented ? "Hide reading history" : "Show reading history")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTypographySettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.topReaderControl)
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
        }
    }

    private var mainContent: some View {
        VStack(spacing: 22) {
            header
            editor
            actions
            aiCleanupFooter
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
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

    private func updateHistorySidebarPersistence(_ isPersistent: Bool) {
        isHistorySidebarPersistent = isPersistent
        if isPersistent {
            isHistoryPresented = false
        }
    }

    private var historyEdgeHandle: some View {
        HStack {
            Color.clear
                .frame(width: 24)
                .contentShape(Rectangle())
                .gesture(openHistoryGesture)
                .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
    }

    private var openHistoryGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                if value.translation.width > 80,
                   abs(value.translation.height) < 60 {
                    isHistoryPresented = true
                }
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
