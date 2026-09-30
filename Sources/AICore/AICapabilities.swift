public struct AICapabilities: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let textGeneration = Self(rawValue: 1 << 0)
    public static let structuredGeneration = Self(rawValue: 1 << 1)
    public static let toolCalling = Self(rawValue: 1 << 2)
    public static let streaming = Self(rawValue: 1 << 3)
    public static let localExecution = Self(rawValue: 1 << 4)
    public static let remoteExecution = Self(rawValue: 1 << 5)
    public static let requiresNetwork = Self(rawValue: 1 << 6)
    public static let privacyPreferred = Self(rawValue: 1 << 7)
    public static let imageInput = Self(rawValue: 1 << 8)
    public static let audioInput = Self(rawValue: 1 << 9)
    public static let embeddings = Self(rawValue: 1 << 10)

    public func satisfies(_ required: Self) -> Bool {
        intersection(required) == required
    }
}
