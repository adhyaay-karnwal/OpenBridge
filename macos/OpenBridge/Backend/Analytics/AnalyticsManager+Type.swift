// MARK: - String Extension for Snake Case Conversion

private extension String {
    func camelCaseToSnakeCase() -> String {
        unicodeScalars.reduce("") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar) {
                return result + "_" + String(scalar).lowercased()
            }
            return result + String(scalar)
        }
    }
}

// MARK: - Analytics Types

extension AnalyticsManager {
    enum Where: Hashable, Codable, Equatable {
        case chat
        case mainWindow
        case app
    }

    enum Action: Hashable, Codable, Equatable {
        // MARK: - App Lifecycle

        case appLaunched
        case appUpdateChecked
        case appUpdateInstalled

        // MARK: - Account

        case accountProfileUpdated

        // MARK: - Chat

        case chatMessageSent(attachmentCount: Int? = nil)
        case chatStopped
        case chatConversationCreated
        case chatConversationDeleted
        case chatConversationSwitched
        case chatAttachmentAdded(
            source: String,
            attachmentType: String,
            fileSize: Int? = nil,
            contentType: String? = nil
        )
        case chatAttachmentUploaded(
            success: Bool,
            attachmentType: String? = nil,
            fileSize: Int? = nil,
            duration: Double? = nil
        )
        case chatModelChanged(from: String, to: String)
        case chatMessageRetried(messageId: String)
        case chatGoodMessage(userMessageId: String)
        case chatBadMessage(userMessageId: String)

        // MARK: - Agent

        case agentTaskStarted(taskName: String, model: String)
        case agentTaskCompleted(
            taskName: String,
            success: Bool,
            durationMs: Int64,
            toolsUsedCount: Int
        )
        case agentTaskCancelled(taskName: String, reason: String)
        case agentTaskAccepted(taskId: String)
        case agentTaskRejected(taskId: String)
        case agentFilesAccepted(fileCount: Int)
        case agentFilesDiscarded(fileCount: Int)
        case agentFilePreview(source: String)

        // MARK: - Window

        case windowOpened(kind: String)
        case windowClosed(kind: String)

        // MARK: - Skill

        case skillImported(
            name: String,
            source: String,
            webDistinctId: String? = nil
        )
        case skillActivated(name: String)
        case skillDeleted(name: String)
        case skillToggled(name: String, enabled: Bool)

        // MARK: - Pinned Skill

        case pinnedSkillClicked(name: String)

        // MARK: - Shortcut

        case shortcutTriggered(shortcutKey: String)

        // MARK: - UI Menus

        case contextMenuAction(action: String)
        case trayMenuAction(action: String)

        // MARK: - Settings

        case settingsFeatureToggled(feature: String, enabled: Bool)
        case settingsAppearanceChanged(appearance: String)
        case settingsAccentColorChanged(color: String)
        case settingsShortcutChanged(shortcutKey: String, newShortcut: String?)
        case settingsShortcutsReset
        case settingsMemoriesCleared

        // MARK: - Agent Quality

        case agentError(errorType: String, errorMessage: String)
        case agentToolUsed(toolName: String, success: Bool)

        // MARK: - Performance

        case chatFirstTokenTime(durationMs: Int64)
        case vmBootTime(durationMs: Int64)
        case apiLatency(endpoint: String, durationMs: Int64)

        // MARK: - Session

        case sessionStarted
        case sessionEnded(durationSec: Int64)
        case chatConversationTurnCount(turns: Int)
        case copyFromChat(contentType: String)

        // MARK: - Event Name

        var name: String {
            let caseName = Mirror(reflecting: self).children.first?.label ?? String(describing: self)
            return caseName.camelCaseToSnakeCase()
        }

        // MARK: - Additional Properties

