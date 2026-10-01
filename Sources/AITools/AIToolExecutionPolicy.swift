public import AICore

public struct AIToolExecutionRequest:
    Hashable,
    Sendable
{
    public let call: AIToolCall
    public let definition: AIToolDefinition

    public init(
        call: AIToolCall,
        definition: AIToolDefinition
    ) {
        self.call = call
        self.definition = definition
    }
}

public enum AIToolExecutionDecision:
    Hashable,
    Sendable
{
    case allow
    case deny(reason: String?)
    case requireConfirmation
}

public protocol AIToolExecutionPolicy: Sendable {
    func decision(
        for request: AIToolExecutionRequest
    ) async -> AIToolExecutionDecision
}

public struct ReadOnlyAIToolExecutionPolicy:
    AIToolExecutionPolicy
{
    public init() {}

    public func decision(
        for request: AIToolExecutionRequest
    ) async -> AIToolExecutionDecision {
        guard
            request.definition.sideEffectLevel == .readOnly
        else {
            return .deny(
                reason:
                    "Only read-only tools are allowed by this policy"
            )
        }

        if request.definition.requiresUserConfirmation {
            return .requireConfirmation
        }

        return .allow
    }
}

public struct UserConfirmationAIToolExecutionPolicy:
    AIToolExecutionPolicy
{
    public let automaticallyAllowsReadOnly: Bool

    public init(
        automaticallyAllowsReadOnly: Bool = true
    ) {
        self.automaticallyAllowsReadOnly =
            automaticallyAllowsReadOnly
    }

    public func decision(
        for request: AIToolExecutionRequest
    ) async -> AIToolExecutionDecision {
        if request.definition.requiresUserConfirmation {
            return .requireConfirmation
        }

        if
            request.definition.sideEffectLevel == .readOnly,
            automaticallyAllowsReadOnly
        {
            return .allow
        }

        return .requireConfirmation
    }
}
