import Foundation

nonisolated struct DatabaseConfiguration: Sendable {
    let databaseURL: URL
    let enableAutoMigration: Bool
    let enableAutoCompression: Bool
    let shouldTraceSQL: Bool
}

extension DatabaseConfiguration {
    nonisolated static func `default`() -> DatabaseConfiguration {
        let directoryURL = Constant
            .applicationLibraryURL
            .appendingPathComponent("database", isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("app.db")
        return DatabaseConfiguration(
            databaseURL: databaseURL,
            enableAutoMigration: true,
            enableAutoCompression: true,
            shouldTraceSQL: false
        )
    }
}
