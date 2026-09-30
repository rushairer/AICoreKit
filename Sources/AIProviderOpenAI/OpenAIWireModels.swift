import AICore

struct OpenAIResponsesRequest: Encodable, Sendable {
    let model: String
    let input: [InputMessage]
    let maxOutputTokens: Int?
    let temperature: Double?
    let stream: Bool
    let store: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case maxOutputTokens = "max_output_tokens"
        case temperature
        case stream
        case store
    }

    struct InputMessage: Encodable, Sendable {
        let role: String
        let content: String

        init(_ message: AIMessage) throws {
            switch message.role {
            case .system:
                role = "system"
            case .user:
                role = "user"
            case .assistant:
                role = "assistant"
            case .tool:
                throw AIError.unsupportedCapability
            }

            content = message.content
        }
    }
}

struct OpenAIResponseObject: Decodable, Sendable {
    let status: String?
    let output: [OutputItem]?
    let usage: Usage?
    let incompleteDetails: IncompleteDetails?
    let error: ResponseError?

    enum CodingKeys: String, CodingKey {
        case status
        case output
        case usage
        case incompleteDetails = "incomplete_details"
        case error
    }

    struct OutputItem: Decodable, Sendable {
        let type: String
        let role: String?
        let content: [OutputContent]?
    }

    struct OutputContent: Decodable, Sendable {
        let type: String
        let text: String?
        let refusal: String?
    }

    struct Usage: Decodable, Sendable {
        let inputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    struct IncompleteDetails: Decodable, Sendable {
        let reason: String?
    }

    struct ResponseError: Decodable, Sendable {
        let code: String?
        let message: String?
    }
}

struct OpenAIResponsesStreamEvent: Decodable, Sendable {
    let type: String
    let delta: String?
    let response: OpenAIResponseObject?
    let error: OpenAIResponseObject.ResponseError?
}

struct OpenAIErrorEnvelope: Decodable, Sendable {
    let error: APIError?

    struct APIError: Decodable, Sendable {
        let message: String?
        let type: String?
        let code: String?
    }
}
