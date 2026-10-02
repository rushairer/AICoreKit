# Migrating FateAtlas from AppAIKit to AICoreKit

Baseline reviewed: `rushairer/FateAtlas` main at `087dcdf4baa31fb7b17093c615573ab7a118115f`.

FateAtlas currently contains a local Swift package named `AppAIKit`. Its architecture strongly overlaps with AICoreKit, so the long-term direction should be one shared AICoreKit dependency rather than two independently evolving provider abstractions.

## Migration goal

Replace reusable `Packages/AppAIKit` infrastructure with AICoreKit while keeping FateAtlas product semantics, settings, prompts, task definitions, status UI, and domain orchestration in FateAtlas.

## Current overlap

The current `AppAIKit` package contains direct equivalents of AICoreKit concepts:

| FateAtlas AppAIKit | AICoreKit |
| --- | --- |
| `AIBackendID` | `AIProviderID` |
| `AICapabilities` | `AICapabilities` |
| `AIExecutionPreference` | `AIExecutionPreference` |
| `AIProvider` | `AIProvider` |
| `AIProviderError` | `AIError` |
| `AIChatMessage` | `AIMessage` |
| `ChatRequest` | `AIRequest` |
| `ChatResponse` | `AIResponse` |
| `StructuredGenerationRequest` | `AIStructuredRequest` |
| `AppleFoundationModelsProvider` | `AIProviderApple` |
| `AnthropicProvider` | `AIProviderAnthropic` |
| `OpenAICompatibleProvider` | `AIProviderOpenAICompatible` |

AICoreKit additionally supplies routing/fallback primitives, dedicated OpenAI Responses and Gemini adapters, normalized tool calls, confirmation policy, retry/observability, and the Core AI local-runtime boundary.

## What must stay in FateAtlas

Keep these concepts product-owned:

- `AIServiceProvider` and its user-facing localized names;
- `ProviderSettings`;
- FateAtlas settings persistence and API-key UX;
- `AIExecutionStrategy` and product semantics such as local-first/cloud-first;
- `AITaskKind` and all astrology/BaZi/zodiac task metadata;
- prompts, structured payload models, and domain validation;
- `AIConversationOrchestrator` behavior that is specifically about FateAtlas UX;
- connection-test presentation and status strings;
- fallback status shown to the user;
- product error messages and localization.

AICoreKit should expose technical provider capabilities, not FateAtlas product terminology such as “模型来源” or “本地运行”.

## Semantics that should change during migration

### AppAIKit overstates Apple capabilities

The current FateAtlas `AppleFoundationModelsProvider` advertises structured generation and tool calling.

Its structured implementation actually asks the text model to return JSON and extracts the first JSON object. That is prompt-based JSON parsing, not a native structured-output guarantee.

AICoreKit intentionally does not advertise `.structuredGeneration` for its Apple provider today.

During migration:

- do not copy the old capability declaration into AICoreKit;
- treat Apple local structured generation as a product fallback with explicit validation if FateAtlas still needs it;
- use native structured cloud adapters when a reliable schema contract is required.

### OpenAI-compatible is not the same as OpenAI Responses

FateAtlas currently routes OpenAI, DeepSeek, and custom endpoints mostly through its OpenAI-compatible adapter.

AICoreKit separates:

- `OpenAIProvider` for the OpenAI Responses API with native structured output and normalized tools;
- `OpenAICompatibleProvider` for generic chat-completions-compatible services.

Recommended mapping:

| FateAtlas source | AICoreKit adapter |
| --- | --- |
| Apple 本地 | `AppleFoundationModelsProvider` |
| OpenAI | Prefer dedicated `OpenAIProvider` after behavior-parity testing |
| Anthropic | `AnthropicProvider` |
| DeepSeek | `OpenAICompatibleProvider` with a product-defined provider ID |
| Custom | `OpenAICompatibleProvider` unless a dedicated adapter is required |

Do not force DeepSeek/custom endpoints through OpenAI-specific Responses semantics.

## Recommended migration sequence

### Phase 0 — Introduce AICoreKit side by side

Add AICoreKit without deleting `Packages/AppAIKit`.

Pin a known revision/pre-1.0 release.

Create a thin product adapter layer so FateAtlas code can switch implementations without changing views or stored settings.

### Phase 1 — Migrate text chat

Map `AIChatMessageAdapter` output to `AIMessage`.

Replace provider chat calls with `AIRequest` + `generate` / `stream`.

Keep:

- history truncation;
- system prompt construction;
- product retry decisions that are genuinely UX policy;
- localized error mapping.

Where possible, move generic HTTP retry to AICoreKit's transport decorator rather than maintaining duplicate provider retry code.

### Phase 2 — Migrate provider construction

Replace `AIProviderFactory` internals with AICoreKit provider configurations.

Credentials should be injected through `AICredentialProviding`. FateAtlas remains responsible for obtaining the configured credential; AICoreKit must not own its persistence.

Use custom `AIProviderID` values when FateAtlas needs to distinguish DeepSeek/custom providers in routing or telemetry.

### Phase 3 — Migrate structured generation

For OpenAI Responses, Anthropic, and Gemini, prefer AICoreKit native structured generation with an explicit `AIStructuredOutputSchema`.

For Apple local execution, preserve FateAtlas's current fallback only if needed, but label it accurately as validated prompt-based JSON rather than native structured output.

