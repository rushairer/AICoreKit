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
