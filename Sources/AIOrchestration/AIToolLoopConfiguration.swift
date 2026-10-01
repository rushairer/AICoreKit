public struct AIToolLoopConfiguration:
    Hashable,
    Sendable
{
    public let maximumRounds: Int

    public init(maximumRounds: Int = 8) {
        self.maximumRounds = max(0, maximumRounds)
    }
}
