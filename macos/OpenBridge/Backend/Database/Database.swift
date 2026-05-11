import Foundation

@preconcurrency import WCDBSwift

final class Database: @unchecked Sendable {
    private nonisolated static let logger = Logger(subsystem: Logger.loggingSubsystem, category: "Database")

    // swiftlint:disable:next force_try
    nonisolated static let shared = MainActor.assumeIsolated { try! Database() }

    let configuration: DatabaseConfiguration
    nonisolated let wcDatabase: WCDBSwift.Database

    init(
        configuration: DatabaseConfiguration? = nil,
        databaseFactory: @escaping (_ path: String) throws -> WCDBSwift.Database = WCDBSwift
            .Database.init,
        fileManager: FileManager = .default
    ) throws {
        let configuration = configuration ?? .default()
        self.configuration = configuration

        let directoryURL = configuration.databaseURL.deletingLastPathComponent()
        try Database.ensureDirectoryExists(
            at: directoryURL,
            fileManager: fileManager
        )

        wcDatabase = try databaseFactory(configuration.databaseURL.path)

        wcDatabase.setAutoMigration(enable: configuration.enableAutoMigration)
        wcDatabase.enableAutoCompression(configuration.enableAutoCompression)

        #if DEBUG
            if configuration.shouldTraceSQL {
                wcDatabase.traceSQL { _, _, _, sql, _ in
                    Self.logger.debug("[SQL] \(sql)")
                }
            }
        #endif

        try Self.prepareSchema(in: wcDatabase)
    }

    var databasePath: String {
        wcDatabase.path
    }
}

extension Database {
    nonisolated static func ensureDirectoryExists(at url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) {
            return
        }

        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    nonisolated static func prepareSchema(in database: WCDBSwift.Database) throws {
        database.add(tokenizer: BuiltinTokenizer.Verbatim)
        try database.create(table: UserTableObject.tableName, of: UserTableObject.self)
        try database.create(
            table: ChatConversationItemTableObject.tableName,
            of: ChatConversationItemTableObject.self
        )
        try database.create(
            table: ChatMessageTableObject.tableName, of: ChatMessageTableObject.self
        )
        try database.create(
            table: ChatAttachmentTableObject.tableName, of: ChatAttachmentTableObject.self
        )
    }
}

extension Database {
    func reset(fileManager: FileManager = .default) throws {
        wcDatabase.close()

        let databaseURL = configuration.databaseURL
        try removeItemIfExists(at: databaseURL, fileManager: fileManager)

        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        try removeItemIfExists(at: walURL, fileManager: fileManager)

        let shmURL = URL(fileURLWithPath: databaseURL.path + "-shm")
        try removeItemIfExists(at: shmURL, fileManager: fileManager)
    }

    private func removeItemIfExists(at url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
