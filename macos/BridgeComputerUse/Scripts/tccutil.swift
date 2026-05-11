#!/usr/bin/env swift

import Foundation

struct TCCUtility {
    struct Configuration {
        var service = "kTCCServiceAccessibility"
        var insertClients: [String] = []
        var enableClients: [String] = []
        var listClients = false
        var userName: String?
        var showVersion = false
        var showHelp = false
    }

    private let version = "0.1.0"

    func run(arguments: [String]) throws {
        let configuration = try parse(arguments: arguments)

        if configuration.showHelp {
            printUsage()
            return
        }

        if configuration.showVersion {
            print("tccutil \(version)")
            return
        }

        let databasePath = try resolveDatabasePath(userName: configuration.userName)

        if configuration.listClients {
            try listClients(service: configuration.service, databasePath: databasePath)
            return
        }

        for client in configuration.insertClients {
            try insertClient(client, service: configuration.service, databasePath: databasePath)
        }

        for client in configuration.enableClients {
            try enableClient(client, service: configuration.service, databasePath: databasePath)
        }
    }

    private func parse(arguments: [String]) throws -> Configuration {
        var configuration = Configuration()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--help", "-h":
                configuration.showHelp = true
            case "--version":
                configuration.showVersion = true
            case "--list", "-l":
                configuration.listClients = true
            case "--service", "-s":
                index += 1
                configuration.service = try value(after: argument, index: index, arguments: arguments)
            case "--insert", "-i":
                index += 1
                try configuration.insertClients.append(value(after: argument, index: index, arguments: arguments))
            case "--enable", "-e":
                index += 1
                try configuration.enableClients.append(value(after: argument, index: index, arguments: arguments))
            case "--user", "-u":
                let nextIndex = index + 1
                if nextIndex < arguments.count, arguments[nextIndex].hasPrefix("-") == false {
                    configuration.userName = arguments[nextIndex]
                    index = nextIndex
                } else {
                    configuration.userName = ""
                }
            default:
                throw ToolError("unexpected argument: \(argument)")
            }

            index += 1
        }

        return configuration
    }

    private func value(after argument: String, index: Int, arguments: [String]) throws -> String {
        guard index < arguments.count else {
            throw ToolError("missing value for \(argument)")
        }

        return arguments[index]
    }

    private func resolveDatabasePath(userName: String?) throws -> String {
        let relativePath = "Library/Application Support/com.apple.TCC/TCC.db"

        guard let userName else {
            return "/Library/Application Support/com.apple.TCC/TCC.db"
        }

        if userName.isEmpty {
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(homeDirectory)/\(relativePath)"
        }

        return try "\(homeDirectory(for: userName))/\(relativePath)"
    }

    private func homeDirectory(for userName: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(userName)", "NFSHomeDirectory"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ToolError("user not found: \(userName)")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .first(where: { $0.contains("NFSHomeDirectory:") })?
            .split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            text.isEmpty == false
        else {
            throw ToolError("failed to resolve home directory for \(userName)")
        }

        return text
    }

    private func insertClient(_ client: String, service: String, databasePath: String) throws {
        let clientType = client.hasPrefix("/") ? 1 : 0
        let escapedService = escapeSQL(service)
        let escapedClient = escapeSQL(client)
        let sql = """
        INSERT OR REPLACE INTO access (
            service,
            client,
            client_type,
            auth_value,
            auth_reason,
            auth_version,
            csreq,
            policy_id,
            indirect_object_identifier_type,
            indirect_object_identifier,
            indirect_object_code_identity,
            flags,
            pid,
            pid_version,
            boot_uuid
        ) VALUES (
            '\(escapedService)',
            '\(escapedClient)',
            \(clientType),
            2,
            4,
            1,
            NULL,
            NULL,
            0,
            'UNUSED',
            NULL,
            0,
            NULL,
            NULL,
            'UNUSED'
        );
        """

        try runSQLite(sql: sql, databasePath: databasePath)
    }

    private func enableClient(_ client: String, service: String, databasePath: String) throws {
        let escapedService = escapeSQL(service)
        let escapedClient = escapeSQL(client)
        let sql = """
        UPDATE access
        SET auth_value = 2
        WHERE client = '\(escapedClient)'
          AND service = '\(escapedService)';
        """

        try runSQLite(sql: sql, databasePath: databasePath)
    }

    private func listClients(service: String, databasePath: String) throws {
        let escapedService = escapeSQL(service)
        let sql = """
        SELECT client
        FROM access
        WHERE service = '\(escapedService)'
        ORDER BY client;
        """

        let output = try runSQLite(sql: sql, databasePath: databasePath, captureOutput: true)
        if output.isEmpty == false {
            print(output)
        }
    }

    @discardableResult
    private func runSQLite(sql: String, databasePath: String, captureOutput: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databasePath, sql]

        let output = Pipe()
        let error = Pipe()
        if captureOutput {
            process.standardOutput = output
        }
        process.standardError = error

        try process.run()
        output.fileHandleForWriting.closeFile()
        error.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw ToolError(errorText.isEmpty ? "sqlite3 failed" : errorText)
        }

        return outputText
    }

    private func escapeSQL(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func printUsage() {
        print("""
        Usage: tccutil [--service NAME] [--insert PATH] [--enable PATH] [--list] [--user [NAME]] [--version]
        """)
    }
}

struct ToolError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

do {
    try TCCUtility().run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch let error as ToolError {
    fputs("\(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
