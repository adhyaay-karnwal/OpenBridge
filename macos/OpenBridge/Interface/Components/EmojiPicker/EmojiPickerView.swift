import SwiftUI

struct EmojiPickerView: View {
    let provider = EmojiProvider()
    let onSelect: (String, String?) -> Void

    @State var searchText: String = ""
    @State var selectedCategory: String?
    @State var dataSource: [EmojiSection] = []
    @State var rawDataSource: [EmojiSection] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(dataSource) { section in
                        sectionHeader(section.sectionTitle)

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(section.emojis) { element in
                                emojiCell(element.emoji)
                            }
                        }
                    }
                }
                .padding(8)
            }

            if !availableCategories.isEmpty {
                categoryBar
            }
        }
        .frame(width: 250, height: 300)
        .onAppear {
            prepareDataSource()
        }
        .onChange(of: searchText) { _, newValue in
            performSearch(newValue)
        }
        .onChange(of: selectedCategory) { _, _ in
            performSearch(searchText)
        }
    }

    private var searchBar: some View {
        TextField(String(localized: "Search Emoji"), text: $searchText)
            .textFieldStyle(.plain)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(12)
    }

    private func emojiCell(_ emoji: EmojiProvider.Emoji) -> some View {
        Button {
            onSelect(emoji.emoji, emoji.backgroundColor)
            provider.insertRecentUsed(emoji: emoji.emoji)
        } label: {
            Text(emoji.emoji)
                .font(.system(size: 24))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(emoji.description)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineSpacing(4)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.vertical, 4)
            Spacer()
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    selectedCategory = nil
                } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 16))
                        .frame(width: 25, height: 20)
                        .background(selectedCategory == nil ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(9)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Recent"))

                Divider()
                    .frame(height: 20)

                ForEach(availableCategories, id: \.self) { category in
                    Button {
                        selectedCategory = category == selectedCategory ? nil : category
                    } label: {
                        Image(systemName: categoryIcon(category))
                            .font(.system(size: 16))
                            .frame(width: 25, height: 20)
                            .background(selectedCategory == category ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                    .help(category)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var availableCategories: [String] {
        let categoryOrder = [
            "Smileys & Emotion",
            "Animals & Nature",
            "Food & Drink",
            "Activities",
            "Travel & Places",
            "Objects",
            "Symbols",
            "Flags",
            "People & Body",
        ]

        let allCategories = provider.retainStaticEmojis().keys
        return categoryOrder.filter { allCategories.contains($0) }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "Smileys & Emotion": "face.smiling"
        case "People & Body": "person"
        case "Animals & Nature": "leaf"
        case "Food & Drink": "fork.knife"
        case "Travel & Places": "airplane"
        case "Activities": "sportscourt"
        case "Objects": "lightbulb"
        case "Symbols": "character.textbox"
        case "Flags": "flag"
        default: "square.grid.2x2"
        }
    }
}

struct EmojiSection: Identifiable, Hashable, Equatable {
    var id: String {
        sectionTitle
    }

    var sectionTitle: String
    var emojis: [EmojiElement]
}

struct EmojiElement: Identifiable, Hashable, Equatable {
    var id: String {
        emoji.emoji
    }

    let emoji: EmojiProvider.Emoji
}
