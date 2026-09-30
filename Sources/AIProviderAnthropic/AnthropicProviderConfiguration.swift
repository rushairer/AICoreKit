import AICore
import Foundation

public struct AnthropicProviderConfiguration: Sendable {
    public let providerID: AIProviderID
    public let displayName: String
    public let model: String
    public let baseURL: URL
    public let messagesPath: String
    public let timeout: TimeInterval
    public let defaultMaxOutputTokens: Int
    public let defaultTemperature: Double?
    public let apiVersion: String
    public let apiKeyHeaderName: String
    public let apiVersionHeaderName: String

    public init(
        providerID: AIProviderID = .anthropic,
        displayName: String = "Anthropic",
        model: String,
        baseURL: URL = URL(
            string: "https://api.anthropic.com/v1"
        )!,
        messagesPath: String = "messages",
        timeout: TimeInterval = 60,
        defaultMaxOutputTokens: Int = 1024,
        defaultTemperature: Double? = nil,
        apiVersion: String = "2023-06-01",
        apiKeyHeaderName: String = "x-api-key",
        apiVersionHeaderName: String = "anthropic-version"
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.model = model
        self.baseURL = baseURL
        self.messagesPath = messagesPath
        self.timeout = timeout
        self.defaultMaxOutputTokens = defaultMaxOutputTokens
        self.defaultTemperature = defaultTemperature
        self.apiVersion = apiVersion
        self.apiKeyHeaderName = apiKeyHeaderName
        self.apiVersionHeaderName = apiVersionHeaderName
    }
}
