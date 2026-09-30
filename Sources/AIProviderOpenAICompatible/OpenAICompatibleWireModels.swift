import AICore

struct OpenAICompatibleChatRequest: Encodable, Sendable {
    let model: String
    let messages: [OpenAICompatibleMessage]
    let maxTokens: Int?
    let temperature: Double?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case stream
    }
}

struct OpenAICompatibleMessage: Encodable, Sendable {
    let role: String
    let content: String
    let name: String?

    init(_ message: AIMessage) throws {
        guard message.role != .tool else {
            throw AIError.unsupportedCapability
        }

        role = message.role.rawValue
        content = message.content
        name = message.name
    }
}

struct OpenAICompatibleChatResponse: Decodable, Sendable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable, Sendable {
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable, Sendable {
        let content: String?
    }

    struct Usage: Decodable, Sendable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}

struct OpenAICompatibleChatChunk: Decodable, Sendable {
    let choices: [Choice]
    let usage: OpenAICompatibleChatResponse.Usage?

    struct Choice: Decodable, Sendable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable, Sendable {
        let content: String?
    }
}

struct OpenAICompatibleErrorEnvelope: Decodable, Sendable {
    let error: APIError?

    struct APIError: Decodable, Sendable {
        let message: String?
    }
}
