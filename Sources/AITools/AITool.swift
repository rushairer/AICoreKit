public import AICore

public struct AIToolResult: Hashable, Sendable, Codable {
    public let toolName: String
    public let content: String
    public let isError: Bool

    public init(toolName: String, content: String, isError: Bool = false) {
        self.toolName = toolName
        self.content = content
        self.isError = isError
    }
}

public protocol AITool: Sendable {
    var definition: AIToolDefinition { get }
    func execute(argumentsJSON: String) async throws -> AIToolResult
}
