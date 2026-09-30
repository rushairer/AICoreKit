public import AICore

public protocol AIToolExecutionPolicy: Sendable {
    func canExecute(_ definition: AIToolDefinition) async -> Bool
}

public struct ReadOnlyAIToolExecutionPolicy: AIToolExecutionPolicy {
    public init() {}

    public func canExecute(_ definition: AIToolDefinition) async -> Bool {
        definition.sideEffectLevel == .readOnly && !definition.requiresUserConfirmation
    }
}
