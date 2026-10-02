# Cloud providers

Cloud providers are optional AICoreKit products. The core package does not persist provider secrets and does not require a cloud dependency.

## HTTP transport

`AIHTTP` defines injectable `AIHTTPTransport` and `AIHTTPStreamingTransport` boundaries.

The default `URLSessionAIHTTPTransport` is suitable for direct client requests, while applications can inject their own transport for:

- tests and deterministic fixtures;
- observability and metrics;
- enterprise networking policy;
- request signing;
- application-owned AI gateways;
- retry and circuit-breaker policy.

### Observability

`ObservingAIHTTPTransport` and `ObservingAIHTTPStreamingTransport` emit request lifecycle events to an injected `AIHTTPObserver`.

Observation metadata is deliberately sanitized by default. It includes only the request ID, operation kind, HTTP method, scheme, host, path, status code, duration, and failure description. It does not expose request headers, response headers, query parameters, request bodies, response bodies, or credentials.

```swift
let observer = ClosureAIHTTPObserver { event in
    metrics.record(event)
}

let transport = ObservingAIHTTPTransport(
    base: URLSessionAIHTTPTransport(),
    observer: observer
)
```

For streaming requests, the response event records time to the returned HTTP line stream and headers, not time until the entire stream is consumed.

## Credentials

Cloud providers request credentials through `AICredentialProviding`.

Do not put production service API keys in a public repository or hard-code them in an application binary. Commercial applications should normally exchange an application session for a server-side AI gateway rather than distributing vendor secrets to every client.

`ClosureAICredentialProvider` is a convenience adapter for application-owned credential systems. A product can use it to fetch a short-lived gateway credential at request time without teaching AICoreKit how the product authenticates:

```swift
let credentials = ClosureAICredentialProvider {
    request in

    try await appSession.shortLivedAIToken(
        providerID: request.providerID
    )
}
```

The closure may read Keychain-backed application sessions, refresh an OAuth token, or call a product gateway. AICoreKit does not cache or persist the returned credential.

## OpenAI-compatible provider

`AIProviderOpenAICompatible` implements the common `POST /chat/completions` text-generation shape used by multiple services. When its injected transport conforms to `AIHTTPStreamingTransport`, the provider also advertises `.streaming` and consumes OpenAI-compatible SSE `data:` events through `AIProvider.stream(_:)`.

Configuration owns endpoint/model metadata, not credentials:

```swift
let configuration = OpenAICompatibleProviderConfiguration(
    providerID: "my.gateway",
    displayName: "My AI Gateway",
    baseURL: URL(string: "https://example.com/v1")!,
    model: "my-model"
)

let provider = OpenAICompatibleProvider(
    configuration: configuration,
    credentialProvider: credentials,
    transport: transport
)
```

The provider always advertises:

- text generation;
- remote execution;
- network requirement.

It additionally advertises streaming only when the injected transport supports streaming. Structured generation and tool calling remain disabled until AICoreKit provides normalized, testable implementations for those behaviors.


## Anthropic provider

`AIProviderAnthropic` implements Anthropic's Messages API for text generation and SSE streaming. The model identifier is supplied by the application so AICoreKit does not hard-code a model lifecycle decision.

```swift
let provider = AnthropicProvider(
    configuration: AnthropicProviderConfiguration(
        model: "claude-sonnet-5"
    ),
    credentialProvider: credentials
)
```

The provider:

- sends API keys through `x-api-key`;
- sends the configured `anthropic-version` header;
- maps AICoreKit system messages to the top-level Messages API `system` field;
- advertises streaming only when the injected transport supports `AIHTTPStreamingTransport`;
- leaves temperature unset by default, so applications opt in explicitly when the selected model supports it;
- supports native structured generation through `output_config.format`;
- maps client `tool_use` blocks into normalized `AIToolCall` values;
- supports stateless continuation by replaying the assistant content blocks and appending user `tool_result` blocks, including native `is_error` mapping.


## Gemini provider

`AIProviderGemini` implements the Gemini Generate Content API for text generation and SSE streaming.

```swift
let provider = GeminiProvider(
    configuration: GeminiProviderConfiguration(
        model: "gemini-3.8-flash"
    ),
    credentialProvider: credentials
)
```

The provider:

