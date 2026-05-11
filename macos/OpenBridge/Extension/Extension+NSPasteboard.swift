import AppKit

extension NSPasteboard {
    func data(forTypeIdentifier typeIdentifier: String) -> Data? {
        data(forType: NSPasteboard.PasteboardType(typeIdentifier))
    }
}
