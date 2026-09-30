public import AICore

public actor AIToolRegistry {
    private var toolsByName: [String: any AITool] = [:]

    public init(tools: [any AITool] = []) {
        for tool in tools {
            toolsByName[tool.definition.name] = tool
        }
    }

    public func register(_ tool: any AITool) throws {
        let name = tool.definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AIError.invalidRequest("Tool name must not be empty")
        }
        toolsByName[name] = tool
    }

    public func unregister(named name: String) {
        toolsByName[name] = nil
    }

    public func tool(named name: String) -> (any AITool)? {
        toolsByName[name]
    }

    public func definitions() -> [AIToolDefinition] {
        toolsByName.values.map(\.definition).sorted { $0.name < $1.name }
    }
}
