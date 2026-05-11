import Foundation
@preconcurrency import WCDBSwift

nonisolated struct UserTableObject: TableCodable, Identifiable, Sendable {
    static let tableName = "user"
    static let localUserId = "local"
    static let localProvider = "local"

    var id: String = UUID().uuidString
    var provider: String
    var providerAccountId: String
    var displayName: String?
    var email: String?
    var avatarURL: String?
    var createdAt: Date = .init()
    var updatedAt: Date = .init()
    var lastSignInAt: Date?

    enum CodingKeys: String, CodingTableKey {
        typealias Root = UserTableObject

        nonisolated static let objectRelationalMapping = TableBinding(
            CodingKeys.self
        ) {
            BindColumnConstraint(id, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(createdAt, defaultTo: .currentTimestamp())
            BindColumnConstraint(updatedAt, defaultTo: .currentTimestamp())
            //            BindIndex(provider, providerAccountId, namedWith: "_provider_account", isUnique: true)
        }

        case id
        case provider
        case providerAccountId = "provider_account_id"
        case displayName = "display_name"
        case email
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSignInAt = "last_sign_in_at"
    }
}