        var additionalProperties: [String: Any] {
            switch self {
            // Chat
            case let .chatMessageSent(attachmentCount):
                return ["attachmentCount": attachmentCount ?? 0]
            case let .chatAttachmentAdded(source, attachmentType, fileSize, contentType):
                var props: [String: Any] = [
                    "source": source,
                    "attachmentType": attachmentType,
                ]
                if let fileSize { props["fileSize"] = fileSize }
                if let contentType { props["contentType"] = contentType }
                return props
            case let .chatAttachmentUploaded(success, attachmentType, fileSize, duration):
                var props: [String: Any] = ["success": success]
                if let attachmentType { props["attachmentType"] = attachmentType }
                if let fileSize { props["fileSize"] = fileSize }
                if let duration { props["duration"] = duration }
                return props
            case let .chatModelChanged(from, to):
                return ["from": from, "to": to]
            case let .chatMessageRetried(messageId):
                return ["messageId": messageId]
            case let .chatGoodMessage(userMessageId):
                return ["userMessageId": userMessageId]
            case let .chatBadMessage(userMessageId):
                return ["userMessageId": userMessageId]
            // Agent
            case let .agentTaskStarted(taskName, model):
                return ["taskName": taskName, "model": model]
            case let .agentTaskCompleted(taskName, success, durationMs, toolsUsedCount):
                return [
                    "taskName": taskName,
                    "success": success,
                    "durationMs": durationMs,
                    "toolsUsedCount": toolsUsedCount,
                ]
            case let .agentTaskCancelled(taskName, reason):
                return ["taskName": taskName, "reason": reason]
            case let .agentTaskAccepted(taskId):
                return ["taskId": taskId]
            case let .agentTaskRejected(taskId):
                return ["taskId": taskId]
            case let .agentFilesAccepted(fileCount):
                return ["fileCount": fileCount]
            case let .agentFilesDiscarded(fileCount):
                return ["fileCount": fileCount]
            case let .agentFilePreview(source):
                return ["source": source]
            // Window
            case let .windowOpened(kind):
                return ["kind": kind]
            case let .windowClosed(kind):
                return ["kind": kind]
            // Skill
            case let .skillImported(name, source, webDistinctId):
                var props: [String: Any] = [
                    "name": name,
                    "source": source,
                ]
                if let webDistinctId { props["webDistinctId"] = webDistinctId }
                return props
            case let .skillActivated(name):
                return ["name": name]
            case let .skillDeleted(name):
                return ["name": name]
            case let .skillToggled(name, enabled):
                return ["name": name, "enabled": enabled]
            // Pinned Skill
            case let .pinnedSkillClicked(name):
                return ["name": name]
            // Shortcut
            case let .shortcutTriggered(shortcutKey):
                return ["shortcutKey": shortcutKey]
            // UI Menus
            case let .contextMenuAction(action):
                return ["action": action]
            case let .trayMenuAction(action):
                return ["action": action]
            // Settings
            case let .settingsFeatureToggled(feature, enabled):
                return ["feature": feature, "enabled": enabled]
            case let .settingsAppearanceChanged(appearance):
                return ["appearance": appearance]
            case let .settingsAccentColorChanged(color):
                return ["color": color]
            case let .settingsShortcutChanged(shortcutKey, newShortcut):
                return ["shortcutKey": shortcutKey, "newShortcut": newShortcut ?? "disabled"]
            // Agent Quality
            case let .agentError(errorType, errorMessage):
                return ["errorType": errorType, "errorMessage": errorMessage]
            case let .agentToolUsed(toolName, success):
                return ["toolName": toolName, "success": success]
            // Performance
            case let .chatFirstTokenTime(durationMs):
                return ["durationMs": durationMs]
            case let .vmBootTime(durationMs):
                return ["durationMs": durationMs]
            case let .apiLatency(endpoint, durationMs):
                return ["endpoint": endpoint, "durationMs": durationMs]
            // Session
            case let .sessionEnded(durationSec):
                return ["durationSec": durationSec]
            case let .chatConversationTurnCount(turns):
                return ["turns": turns]
            case let .copyFromChat(contentType):
                return ["contentType": contentType]
            default:
                return [:]
            }
        }
    }

    struct Event {
        let action: Action
        let location: Where
        let properties: [String: Any]

        init(do: Action, at: Where? = nil, with: [String: Any] = [:]) {
            action = `do`
            location = at ?? .app
            properties = with
        }

        func toName() -> String {
            action.name
        }

        func toDict() -> [String: Any] {
            properties
                .merging(action.additionalProperties) { _, new in new }
                .merging(["location": String(describing: location)]) { _, new in new }
        }
    }
}