- authenticates with the `x-goog-api-key` header;
- maps system messages to `systemInstruction`;
- maps assistant history to Gemini's `model` role;
- uses `generateContent` for non-streaming generation;
- uses `streamGenerateContent?alt=sse` for streaming;
- uses the Interactions API for native JSON-schema structured generation;
- explicitly defaults Interactions `store` to `false`;
- leaves temperature unset by default;
- maps Interactions `function_call` steps into normalized `AIToolCall` values;
- supports stateless multi-turn continuation with `store=false` by replaying the explicit `user_input` step, all model-generated steps exactly as received, and appended `function_result` steps with `is_error` mapping;
- does not yet advertise image or audio capabilities.


## OpenAI provider

`AIProviderOpenAI` is the vendor-specific OpenAI adapter. Unlike `AIProviderOpenAICompatible`, it targets the Responses API rather than emulating Chat Completions.

```swift
let provider = OpenAIProvider(
    configuration: OpenAIProviderConfiguration(
        model: "gpt-5"
    ),
    credentialProvider: credentials
)
```

The provider:

- uses `POST /v1/responses`;
- authenticates with a Bearer token;
- explicitly defaults `store` to `false`;
- maps AICore system, user, and assistant history into Responses API input messages;
- streams normalized text deltas from `response.output_text.delta`;
- derives completion state and usage from terminal Responses API events;
- supports native JSON-schema structured outputs;
- maps Responses API `function_call` output items into normalized `AIToolCall` values;
- supports stateless multi-turn tool continuation with `store=false` by preserving provider-native output items inside opaque continuation state and appending `function_call_output` items on the next turn.


## Retry

Retry is an explicit transport decorator rather than implicit provider behavior.

`RetryingAIHTTPTransport` retries non-streaming requests according to `AIHTTPRetryPolicy`. The default policy retries only HTTP 429, 502, 503, and 504 responses, with exponential backoff and numeric `Retry-After` support.

```swift
let transport = RetryingAIHTTPTransport(
    base: URLSessionAIHTTPTransport(),
    policy: AIHTTPRetryPolicy(
        maximumAttempts: 3
    )
)
```

Transport-level failures are **not** retried by default. For a POST request, a dropped connection can be ambiguous: the remote service may already have processed and billed the request even though the client did not receive the response. Applications or gateways that provide idempotency guarantees can opt in explicitly:

```swift
let policy = AIHTTPRetryPolicy(
    maximumAttempts: 3,
    retryTransportErrors: true
)
```

`RetryingAIHTTPStreamingTransport` preserves streaming capability. Its `data(for:)` path uses the same status-code retry policy. Its `lines(for:)` path only retries transport failures that occur before a line stream is established and only when `retryTransportErrors` is enabled. It never retries after a stream has begun because partial model output cannot be replayed or merged safely in a vendor-neutral way.

### Composing retry and observability

Transport decorators can be ordered according to the desired metric boundary.

To observe every retry attempt:

```swift
let observedBase = ObservingAIHTTPTransport(
    base: URLSessionAIHTTPTransport(),
    observer: observer
)

let transport = RetryingAIHTTPTransport(
    base: observedBase,
    policy: policy
)
```

To observe one logical request including all retry time, put `ObservingAIHTTPTransport` outside the retry wrapper instead.

A production gateway should additionally use its own request ID or vendor-supported idempotency mechanism when duplicate remote work would be unacceptable.


## Reusable provider configuration

`AIProviderConfiguration` centralizes technical cloud-provider configuration without taking ownership of product settings UI or secret persistence.

It provides:

- `AIProviderProfile` for validated provider/model/base-URL metadata;
- `AIProviderPreset` for OpenAI, Anthropic, Gemini, DeepSeek, and custom OpenAI-compatible endpoints;
- `AIConfiguredProviderFactory` for constructing the matching AICoreKit provider;
- `AIProviderConnectionTester` for availability checks and explicit low-token generation probes.

Applications remain responsible for user-facing provider names/policy, whether cloud execution is enabled, model-selection UX, and storage of credentials. API keys should normally live in Keychain or behind an application gateway, not in `UserDefaults`.

Consumer code should prefer these shared profiles/factories over rebuilding vendor endpoint/header semantics independently.
