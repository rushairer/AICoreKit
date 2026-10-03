# ColorCamera integration with AICoreKit

Current integration baseline: 2026-10-03.

ColorCamera is the primary production reference for AICoreKit's lower-minimum host + higher-minimum Core AI runtime, app-supplied local model lifecycle, explicit local/cloud execution policy, and product-owned semantic validation.

This document describes the **current architecture**. Historical product-specific Core AI framework/C ABI experiments are no longer the production design.

## Integration goal

AICoreKit owns reusable AI runtime/provider infrastructure.

ColorCamera owns color-domain truth, prompts, output semantics, deterministic validation, and user experience.

The boundary is:

```text
ColorCamera product intent / color facts
                |
                v
         AICoreKit providers
                |
                v
       generated candidate output
                |
                v
ColorCamera domain/language/role validation
                |
                v
          product UI / apply
```

Generative AI remains optional. Deterministic color math, accessibility analysis, palette editing, and export must continue to work when no generative provider is available.

## Current provider architecture

Color Intelligence has three product execution modes:

- **Automatic** — try on-device providers first, then an explicitly enabled cloud provider if needed;
- **On-device** — use only local/system providers;
- **Cloud** — use only the configured remote provider.

The mode is product state. AICoreKit supplies routing/provider mechanisms but does not own the Settings labels or preference semantics.

### Apple Foundation Models

ColorCamera keeps its product-specific Apple Foundation Models adapter where native product schema behavior is useful.

Do not move palette types or naming semantics into AICoreKit merely to eliminate this adapter.

### Qwen / Core AI local provider

The production local path uses AICoreKit infrastructure:

- `CoreAIModelProfile`;
- `CoreAIDirectoryModelResourceProvider`;
- `CoreAIProvider`;
- `CoreAIModelLifecycleController`;
- `CoreAIModelSettingsStore`;
- `AIProviderCoreAIWeakLink`;
- `WeakLinkedCoreAIBridge`;
- shared `AICoreKitCoreAIRuntime.framework`.

ColorCamera no longer owns a product-specific Core AI framework or C ABI.

The iOS 26 host must not import or directly link `CoreAILM` / `CoreAILanguageModels`. The shared iOS 27 runtime is embedded by the app and loaded through the AICoreKit weak-link boundary only on supported systems.

### Cloud provider

ColorCamera uses `AIProviderConfiguration` profiles/presets/factory infrastructure.

The product owns:

- provider/model/base-URL preferences;
- Keychain credential persistence;
- connection-test UX;
- Automatic/On-device/Cloud semantics.

Remote Color Intelligence receives deterministic palette descriptors. Photos and camera frames are not sent to the cloud generation path.

## Local model provisioning

ColorCamera's developer entry point is:

```bash
./scripts/core_ai/install_qwen3_local_model.sh
```

The product wrapper resolves the AICoreKit revision pinned by the Xcode project and delegates model export/install to AICoreKit shared tooling.

If an existing export exists at `Artifacts/CoreAI/ColorCameraLocalModel`, the wrapper reuses it. Otherwise the shared AICoreKit provisioning path can export Qwen3-0.6B first.

The installed product resource is:

```text
ColorCamera/Resources/ColorCameraLocalModel
```

Generated model files remain git-ignored.

Do not reintroduce independent ColorCamera copies of Apple `coreai-models` checkout/export/copy/validation logic. See `LOCAL_MODELS.md`.

A repository checkout without model assets may still build and report `localModelMissing`. That proves graceful degradation only; it is not local-inference acceptance evidence.

ColorCamera has already completed real signed-device iOS 27 Qwen3-0.6B inference, so the shared runtime/model path has production-consumer evidence.

## Lifecycle contract

Keep these states distinct:

1. model resource installed;
2. persistent preparation absent/present;
3. current-process resource loading;
4. ready for generation;
5. current-process residency unloaded;
6. persistent preparation cache cleared.

First preparation can be expensive. Later launches should use `bootstrapIfPrepared()` and perform only the faster load when persistent preparation already exists.

