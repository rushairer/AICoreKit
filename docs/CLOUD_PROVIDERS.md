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

## Credentials

Cloud providers request credentials through `AICredentialProviding`.

Do not put production service API keys in a public repository or hard-code them in an application binary. Commercial applications should normally exchange an application session for a server-side AI gateway rather than distributing vendor secrets to every client.

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
- maps client `tool_use` blocks into normalized `AIToolCall` values.


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
