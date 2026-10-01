# Compatibility matrix

This document is the compatibility contract for AICoreKit's current provider set.

The matrix describes capabilities that are implemented and covered by the root package test suite. It does not imply that every provider is available on every device at runtime.

## Package platform baseline

| Component | iOS | macOS | Notes |
| --- | ---: | ---: | --- |
| Root AICoreKit package | 17+ | 14+ | Core contracts, orchestration, tools, cloud providers, and host-safe local-provider abstractions. |
| Apple Foundation Models provider | 26+ at runtime | 26+ at runtime | Availability also depends on Apple Intelligence eligibility, enablement, locale, and model readiness. |
| Core AI host-side provider | 17+ | 14+ | Does not import the higher-minimum Core AI runtime directly. |
| Core AI runtime package | 27+ | 27+ | Dynamic runtime target backed by Apple's CoreAILM package. |
| Cloud provider modules | 17+ | 14+ | Require network access and application-supplied credentials. |

Apps that embed the Core AI runtime should use `AIProviderCoreAIWeakLink` and keep the iOS/macOS 27 runtime behind the stable C ABI boundary. The lower-minimum host must not link the high-minimum Swift runtime as an ordinary required framework.

## Provider capability matrix

Legend:

- Yes — capability is implemented and advertised.
- Conditional — capability is advertised only when the injected dependency supports it.
- No — the provider intentionally does not advertise the capability.

| Provider | Text | Structured | Tools | Streaming | Local | Remote | Network | Privacy preferred | Image | Audio | Embeddings |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple Foundation Models | Yes | No | No | No | Yes | No | No | Yes | No | No | No |
| Core AI local model | Yes | No | No | No | Yes | No | No | Yes | No | No | No |
| OpenAI-compatible | Yes | No | No | Conditional | No | Yes | Yes | No | No | No | No |
| OpenAI Responses | Yes | Yes | Yes | Conditional | No | Yes | Yes | No | No | No | No |
| Anthropic Messages | Yes | Yes | Yes | Conditional | No | Yes | Yes | No | No | No | No |
| Gemini | Yes | Yes | Yes | Conditional | No | Yes | Yes | No | No | No | No |

For cloud providers, streaming is advertised only when the injected transport conforms to `AIHTTPStreamingTransport`.

## Tool orchestration

OpenAI Responses, Anthropic, and Gemini support normalized tool calls and multi-turn continuation.

AICoreKit keeps provider-native history inside `AIToolContinuation` and exposes only normalized `AIToolCall` / `AIToolOutput` values to product code.

Current continuation modes:

| Provider | Continuation strategy |
| --- | --- |
| OpenAI Responses | Stateless. Preserves provider output items and appends `function_call_output`. Default `store=false`. |
| Anthropic | Stateless. Replays assistant content blocks and appends user `tool_result` blocks. |
| Gemini | Stateless. Replays explicit `user_input`, all returned model steps, and appended `function_result` steps. Default `store=false`. |

The generic OpenAI-compatible adapter deliberately does not advertise normalized tool calling. Products that require tools should use a dedicated provider adapter or add a tested provider-specific implementation.

## Structured generation

Native structured generation is currently implemented for:

- OpenAI Responses through JSON Schema response formatting;
- Anthropic through `output_config.format`;
- Gemini through the Interactions API response schema.

Prompt-only requests such as "return valid JSON" are not treated as native structured generation.

## Local execution

### Apple Foundation Models

The provider remains present in the lower-minimum package but reports runtime availability dynamically. A supported OS alone is not sufficient; Apple Intelligence and the system language model must also be available.

### Core AI runtime

`AIProviderCoreAI` is host-safe and communicates with the iOS/macOS 27 runtime through a C ABI bridge. Model resources are supplied by the consuming application. AICoreKit does not bundle Qwen or other model weights.

The repository includes build-time compatibility fixtures, but final production validation still requires signed-device testing for lower-OS launch behavior, iOS 27 inference, Release archive behavior, memory pressure, cancellation, and thermal characteristics.

## Conformance policy

`ProviderConformanceTests.swift` treats capability declarations as an explicit contract.

The tests assert:

- stable built-in provider identifiers;
- exact base capability sets for each provider;
- streaming capability changes only with a streaming transport;
- dedicated cloud adapters advertise structured generation and normalized tool calling;
- the generic OpenAI-compatible adapter does not overstate structured or tool capabilities;
- local providers remain local/privacy-preferred and do not accidentally advertise network or remote execution.

Adding or removing an advertised capability therefore requires an intentional test and documentation update.
