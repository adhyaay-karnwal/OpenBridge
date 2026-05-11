import Foundation
import Yams

// MARK: - Zip Import

struct SkillZipImportProgress: Equatable {
    let title: String
    let message: String
    let detail: String?
    let fractionCompleted: Double?
}

extension SkillManager {
    private struct SkillZipImportPlan {
        let manifestName: String
        let rootURL: URL
        let packageFiles: [SkillPackageIOFile]
    }

    /// Import skills from a zip file
    /// - Parameter zipURL: URL to the zip file
    /// - Returns: Array of imported Skill instances
    /// - Throws: SkillError if import fails
    func importSkillFromZip(
        _ zipURL: URL,
        progressHandler: (@MainActor (SkillZipImportProgress) -> Void)? = nil
    ) async throws -> [Skill] {
        await reportImportProgress(
            makeImportProgress(message: String(localized: "Preparing zip file..."), detail: zipURL.lastPathComponent),
            using: progressHandler
        )

        let didStartAccessing = zipURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                zipURL.stopAccessingSecurityScopedResource()
            }
        }

        let tempDir = try makeTemporaryZipImportDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        try await extractZipImportContents(from: zipURL, to: tempDir, progressHandler: progressHandler)
        let topLevelSkillFolders = try findTopLevelSkillFolders(in: tempDir)
        guard !topLevelSkillFolders.isEmpty else {
            throw SkillError.importFailed(
                String(localized: "The selected zip file doesn't contain a valid skill manifest. Expected SKILL.md or skill.md.")
            )
        }

        let (importPlans, planFailures) = await prepareZipImportPlans(
            from: topLevelSkillFolders,
            progressHandler: progressHandler
        )

        guard !importPlans.isEmpty else {
            throw SkillError.importFailed(importFailureMessage(from: planFailures))
        }

        let importResult = await importZipPlansLocally(importPlans, progressHandler: progressHandler)
        let importFailures = planFailures + importResult.failures

        await reportImportProgress(
            makeImportProgress(message: String(localized: "Refreshing imported skills..."), fractionCompleted: 1.0),
            using: progressHandler
        )
        await refreshUserSkills(notify: true, force: true)
        let importedSkills = importResult.skills

        logger.info("✅ Imported \(importedSkills.count) skill(s) from zip")

        guard !importedSkills.isEmpty else {
            throw SkillError.importFailed(importFailureMessage(from: importFailures))
        }

        return importedSkills
    }

    // MARK: - Private Helpers

    private func makeTemporaryZipImportDirectory() throws -> URL {
        let tempBaseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("app.openbridge", isDirectory: true)
            .appendingPathComponent("skill-import", isDirectory: true)

        try FileManager.default.createDirectory(at: tempBaseDir, withIntermediateDirectories: true)

        let tempDir = tempBaseDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func extractZipImportContents(
        from zipURL: URL,
        to tempDir: URL,
        progressHandler: (@MainActor (SkillZipImportProgress) -> Void)?
    ) async throws {
        await reportImportProgress(
            makeImportProgress(message: String(localized: "Extracting archive...")),
            using: progressHandler
        )
        try await unzipFile(zipURL: zipURL, to: tempDir)
        removeIgnoredFiles(in: tempDir)

        await reportImportProgress(
            makeImportProgress(message: String(localized: "Validating skill package...")),
            using: progressHandler
        )
        try validateNoSymlinks(in: tempDir)

        await reportImportProgress(
            makeImportProgress(message: String(localized: "Scanning for skills...")),
            using: progressHandler
        )
    }

    private func prepareZipImportPlans(
        from folders: [URL],
        progressHandler: (@MainActor (SkillZipImportProgress) -> Void)?
    ) async -> (plans: [SkillZipImportPlan], failures: [String]) {
        await reportImportProgress(
            makeImportProgress(
                message: String(localized: "Preparing skills for upload..."),
                detail: String(localized: "\(folders.count) skill(s) found")
            ),
            using: progressHandler
        )

        var plans: [SkillZipImportPlan] = []
        var failures: [String] = []

        for folder in folders {
            do {
                try plans.append(makeZipImportPlan(from: folder))
            } catch {
                let folderName = folder.lastPathComponent
                logger.error("⚠️ Failed to import skill from zip folder \(folderName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failures.append("\(folderName): \(error.localizedDescription)")
            }
        }

        return (plans, failures)
    }

    private func makeZipImportPlan(from folder: URL) throws -> SkillZipImportPlan {
        guard let skillManifestURL = findSkillManifest(in: folder) else {
            throw SkillError.importFailed(
                String(localized: "Missing SKILL.md in \(folder.lastPathComponent)")
            )
        }

        let originalContent = try String(contentsOf: skillManifestURL, encoding: .utf8)
        let tempData = try SkillDecoder().decode(originalContent)
        let manifestName = tempData.frontmatter.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifestName.isEmpty else {
            throw SkillError.invalidSkillName(String(localized: "Skill name cannot be empty."))
        }

        let folderName = try makeUniqueSkillName(manifestName)
        return try .init(
            manifestName: manifestName,
            rootURL: skillDirs.custom.appendingPathComponent(folderName, isDirectory: true),
            packageFiles: buildZipImportPackage(from: folder, renamedSkillName: folderName)
        )
    }

    private func importZipPlansLocally(
        _ importPlans: [SkillZipImportPlan],
        progressHandler: (@MainActor (SkillZipImportProgress) -> Void)?
    ) async -> (skills: [Skill], failures: [String]) {
        let totalUploadFileCount = importPlans.reduce(into: 0) { result, plan in
            result += plan.packageFiles.count { file in
                file.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty == false
            }
        }

        var skills: [Skill] = []
        var failures: [String] = []
        var uploadedFileCount = 0

        for (index, plan) in importPlans.enumerated() {
            await reportImportProgress(
                makeImportProgress(
                    message: String(localized: "Importing '\(plan.manifestName)'..."),
                    detail: uploadProgressDetail(
                        uploadedFileCount: uploadedFileCount,
                        totalUploadFileCount: totalUploadFileCount,
                        currentSkillIndex: index,
                        totalSkillCount: importPlans.count
                    ),
                    fractionCompleted: uploadProgressFraction(
                        uploadedFileCount: uploadedFileCount,
                        totalUploadFileCount: totalUploadFileCount
                    )
                ),
                using: progressHandler
            )

            do {
                try FileManager.default.createDirectory(at: plan.rootURL, withIntermediateDirectories: true)
                for file in plan.packageFiles {
                    let normalizedRelativePath = file.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    guard normalizedRelativePath.isEmpty == false else { continue }

                    let destinationURL = plan.rootURL.appendingPathComponent(normalizedRelativePath, isDirectory: false)
                    try FileManager.default.createDirectory(
                        at: destinationURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try file.data.write(to: destinationURL, options: .atomic)

                    uploadedFileCount += 1
                    await reportImportProgress(
                        makeImportProgress(
                            message: String(localized: "Importing '\(plan.manifestName)'..."),
                            detail: String(localized: "\(uploadedFileCount) of \(totalUploadFileCount) files imported\n\(normalizedRelativePath)"),
                            fractionCompleted: uploadProgressFraction(
                                uploadedFileCount: uploadedFileCount,
                                totalUploadFileCount: totalUploadFileCount
                            )
                        ),
                        using: progressHandler
                    )
                }

                let skill = try Skill.load(from: plan.rootURL.appendingPathComponent("SKILL.md", isDirectory: false))
                upsertRemoteSkill(skill)
                logger.info("✅ Imported skill '\(plan.manifestName)' from zip")
                skills.append(skill)
            } catch {
                logger.error("⚠️ Failed to import skill '\(plan.manifestName, privacy: .public)' from zip: \(error.localizedDescription, privacy: .public)")
                failures.append("\(plan.manifestName): \(error.localizedDescription)")
            }
        }

        return (skills, failures)
    }

    private func importFailureMessage(from failures: [String]) -> String {
        let failureDetails = failures.joined(separator: "\n")
        return if failureDetails.isEmpty {
            String(localized: "No skills were imported from the selected zip file.")
        } else {
            String(localized: "Failed to import any skills from the selected zip file.\n\(failureDetails)")
        }
    }

    private func unzipFile(zipURL: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destination.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw SkillError.unzipFailed(errorMessage)
            }
        } catch let error as SkillError {
            throw error
        } catch {
            throw SkillError.unzipFailed(error.localizedDescription)
        }
    }

    private func findTopLevelSkillFolders(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        var allSkillMarkdowns: [URL] = []

        // Find all SKILL.md files recursively
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            if isSkillManifestName(fileURL.lastPathComponent) {
                allSkillMarkdowns.append(fileURL)
            }
        }

        if allSkillMarkdowns.isEmpty {
            return []
        }

        // Filter out SKILL.md files that have a parent SKILL.md
        var topLevelSkillMarkdowns: [URL] = []

        for skillMarkdown in allSkillMarkdowns {
            let skillDir = skillMarkdown.deletingLastPathComponent()
            var hasParentSkill = false

            // Check if any other SKILL.md is an ancestor of this one
            for otherSkillMarkdown in allSkillMarkdowns {
                guard skillMarkdown != otherSkillMarkdown else { continue }

                let otherSkillDir = otherSkillMarkdown.deletingLastPathComponent()

                // Check if otherSkillDir is an ancestor of skillDir
                if isAncestor(ancestor: otherSkillDir, descendant: skillDir) {
                    hasParentSkill = true
                    break
                }
            }

            if !hasParentSkill {
                topLevelSkillMarkdowns.append(skillMarkdown)
            }
        }

        // Return the directories containing top-level SKILL.md files
        return topLevelSkillMarkdowns.map { $0.deletingLastPathComponent() }
    }

    private func isSkillManifestName(_ fileName: String) -> Bool {
        fileName.caseInsensitiveCompare("SKILL.md") == .orderedSame
    }

    private func findSkillManifest(in folder: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return contents.first { itemURL in
            isSkillManifestName(itemURL.lastPathComponent)
        }
    }

    private func isAncestor(ancestor: URL, descendant: URL) -> Bool {
        let ancestorPath = ancestor.standardizedFileURL.path
        let descendantPath = descendant.standardizedFileURL.path

        // Ensure descendant path starts with ancestor path and is actually a subdirectory
        guard descendantPath.hasPrefix(ancestorPath) else {
            return false
        }

        // Make sure it's actually a child (not the same directory)
        let remainder = descendantPath.dropFirst(ancestorPath.count)
        return remainder.hasPrefix("/") && !remainder.dropFirst().isEmpty
    }

    private func removeIgnoredFiles(in directory: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            if skillIgnoredFileNames.contains(fileURL.lastPathComponent) {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    private func validateNoSymlinks(in directory: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resourceValues.isSymbolicLink == true {
                throw SkillError.unzipFailed("Symlinks are not allowed in zip files")
            }
        }
    }

    private func buildZipImportPackage(from folder: URL, renamedSkillName: String) throws -> [SkillPackageIOFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [SkillPackageIOFile] = []
        for case let itemURL as URL in enumerator {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory == true {
                continue
            }

            let relativePath = itemURL.path.replacingOccurrences(of: folder.path + "/", with: "")
            guard skillIgnoredFileNames.contains(itemURL.lastPathComponent) == false else { continue }

            if isSkillManifestName(relativePath) {
                let originalContent = try String(contentsOf: itemURL, encoding: .utf8)
                var data = try SkillDecoder().decode(originalContent)
                data.frontmatter.name = renamedSkillName
                let encodedContent = try SkillEncoder().encode(data)
                files.append(.init(path: "SKILL.md", data: Data(encodedContent.utf8), contentType: "text/markdown; charset=utf-8"))
                continue
            }

            try files.append(.init(path: relativePath, data: Data(contentsOf: itemURL), contentType: contentType(for: itemURL)))
        }
        return files
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "md":
            "text/markdown; charset=utf-8"
        case "json":
            "application/json"
        case "txt":
            "text/plain; charset=utf-8"
        case "png":
            "image/png"
        case "jpg", "jpeg":
            "image/jpeg"
        case "gif":
            "image/gif"
        case "webp":
            "image/webp"
        case "svg":
            "image/svg+xml"
        default:
            "application/octet-stream"
        }
    }

    private func makeImportProgress(
        message: String,
        detail: String? = nil,
        fractionCompleted: Double? = nil
    ) -> SkillZipImportProgress {
        .init(
            title: String(localized: "Importing Skills"),
            message: message,
            detail: detail,
            fractionCompleted: fractionCompleted
        )
    }

    private func uploadProgressDetail(
        uploadedFileCount: Int,
        totalUploadFileCount: Int,
        currentSkillIndex: Int,
        totalSkillCount: Int
    ) -> String {
        if totalUploadFileCount > 0 {
            return String(localized: "\(uploadedFileCount) of \(totalUploadFileCount) files uploaded")
        }

        return String(localized: "\(currentSkillIndex + 1) of \(totalSkillCount) skills")
    }

    private func uploadProgressFraction(
        uploadedFileCount: Int,
        totalUploadFileCount: Int
    ) -> Double? {
        guard totalUploadFileCount > 0 else { return nil }
        return Double(uploadedFileCount) / Double(totalUploadFileCount)
    }

    private func reportImportProgress(
        _ progress: SkillZipImportProgress,
        using progressHandler: (@MainActor (SkillZipImportProgress) -> Void)?
    ) async {
        guard let progressHandler else { return }
        await MainActor.run {
            progressHandler(progress)
        }
    }
}
