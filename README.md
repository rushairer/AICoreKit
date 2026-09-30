# AICoreKit

AICoreKit is a Swift AI runtime and provider abstraction for Apple-platform applications.

It is designed around capabilities rather than vendors, so product code can use a stable API while execution is routed across system, on-device, and cloud AI providers.

> Status: early development. Public API is not stable yet.

## Goals

- Keep product code independent from a specific AI vendor or model.
- Support system, on-device, and cloud providers behind capability-based routing.
- Treat streaming, structured generation, tool calling, credentials, availability, and fallback as first-class runtime concerns.
- Keep product prompts, domain models, and business tools outside the core package.
- Preserve graceful degradation when generative AI is unavailable.
- Support Apple-platform compatibility boundaries, including newer AI runtimes that require a higher deployment target than the host app.

## Initial modules

- `AICore` — provider contracts, requests, responses, capabilities, availability, errors, credentials, and stream events.
- `AIOrchestration` — provider registry, routing, execution preference, and fallback.
- `AITools` — tool definitions, registry, side-effect classification, and execution policy.
- `AIProviderApple` — Apple Foundation Models provider, gated by runtime availability.
- `AIProviderCoreAI` — host-safe local Core AI provider plus weak-symbol bridge.
- `AICoreKit` — convenience umbrella module.

Future provider modules will include OpenAI-compatible APIs, OpenAI, Anthropic, and Gemini.

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

## Provider boundaries

AICoreKit does **not** contain product-specific prompts or domain types. For example, palette analysis belongs in ColorCamera, practice coaching belongs in the metronome app, and astrology/BaZi tasks belong in FateAtlas.

Provider credentials are injected through protocols. AICoreKit does not persist API keys in `UserDefaults` or ship application secrets.

## Core AI local models

The root package remains usable by lower-minimum hosts. `AIProviderCoreAI` communicates through a stable C ABI resolved by `WeakSymbolCoreAIBridge`.

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

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md).

## License

Apache License 2.0. See [LICENSE](LICENSE).
