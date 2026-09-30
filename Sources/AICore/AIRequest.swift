public struct AIRequest: Sendable {
    public let messages: [AIMessage]
    public let requiredCapabilities: AICapabilities
    public let executionPreference: AIExecutionPreference
    public let tools: [AIToolDefinition]
    public let metadata: [String: String]
    public let maxOutputTokens: Int?
    public let temperature: Double?

    public init(
        messages: [AIMessage],
        requiredCapabilities: AICapabilities = [.textGeneration],
        executionPreference: AIExecutionPreference = .automatic,
        tools: [AIToolDefinition] = [],
        metadata: [String: String] = [:],
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil
    ) {
        self.messages = messages
        self.requiredCapabilities = requiredCapabilities
        self.executionPreference = executionPreference
        self.tools = tools
        self.metadata = metadata
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
    }
}

public struct AIStructuredRequest<Output: Decodable & Sendable>: Sendable {
    public let instructions: String
    public let input: String
    public let requiredCapabilities: AICapabilities
    public let executionPreference: AIExecutionPreference
    public let metadata: [String: String]
    public let schema: AIStructuredOutputSchema?
    public let maxOutputTokens: Int?
    public let temperature: Double?
    public let outputType: Output.Type

    public init(
        instructions: String,
        input: String,
        requiredCapabilities: AICapabilities = [.structuredGeneration],
        executionPreference: AIExecutionPreference = .automatic,
        metadata: [String: String] = [:],
        schema: AIStructuredOutputSchema? = nil,
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        outputType: Output.Type = Output.self
    ) {
        self.instructions = instructions
        self.input = input
        self.requiredCapabilities = requiredCapabilities
        self.executionPreference = executionPreference
        self.metadata = metadata
        self.schema = schema
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.outputType = outputType
    }
}
