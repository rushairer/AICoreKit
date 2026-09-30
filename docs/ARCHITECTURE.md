# Architecture

AICoreKit separates product AI concerns from runtime and provider concerns.

## Layers

1. AICore defines stable, vendor-neutral contracts.
2. AIOrchestration selects providers by capability, availability, and execution preference.
3. AITools defines controlled app capabilities exposed to models.
4. Provider modules adapt vendor or platform APIs to AICore.
5. Product applications own prompts, domain models, validation, and business actions.

## Local runtime boundary

`AIProviderCoreAI` is deliberately host-safe. It does not import `CoreAILanguageModels` and therefore does not force the base Swift package to adopt the Core AI runtime's higher deployment target.

The provider depends on two injected abstractions:

- `CoreAIBridge` — availability and generation across the runtime boundary.
- `CoreAIModelResourceProviding` — host-owned model resource resolution.

The live iOS implementation will use the weak C ABI documented under `CompatibilityLab/`. The higher-minimum Swift runtime stays isolated in an iOS 27-only framework target.

## Non-goals

AICoreKit does not own product prompts, app state, persistence, billing policy, or product-specific domain facts.

## Provider model

Provider selection is capability-based. Product code should not branch on vendor identity unless it needs a provider-specific extension.

A provider declares capabilities such as text generation, structured generation, tool calling, streaming, local execution, remote execution, and network requirements.

## Structured generation

The core protocol exposes structured generation, but a provider must only advertise the capability when it has a reliable implementation. Prompt-only JSON extraction is not treated as native structured generation by default.

## Streaming

Streaming is represented as AsyncThrowingStream<AIStreamEvent, Error>. Providers without native streaming receive a one-shot default implementation and must not advertise the streaming capability.

## Security

Credentials are injected through AICredentialProviding. The package does not persist application secrets. Commercial applications should generally route vendor credentials through a server-side gateway rather than embedding vendor API keys in an app binary.
