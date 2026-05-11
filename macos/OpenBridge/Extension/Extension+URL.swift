import Foundation
import UniformTypeIdentifiers

extension URL {
    /// Detect MIME type by checking file resource metadata first, then falling back to the file extension.
    func detectedMimeType() -> String? {
        if let contentType = try? resourceValues(forKeys: [.contentTypeKey]).contentType,
           let mimeType = contentType.preferredMIMEType
        {
            return mimeType
        }
        return UTType(filenameExtension: pathExtension.lowercased())?.preferredMIMEType
    }
}

extension Data {
    /// Create a `data:` URL with the given MIME type.
    func dataURL(mimeType: String) -> String {
        "data:\(mimeType);base64,\(base64EncodedString())"
    }
}
