# Production consumer plan

AICoreKit 1.0 requires evidence from real product integrations, not only package fixtures.

The target is three production consumers with deliberately different workloads.

## Consumer matrix

| Product | Current state | Intended AICoreKit role | Main validation |
| --- | --- | --- | --- |
| ColorCamera | Pins a validated AICoreKit stabilization revision; shared local Core AI lifecycle/runtime and optional cloud palette execution are both integrated | Shared local lifecycle/runtime + reusable cloud-provider infrastructure while palette semantics remain product-owned | iOS 27 real Qwen inference, weak-link topology, first-use preparation vs fast load, cloud descriptor-only execution |
| FateAtlas | Pins AICoreKit `f6660787`; AppAIKit keeps the product API while provider construction, chat/streaming, structured cloud paths, and connection-test protocol execution delegate to AICoreKit | Incrementally remove duplicated generic provider/runtime plumbing without leaking vendor details into product UI | OpenAI Responses, Anthropic, DeepSeek/custom compatible endpoints, structured generation, streaming/fallback |
| MetronomePro | Pins AICoreKit with shared response validation and local-model provisioning; Practice Coach exposes Automatic / On-device / Cloud routing through `AIProviderConfiguration` and Keychain | Evidence-grounded Practice Coach with explicit local/cloud routing | deterministic evidence boundary, real Qwen resource provisioning/device inference, local-only vs remote-only policy, shared settings across MetronomePro/Metronome26 |

## What counts as a production consumer

A repository counts only when all of the following are true:

1. a production app target has AICoreKit as a real dependency;
2. at least one shipped or release-candidate user-facing path executes through AICoreKit;
3. the integration has product-level tests or explicit validation evidence;
4. production/Release build or archive succeeds;
5. the product does not maintain a second independent generic provider abstraction for the same migrated path.

A migration guide, proof-of-concept target, test fixture, or unused package dependency does not count.

## Consumer 1 — ColorCamera

Recommended validation scope:

- `AIProviderCoreAI` / weak-link integration;
- lower-minimum host launch;
- iOS 27 real local inference;
- model prepare/load/release/reset parity;
- Apple/local/cloud fallback;
- deterministic palette validation retained outside AICoreKit.

ColorCamera should not be forced to remove its product-specific `@Generable` Apple adapter until equivalent behavior exists through a reusable contract.

Current adoption evidence as of 2026-10-03:

- ColorCamera pins AICoreKit in the Xcode project, committed `Package.resolved`, and pre-build revision gate.
- `CoreAIModelLifecycleController` owns the reusable lifecycle and `CoreAIModelSettingsStore` now owns the reusable observable Settings/first-use state+actions layer. ColorCamera deleted its product-side lifecycle store and shares the AICoreKit store across Settings, first-use initialization, and launch bootstrap.
- ColorCamera no longer owns a product-specific Core AI framework/C ABI. It weak-links and embeds the shared iOS 27 `AICoreKitCoreAIRuntime.framework`; the lower-minimum host does not directly import the higher-minimum Core AI runtime.
- Historical Xcode 27 archive/weak-link fixture evidence remains valid for the cross-version topology. ColorCamera has additionally completed real iOS 27 Qwen3-0.6B inference on a signed device and validated its configured cloud Color Intelligence path.
- ColorCamera also links `AIProviderConfiguration`. Its explicit Automatic / On-device / Cloud product policy selects the permitted provider path; cloud access remains opt-in, stores API credentials in Keychain, and sends deterministic palette descriptors rather than photos/camera frames.
- Provider endpoints/protocol construction come from AICoreKit presets/factory. Generic response completion uses `AIResponse.validatedCompletedText()`. Palette prompts, bounded schema/language repair, localization checks, role validation, and authoritative HEX mapping remain product-owned.
- Real iOS 27 local inference is no longer an open question for ColorCamera. Lower-OS signed launch/fallback, repeated memory/thermal/cancellation observation, and current Release/distribution validation remain open gates before ColorCamera counts as a completed production consumer.

See `MIGRATION_COLORCAMERA.md`.

## Consumer 2 — FateAtlas

Recommended validation scope:

- keep `Packages/AppAIKit` as a temporary product compatibility layer while removing generic infrastructure beneath it;
- dedicated OpenAI Responses and Anthropic paths;
- DeepSeek/custom through the OpenAI-compatible adapter;
- native structured outputs where genuinely supported;
- streaming, credentials, retry, observability, routing, connection testing, and model-list UX.

FateAtlas is the strongest test that AICoreKit can replace an organically grown application AI abstraction without leaking vendor-specific concepts into product UI.

Current adoption evidence as of 2026-10-02:

