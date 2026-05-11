import Yams

struct SkillData: Codable {
    enum Visibility: String, Codable {
        case hidden
        case toggled
        case visible
    }

    struct Metadata: Codable {
        var displayName: String?
        var icon: String?
        var color: String?
        var visibility: Visibility?
        var pinned: Bool?
        var disabled: Bool?
        var sendDirectly: Bool?
        var outputDir: String?
        var placeholder: String?
    }

    struct Frontmatter: Codable {
        var name: String
        var description: String
        var disabled: Bool?
        var metadata: Metadata?

        mutating func ensureMetadata() {
            if metadata == nil {
                metadata = Metadata()
            }
        }

        mutating func syncDisabledState() {
            let resolvedDisabled = metadata?.disabled ?? disabled
            disabled = resolvedDisabled == true ? true : nil
            if resolvedDisabled != nil {
                ensureMetadata()
                metadata?.disabled = resolvedDisabled
            }
        }
    }

    var frontmatter: Frontmatter
    var content: String
}

struct SkillEncoder {
    func encode(_ data: SkillData) throws -> String {
        let encoder = YAMLEncoder()
        var frontmatter = data.frontmatter
        frontmatter.syncDisabledState()
        let yaml = try encoder.encode(frontmatter)
        return "---\n\(yaml)---\n\(data.content)"
    }
}

struct SkillDecoder {
    func decode(_ data: String) throws -> SkillData {
        guard data.hasPrefix("---\n") else {
            throw DecodeError.missingFrontmatter
        }

        // Find the closing "---" of frontmatter (must be on its own line)
        // Skip the opening "---\n" (4 characters) and search for "\n---\n" or "\n---" at EOF
        let searchStart = data.index(data.startIndex, offsetBy: 4)
        guard let closingRange = data.range(of: "\n---\n", range: searchStart ..< data.endIndex)
            ?? data.range(of: "\n---", range: searchStart ..< data.endIndex)
        else {
            throw DecodeError.missingFrontmatter
        }

        let frontmatterYAML = String(data[searchStart ..< closingRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let frontmatter: SkillData.Frontmatter
        do {
            let decoder = YAMLDecoder()
            var decodedFrontmatter = try decoder.decode(SkillData.Frontmatter.self, from: frontmatterYAML)
            decodedFrontmatter.syncDisabledState()
            frontmatter = decodedFrontmatter
        } catch {
            throw DecodeError.invalidFrontmatter(error)
        }

        // Content starts after the closing "---\n"
        let contentStart = closingRange.upperBound
        let content = contentStart < data.endIndex ? String(data[contentStart...]) : ""

        return SkillData(frontmatter: frontmatter, content: content)
    }

    enum DecodeError: Error, LocalizedError {
        case missingFrontmatter
        case invalidFrontmatter(Error)

        var errorDescription: String? {
            switch self {
            case .missingFrontmatter:
                String(localized: "Missing frontmatter")
            case let .invalidFrontmatter(error):
                String(localized: "Invalid frontmatter: \(error.localizedDescription)")
            }
        }
    }
}
