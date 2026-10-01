public struct AIToolContinuation:
    Hashable,
    Sendable,
    Codable
{
    public let providerID: AIProviderID
    public let opaqueState: String

    public init(
        providerID: AIProviderID,
        opaqueState: String
    ) {
        self.providerID = providerID
        self.opaqueState = opaqueState
    }
}

public struct AIToolOutput:
    Hashable,
    Sendable,
    Codable
{
    public let callID: String
    public let toolName: String
    public let content: String
    public let isError: Bool

    public init(
        callID: String,
        toolName: String,
        content: String,
        isError: Bool = false
    ) {
        self.callID = callID
        self.toolName = toolName
        self.content = content
        self.isError = isError
    }
}

public protocol AIToolContinuingProvider: AIProvider {
    func continueToolCalls(
        _ continuation: AIToolContinuation,
        outputs: [AIToolOutput]
    ) async throws -> AIResponse
}
