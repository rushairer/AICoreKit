# Consumer integration checklist

Use this checklist when adding AICoreKit to a production application.

The purpose is to prevent a partial integration from being mistaken for a completed one.

## 1. Define the product boundary first

Before adding dependencies, write down:

- which user-facing feature needs generative AI;
- which facts remain deterministic and authoritative;
- which outputs are advisory/generative;
- whether execution may use system, app-supplied local, cloud, or a combination;
- what data is allowed to leave the device.

Do not move product-domain truth into AICoreKit.

## 2. Add only the package products the feature needs

Examples:

- core contracts: `AICore`;
- routing/orchestration: `AIOrchestration`;
- Apple Foundation Models: `AIProviderApple`;
- app-supplied Core AI model: `AIProviderCoreAI`;
- lower-minimum host + embedded higher-minimum runtime: `AIProviderCoreAIWeakLink`;
- cloud profile/factory support: `AIProviderConfiguration`.

Do not import every provider into every app target.

## 3. Make execution policy explicit in the product

If the product offers Automatic / On-device / Cloud, the product owns those labels and preference semantics.

Map them to AICoreKit execution preferences deliberately:

- Automatic: normally local-first, with only explicitly enabled fallback providers;
- On-device: local-only;
- Cloud: remote-only, with no silent local fallback when the user explicitly chose cloud.

AICoreKit supplies routing mechanisms. It does not decide the product's Settings UX.

## 4. App-supplied local model

If the feature uses Qwen/Core AI or another app-supplied model, follow `LOCAL_MODELS.md`.

This is mandatory.

The integration is incomplete until the real model is provisioned and a signed supported device executes a generation.

Do not use a successful no-model build as local-model acceptance evidence.

## 5. Runtime compatibility

For a lower-minimum host using the iOS/macOS 27 Core AI runtime:

- keep direct higher-minimum runtime imports out of the host target;
- build/use the shared `AICoreKitCoreAIRuntime.framework`;
- weak-link it from the host;
- Embed & Sign it in the app;
- use `WeakLinkedCoreAIBridge`;
- validate lower-OS launch/fallback separately from supported-OS inference.

Do not create a new product-specific C ABI or Core AI runtime framework unless AICoreKit's generic boundary is genuinely insufficient.

## 6. Lifecycle

Use the shared local-model lifecycle:

- `CoreAIModelProfile`;
- `CoreAIModelSettingsStore`;
- `CoreAIModelLifecycleController`;
- `CoreAIDirectoryModelResourceProvider`.

Keep persistent preparation distinct from process loading.

A settings screen may customize wording and presentation, but it should not create a second lifecycle state machine.

## 7. Cloud providers and secrets

Use `AIProviderConfiguration` / provider presets and factories for reusable provider construction.

The host owns:

- provider/model/base-URL preference storage;
- Keychain or equivalent secret persistence;
- server/gateway policy;
- user-facing connection test UX.

Never store production API secrets in AICoreKit or plaintext UserDefaults.

## 8. Response validation

For plain text, call:

```swift
let text = try response.validatedCompletedText()
```

before treating a provider response as successful.

Then apply product-specific validation:

- schema/structured-output validation;
- language policy;
- evidence/reference validation;
- semantic role validation;
- safety/business invariants.

AICoreKit's completion validation does not replace domain validation.

## 9. Retry policy

Keep retries bounded and purposeful.

Provider/runtime-wide retry behavior may belong in shared infrastructure. Product repair prompts, schema repair, language repair, or domain correction normally belong in the consumer because they encode product semantics.

Never create an unbounded model retry loop.

## 10. Privacy and evidence boundary

Before enabling a remote provider, document exactly what is sent.

Prefer deterministic descriptors/aggregates over raw media when the feature does not need the raw asset.

Examples:

- ColorCamera sends palette descriptors, not camera frames/photos;
- Metronome Practice Coach sends deterministic practice evidence, not raw practice recordings.

## 11. Tests

At minimum cover:

- execution-mode mapping;
- provider selection/fallback;
- missing/unavailable provider;
- cancellation;
- incomplete/truncated response;
- product validation failure;
- credential/configuration boundary;
- no-model graceful degradation if local assets are intentionally absent from CI.

For local model qualification, tests are not a replacement for signed-device evidence.

## 12. Completion levels

Use precise language when reporting status:

### Dependency integrated

The app compiles with AICoreKit.

### Infrastructure wired

Provider/routing/settings/runtime/resource lookup code exists and contract tests pass.

### Local model provisioned

The real app-supplied model resource has been exported/installed and the app bundle/package resolves it.

### Device validated

A signed supported device executes real inference and the cold/warm lifecycle is verified.

### Production validated

Release/distribution, compatibility/fallback, cancellation, memory/thermal behavior, privacy, and product result quality meet the product's release gate.

Do not collapse these levels into a single "AI integration complete" statement.

## Agent rule

An AI coding agent must stop and report an explicit open gate whenever its environment cannot perform a required physical action such as model export, signing, app installation, or device inference.

It should still finish all code/documentation/tooling that can be completed in the repository, and leave the exact next command/check for the developer.

It must not fabricate successful device validation.
