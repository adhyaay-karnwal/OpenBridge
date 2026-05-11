import Foundation

enum PromptCategory: String, Codable {
    case chatSystemPrompt
    case functionToolPrompt
    case agentSystemPrompt
    case agentToolPrompt

    var displayName: String {
        switch self {
        case .chatSystemPrompt: "Chat System Prompt"
        case .functionToolPrompt: "Function Tool Prompt"
        case .agentSystemPrompt: "Agent System Prompt"
        case .agentToolPrompt: "Agent Tool Prompt"
        }
    }
}

struct PromptTemplate: Identifiable, Codable {
    var id: UUID = .init()
    var key: String
    var category: PromptCategory
    var displayName: String // for UI display
    var content: String
}
