import Foundation
@preconcurrency import WCDBSwift

nonisolated struct ChatAttachmentTableObject: TableCodable, Identifiable, Sendable {
    static let tableName = "attachment"

    var id: String = UUID().uuidString
    var relationMessageIdentifier: String
    var data: Data
    var representationText: String
    var representationImage: Data
    var metadataType: String
    var metadataName: String
    var metadataOriginal: String
    var metadataCreatedAt: Date = .init()
    var metadataExtension: String

    enum CodingKeys: String, CodingTableKey {
        typealias Root = ChatAttachmentTableObject

        nonisolated static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(relationMessageIdentifier, isNotNull: true, defaultTo: "")
            BindColumnConstraint(data, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(representationText, isNotNull: true, defaultTo: "")
            BindColumnConstraint(representationImage, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(metadataType, isNotNull: true, defaultTo: "")
            BindColumnConstraint(metadataName, isNotNull: true, defaultTo: "")
            BindColumnConstraint(metadataOriginal, isNotNull: true, defaultTo: "")
            BindColumnConstraint(metadataCreatedAt, isNotNull: true, defaultTo: .currentTimestamp())
            BindColumnConstraint(metadataExtension, isNotNull: true, defaultTo: "")
            BindIndex(metadataCreatedAt, namedWith: "_creation_index")
            BindIndex(relationMessageIdentifier, namedWith: "_message_identifier_index")
            BindIndex(metadataType, namedWith: "_type_index")
        }

        case id = "attachment_identifier"
        case relationMessageIdentifier = "attachment_relation_message_identifier"
        case data = "attachment_data"
        case representationText = "attachment_representation_text"
        case representationImage = "attachment_representation_image"
        case metadataType = "attachment_metadata_type"
        case metadataName = "attachment_metadata_name"
        case metadataOriginal = "attachment_metadata_original"
        case metadataCreatedAt = "attachment_metadata_created_at"
        case metadataExtension = "attachment_metadata_extension"
    }

    init(
        id: String = UUID().uuidString,
        relationMessageIdentifier: String,
        data: Data = Data(),
        representationText: String = "",
        representationImage: Data = Data(),
        metadataType: String = "",
        metadataName: String = "",
        metadataOriginal: String = "",
        metadataCreatedAt: Date = .init(),
        metadataExtension: String = ""
    ) {
        self.id = id
        self.relationMessageIdentifier = relationMessageIdentifier
        self.data = data
        self.representationText = representationText
        self.representationImage = representationImage
        self.metadataType = metadataType
        self.metadataName = metadataName
        self.metadataOriginal = metadataOriginal
        self.metadataCreatedAt = metadataCreatedAt
        self.metadataExtension = metadataExtension
    }
}
