import Foundation
import UniformTypeIdentifiers

struct DocumentPickerService: Sendable {
    static let allowedContentTypes: [UTType] = [
        .pdf,
        .plainText,
        UTType(importedAs: "org.idpf.epub-container")
    ]

    func copySecurityScopedFile(from url: URL) throws -> ImportedFile {
        let fileManager = FileManager.default
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let importDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("FocusReadImports", isDirectory: true)
        try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)

        let destination = importDirectory
            .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
        } catch {
            throw DocumentImportError.fileCopyFailed
        }

        return ImportedFile(
            localURL: destination,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension.lowercased()
        )
    }
}
