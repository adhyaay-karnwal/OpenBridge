import Foundation

/// Local agent configuration exposed to the chat UI.
struct LocalAgentConfig: Decodable {
    let agentGroupId: String
    let agentId: String
    let systemReminder: String?
    let availableTemplates: [LocalAgentAvailableTemplate]

    private enum CodingKeys: String, CodingKey {
        case agentGroupId = "agent_group_id"
        case agentId = "agent_id"
        case systemReminder = "system_reminder"
        case availableTemplates = "available_templates"
    }

    init(
        agentGroupId: String,
        agentId: String,
        systemReminder: String?,
        availableTemplates: [LocalAgentAvailableTemplate]
    ) {
        self.agentGroupId = agentGroupId
        self.agentId = agentId
        self.systemReminder = systemReminder
        self.availableTemplates = availableTemplates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agentGroupId = try container.decode(String.self, forKey: .agentGroupId)
        agentId = try container.decode(String.self, forKey: .agentId)
        systemReminder = try container.decodeIfPresent(String.self, forKey: .systemReminder)
        availableTemplates = try container.decodeIfPresent([LocalAgentAvailableTemplate].self, forKey: .availableTemplates) ?? []
    }
}

struct LocalAgentAvailableTemplate: Decodable {
    let templateId: String
    let name: String
    let model: String
    let providerType: String?

    private enum CodingKeys: String, CodingKey {
        case templateId = "template_id"
        case name
        case model
        case providerType = "provider_type"
    }
}
