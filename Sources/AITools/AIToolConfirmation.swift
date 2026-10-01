public enum AIToolConfirmationDecision:
    Hashable,
    Sendable
{
    case approved
    case denied
}

public protocol AIToolConfirmationProviding:
    Sendable
{
    func confirm(
        _ request: AIToolExecutionRequest
    ) async throws -> AIToolConfirmationDecision
}

public struct ClosureAIToolConfirmationProvider:
    AIToolConfirmationProviding
{
    public typealias Handler =
        @Sendable (
            AIToolExecutionRequest
        ) async throws -> AIToolConfirmationDecision

    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func confirm(
        _ request: AIToolExecutionRequest
    ) async throws -> AIToolConfirmationDecision {
        try await handler(request)
    }
}
