# Roadmap

## Stabilization status

The planned shared feature surface is closed for the current pre-1.0 baseline. Remaining unchecked items below are production-validation gates, not a backlog for speculative framework expansion. See `STABILIZATION.md`.

## 0.1 Foundation

- [x] Vendor-neutral core types and provider protocol.
- [x] Capability-based routing and fallback.
- [x] Tool registry and side-effect policy primitives.
- [x] Apple Foundation Models text provider.
- [x] Provider contract and routing tests.
- [x] Document the iOS 26 host / iOS 27 Core AI runtime boundary.

## 0.2 Local runtime

- [x] Define a host-safe Core AI provider and injectable bridge contract.
- [x] Generalize the product-neutral C ABI contract from the ColorCamera compatibility spike.
- [x] Define local model resource identity and readiness.
- [x] Generalize Core AI model-directory discovery plus export/install mechanics so product repositories do not need to reimplement deployment plumbing.
- [x] Add a documented one-step local-model provisioning workflow (`provision-coreai-model.sh`) plus CI coverage and explicit host/agent completion gates.
- [x] Add a live weak-symbol host bridge using the stable C ABI.
- [x] Add an isolated iOS/macOS 27 Core AI runtime Swift package.
- [x] Add explicit model prepare / unload lifecycle hooks.
- [x] Separate persistent Core AI preparation from current-process loading, including cache inspection, cache clearing, launch-safe bootstrap, serialized shared in-flight lifecycle tasks, and a reset gate that rejects new readiness while unload/cache-clear is active.
- [x] Add a Qwen3-0.6B reference compatibility fixture without shipping model assets. This fixture is not a product-wide recommendation for the highest-quality model.
- [x] Build and validate the iOS 27 runtime framework artifact on an Xcode 27 CI runner.
- [x] Add a lower-minimum Mach-O host fixture that proves the runtime is weak-linked.
- [x] Add a Swift 5 language-mode consumer fixture for the lifecycle API used by lower-minimum host apps.
- [x] Validate an unsigned Xcode 27 Release archive with an iOS 26 host weak-linking and embedding the iOS 27 runtime; verify bundle/Mach-O minimum OS values, LC_LOAD_WEAK_DYLIB, and the weak ABI reference in the archived app.
- [ ] Close the remaining signed-device/distribution gate: lower-OS launch/fallback, signed/App Store distribution, and repeated memory/cancellation/thermal evidence across production consumers. ColorCamera has already demonstrated real iOS 27 Qwen3-0.6B inference on device, but one successful product path does not close the complete compatibility/distribution matrix. (`AIDiagnostics` provides reusable lifecycle/generation/cancellation timing, memory/thermal reports, explicit cold-vs-warm persistent-preparation evidence, hardware/architecture context, and caller-supplied app/model metadata.)

## 0.3 Cloud providers

- [x] Injectable HTTP transport boundary.
- [x] OpenAI-compatible non-streaming text provider.
- [x] True OpenAI-compatible SSE streaming.
- [x] Anthropic provider.
- [x] Gemini provider.
- [x] Dedicated OpenAI Responses API provider.
- [x] Gateway-oriented credential examples and retry/observability hooks.
- [x] Reusable validated/codable provider profiles and presets with execution defaults, factory construction, and product-owned credential persistence.

## 0.4 Structured generation and tools

- [x] Provider-native structured output adapters for OpenAI Responses, Anthropic, and Gemini.
- [x] Tool-call normalization across OpenAI Responses, Anthropic, and Gemini.
- [x] Multi-turn tool orchestration across OpenAI Responses, Anthropic, and Gemini.
- [x] Confirmation policies for mutating and destructive tools.

## 1.0

- [x] Stable semantic versioning contract.
- [x] Migration guides for ColorCamera, FateAtlas, and MetronomePro.
- [ ] At least three production consumers. FateAtlas is the first validated Release-build consumer; ColorCamera and MetronomePro remain in production validation.
- [x] Compatibility matrix and provider conformance suite.
