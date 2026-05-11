import Foundation

@MainActor
final class PromptManager {
    static let shared = PromptManager()

    private var prompts: [String: PromptTemplate] = [:]

    private init() {
        initializePrompts()
    }

    // MARK: - Template Rendering

    private func getTemplateVariables() -> [String: String] {
        let now = Date()
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .long
        displayFormatter.timeStyle = .short
        displayFormatter.locale = Locale.current
        let formattedDate = displayFormatter.string(from: now)

        let timezone = TimeZone.current
        let timezoneOffset = timezone.secondsFromGMT()
        let hours = timezoneOffset / 3600
        let minutes = abs(timezoneOffset % 3600) / 60
        let timezoneDescription: String
        if minutes == 0 {
            timezoneDescription = hours >= 0
                ? "UTC+\(hours)"
                : "UTC\(hours)"
        } else {
            let sign = hours >= 0 ? "+" : ""
            timezoneDescription = "UTC\(sign)\(hours):\(String(format: "%02d", minutes))"
        }

        let primaryLanguage = SettingsManager.shared.primaryLanguage
        let languageName: String = if !primaryLanguage.isEmpty {
            Locale.current.localizedString(forLanguageCode: primaryLanguage) ?? primaryLanguage
        } else {
            ""
        }

        let userLocation = Locale.current.region?.identifier ?? ""
        let locationName = if !userLocation.isEmpty {
            Locale.current.localizedString(forRegionCode: userLocation) ?? userLocation
        } else {
            ""
        }

        let userHomeDirectory = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path

        return [
            "timezone": timezoneDescription,
            "currentDateTime": formattedDate,
            "userLanguage": languageName,
            "userLocation": locationName,
            "userHomeDirectory": userHomeDirectory,
        ]
    }

    private func renderTemplate(_ template: String, _ customVariables: [String: String] = [:]) -> String {
        var result = template
        for (key, value) in customVariables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        let variables = getTemplateVariables()
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        return result
    }

    // MARK: - Initialize Prompts

    private func initializePrompts() {
        for defaultPrompt in PromptDefaults.allPrompts {
            let key = makeKey(category: defaultPrompt.category, key: defaultPrompt.key)
            prompts[key] = defaultPrompt
        }
    }

    private func makeKey(category: PromptCategory, key: String) -> String {
        "\(category.rawValue).\(key)"
    }

    func getPrompt(category: PromptCategory, key: String) -> PromptTemplate? {
        let compositeKey = makeKey(category: category, key: key)
        return prompts[compositeKey]
    }

    func getPrompts(category: PromptCategory) -> [PromptTemplate] {
        prompts.values.filter { $0.category == category }
    }

    func updatePrompt(prompt: PromptTemplate) {
        let key = makeKey(category: prompt.category, key: prompt.key)
        prompts[key] = prompt
    }

    func resetPrompt(category: PromptCategory, key: String) {
        let compositeKey = makeKey(category: category, key: key)
        if let defaultPrompt = PromptDefaults.allPrompts.first(where: {
            $0.category == category && $0.key == key
        }) {
            prompts[compositeKey] = defaultPrompt
        }
    }

    // MARK: - Rendering Methods

    func renderPrompt(category: PromptCategory, key: String, customVariables: [String: String] = [:]) -> String {
        let prompt = getPrompt(category: category, key: key)
        let template = prompt?.content ?? ""
        return renderTemplate(template, customVariables)
    }

    // MARK: - Convenience Methods

    func renderChatSystemPrompt() -> String {
        renderPrompt(category: .chatSystemPrompt, key: "system")
    }

    func renderAgentSystemPrompt() -> String {
        renderPrompt(category: .agentSystemPrompt, key: "system")
    }

    func renderAgentToolDescription() -> String {
        let skillEntries = SkillManager.shared.skills.map {
            let name = $0.name.count > 20 ? String($0.name.prefix(20)) + "..." : $0.name
            let description = $0.description.count > 100 ? String($0.description.prefix(100)) + "..." : $0.description
            return """
            <skill>
              <name>\(name)</name>
              <description>\(description)</description>
            </skill>
            """
        }
        let skillSection = """
        <available_skills>
        \(skillEntries.joined(separator: "\n"))
        </available_skills>
        """

        return renderPrompt(category: .functionToolPrompt, key: "tool_description", customVariables: ["skills": skillSection])
    }

    func renderFunctionToolDescription(toolName: String) -> String {
        renderPrompt(category: .functionToolPrompt, key: toolName)
    }
}