App launch must not trigger the expensive first preparation for an unprepared model.

`unload()` clears current-process residency only.

`clearPreparationCache()` unloads and clears persistent specialization, causing the next actual use to pay first-preparation cost again while leaving installed model files intact.

Settings and first-use UI consume the shared `CoreAIModelSettingsStore`; do not create a second product lifecycle state machine.

## Product-owned Color Intelligence semantics

These stay in ColorCamera:

- `PaletteFacts` and deterministic color calculations;
- OKLab / OKLCH facts;
- deterministic color descriptors;
- palette naming policy;
- palette-specific prompts;
- palette JSON/structured schema;
- semantic role types and validation;
- role-to-authoritative-HEX mapping;
- output language validation;
- generic-name detection;
- bounded schema/language repair prompts;
- WCAG/accessibility validation;
- Color Intelligence UI/progress copy.

AICoreKit must not learn palette, hue-family, ColorCamera naming, or WCAG product semantics.

## Prompt and small-model rules

Local Qwen prompts must consume deterministic color descriptors rather than asking the language model to derive color truth from raw HEX/hue values.

Do not include concrete creative names as positive style examples. Small models can overfit and repeat them.

Do not list overused words as negative examples merely to forbid them; lexical priming can increase repetition. Keep vocabulary/cliche detection in product-side validators and phrase prompt constraints abstractly.

Locale instructions are not enough. Validate actual generated user-visible fields against the app language.

## Response validation

Provider output is not successful merely because `response.text` is non-empty.

For generic text completion, AICoreKit owns:

```swift
try response.validatedCompletedText()
```

which rejects truncated, blocked, cancelled, failed, tool-call-only, or empty responses as appropriate.

ColorCamera then applies product validation:

1. schema/decoding;
2. required semantic content;
3. language;
4. palette membership and role validity;
5. generic naming/cliche rules;
6. authoritative color mapping.

ColorCamera may perform a **bounded** repair retry for product-specific schema/language problems. Do not move those repair prompts into AICoreKit.

## Cloud privacy boundary

Cloud generation receives only the deterministic palette evidence needed for the feature.

Never send:

- camera frames;
- source photos;
- unrelated user media.

Connection testing is a separate explicit Settings action and does not change the execution-mode privacy contract.

API credentials remain in Keychain or another host-owned secure store. AICoreKit does not persist product secrets.

## Validation evidence

As of 2026-10-03:

- shared AICoreKit lifecycle/store is used by Settings, first use, and launch bootstrap;
- shared `AICoreKitCoreAIRuntime.framework` replaces the old product runtime;
- Qwen3-0.6B local inference has succeeded on a real iOS 27 device;
- configured cloud Color Intelligence has succeeded on a real device;
- first preparation and later warm load are distinguished;
- cloud/local response completion is validated before product semantics;
- lower-minimum host / higher-minimum runtime topology has independent AICoreKit Compatibility Lab archive evidence.

## Remaining production gates

The Color Intelligence implementation is functionally validated, but the complete AICoreKit 1.0 compatibility/distribution gate still includes:

- signed lower-OS physical-device launch/fallback evidence;
- repeated cancellation behavior;
- memory/thermal observation under realistic camera + AI workload;
- current signed Release/distribution/App Store packaging evidence.

These open gates must not be confused with the already successful iOS 27 local inference result.

## Agent rules

When an agent works on ColorCamera AI:

- read AICoreKit `docs/CONSUMER_INTEGRATION.md` and `docs/LOCAL_MODELS.md`;
- do not recreate Core AI runtime/export/install/lifecycle infrastructure in ColorCamera;
- use the product provisioning wrapper before claiming a local-model path is ready;
- keep palette semantics and repair policy in ColorCamera;
- keep deterministic color math authoritative;
- do not claim device/distribution validation that was not actually run;
- when a new reusable issue is discovered, first determine whether it is provider/runtime-wide before moving it into AICoreKit.
