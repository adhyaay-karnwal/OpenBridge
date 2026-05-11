import AppKit
import Foundation
import QuickLookThumbnailing

enum QuickLookPreviewProvider {
    static func warmUp(
        for fileURL: URL,
        size: CGSize,
        scale: CGFloat = 2.0
    ) async -> Bool {
        await cgImage(for: fileURL, size: size, scale: scale) != nil
    }

    static func cgImage(
        for fileURL: URL,
        size: CGSize,
        scale: CGFloat = 2.0
    ) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: scale,
            representationTypes: .all
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                autoreleasepool {
                    continuation.resume(returning: representation?.cgImage)
                }
            }
        }
    }

    static func image(
        for fileURL: URL,
        size: CGSize,
        scale: CGFloat = 2.0
    ) async -> NSImage? {
        guard let cgImage = await cgImage(for: fileURL, size: size, scale: scale) else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    static func pngData(
        for fileURL: URL,
        size: CGSize,
        scale: CGFloat = 2.0
    ) async -> Data? {
        guard let cgImage = await cgImage(for: fileURL, size: size, scale: scale) else { return nil }
        return cgImage.pngData()
    }
}
