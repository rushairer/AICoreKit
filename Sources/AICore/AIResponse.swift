public enum AIFinishReason: String, Hashable, Sendable, Codable {
    case completed
    case toolCallRequested
    case maxOutputReached
    case blocked
    case cancelled
    case failed
}

public struct AIUsage: Hashable, Sendable, Codable {
    public let inputTokens: Int?
    public let outputTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct AIResponse: Sendable {
    public let text: String
    public let toolCalls: [AIToolCall]
    public let providerID: AIProviderID
    public let finishReason: AIFinishReason
    public let usage: AIUsage?
    public let continuation: AIToolContinuation?

    public init(
        text: String,
        toolCalls: [AIToolCall] = [],
        providerID: AIProviderID,
        finishReason: AIFinishReason = .completed,
        usage: AIUsage? = nil,
        continuation: AIToolContinuation? = nil
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.providerID = providerID
        self.finishReason = finishReason
        self.usage = usage
        self.continuation = continuation
    }
}
