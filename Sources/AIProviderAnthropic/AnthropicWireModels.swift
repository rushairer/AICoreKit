import AICore

struct AnthropicMessageRequest: Encodable, Sendable {
    let model: String
    let maxTokens: Int
    let messages: [AnthropicMessage]
    let system: String?
    let temperature: Double?
    let stream: Bool
    let outputConfig: OutputConfiguration?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
        case temperature
        case stream
        case outputConfig = "output_config"
    }

    struct OutputConfiguration: Encodable, Sendable {
        let format: Format

        struct Format: Encodable, Sendable {
            let type: String
            let schema: AIJSONValue

            init(schema: AIStructuredOutputSchema) {
                type = "json_schema"
                self.schema = schema.schema
            }
        }

        init(schema: AIStructuredOutputSchema) {
            format = Format(schema: schema)
        }
    }
}

struct AnthropicMessage: Encodable, Sendable {
    let role: String
    let content: String

    init(_ message: AIMessage) throws {
        switch message.role {
        case .user, .assistant:
            role = message.role.rawValue
            content = message.content
        case .system, .tool:
            throw AIError.unsupportedCapability
        }
    }
}

struct AnthropicMessageResponse: Decodable, Sendable {
    let content: [ContentBlock]
    let stopReason: String?
    let usage: AnthropicUsage?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case usage
    }

    struct ContentBlock: Decodable, Sendable {
        let type: String
        let text: String?
    }
}

struct AnthropicUsage: Decodable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct AnthropicStreamEnvelope: Decodable, Sendable {
    let type: String
    let message: Message?
    let delta: Delta?
    let usage: AnthropicUsage?
    let error: AnthropicAPIError?

    struct Message: Decodable, Sendable {
        let usage: AnthropicUsage?
    }

    struct Delta: Decodable, Sendable {
        let type: String?
        let text: String?
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case stopReason = "stop_reason"
        }
    }
}

struct AnthropicErrorEnvelope: Decodable, Sendable {
    let error: AnthropicAPIError?
}

struct AnthropicAPIError: Decodable, Sendable {
    let type: String?
    let message: String?
}
