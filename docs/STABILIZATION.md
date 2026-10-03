# Stabilization baseline

Status: **feature-frozen pre-1.0 stabilization**.

Date: 2026-10-03.

AICoreKit has reached the intended shared-infrastructure boundary for the current production consumers. The default engineering mode is now stabilization rather than feature expansion.

## What is closed

The shared package already owns the reusable concerns required by the current consumers:

- provider-neutral request/response/capability contracts;
- deterministic provider routing and fallback;
- Apple Foundation Models adapter;
- host-safe Core AI provider boundary;
- weak-linked iOS/macOS 27 Core AI runtime bridge;
- persistent preparation vs process-load lifecycle;
- reusable lifecycle/settings store;
- app-supplied local model provisioning tooling;
- cloud adapters for OpenAI-compatible, OpenAI Responses, Anthropic, and Gemini;
- reusable cloud provider configuration/presets;
- streaming where supported;
- structured generation where genuinely supported;
- normalized tool calling and continuation;
- tool execution/confirmation policies;
- generic completed-response validation;
- diagnostics and compatibility fixtures.

No additional abstraction is required merely because a consumer has a product-specific prompt, schema, repair strategy, settings layout, or domain rule.

## Change admission rule

New public API or package products are not added speculatively.

A new shared primitive is admitted only when all of the following are true:

1. a real production consumer has a concrete need;
2. the behavior is product-neutral;
3. the current public contracts cannot express the behavior cleanly;
4. at least one second plausible consumer would benefit from the same abstraction;
5. tests can define the contract independently of the originating product.

Otherwise the behavior stays in the consuming application.

Bug fixes, compatibility fixes, security fixes, provider protocol maintenance, tests, documentation, diagnostics, and measured reliability/performance improvements remain in scope.

## Local-model policy

AICoreKit does not choose a universally “best” local model.

`Qwen/Qwen3-0.6B` remains the **reference compatibility fixture** because it is small, already validated in ColorCamera, and exercises the complete Core AI lifecycle.

It is not a quality recommendation for every product.

Consumers may select another Apple Core AI-compatible model by overriding the provisioning model identifier and supplying the matching `CoreAIModelProfile`.

Changing the AICoreKit reference model requires an explicit compatibility reason and evidence that the replacement still serves the fixture role. Do not churn the reference model merely because a newer or larger model exists.

Product model selection belongs to the consumer and should be based on measured latency, memory, output quality, language performance, repair rate, and supported-device budget.

## Remaining gates are validation, not feature work

The following remain open for the first stable release:

- signed lower-OS physical-device launch/fallback evidence;
- signed Release/App Store distribution evidence for the Core AI runtime topology;
- repeated cancellation, memory, and thermal observations on representative devices;
- completion of the production-consumer exit rule in `CONSUMERS.md`.

These gates may expose bugs that require fixes. They are not justification for speculative new features.

## Consumer state

- **FateAtlas**: completed production consumer for the validated cloud-provider path.
- **ColorCamera**: real local Qwen/Core AI and configured cloud generation are validated; broader lower-OS/distribution/resource-observation gates remain.
- **MetronomePro / Metronome26**: shared local/cloud infrastructure is wired; the real Qwen resource must be provisioned and signed-device Practice Coach inference must be validated before the Qwen path is counted complete.

## Agent rule

When asked to “continue AICoreKit” without a concrete consumer bug or missing product-neutral contract, do not invent another framework layer.

Prefer one of:

- fix a reproduced defect;
- add a contract/regression test;
- improve compatibility;
- improve documentation/tooling;
- collect production validation evidence;
- implement a consumer feature in the consumer repository.

If a real consumer uncovers a reusable gap, document the product need first and then evaluate whether it passes the change admission rule above.

## Stable handoff

Production consumers should continue to pin an exact reviewed revision until `1.0.0`.

The repository should remain buildable and CI-clean after every maintenance change.

The next major product work should happen in the consumers, with AICoreKit evolving only when those products prove a shared need.
