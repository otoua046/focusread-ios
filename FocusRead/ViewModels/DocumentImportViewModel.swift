import Foundation
import SwiftUI

@MainActor
final class DocumentImportViewModel: ObservableObject {
    @Published var isFileImporterPresented = false
    @Published var isImportSheetPresented = false
    @Published private(set) var state: DocumentImportState = .idle

    private let worker: DocumentImportWorker
    private var importTask: Task<Void, Never>?
    private var lastSelectedURL: URL?

    init(worker: DocumentImportWorker = DocumentImportWorker()) {
        self.worker = worker
    }

    var canRetry: Bool {
        lastSelectedURL != nil
    }

    func presentFilePicker() {
        isFileImporterPresented = true
    }

    func handleFileImporterResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            lastSelectedURL = url
            startImport(from: url)
        case .failure(let error):
            guard !Self.isUserCancellation(error) else {
                return
            }

            state = .failed(.fileCopyFailed)
            isImportSheetPresented = true
        }
    }

    func retryImport() {
        guard let lastSelectedURL else { return }
        startImport(from: lastSelectedURL)
    }

    func chooseAnotherFile() {
        importTask?.cancel()
        importTask = nil
        state = .idle
        isImportSheetPresented = false

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            isFileImporterPresented = true
        }
    }

    func dismissImport() {
        importTask?.cancel()
        importTask = nil
        isImportSheetPresented = false
        state = .idle
    }

    private func startImport(from url: URL) {
        importTask?.cancel()
        state = .loading(.starting)
        isImportSheetPresented = true

        importTask = Task { [weak self] in
            guard let self else { return }

            do {
                let document = try await worker.importDocument(from: url) { [weak self] progress in
                    await MainActor.run {
                        self?.state = .loading(progress)
                    }
                }

                guard !Task.isCancelled else { return }
                state = .preview(document)
            } catch is CancellationError {
                state = .idle
                isImportSheetPresented = false
            } catch let error as DocumentImportError {
                state = .failed(error)
            } catch {
                state = .failed(.noReadableText)
            }
        }
    }

    private static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain &&
            nsError.code == CocoaError.Code.userCancelled.rawValue
    }
}

enum DocumentImportState: Equatable {
    case idle
    case loading(DocumentImportProgress)
    case preview(ImportedDocument)
    case failed(DocumentImportError)
}
