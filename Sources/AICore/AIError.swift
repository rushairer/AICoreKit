public enum AIError: Error, Sendable, Equatable {
    case unavailable(AIUnavailabilityReason)
    case unsupportedCapability
    case invalidRequest(String)
    case authenticationFailed
    case rateLimited
    case transportFailure(String)
    case decodingFailure(String)
    case toolExecutionFailed(String)
    case cancelled
    case exhaustedProviders
    case providerFailure(providerID: AIProviderID, message: String)
}
