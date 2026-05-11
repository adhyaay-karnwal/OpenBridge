import AppKit
import Foundation

final class FileProcessor {
    static let shared = FileProcessor()

    private init() {
        // Ensure directories exist on initialization
        _ = Constant.imagesDirectoryURL
    }

    // MARK: - File Thumbnail Data URL

    /// Generate a base64 data URL for a file thumbnail using QuickLook
    /// Returns nil if thumbnail generation fails
    func generateThumbnailDataURL(for fileURL: URL, size: CGSize = CGSize(width: 64, height: 64)) async -> String? {
        guard let data = await QuickLookPreviewProvider.pngData(for: fileURL, size: size, scale: 2.0) else {
            return nil
        }
        return data.dataURL(mimeType: "image/png")
    }
}
