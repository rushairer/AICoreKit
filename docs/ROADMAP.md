# Roadmap

## 0.1 Foundation

- Vendor-neutral core types and provider protocol.
- Capability-based routing and fallback.
- Tool registry and side-effect policy primitives.
- Apple Foundation Models text provider.
- Provider contract and routing tests.
- Document the iOS 26 host / iOS 27 Core AI runtime boundary.

## 0.2 Local runtime

- Generalize the proven ColorCamera weak-link C ABI bridge.
- Add an iOS 27-only Core AI provider target.
- Define local model resource lifecycle and readiness APIs.
- Add Qwen3-0.6B integration fixture without shipping model assets in the package.
- Add memory, cancellation, and thermal lifecycle hooks.

## 0.3 Cloud providers

- OpenAI-compatible provider.
- Anthropic provider.
- Gemini provider.
- Dedicated OpenAI provider where vendor-specific features justify it.
- Injectable HTTP transport and credential sources.

## 0.4 Structured generation and tools

- Provider-native structured output adapters.
- Tool-call normalization across providers.
- Multi-turn tool orchestration.
- Confirmation policies for mutating and destructive tools.

## 1.0

- Stable semantic versioning contract.
- Migration guides for ColorCamera and FateAtlas.
- At least three production consumers.
- Compatibility matrix and provider conformance suite.
