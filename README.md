# AICoreKit

AICoreKit is a Swift AI runtime and provider abstraction for Apple-platform applications.

It is designed around capabilities rather than vendors, so product code can use a stable API while execution is routed across system, on-device, and cloud AI providers.

> Status: pre-1.0 stabilization. The 1.0 compatibility contract is defined, but public API may still change before the first 1.0.0 tag.

## Goals

- Keep product code independent from a specific AI vendor or model.
- Support system, on-device, and cloud providers behind capability-based routing.
- Treat streaming, structured generation, tool calling, credentials, availability, and fallback as first-class runtime concerns.
- Keep product prompts, domain models, and business tools outside the core package.
- Preserve graceful degradation when generative AI is unavailable.
- Support Apple-platform compatibility boundaries, including newer AI runtimes that require a higher deployment target than the host app.

## Initial modules

- `AICore` — provider contracts, requests, responses, capabilities, availability, errors, credentials, and stream events.
- `AIHTTP` — injectable HTTP transport for cloud providers.
- `AIOrchestration` — provider registry, routing, execution preference, fallback, and multi-turn tool orchestration.
- `AITools` — tool definitions, registry, side-effect classification, and execution policy.
- `AIProviderApple` — Apple Foundation Models provider, gated by runtime availability.
- `AIProviderCoreAI` — host-safe local Core AI provider and dynamic C ABI bridge.
- `AIProviderCoreAIWeakLink` — optional weak-link support for apps embedding the iOS/macOS 27 Core AI runtime.
- `AIProviderOpenAICompatible` — optional OpenAI-compatible chat-completions provider with non-streaming and SSE streaming text generation.
- `AIProviderAnthropic` — optional Anthropic Messages API provider with text, SSE streaming, native structured generation, normalized tool calls, and multi-turn tool continuation.
- `AIProviderGemini` — optional Gemini provider using Generate Content for text/streaming and Interactions for native structured generation, normalized tool calls, and multi-turn tool continuation.
- `AIProviderOpenAI` — optional OpenAI Responses API provider with text, SSE streaming, native structured generation, normalized tool calls, and multi-turn tool continuation.
- `AICoreKit` — convenience umbrella module.

Cloud provider foundations now cover OpenAI-compatible, Anthropic, Gemini, and the OpenAI Responses API. OpenAI Responses, Anthropic, and Gemini also share provider-native structured output, normalized tool calls, stateless multi-turn tool continuation, and application-owned confirmation policies.

## Design principle

Applications should ask for a capability, not branch on a vendor:

```swift
let request = AIRequest(
    messages: [.user("Summarize today's practice.")],
    requiredCapabilities: [.textGeneration],
    executionPreference: .localFirst
)

let response = try await orchestrator.respond(to: request)
```

The runtime decides which registered provider can satisfy the request.



## Tool calling

Tools are application-owned capabilities. AICoreKit normalizes model tool requests, applies execution policy, executes registered tools, and continues the same provider without exposing vendor-specific conversation history to product code.

The default policy only auto-runs read-only tools:

```swift
let toolRegistry = AIToolRegistry(
    tools: [myReadOnlyTool]
)

let request = AIRequest(
    messages: [.user("Use the available tools if needed.")],
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

For mutating, network, destructive, or explicitly confirmation-required tools, applications can opt into `UserConfirmationAIToolExecutionPolicy` and inject their own `AIToolConfirmationProviding` implementation. AICoreKit never owns or renders confirmation UI.

See [docs/TOOLS.md](docs/TOOLS.md) for the complete tool execution and confirmation model.

## Provider boundaries

AICoreKit does **not** contain product-specific prompts or domain types. For example, palette analysis belongs in ColorCamera, practice coaching belongs in the metronome app, and astrology/BaZi tasks belong in FateAtlas.

Provider credentials are injected through protocols. AICoreKit does not persist API keys in `UserDefaults` or ship application secrets.

## Core AI local models

The root package remains usable by lower-minimum hosts. `AIProviderCoreAI` communicates through a stable C ABI resolved dynamically.

Apps that actually embed `AICoreKitCoreAIRuntime.framework` should additionally depend on the `AIProviderCoreAIWeakLink` product and use `WeakLinkedCoreAIBridge`. That optional module carries the tiny weak C reference needed to preserve the runtime framework load command when dead stripping is enabled.

The higher-minimum implementation lives in the nested `Runtime/CoreAIRuntime` package, which requires iOS/macOS 27 and Apple's `CoreAILM` runtime. Model assets are supplied by the host and are not bundled in AICoreKit.

See `CompatibilityLab/CORE_AI_ABI.md` for the boundary contract.

## Installation

AICoreKit is not tagged for production use yet. During early development, depend on the `main` branch only for experiments.

```swift
.package(
    url: "https://github.com/rushairer/AICoreKit.git",
    branch: "main"
)
```

## Development

```bash
swift test
```

## Compatibility

See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) for platform minimums, provider capability support, and the conformance contract.

See [docs/VERSIONING.md](docs/VERSIONING.md) for the SemVer, API stability, deprecation, and Core AI ABI policy.

Migration plans for the first target consumers are documented in [docs/MIGRATION_COLORCAMERA.md](docs/MIGRATION_COLORCAMERA.md) and [docs/MIGRATION_FATEATLAS.md](docs/MIGRATION_FATEATLAS.md).

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md).

## License

Apache License 2.0. See [LICENSE](LICENSE).


## Cloud providers

Cloud integrations are optional package products. The first cloud adapter, `AIProviderOpenAICompatible`, uses injected credentials and an injected `AIHTTPTransport`; it does not persist API keys or force cloud networking into the `AICoreKit` umbrella product.

See [docs/CLOUD_PROVIDERS.md](docs/CLOUD_PROVIDERS.md).
