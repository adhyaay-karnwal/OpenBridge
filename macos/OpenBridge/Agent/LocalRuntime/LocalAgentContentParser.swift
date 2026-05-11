import Foundation

enum LocalAgentContentParser {
    private static let emptyPlaceholder = "<empty/>"
    private static let imageReferenceLineRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"^\s*\[type:"image"\s+env:"((?:\\.|[^"\\])*)"\s+path:"((?:\\.|[^"\\])*)"\]\s*$"#
            )
        } catch {
            fatalError("Failed to build image reference regex: \(error)")
        }
    }()

    private static let quoteReferenceLineRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"^\s*<quote\s+source-message-id="([^"]+)"\s+start="(\d+)"\s+end="(\d+)">([\s\S]*)</quote>\s*$"#
            )
        } catch {
            fatalError("Failed to build quote reference regex: \(error)")
        }
    }()

    static func parse(_ raw: String?) -> [SessionHistoryMessage.Content]? {
        guard let raw, !raw.isEmpty else {
            return nil
        }

        if let jsonContent = parseJSONContentBlocks(raw) {
            return jsonContent
        }

        let lineContent = parseReferenceLines(raw)
        if !lineContent.isEmpty {
            return lineContent
        }

        guard let sanitizedText = sanitizeText(raw) else {
            return []
        }

        return [makeTextContent(sanitizedText)]
    }

    private static func parseJSONContentBlocks(_ raw: String) -> [SessionHistoryMessage.Content]? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        if let array = json as? [Any] {
            return array.compactMap(normalizeContentBlock).flatMap(expandTextBlock)
        }

        if let object = json as? [String: Any] {
            if let normalized = normalizeContentBlock(object) {
                return expandTextBlock(normalized)
            }
            if let text = object["text"] as? String {
                guard let sanitizedText = sanitizeText(text) else {
                    return []
                }
                return expandTextBlock(makeTextContent(sanitizedText))
            }
        }

        return nil
    }

    /// If a text block contains embedded image references, split it into text + image blocks.
    private static func expandTextBlock(_ block: SessionHistoryMessage.Content) -> [SessionHistoryMessage.Content] {
        guard block.type == "text", let text = block.text else {
            return [block]
        }

        let parsed = parseReferenceLines(text)
        // Only expand if at least one non-text block was found.
        let hasStructuredContent = parsed.contains { $0.type != "text" }
        return hasStructuredContent ? parsed : [block]
    }

    private static func normalizeContentBlock(_ raw: Any) -> SessionHistoryMessage.Content? {
        guard let object = raw as? [String: Any] else {
            return nil
        }

        let type = (object["type"] as? String) ?? "text"
        let text = object["text"] as? String
        let url = object["url"] as? String
        let rawFileRefs = normalizeFileRefs(object["fileRefs"] ?? object["file_refs"])
        let rawFileRef = normalizeFileRef(object["fileRef"] ?? object["file_ref"])
        let fileRefs = LocalAgentAttachmentFileRefs.mergedFileRefs(
            primary: rawFileRef,
            fileRefs: rawFileRefs
        )
        let fileRef = LocalAgentAttachmentFileRefs.primaryDisplayFileRef(
            primary: rawFileRef,
            mergedFileRefs: fileRefs
        )
        let fileName = (object["fileName"] as? String) ?? (object["file_name"] as? String)
        let mimeType = (object["mimeType"] as? String) ?? (object["mime_type"] as? String)
        let sizeBytes = (object["sizeBytes"] as? NSNumber)?.int64Value ?? (object["size_bytes"] as? NSNumber)?.int64Value
        let entryKind = (object["entryKind"] as? String) ?? (object["entry_kind"] as? String)
        let quoteRef = normalizeQuoteRef(object["quoteRef"] ?? object["quote_ref"])

        if type == "text", let text, quoteRef == nil {
            guard let sanitizedText = sanitizeText(text) else {
                return nil
            }
            return makeTextContent(sanitizedText)
        }

        return SessionHistoryMessage.Content(
            type: type,
            text: text,
            url: LocalAgentAttachmentFileRefs.browserAttachmentURL(
                existingURL: url,
                entryKind: entryKind,
                mergedFileRefs: fileRefs
            ),
            fileRef: fileRef,
            fileRefs: fileRefs.isEmpty ? nil : fileRefs,
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            entryKind: entryKind,
            quoteRef: quoteRef
        )
    }

    private static func normalizeFileRef(_ raw: Any?) -> SessionHistoryMessage.FileRef? {
        guard let object = raw as? [String: Any],
              let path = object["path"] as? String
        else {
            return nil
        }

        let environmentId = (object["environmentId"] as? String) ?? (object["environment_id"] as? String)
        return SessionHistoryMessage.FileRef(environmentId: environmentId, path: path)
    }

    private static func normalizeFileRefs(_ raw: Any?) -> [SessionHistoryMessage.FileRef]? {
        guard let array = raw as? [Any] else {
            return nil
        }

        let refs = array.compactMap(normalizeFileRef)
        return refs.isEmpty ? nil : refs
    }

    private static func normalizeQuoteRef(_ raw: Any?) -> SessionHistoryMessage.QuoteReference? {
        guard let object = raw as? [String: Any],
              let sourceMessageId = (object["sourceMessageId"] as? String) ?? (object["source_message_id"] as? String),
              let startOffset = normalizeInt(object["startOffset"] ?? object["start_offset"]),
              let endOffset = normalizeInt(object["endOffset"] ?? object["end_offset"])
        else {
            return nil
        }

        return SessionHistoryMessage.QuoteReference(
            sourceMessageId: sourceMessageId,
            startOffset: startOffset,
            endOffset: endOffset
        )
    }

    private static func parseReferenceLines(_ raw: String) -> [SessionHistoryMessage.Content] {
        let lines = raw.components(separatedBy: "\n")
        var content: [SessionHistoryMessage.Content] = []
        var bufferedTextLines: [String] = []

        func flushBufferedText() {
            let text = bufferedTextLines.joined(separator: "\n")
            if let sanitizedText = sanitizeText(text) {
                content.append(makeTextContent(sanitizedText))
            }
            bufferedTextLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if let imageContent = parseImageReferenceLine(line) {
                flushBufferedText()
                content.append(imageContent)
                continue
            }

            if let quoteContent = parseQuoteReferenceLine(line) {
                flushBufferedText()
                content.append(quoteContent)
                continue
            }

            bufferedTextLines.append(line)
        }

        flushBufferedText()
        return content
    }

    private static func parseImageReferenceLine(_ rawLine: String) -> SessionHistoryMessage.Content? {
        let range = NSRange(rawLine.startIndex..., in: rawLine)
        guard let match = imageReferenceLineRegex.firstMatch(in: rawLine, range: range),
              match.range.location != NSNotFound,
              match.range.length == range.length
        else {
            return nil
        }

        guard let environmentRange = Range(match.range(at: 1), in: rawLine),
              let pathRange = Range(match.range(at: 2), in: rawLine)
        else {
            return nil
        }

        let environmentId = unescapeReferenceComponent(String(rawLine[environmentRange]))
        let filePath = unescapeReferenceComponent(String(rawLine[pathRange]))
        let fileURL = URL(fileURLWithPath: (filePath as NSString).expandingTildeInPath)
        let mimeType = fileURL.detectedMimeType() ?? "image/jpeg"
        let fileName = fileURL.lastPathComponent.isEmpty ? nil : fileURL.lastPathComponent

        return SessionHistoryMessage.Content(
            type: "image",
            text: nil,
            url: localFileDataURL(for: fileURL, mimeType: mimeType),
            fileRef: .init(environmentId: environmentId, path: filePath),
            fileName: fileName,
            mimeType: mimeType
        )
    }

    private static func parseQuoteReferenceLine(_ rawLine: String) -> SessionHistoryMessage.Content? {
        let range = NSRange(rawLine.startIndex..., in: rawLine)
        guard let match = quoteReferenceLineRegex.firstMatch(in: rawLine, range: range),
              match.range.location != NSNotFound,
              match.range.length == range.length
        else {
            return nil
        }

        guard let sourceMessageIdRange = Range(match.range(at: 1), in: rawLine),
              let startOffsetRange = Range(match.range(at: 2), in: rawLine),
              let endOffsetRange = Range(match.range(at: 3), in: rawLine),
              let textRange = Range(match.range(at: 4), in: rawLine),
              let startOffset = Int(rawLine[startOffsetRange]),
              let endOffset = Int(rawLine[endOffsetRange])
        else {
            return nil
        }

        return SessionHistoryMessage.Content(
            type: "quote",
            text: unescapeQuoteText(String(rawLine[textRange])),
            quoteRef: .init(
                sourceMessageId: String(rawLine[sourceMessageIdRange]),
                startOffset: startOffset,
                endOffset: endOffset
            )
        )
    }

    private static func localFileDataURL(for fileURL: URL, mimeType: String) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return data.dataURL(mimeType: mimeType)
    }

    private static func makeTextContent(_ text: String) -> SessionHistoryMessage.Content {
        SessionHistoryMessage.Content(
            type: "text",
            text: text,
            url: nil,
            fileRef: nil,
            fileName: nil,
            mimeType: nil
        )
    }

    private static func sanitizeText(_ text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, trimmedText != emptyPlaceholder else {
            return nil
        }
        return text
    }

    private static func normalizeInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }

    private static func unescapeQuoteText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&#10;", with: "\n")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func unescapeReferenceComponent(_ value: String) -> String {
        var result = ""
        var isEscaping = false

        for character in value {
            if isEscaping {
                result.append(character)
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                result.append(character)
            }
        }

        if isEscaping {
            result.append("\\")
        }

        return result
    }
}
