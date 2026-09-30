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
- [ ] Build the iOS 27-only Core AI runtime framework target.
- [ ] Connect the weak C ABI live bridge on an iOS 26 host.
- [ ] Add a Qwen3-0.6B integration fixture without shipping model assets in the package.
- [ ] Validate iOS 26 launch, iOS 27 inference, Release archive, memory, cancellation, and thermal behavior.
- [ ] Add explicit model unload / memory-pressure lifecycle hooks.

## 0.3 Cloud providers

- [ ] OpenAI-compatible provider.
- [ ] Anthropic provider.
- [ ] Gemini provider.
- [ ] Dedicated OpenAI provider where vendor-specific features justify it.
- [ ] Injectable HTTP transport and credential sources.

## 0.4 Structured generation and tools

- [ ] Provider-native structured output adapters.
- [ ] Tool-call normalization across providers.
- [ ] Multi-turn tool orchestration.
- [ ] Confirmation policies for mutating and destructive tools.

## 1.0

- [ ] Stable semantic versioning contract.
- [ ] Migration guides for ColorCamera and FateAtlas.
- [ ] At least three production consumers.
- [ ] Compatibility matrix and provider conformance suite.
