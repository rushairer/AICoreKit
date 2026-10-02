# Production consumer plan

AICoreKit 1.0 requires evidence from real product integrations, not only package fixtures.

The target is three production consumers with deliberately different workloads.

## Consumer matrix

| Product | Current state | Intended AICoreKit role | Main validation |
| --- | --- | --- | --- |
| ColorCamera | Pins AICoreKit `f6660787`; local Core AI lifecycle uses reset-safe serialized readiness; optional cloud palette fallback uses `AIProviderConfiguration` with Keychain credentials | Shared local lifecycle + reusable cloud-provider infrastructure while palette semantics remain product-owned | iOS 26 host / iOS 27 local runtime, weak link, first-use preparation vs fast load, cloud descriptor-only fallback |
| FateAtlas | Pins AICoreKit `f6660787`; AppAIKit keeps the product API while provider construction, chat/streaming, structured cloud paths, and connection-test protocol execution delegate to AICoreKit | Incrementally remove duplicated generic provider/runtime plumbing without leaking vendor details into product UI | OpenAI Responses, Anthropic, DeepSeek/custom compatible endpoints, structured generation, streaming/fallback |
| MetronomePro | Pins AICoreKit `f6660787`; Practice Coach is Apple-local-first with optional user-configured cloud fallback through `AIProviderConfiguration` and Keychain | Evidence-grounded Practice Coach with reusable local/cloud routing | deterministic evidence boundary, local-first fallback, shared settings across MetronomePro/Metronome26 |

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

Current adoption evidence as of 2026-10-02:

- ColorCamera pins AICoreKit `f6660787` in both the Xcode project and committed `Package.resolved`.
- `CoreAIModelLifecycleController` now owns the reusable lifecycle: persistent preparation, prepared-resource loading, full readiness, and launch bootstrap share serialized in-flight work; unload/cache-clear gate out new readiness until reset finishes.
- The product-owned iOS 27 `ColorCameraCoreAI` runtime and its weak C ABI remain the compatibility boundary for palette generation. The iOS 26 host does not directly import the higher-minimum Core AI runtime.
- Historical Xcode 27 archive/weak-link fixture evidence remains valid for the established cross-version topology, but this round does not claim a new signed archive or Xcode Cloud result.
- ColorCamera also links `AIProviderConfiguration`. Cloud fallback is opt-in, comes after on-device providers, stores API credentials in Keychain, and sends deterministic palette descriptors rather than photos/camera frames.
- Provider endpoints/protocol construction come from AICoreKit presets/factory. Palette prompts, localization checks, role validation, and authoritative HEX mapping remain product-owned.
- Signed-device iOS 26/iOS 27 qualification, repeated memory/thermal/cancellation observation, and current Release/distribution validation remain open gates before ColorCamera counts as a completed production consumer.

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
- Apple-local-first with optional cloud fallback.

MetronomePro must preserve the architectural rule that generative AI interprets deterministic evidence rather than generating the evidence itself.

Current adoption evidence as of 2026-10-02:

- MetronomePro pins AICoreKit `f6660787` through `Packages/PracticeCoachAI`.
- `PracticeFeature` remains the deterministic source of session/activity/timing evidence; `PracticeCoachAI` owns only generative interpretation.
- The default service registry contains Apple Foundation Models first and requests `.localFirst`. If the user explicitly enables a valid remote profile, the AICoreKit orchestrator may fall back to it after local generation fails.
- Remote presets are constructed through `AIProviderConfiguration`; shared SettingsFeature UI edits provider/model/base-URL preferences and stores API credentials in Keychain.
- MetronomePro and Metronome26 share the same settings implementation rather than forking provider configuration.
- Contract tests protect the evidence-only request boundary and remote profile settings. Raw practice recordings are not sent to remote language models, and AI output cannot mutate factual practice time, goals, achievements, or leaderboard data.
- Historical module-level validation remains useful evidence, but this round does not claim a new full-app Release/archive or CI result. Full application production validation remains open.

Until a real current full-app production/Release build or archive succeeds, MetronomePro does **not** count as a completed production consumer.

See `MIGRATION_METRONOMEPRO.md`.

## 1.0 exit rule

The Roadmap item “At least three production consumers” remains unchecked. FateAtlas currently counts as one completed production consumer; ColorCamera and MetronomePro still have open production-validation gates.

The first `1.0.0` tag should also wait for the signed-device Core AI validation gate in the Local Runtime roadmap section.
