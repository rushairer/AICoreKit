public enum AIToolSideEffectLevel: String, Hashable, Sendable, Codable {
    case readOnly
    case localMutation
    case networkRequest
    case destructive
}

public struct AIToolDefinition: Hashable, Sendable, Codable {
    public let name: String
    public let description: String
    public let inputSchemaJSON: String
    public let sideEffectLevel: AIToolSideEffectLevel
    public let requiresUserConfirmation: Bool

    public init(
        name: String,
        description: String,
        inputSchemaJSON: String,
        sideEffectLevel: AIToolSideEffectLevel = .readOnly,
        requiresUserConfirmation: Bool = false
    ) {
        self.name = name
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
        self.sideEffectLevel = sideEffectLevel
        self.requiresUserConfirmation = requiresUserConfirmation
    }

    public func parsedInputSchema() throws -> AIJSONValue {
        let schema = try AIJSONValue(
            jsonString: inputSchemaJSON
        )

        guard case .object = schema else {
            throw AIError.invalidRequest(
                "Tool input schema must be a JSON object"
            )
        }

        return schema
    }
}

public struct AIToolCall: Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}
