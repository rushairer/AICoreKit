# Production consumer plan

AICoreKit 1.0 requires evidence from real product integrations, not only package fixtures.

The target is three production consumers with deliberately different workloads.

## Consumer matrix

| Product | Current state | Intended AICoreKit role | Main validation |
| --- | --- | --- | --- |
| ColorCamera | AICoreKit is a real app dependency; lifecycle is routed through `CoreAIModelLifecycleController`; product `ColorCameraCoreAI` now exposes one-to-one Prepare/Load/Reset/Clear semantics and passes Xcode 27 Release archive + iOS 26 weak-host validation; full signed app/distribution validation remains open | Gradual migration of reusable provider/runtime infrastructure | iOS 26 host / iOS 27 local runtime, weak link, resource lifecycle, local fallback |
| FateAtlas | Production cloud chat/streaming paths now delegate to AICoreKit; AppAIKit remains the product-facing compatibility layer; package tests and a Release generic iOS app build pass | Replace duplicated generic transport/provider runtime incrementally | cloud providers, user-selected endpoints, structured generation, streaming/fallback |
| MetronomePro | User-visible Practice Coach now routes through a dedicated `PracticeCoachAI` package pinned to AICoreKit; module Release build and contract tests pass; full app Release validation remains blocked by private dependency CI credentials | New AI Practice Coach and natural-language actions | evidence-grounded generation, tool calling, local/cloud routing |

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
- local/system fallback;
- deterministic palette validation retained outside AICoreKit.

ColorCamera should not be forced to remove its product-specific `@Generable` Apple adapter until equivalent behavior exists through a reusable contract.

Current adoption evidence as of 2026-10-02:

- ColorCamera main `be6c77e2` pins the validated AICoreKit baseline `794abcbd` and links only the host-safe `AICore` + `AIProviderCoreAI` products into the iOS 26 app target.
- The existing `CoreAIModelPrewarmer` is now a product facade over AICoreKit's `CoreAIModelLifecycleController`; persistent preparation inspection, launch-safe bootstrap, shared readiness, runtime unload, preparation-cache clearing, and stale-completion invalidation are coordinated by AICoreKit.
- The iOS 27 `ColorCameraCoreAI` framework remains product-specific for palette generation and repair. The migration intentionally does not import AICoreKit's higher-minimum runtime into the iOS 26 host.
- ColorCamera main `294ca270` splits its product C ABI into `CCACoreAIPrepare` (persistent `PreparedModel.prepare`) and `CCACoreAILoad` (process-resident eager load); `CCACoreAIReset` unloads without clearing preparation, `CCACoreAIClearPreparationCache` removes persistent specialization, and legacy `CCACoreAIPrewarm` remains only as prepare-if-needed + load compatibility.
- ColorCamera main `d9595df9` passes the Xcode 27 product Core AI **Release archive** after that runtime split. Main `be6c77e2` extends the fixture so the iOS 26 host directly references `CCACoreAIIsAvailable`, `CCACoreAIPrepare`, and `CCACoreAILoad`; all three references remain weak and the archive stays green.
- AICoreKit CI now includes a Swift 5 language-mode lifecycle consumer fixture, matching ColorCamera's host language mode, and that fixture compiles successfully.
- The Compatibility Lab now also archives a minimal iOS 26 application that weak-links and embeds the iOS 27 Core AI runtime. Xcode 27 Release archive succeeds with app `MinimumOSVersion = 26.0`, runtime `MinimumOSVersion = 27.0`, `LC_LOAD_WEAK_DYLIB`, and the weak C ABI reference intact. This proves the cross-version archive topology independently from ColorCamera; it does not replace ColorCamera's signed-device/App Store distribution gate.
- ColorCamera's release gate checks the immutable AICoreKit revision in both the Xcode project and committed `Package.resolved`; the resolved-file origin hash was also updated for the new top-level dependency graph.
- ColorCamera Xcode Cloud was already failing on the pre-migration baseline `ca333dd1` and several earlier commits. The current Xcode Cloud failure therefore remains a separate historical CI/release issue rather than evidence that the AICoreKit lifecycle migration introduced a regression.
- The product Core AI runtime/archive boundary is now validated, but a full ColorCamera production target Release/archive with signing/distribution evidence and signed-device iOS 26/iOS 27 validation are still required before ColorCamera counts as a completed production consumer.

See `MIGRATION_COLORCAMERA.md`.