For generic OpenAI-compatible services, do not assume every endpoint supports the same JSON-schema extension. Keep a product-owned validated fallback or add a dedicated provider adapter when required.

### Phase 4 — Simplify orchestration

Evaluate each piece of `AIConversationOrchestrator`:

Move to AICoreKit when generic:

- capability-based provider selection;
- local/remote execution preference;
- first-response fallback;
- tool-call continuation;
- confirmation policy;
- retry/observability.

Keep in FateAtlas when product-specific:

- provider settings selection;
- connection-test UX;
- model-list UX;
- fallback labels;
- astrology task routing;
- user-facing “local/cloud” status.

The target is a smaller FateAtlas orchestrator that translates product policy into AICoreKit requests.

### Phase 5 — Remove AppAIKit

Delete `Packages/AppAIKit` only after all call sites and tests use AICoreKit.

Remove duplicate core/provider types rather than maintaining compatibility aliases indefinitely.

## Type migration examples

### Chat

Old conceptual flow:

```swift
provider.chat(
    request: ChatRequest(
        messages: messages,
        preference: .remoteOnly
    )
)
```

Target flow:

```swift
try await provider.generate(
    AIRequest(
        messages: messages,
        requiredCapabilities: [.textGeneration],
        executionPreference: .remoteOnly
    )
)
```

### DeepSeek/custom provider identity

Use the generic transport shape without losing product identity:

```swift
OpenAICompatibleProviderConfiguration(
    providerID: AIProviderID(
        rawValue: "fateatlas.deepseek"
    ),
    displayName: "DeepSeek",
    baseURL: settings.baseURL,
    model: settings.model
)
```

## Acceptance gates

Before deleting `AppAIKit`, verify:

- Apple local availability and text chat behavior;
- OpenAI chat and configured model behavior;
- Anthropic chat and structured generation;
- DeepSeek/custom OpenAI-compatible endpoints;
- streaming on supported transports;
- local-first/cloud-first fallback semantics;
- current connection-test UI;
- structured zodiac/BaZi/astrology payload decoding;
- missing/invalid credential errors;
- cancellation and rate-limit handling;
- existing FateAtlas tests;
- archive/build of the production app.

## Expected cleanup

After migration, FateAtlas should no longer need its own copies of:

- provider protocol/core capability types;
- generic chat request/response types;
- generic cloud provider implementations;
- generic provider error taxonomy;
- generic retry/streaming plumbing already supplied by AICoreKit.

The product should still own its domain service layer.

## Migration status update — 2026-10-02

FateAtlas now pins AICoreKit `f6660787` through `Packages/AppAIKit`. AppAIKit remains the product-facing compatibility layer, but its generic cloud-provider construction has moved behind AICoreKit's reusable configuration boundary.

Current cloud-provider state:

- AppAIKit depends directly on `AICore` and `AIProviderConfiguration`; it no longer needs direct target dependencies on the OpenAI, Anthropic, or OpenAI-compatible provider modules;
- `OpenAIResponsesProvider`, `AnthropicProvider`, and `OpenAICompatibleProvider` preserve their existing FateAtlas-facing APIs while internally building `AIProviderProfile` values and delegating provider construction to `AIConfiguredProviderFactory`;
- profile construction preserves FateAtlas's existing endpoint, model, provider identity, timeout, maximum-output-token, and temperature semantics;
- first-party OpenAI generation and connection testing now both execute through the Responses API path;
- Anthropic generation/connection testing execute through the same AICoreKit Anthropic path;
- DeepSeek/custom OpenAI-compatible generation/connection testing execute through the same compatible provider path;
- duplicate URLSession/header implementations previously used only by connection testing have been removed;
- product-owned model discovery remains intentionally separate: the OpenAI-compatible `/models` helper is still a FateAtlas feature because model-list UX and endpoint compatibility policy are not a generic generation contract.

Structured generation remains intentionally split by actual provider capability:

- OpenAI Responses and Anthropic use AICoreKit native schema-backed structured generation when an explicit schema is supplied;
- DeepSeek/custom compatible services retain FateAtlas's validated prompt/JSON fallback because generic compatible endpoints do not share one guaranteed schema extension;
- Apple local structured generation remains product-owned until a reusable native Apple structured-output contract is justified.

FateAtlas still owns provider selection UI, stored settings, model-list presentation, connection-test presentation/status text, task routing, fallback labels, and astrology/BaZi/zodiac domain validation. AICoreKit owns the technical provider protocol construction underneath those product decisions.

The broader AppAIKit migration remains incremental. No new Release/CI evidence is claimed by this documentation update; previously established production evidence remains historical evidence rather than a claim about the latest commit.

## Why FateAtlas matters to AICoreKit 1.0

FateAtlas is the strongest migration test for the cloud/provider abstraction because it already uses Apple local execution, OpenAI-compatible services, Anthropic, DeepSeek/custom endpoints, structured tasks, streaming, fallback, and user-configurable provider settings.

A successful migration is therefore a meaningful 1.0 compatibility gate rather than a documentation exercise.


### Phase 3 validation evidence

FateAtlas main `cc357684` passes both the AppAIKit package test job and the full code-signing-disabled Release generic iOS application build after the dedicated OpenAI Responses migration. This keeps the protocol split explicit: OpenAI uses Responses, Anthropic uses Messages, and DeepSeek/custom remain generic compatible endpoints.
