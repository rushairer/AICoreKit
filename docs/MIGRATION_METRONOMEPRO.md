# Adopting AICoreKit in MetronomePro

Baseline reviewed: `rushairer/MetronomePro` main at `cd85903140fcb552d1c427f966de9579693d0e23`.

MetronomePro is a strong third AICoreKit consumer because its architecture already separates deterministic musical evidence from future generative interpretation.

## Product rule

MetronomePro's existing architecture contract is authoritative:

> DSP and deterministic measurements come before generative AI.

AICoreKit may explain evidence, connect observations across practice history, and propose exercises. It must not replace onset detection, timing alignment, effective-practice estimation, score identity, or other deterministic analysis with free-form model judgment.

The existing principle that Practice Activity Analysis is an observational aid rather than an authority also remains unchanged. AI output must not alter factual Practice time, goals, streaks, achievements, or leaderboards.

## Best first integration

The first production AICoreKit feature should be a post-session Practice Coach summary.

Input should be structured evidence already computed by MetronomePro, for example:

- factual Practice duration;
- Estimated Effective Time plus analysis coverage;
- trusted timing tendency/spread/coverage;
- tempo trajectory;
- trusted difficult ranges;
- stable score/event/range references when available;
- recent longitudinal trend when 1.7 analytics provides it.

Output should be concise language such as:

- what the measurements suggest;
- one or two actionable next exercises;
- a suggested tempo/range for the next practice task.

The model must not invent unmeasured pitch accuracy, musical expression, effort, cheating, or mistakes.

## Why this validates AICoreKit

This consumer exercises a different part of the library than ColorCamera and FateAtlas:

| Consumer | Primary AICoreKit validation |
| --- | --- |
| ColorCamera | lower-minimum host + higher-minimum local Core AI runtime, local fallback, privacy |
| FateAtlas | cloud providers, structured output, streaming, user-selected providers |
| MetronomePro | evidence-grounded generation, local/cloud routing, structured tool actions |

Together the three products cover the main reusable architecture without forcing one product's domain into the shared package.

## Evidence boundary

MetronomePro already exposes stable downstream identities such as:

- `PerformanceObservationReference`;
- `PracticeFindingReference`;
- `ScoreRangeReference`;
- `AIEvidenceReference`.

These identities should remain outside AICoreKit as product/domain data.

When sent to a model, use a product-owned DTO that includes:

- human-readable evidence needed for interpretation;
- stable internal evidence IDs/references for traceability;
- confidence/coverage state;
- explicit statements of what was not measured.

AICoreKit transports and routes this input. It does not define musical truth.

## Recommended architecture

```text
Practice / DigitalScore / DSP
          |
          v
Deterministic Evidence Builder
          |
          +--> factual Practice UI
          |
          +--> AI Coach Input DTO
                    |
                    v
               AICoreKit
          local/system/cloud provider
                    |
                    v
        AI Coach Structured Response
                    |
                    v
       Product Validation / Rendering
                    |
                    +--> summary
                    +--> recommendation
                    +--> optional practice action
```

## Phase 0 — Dependency integration

Add AICoreKit to the appropriate app/package boundary without adding user-visible AI.

Pin a known pre-1.0 revision.

Verify:

- both Metronome26 and MetronomePro product targets still build where applicable;
- package dependency direction remains acyclic;
- DigitalScore and Practice packages do not start depending on provider-specific modules.

Prefer a small product-side AI feature package/service that depends on both domain evidence and AICoreKit, rather than making low-level DSP/DigitalScore packages import AICoreKit.

## Phase 1 — AI Practice Summary

Create a product DTO, for example conceptually:

```text
PracticeCoachEvidence
- session duration
- estimated effective duration
- analysis coverage
- timing observations
- tempo observations
- trusted finding references
- explicit unknowns
```

Generate a short summary after a session.

Initial policy:

- local-first when a supported local provider is available;
- graceful no-AI fallback;
- no effect on persisted factual metrics;
- no effect on Game Center/leaderboards;
- output may be discarded/re-generated because the evidence is canonical, not the prose.

## Phase 2 — Structured recommendation

Use native structured output where the selected provider supports it.

A product-owned response might contain:

```text
PracticeCoachRecommendation
- summary
- evidenceReferenceIDs
- suggestedExercise
- suggestedTempoBPM?
- suggestedRange?
- confidenceLanguage
```

Validate all references against the current session/score before rendering.

Never let the model manufacture a score range or event ID that does not resolve.

For Apple local execution, do not call AICoreKit's text-only Apple provider “native structured generation” unless that capability is actually added. A product-specific validated adapter is acceptable.

## Phase 3 — Natural-language metronome actions

AICoreKit tool calling is a good fit for commands such as:

- set tempo;
- change time signature;
- change accent pattern;
- start a timed tempo progression;
- create a targeted practice task from an AI recommendation.

Tools should be product-owned and schema-constrained.

Examples of safe tool categories:

- read current metronome state;
- set BPM within product limits;
- select a known time signature;
- create a draft practice routine.

Do not expose arbitrary persistence/destructive actions as auto-approved tools.

AICoreKit's default read-only policy and confirmation policy should remain in force for mutating actions.

## Phase 4 — Parent/week review

Once longitudinal Practice Analytics is stable, AICoreKit can turn deterministic weekly aggregates into a parent-facing report.

The report should explain:

- practice frequency/duration;
- estimated effective-time context and coverage;
- tempo/stability trends;
- repeated trusted findings;
- suggested next focus.

It should not claim motivation, diligence, dishonesty, or musical quality that the data does not measure.

## Local-model option

Qwen3-0.6B/Core AI is potentially useful for short summaries and intent parsing if device latency and memory are acceptable.

Do not move DSP into the language model.

