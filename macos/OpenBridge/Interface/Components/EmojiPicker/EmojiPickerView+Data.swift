import Foundation

extension EmojiPickerView {
    func prepareDataSource() {
        let recentUsed = provider.obtainRecentUsed()
        let staticEmojis = provider.retainStaticEmojis()

        var dataSource = [EmojiSection]()

        var recent = [EmojiElement]()
        for emojiString in recentUsed {
            outerLoop: for (_, value) in staticEmojis {
                for lookup in value {
                    if lookup.emoji == emojiString {
                        recent.append(EmojiElement(emoji: lookup))
                        break outerLoop
                    }
                }
            }
        }

        if !recent.isEmpty {
            let section = EmojiSection(
                sectionTitle: String(localized: "Recent Used"),
                emojis: recent
            )
            dataSource.append(section)
        }

        let keys = staticEmojis.keys.sorted()
        for key in keys {
            guard let emojis = staticEmojis[key], !emojis.isEmpty else {
                continue
            }
            let elements = emojis
                .sorted { $0.emoji < $1.emoji }
                .map { EmojiElement(emoji: $0) }
            let section = EmojiSection(
                sectionTitle: key.isEmpty ? String(localized: "Ungrouped") : key,
                emojis: elements
            )
            dataSource.append(section)
        }

        rawDataSource = dataSource
        self.dataSource = dataSource
    }

    func performSearch(_ searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty, selectedCategory == nil {
            dataSource = rawDataSource
            return
        }

        let filtered = searchFiltering(text: trimmed)
        dataSource = filtered
    }

    func searchFiltering(text: String) -> [EmojiSection] {
        let searchLower = text.lowercased()

        return rawDataSource.compactMap { section -> EmojiSection? in
            if let selected = selectedCategory, section.sectionTitle != selected {
                if section.sectionTitle != String(localized: "Recent Used") {
                    return nil
                }
            }

            if searchLower.isEmpty {
                return section
            }

            let emojis = section.emojis.filter { element in
                let emoji = element.emoji

                if emoji.emoji.lowercased().contains(searchLower) {
                    return true
                }

                if section.sectionTitle.lowercased().contains(searchLower) {
                    return true
                }

                if emoji.description.lowercased().contains(searchLower) {
                    return true
                }

                if emoji.aliases.contains(where: { $0.lowercased().contains(searchLower) }) {
                    return true
                }

                if emoji.tags.contains(where: { $0.lowercased().contains(searchLower) }) {
                    return true
                }

                return false
            }

            if emojis.isEmpty {
                return nil
            }

            return EmojiSection(sectionTitle: section.sectionTitle, emojis: emojis)
        }
    }
}
