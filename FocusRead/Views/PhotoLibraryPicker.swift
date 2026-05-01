import PhotosUI
import SwiftUI
import UIKit

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    static let maximumSelectionCount = 12

    let selectionLimit: Int
    let onImagesPicked: ([UIImage]) -> Void
    let onCancel: () -> Void
    let onFailure: (DocumentImportError) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagesPicked: onImagesPicked, onCancel: onCancel, onFailure: onFailure)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImagesPicked: ([UIImage]) -> Void
        private let onCancel: () -> Void
        private let onFailure: (DocumentImportError) -> Void

        init(
            onImagesPicked: @escaping ([UIImage]) -> Void,
            onCancel: @escaping () -> Void,
            onFailure: @escaping (DocumentImportError) -> Void
        ) {
            self.onImagesPicked = onImagesPicked
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                onCancel()
                return
            }

            Task {
                do {
                    let images = try await Self.loadImages(from: results)
                    await MainActor.run {
                        onImagesPicked(images)
                    }
                } catch {
                    await MainActor.run {
                        onFailure(.imageImportFailed)
                    }
                }
            }
        }

        private static func loadImages(from results: [PHPickerResult]) async throws -> [UIImage] {
            var images: [UIImage] = []
            images.reserveCapacity(min(results.count, PhotoLibraryPicker.maximumSelectionCount))

            for result in results.prefix(PhotoLibraryPicker.maximumSelectionCount) {
                try Task.checkCancellation()
                let image = try await loadImage(from: result.itemProvider)
                images.append(image)
            }

            return images
        }

        private static func loadImage(from provider: NSItemProvider) async throws -> UIImage {
            try await withCheckedThrowingContinuation { continuation in
                guard provider.canLoadObject(ofClass: UIImage.self) else {
                    continuation.resume(throwing: DocumentImportError.imageImportFailed)
                    return
                }

                provider.loadObject(ofClass: UIImage.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let image = object as? UIImage else {
                        continuation.resume(throwing: DocumentImportError.imageImportFailed)
                        return
                    }

                    continuation.resume(returning: image)
                }
            }
        }
    }
}
