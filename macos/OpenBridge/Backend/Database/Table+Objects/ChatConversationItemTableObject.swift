import Foundation
@preconcurrency import WCDBSwift

nonisolated struct ChatConversationItemTableObject: TableCodable, Identifiable, Sendable {
    static let tableName = "conversation"

    var id: String = UUID().uuidString
    var metadataTitle: String
    var metadataCreatedAt: Date = .init()
    var metadataExtension: String
    var flagsIsFavorite: Bool
    var flagsShouldAutoRename: Bool

    enum CodingKeys: String, CodingTableKey {
        typealias Root = ChatConversationItemTableObject

        nonisolated static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(metadataTitle, isNotNull: true, defaultTo: "")
            BindColumnConstraint(metadataCreatedAt, isNotNull: true, defaultTo: .currentTimestamp())
            BindColumnConstraint(metadataExtension, isNotNull: true, defaultTo: "")
            BindColumnConstraint(flagsIsFavorite, isNotNull: true, defaultTo: false)
            BindColumnConstraint(flagsShouldAutoRename, isNotNull: true, defaultTo: true)
            BindIndex(metadataCreatedAt, namedWith: "_creation_index")
            BindIndex(flagsIsFavorite, namedWith: "_favorite_index")
        }

        case id = "conversation_identifier"
        case metadataTitle = "conversation_metadata_title"
        case metadataCreatedAt = "conversation_metadata_created_at"
        case metadataExtension = "conversation_metadata_extension"
        case flagsIsFavorite = "conversation_flags_is_favorite"
        case flagsShouldAutoRename = "conversation_flags_should_auto_rename"
    }

    init(
        id: String = UUID().uuidString,
        metadataTitle: String = "",
        metadataCreatedAt: Date = .init(),
        metadataExtension: String = "",
        flagsIsFavorite: Bool = false,
        flagsShouldAutoRename: Bool = true
    ) {
        self.id = id
        self.metadataTitle = metadataTitle
        self.metadataCreatedAt = metadataCreatedAt
        self.metadataExtension = metadataExtension
        self.flagsIsFavorite = flagsIsFavorite
        self.flagsShouldAutoRename = flagsShouldAutoRename
    }
}
