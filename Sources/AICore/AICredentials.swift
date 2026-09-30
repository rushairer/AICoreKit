public enum AICredentialKind: Hashable, Sendable, Codable {
    case apiKey
    case bearerToken
    case oauthAccessToken
    case custom(String)
}

public struct AICredentialRequest: Hashable, Sendable, Codable {
    public let providerID: AIProviderID
    public let kind: AICredentialKind

    public init(providerID: AIProviderID, kind: AICredentialKind) {
        self.providerID = providerID
        self.kind = kind
    }
}

public protocol AICredentialProviding: Sendable {
    func credential(for request: AICredentialRequest) async throws -> String?
}
