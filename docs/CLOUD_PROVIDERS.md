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
