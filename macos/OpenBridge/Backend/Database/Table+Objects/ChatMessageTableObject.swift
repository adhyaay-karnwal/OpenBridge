import Foundation
@preconcurrency import WCDBSwift

nonisolated struct ChatMessageTableObject: TableCodable, Identifiable, Sendable {
    static let tableName = "message"

    var id: String = UUID().uuidString
    var relationConversationIdentifier: String
    var metadataCreatedAt: Date = .init()
    var metadataRole: String
    var metadataType: String
    var contentRaw: String
    var metadataExtension: String

    nonisolated enum CodingKeys: String, CodingTableKey {
        typealias Root = ChatMessageTableObject

        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(relationConversationIdentifier, isNotNull: true, defaultTo: "")
            BindColumnConstraint(metadataCreatedAt, isNotNull: true, defaultTo: .currentTimestamp())
            BindColumnConstraint(metadataRole, isNotNull: true, defaultTo: "")
            BindColumnConstraint(metadataType, isNotNull: true, defaultTo: "message")
            BindColumnConstraint(contentRaw, isNotNull: true, defaultTo: "{}")
            BindColumnConstraint(metadataExtension, isNotNull: true, defaultTo: "")
            BindIndex(relationConversationIdentifier, namedWith: "_conversation_index")
            BindIndex(metadataCreatedAt, namedWith: "_creation_index")
        }

        case id = "message_identifier"
        case relationConversationIdentifier = "message_relation_conversation_identifier"
        case metadataCreatedAt = "message_metadata_created_at"
        case metadataRole = "message_metadata_role"
        case metadataType = "message_metadata_type"
        case contentRaw = "message_content_raw"
        case metadataExtension = "message_metadata_extension"
    }

    init(
        id: String = UUID().uuidString,
        relationConversationIdentifier: String,
        metadataCreatedAt: Date = .init(),
        metadataRole: String,
        metadataType: String = "message",
        contentRaw: String = "{}",
        metadataExtension: String = ""
    ) {
        self.id = id
        self.relationConversationIdentifier = relationConversationIdentifier
        self.metadataCreatedAt = metadataCreatedAt
        self.metadataRole = metadataRole
        self.metadataType = metadataType
        self.contentRaw = contentRaw
        self.metadataExtension = metadataExtension
    }
}
