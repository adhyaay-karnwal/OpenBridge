import Foundation
import SwiftUI

class EmojiProvider {
    struct Emoji: Codable, Hashable, Equatable, Identifiable {
        var id: String {
            emoji
        }

        var emoji: String
        var description: String
        var category: String
        var aliases: [String]
        var tags: [String]
        var unicodeVersion: String?
        var iosVersion: String?
        var backgroundColor: String?
        var backgroundColorDark: String?

        enum CodingKeys: String, CodingKey {
            case emoji
            case description
            case category
            case aliases
            case tags
            case unicodeVersion = "unicode_version"
            case iosVersion = "ios_version"
            case backgroundColor = "background_color"
            case backgroundColorDark = "background_color_dark"
        }
    }

    private static let bundledEmoji: [String: [Emoji]] = {
        guard let url = Bundle.main.url(forResource: "Emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let array = try? JSONDecoder().decode([Emoji].self, from: data)
        else {
            assertionFailure("Failed to load Emoji.json from bundle")
            return [:]
        }

        var result = [String: [Emoji]]()
        for item in array {
            result[item.category, default: []].append(item)
        }
        return result
    }()

    private let userDefaults = UserDefaults.standard
    private let recentEmojiKey = "EmojiPicker.RecentEmoji"

    func retainStaticEmojis() -> [String: [Emoji]] {
        Self.bundledEmoji
    }

    func obtainRecentUsed() -> [String] {
        guard let data = userDefaults.data(forKey: recentEmojiKey),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return array
    }

    func insertRecentUsed(emoji: String) {
        var build = obtainRecentUsed()
        build = [emoji] + build

        if build.count > 50 {
            build.removeLast(build.count - 50)
        }

        var seen = Set<String>()
        build = build.filter { seen.insert($0).inserted }

        if let data = try? JSONEncoder().encode(build) {
            userDefaults.set(data, forKey: recentEmojiKey)
        }
    }
}
