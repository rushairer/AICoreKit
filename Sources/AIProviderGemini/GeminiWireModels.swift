import AICore

struct GeminiGenerateContentRequest: Encodable, Sendable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent?
    let generationConfig: GeminiGenerationConfig?

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction
        case generationConfig
    }
}

struct GeminiContent: Codable, Sendable {
    let role: String?
    let parts: [GeminiPart]

    init(role: String?, text: String) {
        self.role = role
        self.parts = [GeminiPart(text: text)]
    }

    init(_ message: AIMessage) throws {
        switch message.role {
        case .user:
            role = "user"
        case .assistant:
            role = "model"
        case .system, .tool:
            throw AIError.unsupportedCapability
        }

        parts = [GeminiPart(text: message.content)]
    }
}

struct GeminiPart: Codable, Sendable {
    let text: String?
}

struct GeminiGenerationConfig: Encodable, Sendable {
    let maxOutputTokens: Int?
    let temperature: Double?

    enum CodingKeys: String, CodingKey {
        case maxOutputTokens
        case temperature
    }

    var isEmpty: Bool {
        maxOutputTokens == nil && temperature == nil
    }
}

struct GeminiGenerateContentResponse: Decodable, Sendable {
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let usageMetadata: UsageMetadata?

    struct Candidate: Decodable, Sendable {
        let content: GeminiContent?
        let finishReason: String?
    }

    struct PromptFeedback: Decodable, Sendable {
        let blockReason: String?
    }

    struct UsageMetadata: Decodable, Sendable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let totalTokenCount: Int?
    }
}

struct GeminiErrorEnvelope: Decodable, Sendable {
    let error: APIError?

    struct APIError: Decodable, Sendable {
        let code: Int?
        let message: String?
        let status: String?
    }
}


struct GeminiInteractionRequest: Encodable, Sendable {
    let model: String
    let input: String
    let systemInstruction: String?
    let responseFormat: ResponseFormat
    let store: Bool
    let generationConfig: GenerationConfiguration?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case systemInstruction = "system_instruction"
        case responseFormat = "response_format"
        case store
        case generationConfig = "generation_config"
    }

    struct ResponseFormat: Encodable, Sendable {
        let type: String
        let mimeType: String
        let schema: AIJSONValue

        enum CodingKeys: String, CodingKey {
            case type
            case mimeType = "mime_type"
            case schema
        }

        init(schema: AIStructuredOutputSchema) {
            type = "text"
            mimeType = "application/json"
            self.schema = schema.schema
        }
    }

    struct GenerationConfiguration: Encodable, Sendable {
        let maxOutputTokens: Int?
        let temperature: Double?

        enum CodingKeys: String, CodingKey {
            case maxOutputTokens = "max_output_tokens"
            case temperature
        }

        var isEmpty: Bool {
            maxOutputTokens == nil && temperature == nil
        }
    }
}

struct GeminiInteractionResponse: Decodable, Sendable {
    let status: String
    let steps: [Step]?
    let usage: Usage?

    struct Step: Decodable, Sendable {
        let type: String
        let content: [Content]?
    }

    struct Content: Decodable, Sendable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable, Sendable {
        let totalInputTokens: Int?
        let totalOutputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case totalInputTokens = "total_input_tokens"
            case totalOutputTokens = "total_output_tokens"
        }
    }
}
