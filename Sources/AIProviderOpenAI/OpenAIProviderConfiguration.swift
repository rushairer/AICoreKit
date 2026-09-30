import AICore
import Foundation

public struct OpenAIProviderConfiguration: Sendable {
    public let providerID: AIProviderID
    public let displayName: String
    public let model: String
    public let baseURL: URL
    public let responsesPath: String
    public let timeout: TimeInterval
    public let defaultMaxOutputTokens: Int?
    public let defaultTemperature: Double?
    public let authorizationHeaderName: String
    public let authorizationPrefix: String
    public let storeResponses: Bool

    public init(
        providerID: AIProviderID = .openAI,
        displayName: String = "OpenAI",
        model: String,
        baseURL: URL = URL(
            string: "https://api.openai.com/v1"
        )!,
        responsesPath: String = "responses",
        timeout: TimeInterval = 60,
        defaultMaxOutputTokens: Int? = nil,
        defaultTemperature: Double? = nil,
        authorizationHeaderName: String = "Authorization",
        authorizationPrefix: String = "Bearer",
        storeResponses: Bool = false
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.model = model
        self.baseURL = baseURL
        self.responsesPath = responsesPath
        self.timeout = timeout
        self.defaultMaxOutputTokens = defaultMaxOutputTokens
        self.defaultTemperature = defaultTemperature
        self.authorizationHeaderName = authorizationHeaderName
        self.authorizationPrefix = authorizationPrefix
        self.storeResponses = storeResponses
    }
}
