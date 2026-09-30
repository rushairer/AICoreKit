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
- does not yet advertise tool calling or structured generation.
