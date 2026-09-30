import AICore
import Foundation

public struct GeminiProviderConfiguration: Sendable {
    public let providerID: AIProviderID
    public let displayName: String
    public let model: String
    public let baseURL: URL
    public let apiVersion: String
    public let interactionsPath: String
    public let timeout: TimeInterval
    public let defaultMaxOutputTokens: Int?
    public let defaultTemperature: Double?
    public let apiKeyHeaderName: String
    public let storeInteractions: Bool

    public init(
        providerID: AIProviderID = .gemini,
        displayName: String = "Gemini",
        model: String,
        baseURL: URL = URL(
            string: "https://generativelanguage.googleapis.com"
        )!,
        apiVersion: String = "v1beta",
        interactionsPath: String = "interactions",
        timeout: TimeInterval = 60,
        defaultMaxOutputTokens: Int? = nil,
        defaultTemperature: Double? = nil,
        apiKeyHeaderName: String = "x-goog-api-key",
        storeInteractions: Bool = false
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.model = model
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.interactionsPath = interactionsPath
        self.timeout = timeout
        self.defaultMaxOutputTokens = defaultMaxOutputTokens
        self.defaultTemperature = defaultTemperature
        self.apiKeyHeaderName = apiKeyHeaderName
        self.storeInteractions = storeInteractions
    }
}
