# Production consumer plan

AICoreKit 1.0 requires evidence from real product integrations, not only package fixtures.

The target is three production consumers with deliberately different workloads.

## Consumer matrix

| Product | Current state | Intended AICoreKit role | Main validation |
| --- | --- | --- | --- |
| ColorCamera | Existing Apple Foundation Models + product-specific Core AI/Qwen implementation | Gradual migration of reusable provider/runtime infrastructure | iOS 26 host / iOS 27 local runtime, weak link, resource lifecycle, local fallback |
| FateAtlas | Existing internal `AppAIKit` with Apple/cloud providers | Replace duplicated generic AI package with AICoreKit | cloud providers, user-selected endpoints, structured generation, streaming/fallback |
| MetronomePro | AICoreKit pinned in PracticeFeature; on-demand AI Practice Coach path implemented on main, build/archive verification pending | New AI Practice Coach and natural-language actions | evidence-grounded generation, tool calling, local/cloud routing |

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

See `MIGRATION_COLORCAMERA.md`.

## Consumer 2 — FateAtlas

Recommended validation scope:

- replace `Packages/AppAIKit` generic provider/core types;
- dedicated OpenAI Responses and Anthropic adapters;
- DeepSeek/custom through OpenAI-compatible adapter;
- native structured outputs where genuinely supported;
- streaming, credentials, retry, observability, and routing.

FateAtlas is the strongest test that AICoreKit can replace an organically grown application AI abstraction without leaking vendor-specific concepts into product UI.

See `MIGRATION_FATEATLAS.md`.

## Consumer 3 — MetronomePro

Recommended validation scope:

- AI Practice Summary from deterministic evidence;
- structured next-exercise recommendation;
- evidence-reference validation;
- natural-language metronome/practice actions through tools;
- local-first with optional cloud fallback.

MetronomePro must preserve the architectural rule that generative AI interprets deterministic evidence rather than generating the evidence itself.

Current adoption evidence as of 2026-10-01:

- MetronomePro main `578baf32` pins AICoreKit revision `90ccfa36` in `PracticeFeature` and adds the evidence-grounded Practice Coach service plus product-level evidence-boundary tests.
- MetronomePro main `4209f9e1` adds the user-visible, on-demand Practice Session Detail review path and complete Practice Coach localization coverage for the existing 15 PracticeFeature locales.
- The generated review is ephemeral, cancellable, and cannot mutate Practice facts, Estimated Effective Time, goals, streaks, achievements, or leaderboard data.
- GitHub Actions does not currently provide build/archive evidence for this integration because `METRONOMEPRO_CI_READ_TOKEN` is not configured; the workflow therefore skips targets that require the private `MetronomeEngine` dependency.
- Until a real PracticeFeature build/test and production/Release archive succeed, MetronomePro does **not** count as a completed production consumer.

See `MIGRATION_METRONOMEPRO.md`.

## 1.0 exit rule

The Roadmap item “At least three production consumers” remains unchecked until all three integrations satisfy the production-consumer definition above.

The first `1.0.0` tag should also wait for the signed-device Core AI validation gate in the Local Runtime roadmap section.
