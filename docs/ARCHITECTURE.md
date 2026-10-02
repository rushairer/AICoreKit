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


## Tool-call continuation

Tool-call normalization and execution are intentionally separated.

Providers return normalized `AIToolCall` values. If a response requires another model turn, the provider may also attach an opaque `AIToolContinuation`. The continuation belongs to that provider and preserves provider-native state without leaking OpenAI response items, Anthropic content blocks, Gemini interaction steps, or other vendor history formats into `AIMessage`.

`DefaultAIOrchestrator.respondWithTools` keeps provider affinity after the first successful model response, executes registered tools sequentially through `AIToolRegistry`, and asks the same `AIToolContinuingProvider` to continue. Provider fallback is allowed only before a provider has successfully produced the first response; this avoids replaying tool side effects against a different model after execution begins.

The default execution policy permits only read-only tools that do not require user confirmation. Mutating, network, destructive, or confirmation-required tools remain blocked unless the application injects a more permissive policy.


## Tool execution confirmation

Tool execution uses two independent application-owned controls:

1. An `AIToolExecutionPolicy` classifies each concrete tool call as `allow`, `deny`, or `requireConfirmation`.
2. An optional `AIToolConfirmationProviding` implementation performs the product-specific confirmation interaction when required.

The default `ReadOnlyAIToolExecutionPolicy` continues to auto-run only read-only tools. It never permits mutating, network, or destructive tools. `UserConfirmationAIToolExecutionPolicy` auto-runs ordinary read-only tools and requires confirmation for side-effecting tools or any tool explicitly marked `requiresUserConfirmation`.

AICoreKit does not render alerts or decide consent UX. Applications inject confirmation UI through `AIToolConfirmationProviding`, which receives both the normalized `AIToolCall` (including arguments) and its `AIToolDefinition`. Missing or denied confirmation is represented by explicit `AIError.toolConfirmationRequired` and `AIError.toolConfirmationDenied` values.

This keeps model intent, authorization policy, user consent, and business execution as separate boundaries.


## Local model lifecycle

AICoreKit treats persistent model preparation and current-process loading as different states.

`CoreAIModelLifecycleController` exposes the product-neutral lifecycle:

```text
notPrepared
    |
    | explicit first use / prepareResources()
    v
preparing
    v
prepared
    |
    | loadPreparedResources()
    v
loading
    v
ready
```

`bootstrapIfPrepared()` is intentionally asymmetric: it checks the persistent Core AI preparation cache and performs only the faster runtime load when that cache already exists. It returns `false` without preparing anything when the cache is absent. This makes it safe for an application-launch bootstrap path.

`releaseResources()` unloads only current-process residency. `clearPreparationCache()` unloads first and then removes persistent specialization while leaving installed model files untouched.

Provider instances share one lifecycle controller internally. All forward readiness operations — explicit persistent preparation, explicit prepared-resource loading, full `ensureReady()`, and launch-safe `bootstrapIfPrepared()` — register or join the shared in-flight task **before** performing asynchronous resource/preparation checks. Callers that wake after an earlier phase completes re-check the shared task/state and join a successor load when one already exists. This prevents actor reentrancy from turning concurrent UI, bootstrap, and inference requests into duplicate native prepare/load operations.

The iOS 27 runtime independently coalesces Core AI preparation and model loading as a second safety boundary.

Lifecycle unload and preparation-cache clearing enter an explicit reset gate before touching the runtime. While that gate is active, new prepare/load/ensure/bootstrap requests are rejected with cancellation instead of racing a reset. Reset also invalidates the current readiness generation, so a late native callback from an older prepare/load cannot transition the controller back to `ready`. Cache clearing waits for the invalidated readiness task to settle before the final persistent-cache removal, covering bridges whose native preparation cannot be cancelled synchronously.


### Lifecycle observation

`CoreAIModelLifecycleController.stateChanges(includeCurrentState:)` exposes a multi-subscriber `AsyncStream` of product-neutral lifecycle states. It emits only real state transitions and can optionally begin with the current state.

Consumer UI should map this stream into product wording and actions instead of maintaining a second prepare/load/ready state machine. Request-execution stages such as model warming, text generation, and product-side validation remain separate from model lifecycle state.


## Device diagnostics

`AIDiagnostics` is a provider-neutral validation layer for production and signed-device qualification. It records availability, resource preparation, generation, cancellation, and release as ordered diagnostic steps.

Each step captures elapsed time plus before/after process snapshots with physical footprint, resident memory, thermal state, low-power mode, and OS version where available. The runner accepts any `AIProvider`; providers that also implement `AIResourceManaging` automatically participate in prepare/release measurement.

The diagnostics module deliberately does not decide pass/fail thresholds for memory or thermals. Product teams and device qualification plans own those thresholds because acceptable budgets vary by model size, foreground workload, camera/audio coexistence, and supported device tier.

A cancellation probe is explicit and reports whether cancellation was actually observed. If generation finishes before cancellation can take effect, the diagnostic step is reported as a failure rather than falsely claiming cancellation support.


### Model resource deployment

AICoreKit separates model identity/lifecycle from product distribution policy.

`CoreAIModelProfile` is the reusable technical identity for a local model: a stable identifier, a user-presentable display name, and an optional upstream/source model identifier. It deliberately does not own bundle resource names, download/install policy, settings UI, or product copy.

`CoreAIDirectoryModelResourceProvider` is the reusable resource-discovery layer for Core AI model directories. It accepts either a raw identifier or a `CoreAIModelProfile`, validates that the directory exists and, by default, that it contains at least one `.aimodel` descendant before exposing a `CoreAIModelResource`.

The package also ships reusable export/install scripts under `Scripts/`. These cover the mechanics proven in ColorCamera: pinned `coreai-models` export, model-directory validation, profile emission, and safe copying into a product-owned resource directory.

AICoreKit intentionally does not decide whether an application bundles a model, downloads it on demand, or omits it. That is a product distribution policy. Once a directory is available, preparation, process loading, unload, preparation-cache clearing, provider execution, and device diagnostics are shared infrastructure.


### Persistent resource lifecycle capability

Providers whose first-use preparation is materially different from process-local loading should implement `AIPersistentResourceManaging`.

The protocol separates `preparePersistentResources()` from `loadPreparedResources()` while retaining `AIResourceManaging` for providers with a single preparation phase. `CoreAIProvider` implements the persistent protocol. Device diagnostics detect it automatically and report first-use preparation and runtime loading as separate timing/memory/thermal steps.
