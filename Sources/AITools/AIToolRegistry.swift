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

    public func execute(
        _ call: AIToolCall,
        policy: any AIToolExecutionPolicy,
        confirmationProvider:
            (any AIToolConfirmationProviding)? = nil
    ) async throws -> AIToolOutput {
        guard let tool = toolsByName[call.name] else {
            throw AIError.toolExecutionFailed(
                "No registered tool named \(call.name)"
            )
        }

        let executionRequest = AIToolExecutionRequest(
            call: call,
            definition: tool.definition
        )

        let decision = await policy.decision(
            for: executionRequest
        )

        switch decision {
        case .allow:
            break

        case .deny(let reason):
            let suffix = reason.map {
                ": " + $0
            } ?? ""

            throw AIError.toolExecutionFailed(
                "Tool \(call.name) is blocked by the execution policy"
                + suffix
            )

        case .requireConfirmation:
            guard let confirmationProvider else {
                throw AIError.toolConfirmationRequired(
                    toolName: call.name,
                    callID: call.id
                )
            }

            let confirmation: AIToolConfirmationDecision
            do {
                confirmation =
                    try await confirmationProvider.confirm(
                        executionRequest
                    )
            } catch is CancellationError {
                throw AIError.cancelled
            } catch let error as AIError {
                throw error
            } catch {
                throw AIError.toolExecutionFailed(
                    "Tool confirmation failed for "
                    + call.name
                    + ": "
                    + error.localizedDescription
                )
            }

            guard confirmation == .approved else {
                throw AIError.toolConfirmationDenied(
                    toolName: call.name,
                    callID: call.id
                )
            }
        }

        try Task.checkCancellation()

        let result: AIToolResult
        do {
            result = try await tool.execute(
                argumentsJSON: call.argumentsJSON
            )
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.toolExecutionFailed(
                "Tool \(call.name) failed: \(error.localizedDescription)"
            )
        }

        return AIToolOutput(
            callID: call.id,
            toolName: result.toolName,
            content: result.content,
            isError: result.isError
        )
    }

    public func execute(
        _ calls: [AIToolCall],
        policy: any AIToolExecutionPolicy,
        confirmationProvider:
            (any AIToolConfirmationProviding)? = nil
    ) async throws -> [AIToolOutput] {
        var outputs: [AIToolOutput] = []
        outputs.reserveCapacity(calls.count)

        for call in calls {
            outputs.append(
                try await execute(
                    call,
                    policy: policy,
                    confirmationProvider:
                        confirmationProvider
                )
            )
        }

        return outputs
    }
}
