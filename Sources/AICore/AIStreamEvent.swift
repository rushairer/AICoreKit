public enum AIStreamEvent: Sendable {
    case textDelta(String)
    case toolCall(AIToolCall)
    case usage(AIUsage)
    case completed(AIResponse)
}

public typealias AIResponseStream = AsyncThrowingStream<AIStreamEvent, Error>
