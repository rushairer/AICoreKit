# Roadmap

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
- [x] Add a live weak-symbol host bridge using the stable C ABI.
- [x] Add an isolated iOS/macOS 27 Core AI runtime Swift package.
- [x] Add explicit model prepare / unload lifecycle hooks.
- [x] Add a Qwen3-0.6B export and integration fixture without shipping model assets.
- [x] Build and validate the iOS 27 runtime framework artifact on an Xcode 27 CI runner.
- [x] Add a lower-minimum Mach-O host fixture that proves the runtime is weak-linked.
- [ ] Validate a signed app on a lower OS, iOS 27 inference, Release archive, memory, cancellation, and thermal behavior.

## 0.3 Cloud providers

- [x] Injectable HTTP transport boundary.
- [x] OpenAI-compatible non-streaming text provider.
- [x] True OpenAI-compatible SSE streaming.
- [x] Anthropic provider.
- [x] Gemini provider.
- [x] Dedicated OpenAI Responses API provider.
- [ ] Gateway-oriented credential examples and retry/observability hooks.

## 0.4 Structured generation and tools

- [x] Provider-native structured output adapters for OpenAI Responses, Anthropic, and Gemini.
- [x] Tool-call normalization across OpenAI Responses, Anthropic, and Gemini.
- [ ] Multi-turn tool orchestration. (Safe core loop and OpenAI Responses stateless continuation complete; Anthropic and Gemini adapters pending.)
- [ ] Confirmation policies for mutating and destructive tools.

## 1.0

- [ ] Stable semantic versioning contract.
- [ ] Migration guides for ColorCamera and FateAtlas.
- [ ] At least three production consumers.
- [ ] Compatibility matrix and provider conformance suite.
