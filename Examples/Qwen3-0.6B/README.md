# Qwen3-0.6B Core AI fixture

AICoreKit does not redistribute Qwen model assets. This fixture documents how to create a local Core AI resource bundle and inject it into `CoreAIProvider`.

## Export for iOS

From a checkout of Apple's pinned `coreai-models` revision:

```bash
uv run coreai.llm.export \
  Qwen/Qwen3-0.6B \
  --platform iOS \
  --max-context-length 4096
```

Keep the first integration at the iOS default context length before benchmarking larger contexts.

## AICoreKit host setup

Resolve the exported resource directory in the host app and inject it:

```swift
let resource = CoreAIModelResource(
    identifier: "qwen3-0.6b",
    path: exportedModelDirectory.path
)

let provider = CoreAIProvider(
    bridge: WeakSymbolCoreAIBridge(),
    resourceProvider: StaticCoreAIModelResourceProvider(
        resource: resource
    )
)

try await provider.prepareResources()
let response = try await provider.generate(
    AIRequest(messages: [.user("Hello")])
)
try await provider.releaseResources()
```

The runtime framework must already be embedded and weak-linked by the host. Do not import the iOS 27 runtime Swift module from a lower-minimum host target.

## Repository policy

Do not commit generated model bundles to AICoreKit. Product applications decide whether assets are bundled, downloaded on demand, or omitted entirely.
