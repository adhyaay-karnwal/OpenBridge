import Foundation

extension SkillManager {
    // MARK: - Sync Skill Folders Management

    func getSkillsFromSyncFolder(folder: URL) -> [Skill] {
        let resolvedPath = folder.resolvingSymlinksInPath().standardized.path
        return skills.filter {
            guard $0.category == .synced else { return false }
            let skillPath = $0.folderURL.resolvingSymlinksInPath().standardized.path
            return skillPath.hasPrefix(resolvedPath)
        }
    }

    /// Validate symbolic links in sync directory and log warnings for broken links
    func validateSymbolicLinks(in syncDir: URL) throws {
        let fm = FileManager.default

        guard let existingLinks = try? fm.contentsOfDirectory(
            at: syncDir,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        ) else {
            return
        }

        for linkURL in existingLinks {
            guard let resourceValues = try? linkURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  resourceValues.isSymbolicLink == true
            else {
                continue
            }

            let destination = linkURL.resolvingSymlinksInPath()
            let destinationPath = destination.standardizedFileURL.path

            if !fm.fileExists(atPath: destinationPath) {
                logger.warning("⚠️ Broken symbolic link detected: \(linkURL.lastPathComponent) -> \(destinationPath) (target does not exist)")
            }
        }
    }

    func addSyncSkillFolder(url: URL, alias: String? = nil) throws {
        let fm = FileManager.default

        guard try (url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
        else {
            throw SkillError.failedAddSyncSkillFolder("Cannot add skill folder: path is not a directory: " + url.path)
        }

        let standardizedURL = url.standardized

        // Check if already added
        let existingURLs = skillDirs.getResolvedSyncSkillFolderURLs()
        if existingURLs.contains(standardizedURL) { return }

        let baseName = alias ?? standardizedURL.lastPathComponent
        var linkName = baseName
        var linkURL = skillDirs.sync.appendingPathComponent(linkName)
        var counter = 0

        while fm.fileExists(atPath: linkURL.path) {
            counter += 1
            linkName = "\(baseName)-\(counter)"
            linkURL = skillDirs.sync.appendingPathComponent(linkName)
        }

        do {
            try fm.createSymbolicLink(at: linkURL, withDestinationURL: standardizedURL)
            logger.info("🔗 Created symbolic link: \(linkName) -> \(standardizedURL.path)")
        } catch {
            throw SkillError.failedAddSyncSkillFolder("Failed to create symbolic link: \(error.localizedDescription)")
        }
    }

    func removeSyncSkillFolder(url: URL) throws {
        let fm = FileManager.default
        let resolvedURL = url.resolvingSymlinksInPath().standardized

        guard let entries = try? fm.contentsOfDirectory(
            at: skillDirs.sync,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        ) else { return }

        for entry in entries {
            if entry.resolvingSymlinksInPath().standardized == resolvedURL {
                try fm.removeItem(at: entry)
                logger.info("🗑️ Removed symbolic link: \(entry.lastPathComponent)")
                return
            }
        }
    }
}
