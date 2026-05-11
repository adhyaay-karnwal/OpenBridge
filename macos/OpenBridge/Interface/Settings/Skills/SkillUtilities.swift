import SwiftUI

// MARK: - String Extensions for Emoji

extension String {
    var isEmojiOnly: Bool {
        guard !isEmpty else { return false }
        return allSatisfy { character in
            character.unicodeScalars.contains { scalar in
                scalar.properties.isEmoji
            }
        }
    }
}
