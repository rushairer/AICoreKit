# Qwen3-0.6B Core AI fixture

## Preferred provision command

For a host application that bundles Qwen3-0.6B, prefer the single AICoreKit provisioning command:

```bash
./Scripts/provision-coreai-model.sh \
  --destination /path/to/Product/Resources/ProductLocalModel \
  --output-name ProductLocalModel
```

This performs export + install and then prints the remaining host-app gates. If an export already exists, pass `--source /path/to/exported-model`.

A host build that omits the model is useful for testing graceful degradation, but it is not a successful local-model qualification.

AICoreKit does not redistribute Qwen model assets. This fixture documents how to create a local Core AI resource bundle and inject it into `CoreAIProvider`.

## Export for iOS

AICoreKit includes a reusable export script pinned to the same Core AI revision as the runtime:

```bash
COREAI_MODEL_ID=Qwen/Qwen3-0.6B \
COREAI_OUTPUT_NAME=Qwen3-0.6B-iOS \
./Scripts/export-coreai-model.sh
```

Override `COREAI_MAX_CONTEXT_LENGTH`, `COREAI_OUTPUT_ROOT`, or `COREAI_PLATFORM` when a product needs a different build. Generated model assets remain outside source control.

## AICoreKit host setup

Resolve the exported resource directory in the host app and inject it:

```swift
let modelProfile =
    CoreAIModelProfile(
        identifier: "qwen3-0.6b",
        displayName: "Qwen3-0.6B",
        sourceIdentifier: "Qwen/Qwen3-0.6B"
    )

let resourceProvider =
    CoreAIDirectoryModelResourceProvider(
        profile: modelProfile,
        directoryURL:
            Bundle.main.url(
                forResource:
                    "Qwen3-0.6B-iOS",
                withExtension: nil
            )
    )

let provider = CoreAIProvider(
    bridge: WeakSymbolCoreAIBridge(),
    resourceProvider: resourceProvider
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


## Install an existing export only

For bundled-model products that already have an exported directory, use the shared install helper rather than duplicating copy/validation logic:

```bash
./Scripts/install-coreai-model-resource.sh \
  ./Artifacts/CoreAI/Qwen3-0.6B-iOS \
  /path/to/Product/Resources/Qwen3-0.6B-iOS
```

The helper preserves an existing `.gitkeep` and verifies that at least one `.aimodel` exists after the copy. Products still own the destination path and whether the model is bundled, downloaded, or omitted.


For the complete integration and agent completion checklist, see `docs/LOCAL_MODELS.md`.
