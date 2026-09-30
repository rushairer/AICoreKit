import AICore
import Foundation

public struct OpenAICompatibleProviderConfiguration: Sendable {
    public let providerID: AIProviderID
    public let displayName: String
    public let baseURL: URL
    public let model: String
    public let chatCompletionsPath: String
    public let timeout: TimeInterval
    public let defaultMaxOutputTokens: Int?
    public let defaultTemperature: Double?
    public let credentialKind: AICredentialKind
    public let authorizationHeaderName: String
    public let authorizationPrefix: String?

    public init(
        providerID: AIProviderID = .openAICompatible,
        displayName: String = "OpenAI Compatible",
        baseURL: URL,
        model: String,
        chatCompletionsPath: String = "chat/completions",
        timeout: TimeInterval = 60,
        defaultMaxOutputTokens: Int? = nil,
        defaultTemperature: Double? = nil,
        credentialKind: AICredentialKind = .bearerToken,
        authorizationHeaderName: String = "Authorization",
        authorizationPrefix: String? = "Bearer"
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.baseURL = baseURL
        self.model = model
        self.chatCompletionsPath = chatCompletionsPath
        self.timeout = timeout
        self.defaultMaxOutputTokens = defaultMaxOutputTokens
        self.defaultTemperature = defaultTemperature
        self.credentialKind = credentialKind
        self.authorizationHeaderName = authorizationHeaderName
        self.authorizationPrefix = authorizationPrefix
    }
}
