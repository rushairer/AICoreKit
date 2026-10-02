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

## Cloud option

Cloud providers can be enabled without coupling product code to a vendor:

- OpenAI Responses;
- Anthropic;
- Gemini;
- an OpenAI-compatible application gateway.

Production credentials should normally be supplied through an application/server gateway rather than embedded vendor secrets.

The user's practice evidence sent to a remote provider should be minimized to what is needed for the requested feature.

## Migration status update — 2026-10-02

The first production feature is now implemented and partially validated:

- `Packages/PracticeCoachAI` is the product-side AI boundary. MetronomePro main `98a48f0a` pins it to the validated AICoreKit baseline `794abcbd`; the package contains only the evidence DTO plus generative interpretation service.
- `Packages/PracticeFeature` retains deterministic activity/timing evidence construction and the user-visible Practice Session Detail flow.
- The service uses `DefaultAIOrchestrator` with `AppleFoundationModelsProvider`, requires only `.textGeneration`, and requests `.localFirst` execution.
- AI prose remains ephemeral and cancellable. It cannot mutate factual Practice time, Estimated Effective Time, goals, streaks, achievements, or leaderboard submissions.
- Contract tests verify that only deterministic evidence JSON and explicit unknowns are sent to the provider.
- GitHub Actions successfully builds `PracticeCoachAI` in Release configuration and runs its tests against AICoreKit `794abcbd` without needing private `MetronomeEngine` access.
- The full PracticeFeature and both iOS app Release builds are prepared in CI but remain skipped until `METRONOMEPRO_CI_READ_TOKEN` is configured. This keeps module validation distinct from application Release evidence.

The extraction is intentional: it prevents the AI layer from inheriting DSP/engine responsibilities and gives AICoreKit a small, independently testable real-product consumer while preserving the product's deterministic evidence boundary.

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
