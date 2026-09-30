# AICoreKit Core AI Runtime

This nested Swift package is intentionally separate from the root AICoreKit package.

## Why it is separate

Apple's `coreai-models` package requires iOS/macOS 27 and Xcode 27. The root AICoreKit package keeps a lower deployment target so applications can continue to support earlier operating systems.

This runtime package:

- requires iOS 27 / macOS 27;
- depends on Apple's `CoreAILM` product;
- loads exported Core AI language-model resources;
- runs them through `FoundationModels.LanguageModelSession`;
- exposes only the stable C ABI symbols consumed by `WeakSymbolCoreAIBridge`.

## Integration model

The intended production packaging is:

```text
Host app (iOS 17/26+)
  -> AICoreKit / AIProviderCoreAI
  -> WeakSymbolCoreAIBridge
  -> weak-linked AICoreKitCoreAIRuntime.framework (iOS 27+)
  -> CoreAILM / Core AI
```

The runtime should be built as an iOS 27+ dynamic framework and embedded in the host application with a weak load command. Do not import this Swift module from lower-minimum host code.

## Model assets

Model assets are not stored in this repository. Export a supported model such as Qwen3-0.6B for the target platform using Apple's `coreai-models` tools, then provide the exported resource directory through `CoreAIModelResourceProviding`.

The public repository must not redistribute model assets unless their license and size policy explicitly permit it.