If MetronomePro adopts the Core AI runtime, reuse AICoreKit's generic Core AI boundary rather than cloning ColorCamera's product-specific C ABI. Product-specific model packaging/resource UX remains owned by MetronomePro.

MetronomePro/26 now use Apple Foundation Models plus an optional Qwen3-0.6B Core AI provider for the On-device Practice Coach path. Both apps share AICoreKit `CoreAIModelProfile`, `CoreAIModelSettingsStore`, `CoreAIDirectoryModelResourceProvider`, and the product-neutral weak-link runtime. The iOS targets weak-link/embed `AICoreKitCoreAIRuntime.framework`.

The missing operational step is explicit: the real Qwen resource must be provisioned into `Packages/PracticeCoachAI/Sources/PracticeCoachAI/Resources/MetronomeLocalModel` before the Qwen path can be device-qualified. The product wrapper is:

```bash
./Scripts/install_practice_coach_local_model.sh
```

That wrapper resolves the AICoreKit revision pinned by `PracticeCoachAI` and delegates export/install to AICoreKit `Scripts/provision-coreai-model.sh`. An existing exported model directory may be passed as the first positional argument. A no-model build is expected to degrade cleanly, but it is not evidence that Qwen inference works. See `LOCAL_MODELS.md`.

## Cloud option

Cloud providers can be enabled without coupling product code to a vendor:

- OpenAI Responses;
- Anthropic;
- Gemini;
- an OpenAI-compatible application gateway.

Production credentials should normally be supplied through an application/server gateway rather than embedded vendor secrets.

The user's practice evidence sent to a remote provider should be minimized to what is needed for the requested feature.

## Migration status update — 2026-10-03

MetronomePro now pins an AICoreKit stabilization revision that includes shared response-completion validation and local-model provisioning through `Packages/PracticeCoachAI`.

The production boundary remains deliberately small:

- `PracticeFeature` computes deterministic practice/session/activity/timing evidence;
- `PracticeCoachAI` translates only that evidence into a short generative review;
- `SettingsFeature` exposes the product-facing provider configuration without implementing vendor HTTP semantics.

Provider behavior is now:

- Practice Coach exposes explicit **Automatic / On-device / Cloud** execution modes through the shared SettingsFeature used by both MetronomePro and Metronome26;
- Automatic registers the available local providers (Apple Foundation Models plus the optional provisioned Qwen/Core AI provider) and may add an enabled/configured remote provider, then requests `.localFirst`;
- On-device registers the available local providers (Apple plus optional Qwen/Core AI) and requests `.localOnly`;
- Cloud registers the configured remote provider only and requests `.remoteOnly`; a missing/invalid cloud configuration does not silently fall back to Apple;
- each generated review resolves the current configured service, so mode/provider changes apply without restarting the app or recreating the session screen;
- remote providers are constructed through `AIProviderConfiguration`;
- supported presets include OpenAI, Anthropic, Gemini, DeepSeek, and a custom OpenAI-compatible endpoint;
- provider/model/base-URL preferences are product settings, while API credentials are stored in Keychain;
- cloud connection status uses the same full-width row/divider composition as the rest of Settings and user-facing success/failure strings are localized rather than exposing raw provider-library errors.

Privacy/evidence boundary:

- only deterministic `PracticeCoachEvidence` already visible to the product flow may be sent to the remote provider;
- raw practice recordings are not sent to the language model;
- missing analysis coverage remains an explicit unknown rather than being converted into inactivity, poor effort, cheating, pitch accuracy, expression, or other unmeasured claims;
- AI prose remains advisory and cannot mutate practice duration, estimated effective time, goals, streaks, achievements, or leaderboard submissions.

Contract tests cover the evidence-only request boundary, execution-mode mapping, and remote-provider settings/profile construction. The shared Settings implementation is used by both MetronomePro and Metronome26, avoiding separate provider configuration forks. SettingsFeature's current user-visible key set is complete across all 15 supported localizations, and a UI regression asserts that the shared Practice Coach settings expose three execution modes.

No new full-app Release/CI evidence is claimed by this update. Application-level archive validation remains a later gate when build capacity/private dependency access is available.

## Acceptance gates for first production feature

Do not count MetronomePro as an AICoreKit production consumer until:

- the app actually links a pinned AICoreKit version/revision;
- one user-visible AI feature uses it;
- deterministic analysis remains the source of truth;
- AI output cannot change factual practice time or leaderboard submissions;
- no-recording / zero-analysis-coverage cases are described conservatively;
- insufficient timing evidence remains insufficient rather than becoming a negative judgment;
- evidence references survive structured-response validation;
- cancellation and provider-unavailable paths degrade cleanly;
- if Qwen/Core AI is part of the claimed feature, the real model resource has been provisioned with the documented wrapper and resolves from the shared `PracticeCoachAI` package bundle;
- a signed supported device has executed a real Qwen Practice Coach generation; a no-model CI/device build does not satisfy this gate;
- relevant localization is verified;
- CI and production archive succeed.

## Recommended first feature boundary

For the first integration, avoid building an open-ended chatbot.

The highest-value, lowest-risk boundary is:

```text
Practice session ends
    -> collect existing structured evidence
    -> AICoreKit generates 1–3 sentence review
    -> optional structured next-exercise recommendation
    -> user may apply recommendation as a Practice task
```

This directly advances the documented 1.8 AI Practice Coach direction while preserving the 1.6/1.7 factual foundations.


## Result-validation requirement

Practice Coach must not treat non-empty text as sufficient evidence of a successful generation. Consumers should call `AIResponse.validatedCompletedText()` first so truncated/blocked/failed responses fail closed, then apply Practice Coach-specific constraints. One bounded repair retry is acceptable for incomplete output; factual practice evidence remains immutable.
