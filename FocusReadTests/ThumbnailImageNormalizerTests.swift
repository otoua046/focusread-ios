import XCTest
import UIKit
@testable import FocusRead

final class ThumbnailImageNormalizerTests: XCTestCase {
    func testTallCoverKeepsAspectRatio() {
        assertNormalizedImagePreservesAspectRatio(
            sourceSize: CGSize(width: 300, height: 900),
            maximumDimension: 360
        )
    }

    func testWidePreviewKeepsAspectRatio() {
        assertNormalizedImagePreservesAspectRatio(
            sourceSize: CGSize(width: 900, height: 300),
            maximumDimension: 360
        )
    }

    func testSquareCoverKeepsAspectRatio() {
        assertNormalizedImagePreservesAspectRatio(
            sourceSize: CGSize(width: 600, height: 600),
            maximumDimension: 360
        )
    }

    private func assertNormalizedImagePreservesAspectRatio(
        sourceSize: CGSize,
        maximumDimension: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sourceImage = makeImage(size: sourceSize)
        let normalizedImage = ThumbnailImageNormalizer.normalized(
            image: sourceImage,
            maximumDimension: maximumDimension
        )

        XCTAssertLessThanOrEqual(
            max(normalizedImage.size.width, normalizedImage.size.height),
            maximumDimension,
            file: file,
            line: line
        )
        XCTAssertEqual(
            normalizedImage.size.width / normalizedImage.size.height,
            sourceSize.width / sourceSize.height,
            accuracy: 0.01,
            file: file,
            line: line
        )
    }

    private func makeImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
