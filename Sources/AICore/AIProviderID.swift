public struct AIProviderID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public extension AIProviderID {
    static let appleFoundationModels: Self = "apple.foundation-models"
    static let coreAI: Self = "apple.core-ai"
    static let openAI: Self = "openai"
    static let anthropic: Self = "anthropic"
    static let gemini: Self = "google.gemini"
    static let openAICompatible: Self = "openai-compatible"
}
