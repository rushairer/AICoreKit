public enum AIAvailability: Sendable, Equatable {
    case available
    case unavailable(AIUnavailabilityReason)
}

public enum AIUnavailabilityReason: Sendable, Equatable {
    case unsupportedPlatform
    case frameworkUnavailable
    case deviceUnsupported
    case featureDisabled
    case modelNotReady
    case modelMissing
    case networkUnavailable
    case authenticationMissing
    case authenticationExpired
    case localeUnsupported
    case quotaExceeded
    case serviceUnavailable
    case unsupportedCapability
    case unknown(String? = nil)
}