## Consumer 2 — FateAtlas

Recommended validation scope:

- replace `Packages/AppAIKit` generic provider/core types;
- dedicated OpenAI Responses and Anthropic adapters;
- DeepSeek/custom through OpenAI-compatible adapter;
- native structured outputs where genuinely supported;
- streaming, credentials, retry, observability, and routing.

FateAtlas is the strongest test that AICoreKit can replace an organically grown application AI abstraction without leaking vendor-specific concepts into product UI.

Current adoption evidence as of 2026-10-02:

- FateAtlas main `03b65310` pins the validated AICoreKit baseline `794abcbd` through `Packages/AppAIKit`.
- OpenAI-compatible chat/streaming (including DeepSeek/custom endpoints) and Anthropic chat/streaming execute through AICoreKit providers while AppAIKit preserves FateAtlas's existing public API.
- Product-specific `fetchModels()` and connection testing remain in AppAIKit for incremental migration; the migrated chat/streaming path no longer maintains an independent URLSession/SSE transport implementation.
- FateAtlas main `03b428cb` adds explicit product-owned JSON Schemas for zodiac, astrology, and BaZi enhancement payloads. When the configured remote protocol is Anthropic, those three production structured tasks now execute through AICoreKit's native `AIProviderAnthropic.generateStructured` path rather than prompt-only JSON extraction.
- DeepSeek/custom/OpenAI-compatible structured generation intentionally keeps the validated product fallback because generic chat-completions endpoints do not share one reliable JSON Schema extension. Apple local structured generation also remains a product fallback.
- AppAIKit package tests pass after the native structured migration.
- The full FateAtlas app succeeds in a code-signing-disabled **Release** generic iOS build after the native Anthropic structured migration, with the AICoreKit-backed path linked into the production app target.
- This satisfies the current production-consumer gate for the migrated cloud chat/streaming path. Remaining AppAIKit capabilities can migrate incrementally without invalidating that evidence.

FateAtlas therefore counts as the **first completed AICoreKit production consumer**.

See `MIGRATION_FATEATLAS.md`.

## Consumer 3 — MetronomePro

Recommended validation scope:

- AI Practice Summary from deterministic evidence;
- structured next-exercise recommendation;
- evidence-reference validation;
- natural-language metronome/practice actions through tools;
- local-first with optional cloud fallback.

MetronomePro must preserve the architectural rule that generative AI interprets deterministic evidence rather than generating the evidence itself.

Current adoption evidence as of 2026-10-02:

- MetronomePro main `98a48f0a` keeps the generative layer in `Packages/PracticeCoachAI`, now pinned to the validated AICoreKit baseline `794abcbd`. `PracticeFeature` keeps deterministic session/activity/timing evidence construction and depends on the small AI package only for interpretation.
- The production Practice Session Detail path still creates `PracticeCoachEvidence` from deterministic facts and calls `PracticeCoachService`; there is no alternate generic provider abstraction for this migrated path.
- `PracticeCoachAI` uses AICoreKit `AICore`, `AIOrchestration`, and `AIProviderApple` with `.localFirst` text generation. Its contract tests verify that the request contains only the supplied evidence JSON plus explicit unknowns and cannot turn unmeasured time, motivation, cheating, pitch accuracy, or musical expression into facts.
- MetronomePro main `98a48f0a` has repeatable CI evidence that `PracticeCoachAI` builds in **Release** configuration and its tests pass against AICoreKit `794abcbd` without access to the private `MetronomeEngine` repository.
- Full `PracticeFeature`, MetronomePro, and Metronome26 Release builds remain gated by `METRONOMEPRO_CI_READ_TOKEN`. When the token is absent the workflow explicitly warns and skips those steps; the green workflow is therefore module-level evidence, not full application Release evidence.
- Both Metronome Xcode Cloud workflows were already failing before the current AICoreKit/package extraction, so those historical red statuses are tracked separately rather than treated as proof of an AICoreKit regression.
- Until a real full-app production/Release build or archive succeeds, MetronomePro does **not** count as a completed production consumer.

See `MIGRATION_METRONOMEPRO.md`.

## 1.0 exit rule

The Roadmap item “At least three production consumers” remains unchecked. FateAtlas currently counts as one completed production consumer; ColorCamera and MetronomePro still have open production-validation gates.

The first `1.0.0` tag should also wait for the signed-device Core AI validation gate in the Local Runtime roadmap section.
