# Tool calling and execution

AICoreKit treats tool calling as four separate responsibilities:

1. the provider decides that a tool should be called;
2. AICoreKit normalizes the provider response into `AIToolCall`;
3. application-owned policy and confirmation decide whether execution is authorized;
4. the application-owned `AITool` performs the business action.

Provider-specific history is kept behind `AIToolContinuation`. Product code does not need to construct OpenAI response items, Anthropic content blocks, or Gemini interaction steps.

## Define a tool

A tool exposes a provider-neutral definition and an async executor.

```swift
struct CurrentPaletteTool: AITool {
    let definition = AIToolDefinition(
        name: "current_palette",
        description: "Returns the current palette.",
        inputSchemaJSON: """
        {
          "type": "object",
          "properties": {},
          "additionalProperties": false
        }
        """
    )

    func execute(
        argumentsJSON: String
    ) async throws -> AIToolResult {
        AIToolResult(
            toolName: definition.name,
            content: #"{"colors":["#FF0000","#00FF00"]}"#
        )
    }
}
```

The input schema must be a JSON object. Invalid schemas are rejected before they are sent to a provider.

## Register and execute

```swift
let toolRegistry = AIToolRegistry(
    tools: [CurrentPaletteTool()]
)

let request = AIRequest(
    messages: [
        .user("Describe my current palette.")
    ],
    requiredCapabilities: [
        .textGeneration,
        .toolCalling
    ],
    tools: await toolRegistry.definitions()
)

let response = try await orchestrator.respondWithTools(
    to: request,
    toolRegistry: toolRegistry
)
```

`respondWithTools` selects a provider, keeps provider affinity after the first successful model response, executes requested tools sequentially, and continues until the model returns a final response or the configured round limit is reached.

The default maximum is eight tool rounds.

## Side-effect classification

Every tool declares an `AIToolSideEffectLevel`:

| Level | Meaning |
| --- | --- |
| `readOnly` | Reads state without changing it. |
| `localMutation` | Changes application or device-local state. |
| `networkRequest` | Performs an external/network action. |
| `destructive` | Deletes, replaces, irreversibly changes, or otherwise performs a destructive action. |

A tool can also set `requiresUserConfirmation: true` even when it is read-only.

## Default policy

`ReadOnlyAIToolExecutionPolicy` is the default.

It:

- allows ordinary read-only tools;
- requires confirmation for read-only tools explicitly marked `requiresUserConfirmation`;
- denies local mutation, network, and destructive tools.

Because `respondWithTools` does not provide a confirmation UI by default, a confirmation-required call fails closed with `AIError.toolConfirmationRequired`.

## User-confirmed side effects

Applications that want the model to request side-effecting actions can explicitly opt into `UserConfirmationAIToolExecutionPolicy`.

```swift
let confirmation =
    ClosureAIToolConfirmationProvider { request in
        let approved = try await appConfirmationUI.confirm(
            toolName: request.definition.name,
            description: request.definition.description,
            argumentsJSON: request.call.argumentsJSON
        )

        return approved ? .approved : .denied
    }

let response = try await orchestrator.respondWithTools(
    to: request,
    toolRegistry: toolRegistry,
    executionPolicy:
        UserConfirmationAIToolExecutionPolicy(),
    confirmationProvider: confirmation
)
```

Under this policy:

- ordinary read-only tools can run without interruption;
- tools marked `requiresUserConfirmation` require confirmation;
- local mutation, network, and destructive tools require confirmation;
- denied confirmation produces `AIError.toolConfirmationDenied`;
- missing confirmation infrastructure produces `AIError.toolConfirmationRequired`.

The confirmation request includes the normalized call ID, tool name, argument JSON, description, side-effect level, and explicit confirmation flag through its `AIToolCall` and `AIToolDefinition`.

AICoreKit does not provide alert, sheet, voice, biometric, or other consent UI. Each product owns that interaction.

## Provider continuation

### OpenAI Responses

AICoreKit uses stateless continuation compatible with `store=false`. The original input and provider output items are preserved in opaque continuation state, then `function_call_output` items are appended for the next turn.

This preserves provider-native items such as reasoning output without leaking them into `AIMessage`.

### Anthropic

The assistant content blocks are replayed exactly enough to retain `tool_use` state, followed by user `tool_result` blocks. Tool errors map to Anthropic's native `is_error` field.

### Gemini Interactions

With stateless Interactions, AICoreKit reconstructs explicit history containing the initial `user_input`, all model-generated steps returned by Gemini, and appended `function_result` steps.

Model-generated steps are replayed from the raw response so thought signatures and future provider fields are not discarded. Tool errors map to Gemini's native `is_error` field.

## Fallback and side effects

Provider fallback is allowed only before a provider has successfully returned the first response.

Once tool execution begins, AICoreKit keeps the same provider for the entire tool loop. It never retries an already-started tool loop against another provider, which avoids duplicating side effects.

## Streaming

Text streaming remains provider-native.

When a request includes tools, the current OpenAI Responses, Anthropic, and Gemini adapters normalize the tool flow through the non-streaming generation path and expose it through the standard response/tool events rather than attempting partial argument execution.

This intentionally avoids executing incomplete streamed tool arguments.
