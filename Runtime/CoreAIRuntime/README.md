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
  -> AICoreKit / AIProviderCoreAIWeakLink
  -> WeakLinkedCoreAIBridge
  -> embedded AICoreKitCoreAIRuntime.framework (iOS 27+, loaded on demand)
  -> CoreAILM / Core AI
```

The runtime should be built as an iOS 27+ dynamic framework and embedded in the host application with a weak load command. Do not import this Swift module from lower-minimum host code.

### Reusable Xcode host integration

AICoreKit owns the runtime build path. Product apps should not create their own Core AI bridge framework.

For standalone artifact creation:

```bash
/bin/sh Scripts/build-coreai-runtime-framework.sh \
  /path/to/output \
  Release \
  iphoneos
```

For an Xcode application target, add one build phase before the Frameworks phase that locates the resolved AICoreKit checkout and invokes:

```bash
/bin/sh "$AICOREKIT_DIR/Scripts/xcode-build-coreai-runtime.sh"
```

The script writes `AICoreKitCoreAIRuntime.framework` into `BUILT_PRODUCTS_DIR`. The app target then:

1. references that framework from `BUILT_PRODUCTS_DIR`;
2. links it with the Xcode **Weak** attribute;
3. embeds and signs it in the app Frameworks directory without adding it to the host link phase;
4. depends on the root-package `AIProviderCoreAIWeakLink` product and uses `WeakLinkedCoreAIBridge`, which `dlopen`s the embedded runtime only on supported OS versions.

The final weak-link and embed declarations remain properties of the host application target because only the host owns the final Mach-O and app bundle. The runtime implementation, ABI, builder, verifier, and bridge remain AICoreKit responsibilities.

## Model assets

Model assets are not stored in this repository. Export a supported model such as Qwen3-0.6B for the target platform using Apple's `coreai-models` tools, then provide the exported resource directory through `CoreAIModelResourceProviding`.

The public repository must not redistribute model assets unless their license and size policy explicitly permit it.


## Upstream pinning

The runtime currently pins Apple's `coreai-models` repository to revision
`3efa838ebf1a1e816ef4c17eb5022fe22cda2cb9`.

Update that revision deliberately and let the dedicated runtime CI job validate the integration before merging.


## Preparation and loading lifecycle

The runtime distinguishes persistent Core AI specialization from current-process model residency.

- `AICKCoreAIIsPrepared` inspects `PreparedModel.isCached` for every model asset without triggering specialization.
- `AICKCoreAIPrepare` specializes uncached assets and does not make the language model resident.
- `AICKCoreAILoad` requires persistent preparation and creates the eager in-process `CoreAILanguageModel`.
- `AICKCoreAIUnload` releases the resident engine but keeps persistent preparation.
- `AICKCoreAIClearPreparationCache` unloads the engine and removes Core AI specialization with `PreparedModel.clearCache`.

Preparation and loading each deduplicate concurrent callers through one shared in-flight task per model path.
