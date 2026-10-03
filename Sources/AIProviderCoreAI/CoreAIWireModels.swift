import AICore

struct CoreAIWireRequest: Encodable, Sendable {
    let messages: [CoreAIWireMessage]
    let maxOutputTokens: Int?
    let temperature: Double?
    let metadata: [String: String]
    let structuredSchema:
        CoreAIWireStructuredSchema?
}

struct CoreAIWireStructuredSchema:
    Encodable,
    Sendable
{
    let name: String
    let description: String?
    let schemaJSON: String
    let strict: Bool
}

struct CoreAIWireMessage: Encodable, Sendable {
    let role: String
    let content: String
    let name: String?

    init(_ message: AIMessage) {
        role = message.role.rawValue
        content = message.content
        name = message.name
    }

    init(
        role: String,
        content: String,
        name: String? = nil
    ) {
        self.role = role
        self.content = content
        self.name = name
    }
}

struct CoreAIWireResponse: Decodable, Sendable {
    let text: String
    let finishReason: String?
    let inputTokens: Int?
    let outputTokens: Int?
}

extension CoreAIWireResponse {
    var normalizedFinishReason: AIFinishReason {
        switch finishReason {
        case "completed", nil:
            return .completed
        case "maxOutputReached":
            return .maxOutputReached
        case "blocked":
            return .blocked
        case "cancelled":
            return .cancelled
        case "failed":
            return .failed
        default:
            return .completed
        }
    }
}
