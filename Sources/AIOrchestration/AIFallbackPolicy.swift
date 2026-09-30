import AICore

public struct AIFallbackPolicy: Hashable, Sendable {
    public let allowsFallback: Bool
    public let maximumProviderAttempts: Int?

    public init(
        allowsFallback: Bool = true,
        maximumProviderAttempts: Int? = nil
    ) {
        self.allowsFallback = allowsFallback
        self.maximumProviderAttempts = maximumProviderAttempts
    }

    public static let enabled = Self()
    public static let disabled = Self(allowsFallback: false, maximumProviderAttempts: 1)
}
