//
//  CommandItem.swift
//  ComposerEditor
//

import AppKit

/// Represents a command item that can be inserted as a token
public struct CommandItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String?

    /// Pre-rendered icon image (including background)
    public let iconImage: NSImage?

    /// The plain text representation when submitting (e.g. for API calls)
    /// Defaults to "/name" if not specified
    public let plainTextContentRepresentation: String

    public init(
        id: String,
        name: String,
        description: String? = nil,
        iconImage: NSImage? = nil,
        plainTextContentRepresentation: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconImage = iconImage
        self.plainTextContentRepresentation = plainTextContentRepresentation ?? ("/" + name)
    }

    public static func == (lhs: CommandItem, rhs: CommandItem) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.description == rhs.description &&
            lhs.plainTextContentRepresentation == rhs.plainTextContentRepresentation
    }
}

/// Data source protocol for providing command items to the command menu
@MainActor
public protocol CommandMenuDataSource: AnyObject {
    /// Returns all available command items
    func commandMenuItems() -> [CommandItem]

    /// Returns filtered command items based on search query
    func commandMenuItems(matching query: String) -> [CommandItem]
}

/// Default implementation for filtering
public extension CommandMenuDataSource {
    func commandMenuItems(matching query: String) -> [CommandItem] {
        let items = commandMenuItems()
        guard !query.isEmpty else { return items }
        let lowercasedQuery = query.lowercased()
        return items.filter { item in
            item.name.lowercased().contains(lowercasedQuery) ||
                (item.description?.lowercased().contains(lowercasedQuery) ?? false)
        }
    }
}
