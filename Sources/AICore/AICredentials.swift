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


public struct ClosureAICredentialProvider:
    AICredentialProviding
{
    public typealias Handler =
        @Sendable (
            AICredentialRequest
        ) async throws -> String?

    private let handler: Handler

    public init(
        handler: @escaping Handler
    ) {
        self.handler = handler
    }

    public func credential(
        for request: AICredentialRequest
    ) async throws -> String? {
        try await handler(request)
    }
}