- FateAtlas pins AICoreKit `f6660787` through `Packages/AppAIKit`.
- AppAIKit now directly depends on `AICore` and `AIProviderConfiguration` rather than directly depending on each concrete cloud-provider target.
- FateAtlas now stores API credentials in Keychain while leaving non-secret provider/model/base-URL/strategy preferences in UserDefaults; legacy plaintext credentials migrate on first read and are removed after successful secure persistence.
- Its existing OpenAI Responses, Anthropic, and OpenAI-compatible wrappers construct validated `AIProviderProfile` values and delegate provider creation to `AIConfiguredProviderFactory`, preserving endpoint/model/provider identity plus timeout/token/temperature defaults.
- OpenAI generation and connection testing both use the Responses path; Anthropic uses the Anthropic path; DeepSeek/custom compatible endpoints use the compatible path. Duplicate raw URLSession/header implementations that existed only for connection testing were removed.
- Native structured generation remains enabled where the provider contract supports it; DeepSeek/custom compatible structured output keeps the product's validated fallback because generic compatible endpoints do not guarantee one JSON-schema extension.
- Model discovery remains product-owned intentionally: the compatible `/models` helper supports FateAtlas's model-list UX and is not treated as a generic generation contract.
- Earlier package/Release evidence established FateAtlas as the first completed production consumer for the migrated cloud path. No new Release/CI result is claimed for the latest provider-configuration refactor in this round.

FateAtlas therefore remains the **first completed AICoreKit production consumer** for the already-validated migrated cloud path, while broader AppAIKit cleanup can continue incrementally.

See `MIGRATION_FATEATLAS.md`.

## Consumer 3 — MetronomePro

Recommended validation scope:

- AI Practice Summary from deterministic evidence;
- structured next-exercise recommendation;
- evidence-reference validation;
- natural-language metronome/practice actions through tools;
- explicit Automatic / On-device / Cloud Practice Coach execution policy.

MetronomePro must preserve the architectural rule that generative AI interprets deterministic evidence rather than generating the evidence itself.

Current adoption evidence as of 2026-10-03:

- MetronomePro pins an AICoreKit stabilization revision through `Packages/PracticeCoachAI`; the current pin includes `AIResponse.validatedCompletedText()` and the shared local-model provisioning workflow.
- `PracticeFeature` remains the deterministic source of session/activity/timing evidence; `PracticeCoachAI` owns only generative interpretation.
- Practice Coach execution mode is explicit product state: **Automatic** builds available local providers (Apple Foundation Models plus optional Qwen/Core AI) and may add the configured remote provider, then requests `.localFirst`; **On-device** uses the available local providers and requests `.localOnly`; **Cloud** builds remote only and requests `.remoteOnly`. An invalid/missing Cloud configuration does not silently fall back to local execution.
- The configured service is recreated for each generated review, so a Settings change takes effect without restarting or recreating the session view.
- Remote presets are constructed through `AIProviderConfiguration`; shared SettingsFeature UI edits provider/model/base-URL preferences and stores API credentials in Keychain.
- MetronomePro and Metronome26 share the same SettingsFeature implementation, including the three-mode picker, full-width cloud connection-status rows, and all 15 SettingsFeature localizations.
- Contract tests protect the evidence-only request boundary, execution-mode mapping, and remote profile settings. Raw practice recordings are not sent to remote language models, and AI output cannot mutate factual practice time, goals, achievements, or leaderboard data.
- MetronomePro/26 wire an optional Qwen3-0.6B Core AI provider plus shared `CoreAIModelSettingsStore` lifecycle UI. The product command `./Scripts/install_practice_coach_local_model.sh` now delegates export/install to AICoreKit `provision-coreai-model.sh` and targets the shared `PracticeCoachAI` Swift Package resource used by both apps. The generated model remains git-ignored. **The real Qwen resource still needs to be provisioned and exercised on a signed device before the Qwen Practice Coach path is considered validated.**
- AICore exposes `AIResponse.validatedCompletedText()` so consumers reject non-empty truncated, blocked, cancelled, failed, or otherwise incomplete generations before product-specific validation. Practice Coach performs one bounded repair retry for incomplete output.

Until a real current full-app production/Release build or archive succeeds, MetronomePro does **not** count as a completed production consumer.

See `MIGRATION_METRONOMEPRO.md`.

## 1.0 exit rule

The Roadmap item “At least three production consumers” remains unchecked. FateAtlas currently counts as one completed production consumer; ColorCamera and MetronomePro still have open production-validation gates.

The first `1.0.0` tag should also wait for the signed-device Core AI validation gate in the Local Runtime roadmap section.
