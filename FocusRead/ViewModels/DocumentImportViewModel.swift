import AVFoundation
import Foundation
import ImageIO
import SwiftUI
import UIKit

@MainActor
final class DocumentImportViewModel: ObservableObject {
    @Published var isFileImporterPresented = false
    @Published var isImportSheetPresented = false
    @Published var isCameraCapturePresented = false
    @Published var isPhotoLibraryPickerPresented = false
    @Published private(set) var state: DocumentImportState = .idle
    @AppStorage(ReaderBehaviorSettingsKey.smartCleanupMode) private var smartCleanupMode: String = ""

    private let worker: DocumentImportWorker
    private var importTask: Task<Void, Never>?
    private var activeImportID: UUID?
    private var lastSelectedURL: URL?
    private var lastImageImport: ImageImportRequest?

    init(worker: DocumentImportWorker = DocumentImportWorker()) {
        self.worker = worker
    }

    var canRetry: Bool {
        lastSelectedURL != nil || lastImageImport != nil
    }

    func presentFilePicker() {
        isFileImporterPresented = true
    }

    func presentImportSource(_ source: ImportSource) {
        switch source {
        case .files:
            presentFilePicker()
        case .camera:
            presentCameraCapture()
        case .photoLibrary:
            isPhotoLibraryPickerPresented = true
        }
    }

