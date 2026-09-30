# AICoreKit Engineering Rules

## Scope

AICoreKit is shared AI infrastructure. Keep product-specific domain logic out of this repository.

## Public API

- Prefer capability-based APIs over vendor switches.
- Do not add FateAtlas, ColorCamera, metronome, palette, astrology, BaZi, or other product domain types to AICore.
- Keep provider identifiers extensible. Do not turn AIProviderID into a closed enum.
- A provider must not advertise a capability it cannot reliably implement.
- Preserve Sendable correctness and Swift 6 concurrency safety.

## Security

- Never commit API keys, tokens, model licenses that prohibit redistribution, or private service endpoints.
- The package must not persist API keys in UserDefaults.
- Credentials must come through injected credential providers or host-owned gateways.

## Apple platform compatibility

- Keep the base package usable by applications that do not opt into newer AI runtimes.
- Do not raise the package or host minimum OS merely to simplify a provider integration.
- Isolate higher-minimum runtime code behind a module or ABI boundary.
- Do not use private APIs or runtime code downloading.

## Testing

Every provider should receive contract tests for capability declaration, availability mapping, cancellation, errors, and response normalization. Routing and fallback behavior must be deterministic and covered independently of real network/model calls.
