import AppKit

/// Shared pasteboard → attachment parsing used by both the composer drop/paste
/// handler and the WebView file-drop interception in the host app.
public enum PasteboardImporter {
    /// The result of parsing a pasteboard for droppable/pasteable content.
    public enum Content {
        case fileURLs([URL])
        case imageData(Data, format: String)
    }

    /// Returns whether the pasteboard contains supported file or image content.
    public static func containsImportableContent(in pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        return types.contains(.fileURL) || types.contains(.png) || types.contains(.tiff)
    }

    /// Attempts to extract file URLs or image data from the given pasteboard.
    /// Returns `nil` when the pasteboard contains nothing importable.
    public static func extractContent(from pasteboard: NSPasteboard) -> Content? {
        guard let types = pasteboard.types else { return nil }

        if types.contains(.fileURL),
           let urls = pasteboard.readObjects(
               forClasses: [NSURL.self],
               options: [.urlReadingFileURLsOnly: true]
           ) as? [URL],
           !urls.isEmpty
        {
            return .fileURLs(urls)
        }

        if types.contains(.png), let data = pasteboard.data(forType: .png) {
            return .imageData(data, format: "png")
        }

        if types.contains(.tiff),
           let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let tiffRep = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffRep),
           let pngData = bitmapRep.representation(using: .png, properties: [:])
        {
            return .imageData(pngData, format: "png")
        }

        return nil
    }
}
