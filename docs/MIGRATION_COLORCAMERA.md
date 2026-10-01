# Migrating ColorCamera to AICoreKit

Baseline reviewed: `rushairer/ColorCamera` main at `0013fccf4cfd31f3e86d5f39852d628c33b815db`.

This guide is intentionally conservative. ColorCamera is the source of several AICoreKit compatibility ideas, but its current AI implementation also contains product-specific capabilities that AICoreKit must not erase.

## Migration goal

Use AICoreKit for reusable AI runtime/provider infrastructure while keeping ColorCamera's color-domain intelligence, deterministic validation, localization, UI progress, and model UX inside ColorCamera.

The migration is complete only when behavior is preserved on both iOS 26 and iOS 27.

## Current ColorCamera architecture

The current product has two generative paths behind `ColorIntelligenceProviding`:

1. `AppleFoundationModelColorIntelligenceProvider`
   - uses Apple Foundation Models directly;
   - uses `@Generable` product-specific output types;
   - maps generated color indices back to authoritative palette colors.

2. `CoreAILocalModelColorIntelligenceProvider`
   - uses the weak-linked `ColorCameraCoreAI` iOS 27 framework;
   - owns Qwen model resource discovery;
   - coordinates preparation, runtime loading, prewarming, reset, progress, retry, and timeout behavior;
   - exchanges a product-specific palette request/response over the current `CCACoreAI*` C ABI.

`ColorIntelligenceService` owns fallback ordering and runs generated output through product validation before returning it.

## What must stay in ColorCamera

The following are product/domain logic and should not move into AICoreKit:

- `PaletteFacts`, `PaletteFactsBuilder`, and deterministic color calculations;
- semantic color descriptors such as hue/lightness/chroma bands;
- `PaletteIntelligence` and palette-role domain types;
- `PaletteRoleValidator`;
- output-language validation and locale-specific generation instructions;
- product prompts and naming rules;
- generic-name repair rules;
- mapping generated role indices back to authoritative palette HEX values;
- ColorCamera UI progress states and Settings UI;
- model-install UX and product-owned resource packaging decisions.

AICoreKit should never learn what a palette, hue family, WCAG rule, or ColorCamera naming convention is.

## What AICoreKit can replace

AICoreKit is the intended home for reusable infrastructure such as:

- provider identity, availability, capabilities, and normalized errors;
- provider routing/fallback primitives where they fit the product flow;
- weak-linked Core AI host/runtime boundary;
- local model resource lifecycle abstractions;
- cloud provider adapters;
- credentials, retry, and observability;
- normalized structured generation and tool calling for providers that support those contracts.

## Important parity gaps

Do not delete ColorCamera's current AI code until these differences are resolved.

| Area | ColorCamera today | AICoreKit today | Migration implication |
| --- | --- | --- | --- |
| Apple structured output | Native `@Generable` product schema | Apple provider advertises text generation only | Keep the ColorCamera Apple adapter until AICoreKit has an equally reliable native structured extension, or intentionally keep this adapter permanently as a product-specific provider. |
| Core AI ABI | `CCACoreAIAnalyze/Prewarm/Reset` with product JSON and progress | Generic `AICKCoreAIGenerate/Prepare/Unload` ABI | Do not swap binaries in place. Introduce an adapter/runtime migration with explicit parity tests. |
| Progress | Preparing/loading/warming/generating stages | Generic provider response has no model-progress channel | Keep ColorCamera progress coordination until a reusable progress contract exists. |
| Preparation semantics | Persistent preparation is separate from runtime loading; app tracks prepared/ready states | Generic lifecycle exposes prepare/release | Verify semantic equivalence before replacing ColorCamera initialization state. |
| Reset | Product exposes runtime cache reset | Generic lifecycle currently exposes unload/release, not the same UX contract | Preserve reset behavior or add a reusable runtime-reset extension first. |
| Domain validation | Strong post-generation language/role validation | Provider-neutral | Must remain in ColorCamera. |

## Recommended migration sequence

### Phase 0 — Add AICoreKit without behavior changes

Add AICoreKit as a package dependency, pinned to a known revision or pre-1.0 release.

Do not remove:

- `ColorCameraCoreAI`;
- the current weak bridge;
- `AppleFoundationModelColorIntelligenceProvider`;
- `CoreAILocalModelColorIntelligenceProvider`.

The purpose of this phase is compile/link integration only.

### Phase 1 — Adopt common contracts at the edges

Introduce ColorCamera adapters that translate between product types and AICoreKit types where this is genuinely reusable:

- map AICoreKit availability/errors into `ColorIntelligenceUnavailableReason`;
- use AICoreKit provider IDs/capabilities for diagnostics rather than inventing another provider taxonomy;
- use AICoreKit observability for provider/runtime metrics where it does not expose palette data.

Keep `ColorIntelligenceProviding` as the product-facing protocol.

### Phase 2 — Migrate the Core AI host boundary

Build an A/B implementation behind `ColorIntelligenceProviding`:

- current `CCACoreAI*` path;
- AICoreKit `AIProviderCoreAI` + `AIProviderCoreAIWeakLink` path.

The AICoreKit path must preserve:

- iOS 26 launch without loading the iOS 27 image;
- iOS 27 model discovery;
- long first preparation versus fast subsequent runtime load;
- explicit reset semantics;
- cancellation/timeouts;
- user-visible progress;
- identical deterministic post-validation.

If progress/reset cannot be preserved, extend AICoreKit with a reusable contract before switching the product.

### Phase 3 — Decide Apple Foundation Models ownership

ColorCamera currently gets value from product-native `@Generable` output.

Two valid end states exist:

1. AICoreKit gains a reliable Apple-native structured-generation extension and ColorCamera adopts it; or
2. ColorCamera keeps a thin Apple product adapter while AICoreKit remains responsible for the shared provider/runtime infrastructure.

Do not downgrade native structured generation to prompt-only JSON simply to reduce file count.

### Phase 4 — Remove duplicated runtime infrastructure

Only after device/archive parity is proven:

- remove redundant ColorCamera weak-link/runtime code that AICoreKit fully replaces;
- remove duplicate availability/error normalization;
- keep domain prompts, validation, and UI state in ColorCamera.

## Acceptance gates

The migration is not complete until all of these pass:

- iOS 26 physical-device cold launch with the iOS 27 runtime embedded weakly;
- iOS 27 physical-device real Qwen inference;
- first preparation and subsequent fast-load behavior;
- model reset followed by a clean re-preparation cycle;
- cancellation and timeout handling;
- memory and thermal observation during repeated inference;
- Release archive and distribution validation;
- existing ColorCamera language-validation tests;
- deterministic role/HEX validation;
- current Xcode Cloud build.

## Dependency direction

The desired dependency graph is:

```text
ColorCamera domain/UI
        |
        +-- ColorIntelligenceProviding
        |       |
        |       +-- product-specific adapters
        |
        +-- AICoreKit
                |
                +-- Apple/system provider infrastructure
                +-- Core AI host/runtime infrastructure
                +-- optional cloud providers
```

AICoreKit must not depend on ColorCamera.

## First production use

ColorCamera is a strong candidate to become the first AICoreKit production consumer because it already exercises the hardest compatibility boundary: a lower-minimum iOS host with an optional higher-minimum local AI runtime.

The migration should remain incremental until the remaining signed-device and distribution gates are complete.
