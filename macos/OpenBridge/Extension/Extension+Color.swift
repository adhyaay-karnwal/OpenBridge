import SwiftUI

extension ShapeStyle where Self == Color {
    static var formSectionBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                NSColor(red: 37 / 255, green: 37 / 255, blue: 37 / 255, alpha: 1)
            } else {
                NSColor(red: 247 / 255, green: 247 / 255, blue: 247 / 255, alpha: 1)
            }
        })
    }
}
