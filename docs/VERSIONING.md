# Versioning and API stability

AICoreKit follows Semantic Versioning for published releases.

The repository is still in pre-1.0 stabilization. The rules below define the contract that will become binding when the first `1.0.0` tag is published.

## Before 1.0

Until `1.0.0`:

- patch releases are intended for compatible fixes and documentation;
- minor releases may still contain source-breaking API changes;
- every intentional breaking change should be documented in release notes;
- applications should pin an exact version or revision for production evaluation rather than tracking `main`.

No `1.0.0` tag should be created until the remaining production-validation and migration gates in the roadmap are satisfied.

### Pre-1.0 stabilization freeze

The default mode before 1.0 is stabilization, not speculative expansion.

- Prefer production-consumer evidence, bug fixes, tests, documentation, compatibility work, and reliability improvements.
- Add a new public abstraction only when a real consumer has a concrete product-neutral need that the current contracts cannot express cleanly.
- Do not move product prompts, repair policy, domain schemas, localized UX, or business truth into AICoreKit merely to reduce code in one application.
- When ColorCamera, MetronomePro, FateAtlas, or another consumer exposes a reusable issue, first prove that the issue is provider/runtime-wide before promoting it into the shared package.
- Keep exact-revision pins in production consumers until the 1.0 compatibility contract is published.

## Starting with 1.0

For `1.x` releases:

### Patch

A patch release may contain:

- bug fixes;
- provider wire-format fixes that preserve the public Swift API;
- documentation and test improvements;
- performance, memory, cancellation, or reliability fixes that do not intentionally change public semantics;
- vendor endpoint or protocol maintenance required to preserve existing advertised behavior.

A patch release must not intentionally remove or rename public API.

### Minor

A minor release may contain backward-compatible additions:

- new public types, methods, configuration options, providers, or package products;
- new optional capabilities;
- new tool policies or orchestration features;
- support for additional OS versions or model runtimes;
- additive Core AI C ABI symbols;
- deprecations that leave the existing API functional.

Existing source-compatible callers should continue to build.

### Major

A major release is required for intentional incompatible changes, including:

- removing or renaming public Swift symbols;
- changing public method signatures in a source-incompatible way;
- changing the meaning of an existing `AICapabilities` flag;
- changing or removing a built-in `AIProviderID`;
- removing an advertised provider capability when the old contract can no longer be preserved;
- raising the root package minimum deployment target;
- changing the Core AI C ABI in a way that makes an existing host/runtime pair incompatible;
- changing required request/response fields or status-code semantics across the Core AI ABI boundary.

Security emergencies or upstream service shutdowns may require an exceptional behavioral change outside this schedule. Such cases must be called out explicitly in release notes.

## Stable public surface

After `1.0.0`, the compatibility promise covers:

- Swift Package Manager product names declared by the root package;
- public symbols in `AICore`, `AIHTTP`, `AIOrchestration`, `AITools`, and public provider modules;
- built-in `AIProviderID` values;
- documented `AICapabilities` semantics;
- public configuration structures and their documented defaults;
- normalized tool-call, tool-output, confirmation, routing, and fallback contracts;
- the documented Core AI C ABI symbols, JSON envelopes, and status codes.

The compatibility promise is about API and documented behavior, not about guaranteeing the continued availability of a third-party cloud service or model.

## Non-stable implementation surface

The following are not public compatibility contracts unless explicitly documented otherwise:

- `internal`, `private`, and test-only types;
- provider wire models used only inside an adapter;
- fixture payloads and CI implementation details;
- `CompatibilityLab` experiments other than the explicitly documented Core AI ABI contract;
- internal implementation details of `Runtime/CoreAIRuntime`;
- vendor response fields preserved only inside opaque `AIToolContinuation` state;
- README examples and documentation prose that do not describe a declared API guarantee.

Opaque continuation state must never be persisted as an application-owned long-term format. It is valid only for continuation with the provider implementation that created it.

## Deprecation policy

When practical, public API scheduled for removal should first be deprecated for at least one minor release.

A deprecation should:

1. identify the replacement API when one exists;
2. preserve source compatibility during the deprecation window;
3. include a migration note for non-trivial changes.

Removal occurs only in the next major release unless an exceptional security or upstream-platform constraint makes continued support impossible.

## Provider capability stability

Provider capability declarations are part of the behavioral contract.

Adding an advertised capability is additive and may ship in a minor release.

Removing an advertised capability or changing its semantics is breaking because routing decisions may depend on it. The provider conformance suite and compatibility matrix must be updated in the same change.

Capabilities that are explicitly conditional remain conditional. For example, cloud streaming is advertised only when the injected transport conforms to `AIHTTPStreamingTransport`.

## Core AI ABI stability

The weak-linked Core AI boundary is a cross-deployment-target ABI and receives stronger compatibility treatment than ordinary implementation details.

Within a major release:

- existing exported C symbols must retain their calling convention and meaning;
- existing status code numeric values must not be reassigned;
- existing required JSON fields must retain their meaning;
- additive optional JSON fields are allowed;
- additive exported symbols are allowed.

If an incompatible runtime protocol is ever required, introduce a versioned ABI rather than silently changing the meaning of existing symbols.

## Release checklist

Before publishing a stable release:

1. root `swift test` passes;
2. Core AI runtime build and weak-link CI pass;
3. compatibility matrix matches the conformance suite;
4. migration notes exist for user-visible API changes;
5. changelog/release notes identify additions, fixes, deprecations, and breaking changes;
6. production validation gates appropriate to the release have been completed.

For the first `1.0.0` release, the roadmap additionally requires production consumers and migration validation.
