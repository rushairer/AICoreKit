public enum AIError: Error, Sendable, Equatable {
    case unavailable(AIUnavailabilityReason)
    case unsupportedCapability
    case invalidRequest(String)
    case authenticationFailed
    case rateLimited
    case transportFailure(String)
    case decodingFailure(String)
    case toolExecutionFailed(String)
    case toolConfirmationRequired(
        toolName: String,
        callID: String
    )
    case toolConfirmationDenied(
        toolName: String,
        callID: String
    )
    case cancelled
    case exhaustedProviders
    case providerFailure(providerID: AIProviderID, message: String)
}
