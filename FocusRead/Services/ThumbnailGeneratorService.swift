import Foundation
import UIKit

actor ThumbnailGeneratorService {
    static let shared = ThumbnailGeneratorService()

    private let fileManager: FileManager
    private let dataCache = NSCache<NSString, NSData>()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        dataCache.countLimit = 200
    }

    func thumbnailData(for read: SavedRead) async -> Data? {
        let cacheKey = cacheKey(for: read)
        if let cached = dataCache.object(forKey: cacheKey as NSString) {
            return cached as Data
        }

        if let data = loadThumbnailData(for: read) {
            dataCache.setObject(data as NSData, forKey: cacheKey as NSString)
            return data
        }

        let image = renderThumbnail(for: read, previewImageData: nil)
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            return nil
        }
        try? persist(data: data, for: read)
        dataCache.setObject(data as NSData, forKey: cacheKey as NSString)
        return data
    }

    func attachThumbnail(to read: SavedRead, previewImageData: Data?) async -> SavedRead {
        let thumbnailURL = self.thumbnailURL(for: read)
        if previewImageData == nil, fileManager.fileExists(atPath: thumbnailURL.path) {
            var updated = read
            updated.thumbnailPath = thumbnailRelativePath(for: read)
            return updated
        }

        let image = renderThumbnail(for: read, previewImageData: previewImageData)
        do {
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                return read
            }
            try persist(data: data, for: read)
            dataCache.setObject(data as NSData, forKey: cacheKey(for: read) as NSString)
        } catch {
            return read
        }

        var updated = read
        updated.thumbnailPath = thumbnailRelativePath(for: read)
        return updated
    }

    func removeThumbnail(for read: SavedRead) {
        let folderURL = readFolderURL(for: read)
        try? fileManager.removeItem(at: folderURL)
        dataCache.removeObject(forKey: cacheKey(for: read) as NSString)
    }

    func thumbnailRelativePath(for read: SavedRead) -> String {
        "SavedReads/\(read.id.uuidString)/thumbnail.jpg"
    }

    private func loadThumbnailData(for read: SavedRead) -> Data? {
        let thumbnailURL = self.thumbnailURL(for: read)
        return try? Data(contentsOf: thumbnailURL)
    }

    private func persist(data: Data, for read: SavedRead) throws {
        let folderURL = readFolderURL(for: read)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try data.write(to: thumbnailURL(for: read), options: [.atomic])
    }

    private func thumbnailURL(for read: SavedRead) -> URL {
        readFolderURL(for: read).appendingPathComponent("thumbnail.jpg")
    }

    private func readFolderURL(for read: SavedRead) -> URL {
        storageRootURL.appendingPathComponent(read.id.uuidString, isDirectory: true)
    }

    private var storageRootURL: URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return supportDirectory
            .appendingPathComponent("FocusRead", isDirectory: true)
            .appendingPathComponent("SavedReads", isDirectory: true)
    }

    private func renderThumbnail(for read: SavedRead, previewImageData: Data?) -> UIImage {
        if let previewImageData,
           let image = UIImage(data: previewImageData) {
            return normalized(image: image)
        }

        return renderPlaceholderCover(for: read)
    }

    private func normalized(image: UIImage) -> UIImage {
        let targetSize = CGSize(width: 840, height: 1120)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            UIColor.secondarySystemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else {
                return
            }

            let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
            let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let origin = CGPoint(
                x: (targetSize.width - scaledSize.width) / 2,
                y: (targetSize.height - scaledSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }

    private func renderPlaceholderCover(for read: SavedRead) -> UIImage {
        let size = CGSize(width: 840, height: 1120)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let colors = palette(for: read.sourceType)
            let cgColors = colors.map(\.cgColor) as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: [0, 1]) else {
                return
            }

            context.cgContext.saveGState()
            context.cgContext.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 42).cgPath)
            context.cgContext.clip()
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            context.cgContext.restoreGState()

            let coverRect = CGRect(x: 60, y: 60, width: size.width - 120, height: size.height - 120)
            let cardPath = UIBezierPath(roundedRect: coverRect, cornerRadius: 30)
            UIColor.white.withAlphaComponent(0.12).setFill()
            cardPath.fill()

            UIColor.white.withAlphaComponent(0.18).setStroke()
            cardPath.lineWidth = 2
            cardPath.stroke()

            let badgeRect = CGRect(x: 96, y: 110, width: 180, height: 54)
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 18)
            UIColor.white.withAlphaComponent(0.18).setFill()
            badgePath.fill()

            let badgeText = NSString(string: read.sourceType.rawValue.uppercased())
            badgeText.draw(
                in: badgeRect.insetBy(dx: 16, dy: 12),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.92)
                ]
            )

            let titleRect = CGRect(x: 96, y: 240, width: size.width - 192, height: 560)
            let title = NSString(string: read.displayTitle)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            paragraph.lineBreakMode = .byWordWrapping
            title.draw(
                in: titleRect,
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 64, weight: .semibold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
            )

            let subtitle = NSString(string: read.originalFileName ?? "Saved Read")
            let subtitleRect = CGRect(x: 96, y: size.height - 220, width: size.width - 192, height: 60)
            subtitle.draw(
                in: subtitleRect,
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.88)
                ]
            )
        }
    }

    private func palette(for sourceType: SavedReadSourceType) -> [UIColor] {
        switch sourceType {
        case .epub:
            return [UIColor(red: 0.20, green: 0.29, blue: 0.52, alpha: 1), UIColor(red: 0.57, green: 0.69, blue: 0.96, alpha: 1)]
        case .pdf:
            return [UIColor(red: 0.44, green: 0.20, blue: 0.16, alpha: 1), UIColor(red: 0.84, green: 0.50, blue: 0.38, alpha: 1)]
        case .image:
            return [UIColor(red: 0.14, green: 0.38, blue: 0.34, alpha: 1), UIColor(red: 0.45, green: 0.72, blue: 0.66, alpha: 1)]
        case .txt:
            return [UIColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1), UIColor(red: 0.50, green: 0.56, blue: 0.68, alpha: 1)]
        case .pastedText:
            return [UIColor(red: 0.23, green: 0.19, blue: 0.15, alpha: 1), UIColor(red: 0.69, green: 0.58, blue: 0.46, alpha: 1)]
        }
    }

    private func cacheKey(for read: SavedRead) -> String {
        read.id.uuidString
    }
}
