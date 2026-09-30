# Cloud providers

Cloud providers are optional AICoreKit products. The core package does not persist provider secrets and does not require a cloud dependency.

## HTTP transport

`AIHTTP` defines the injectable `AIHTTPTransport` boundary.

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

`AIProviderOpenAICompatible` implements the common non-streaming `POST /chat/completions` text-generation shape used by multiple services.

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

The initial implementation deliberately advertises only:

- text generation;
- remote execution;
- network requirement.

Streaming, structured generation, and tool calling will be added only after AICoreKit provides normalized, testable implementations for those behaviors.