    func handleFileImporterResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            lastSelectedURL = url
            lastImageImport = nil
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
        if let lastSelectedURL {
            startImport(from: lastSelectedURL)
        } else if let lastImageImport {
            startImageImport(lastImageImport)
        }
    }

    func chooseAnotherFile() {
        importTask?.cancel()
        importTask = nil
        activeImportID = nil
        state = .idle
        isImportSheetPresented = false

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.presentImportSource(.files)
        }
    }

    func dismissImport() {
        importTask?.cancel()
        importTask = nil
        activeImportID = nil
        isImportSheetPresented = false
        state = .idle
    }

    func handleCameraCapture(_ image: UIImage) {
        isCameraCapturePresented = false
        guard let request = makeImageImportRequest(
            from: [image],
            title: "Camera Scan",
            fileNamePrefix: "Camera Scan"
        ) else {
            state = .failed(.imageImportFailed)
            isImportSheetPresented = true
            return
        }

        lastSelectedURL = nil
        lastImageImport = request
        startImageImport(request)
    }

    func handlePhotoLibrarySelection(_ images: [UIImage]) {
        isPhotoLibraryPickerPresented = false
        guard let request = makeImageImportRequest(
            from: images,
            title: "Photo Import",
            fileNamePrefix: "Photo Import"
        ) else {
            state = .failed(.imageImportFailed)
            isImportSheetPresented = true
            return
        }

        lastSelectedURL = nil
        lastImageImport = request
        startImageImport(request)
    }

    func handleImagePickerCancellation() {
        isCameraCapturePresented = false
        isPhotoLibraryPickerPresented = false
    }

    func handleImagePickerFailure(_ error: DocumentImportError) {
        isCameraCapturePresented = false
        isPhotoLibraryPickerPresented = false
        state = .failed(error)
        isImportSheetPresented = true
    }

    private func presentCameraCapture() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            state = .failed(.cameraUnavailable)
            isImportSheetPresented = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraCapturePresented = true
        case .notDetermined:
            Task { [weak self] in
                let isGranted = await Self.requestCameraAccess()
                guard let self else { return }
                if isGranted {
                    isCameraCapturePresented = true
                } else {
                    state = .failed(.cameraAccessDenied)
                    isImportSheetPresented = true
                }
            }
        case .denied, .restricted:
            state = .failed(.cameraAccessDenied)
            isImportSheetPresented = true
        @unknown default:
            state = .failed(.cameraAccessDenied)
            isImportSheetPresented = true
        }
    }

    private func startImport(from url: URL) {
        importTask?.cancel()
        let importID = UUID()
        activeImportID = importID
        state = .loading(.starting)
        isImportSheetPresented = true
        let cleanupMode = SmartCleanupAvailability.effectiveMode(savedRawValue: smartCleanupMode)
        if smartCleanupMode != cleanupMode.rawValue {
            smartCleanupMode = cleanupMode.rawValue
        }

        importTask = Task { [weak self] in
            guard let self else { return }

            do {
                let document = try await worker.importDocument(from: url, smartCleanupMode: cleanupMode) { [weak self] progress in
                    await MainActor.run {
                        guard self?.activeImportID == importID else { return }
                        self?.state = .loading(progress)
                    }
                }

                guard !Task.isCancelled, activeImportID == importID else { return }
                state = .preview(document)
            } catch is CancellationError {
                guard activeImportID == importID else { return }
                state = .idle
                isImportSheetPresented = false
            } catch let error as DocumentImportError {
                guard activeImportID == importID else { return }
                state = .failed(error)
            } catch {
                guard activeImportID == importID else { return }
                state = .failed(.noReadableText)
            }

            if activeImportID == importID {
                importTask = nil
            }
        }
    }

    private func startImageImport(_ request: ImageImportRequest) {
        importTask?.cancel()
        let importID = UUID()
        activeImportID = importID
        state = .loading(DocumentImportProgress(
            message: "Recognizing text...",
            completedUnitCount: 0,
            totalUnitCount: request.images.count,
            unitName: "images"
        ))
        isImportSheetPresented = true
        let cleanupMode = SmartCleanupAvailability.effectiveMode(savedRawValue: smartCleanupMode)
        if smartCleanupMode != cleanupMode.rawValue {
            smartCleanupMode = cleanupMode.rawValue
        }

        importTask = Task { [weak self] in
            guard let self else { return }

            do {
                let document = try await worker.importImages(
                    request.images,
                    title: request.title,
                    fileName: request.fileName,
                    smartCleanupMode: cleanupMode
                ) { [weak self] progress in
                    await MainActor.run {
                        guard self?.activeImportID == importID else { return }
                        self?.state = .loading(progress)
                    }
                }

                guard !Task.isCancelled, activeImportID == importID else { return }
                state = .preview(document)
            } catch is CancellationError {
                guard activeImportID == importID else { return }
                state = .idle
                isImportSheetPresented = false
            } catch let error as DocumentImportError {
                guard activeImportID == importID else { return }
                state = .failed(error)
            } catch {
                guard activeImportID == importID else { return }
                state = .failed(.noReadableText)
            }

            if activeImportID == importID {
                importTask = nil
            }
        }
    }

    private func makeImageImportRequest(
        from images: [UIImage],
        title: String,
        fileNamePrefix: String
    ) -> ImageImportRequest? {
        let pages = images.compactMap(Self.ocrPage)
        guard pages.count == images.count, !pages.isEmpty else {
            return nil
        }

        let timestamp = Self.fileTimestampFormatter.string(from: Date())
        return ImageImportRequest(
            images: pages,
            title: title,
            fileName: "\(fileNamePrefix) \(timestamp).image"
        )
    }

    private static func ocrPage(from image: UIImage) -> OCRImagePage? {
        if let cgImage = image.cgImage {
            return OCRImagePage(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }

        guard let cgImage = renderedImage.cgImage else {
            return nil
        }
        return OCRImagePage(cgImage: cgImage)
    }

    private static func requestCameraAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { isGranted in
                continuation.resume(returning: isGranted)
            }
        }
    }

    private static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain &&
            nsError.code == CocoaError.Code.userCancelled.rawValue
    }

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()
}

private struct ImageImportRequest {
    let images: [OCRImagePage]
    let title: String
    let fileName: String
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

enum DocumentImportState: Equatable {
    case idle
    case loading(DocumentImportProgress)
    case preview(ImportedDocument)
    case failed(DocumentImportError)
}
