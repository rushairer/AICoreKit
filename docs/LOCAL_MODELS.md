# Local Core AI model integration

This document is the required integration contract for applications that use AICoreKit with an app-supplied Core AI model such as Qwen3-0.6B.

AICoreKit owns the reusable export, install, lifecycle, weak-link runtime, and validation infrastructure. The host application owns the product resource destination, bundling/download policy, user-facing settings, and product-specific inference semantics.

## Important distinction

A host that compiles successfully without a model resource has proved only **graceful degradation**.

It has **not** proved that local Core AI works.

Do not mark an AICoreKit local-model integration complete until a real model resource is installed into the host, resolved at runtime, and used for a signed-device generation.

## Recommended one-step provisioning

From an AICoreKit checkout:

```bash
./Scripts/provision-coreai-model.sh \
  --destination /path/to/App/Resources/AppLocalModel \
  --output-name AppLocalModel
```

The default source model is `Qwen/Qwen3-0.6B`, the default platform is iOS, and the default maximum context length is 4096.

The provisioning script:

1. checks out the pinned Apple `coreai-models` revision through `export-coreai-model.sh`;
2. exports the selected model for Core AI;
3. installs the exported directory into the host resource directory through `install-coreai-model-resource.sh`;
4. verifies that at least one `.aimodel` exists;
5. preserves host-owned `.gitkeep`, `.gitignore`, and `README.md` sentinels;
6. leaves generated model assets outside the AICoreKit source tree.

If the model was already exported, skip the export step:

```bash
./Scripts/provision-coreai-model.sh \
  --source /path/to/exported-model \
  --destination /path/to/App/Resources/AppLocalModel
```

Run `./Scripts/provision-coreai-model.sh --help` for model, platform, output, and context-length overrides.

## Host repository wrapper

A product repository may keep a short convenience script such as:

```text
Scripts/install_local_model.sh
```

That wrapper should only:

- locate the AICoreKit revision used by the product;
- choose the product resource destination;
- choose the product resource/output name;
- invoke AICoreKit's provisioning script.

Do not copy the export/install implementation into each product repository.

This keeps model validation, Apple Core AI revision policy, and provisioning behavior in one place.

## What “install/upload” means

For the normal bundled-model workflow, provisioning has three physical stages:

1. export/convert the source model on the developer Mac;
2. copy the exported Core AI resource into the host application's or Swift Package's resource directory;
3. build/sign/install the app, at which point Xcode includes that resource in the application bundle delivered to the device.

AICoreKit does not need a separate private “upload model to iPhone” API for this bundled flow.

If a product chooses application-managed or on-demand model download instead, the host owns that network/storage/licensing policy. AICoreKit consumes the resolved local directory after the product makes it available. Runtime executable code must not be downloaded dynamically.

## Required host setup

Provisioning the model resource is necessary but not sufficient.

The host must also:

1. depend on `AIProviderCoreAI`;
2. depend on `AIProviderCoreAIWeakLink` when embedding the shared higher-minimum runtime;
3. weak-link and Embed & Sign `AICoreKitCoreAIRuntime.framework`;
4. keep the lower-minimum app target free of direct `CoreAILM` / `CoreAILanguageModels` imports;
5. include the installed model directory in app or Swift Package resources;
6. resolve the actual bundled directory with `CoreAIDirectoryModelResourceProvider`;
7. use `CoreAIModelProfile` and `CoreAIModelSettingsStore` instead of inventing a second lifecycle state machine.

Example:

```swift
let profile = CoreAIModelProfile(
    identifier: "app.qwen3-0.6b",
    displayName: "Qwen3-0.6B",
    sourceIdentifier: "Qwen/Qwen3-0.6B"
)

let resourceProvider = CoreAIDirectoryModelResourceProvider(
    profile: profile,
    directoryURL: Bundle.main.url(
        forResource: "AppLocalModel",
        withExtension: nil
    )
)
```

For Swift Package resources, resolve the directory from the package bundle rather than assuming `Bundle.main`.

## Resource and source-control policy

Generated model resources are normally large and may have separate redistribution terms.

Therefore:

- do not commit generated model assets unless the product intentionally permits redistribution and licensing has been reviewed;
- keep an empty resource directory or README/sentinel in source control;
- git-ignore generated contents;
- make the provisioning command reproducible;
- do not treat the absence of a model in CI as proof that the signed-device local path works.

A product may instead download a model using an application-owned policy, but AICoreKit does not download executable runtime code and does not silently choose a network distribution policy for the host.

## Lifecycle contract

Keep these states distinct:

1. model resource installed in the app bundle or application-managed storage;
2. persistent Core AI preparation completed;
3. prepared resources loaded into the current process;
4. generation ready;
5. runtime unloaded;
6. persistent preparation cache cleared.

The first expensive preparation is not the same operation as ordinary launch-time loading.

Use `CoreAIModelSettingsStore` / `CoreAIModelLifecycleController` for this lifecycle.

## Agent completion gate

When an AI coding agent integrates AICoreKit local inference into a product, it must explicitly verify the following before reporting the local model as complete:

- [ ] the product has a reproducible model provisioning command;
- [ ] the provisioning command delegates to AICoreKit tooling rather than duplicating export/copy logic;
- [ ] the real model resource has been provisioned for device qualification;
- [ ] the resource directory is included in the app or package bundle;
- [ ] bundle/resource lookup resolves the expected model directory;
- [ ] `AICoreKitCoreAIRuntime.framework` is weak-linked and embedded correctly when required;
- [ ] a supported signed device executes a real generation;
- [ ] cold first preparation and warm relaunch are distinguished;
- [ ] cancellation/error handling is tested;
- [ ] product UI does not claim the local model is available merely because the app built successfully.

If the agent cannot run the export/provision command because the current environment lacks Xcode 27, `uv`, device access, or required model tooling, it must state that **model provisioning/device qualification remains open** and leave the exact command in the product repository. It must not silently substitute a no-model build.

## Production qualification

Before calling a local model production-ready, also follow `DEVICE_VALIDATION.md`.

At minimum retain:

- signed build/archive identity;
- device and OS version;
- cold preparation evidence;
- warm launch evidence;
- actual generation result;
- cancellation behavior;
- memory and thermal observations relevant to the host workload.

## Reference compatibility model

Qwen3-0.6B is the current **reference compatibility model** because it is small, already exercised through the complete Core AI lifecycle in a real production consumer, and provides a practical baseline for provisioning/runtime tests.

It is **not** a claim that Qwen3-0.6B is the newest or highest-quality product model.

Applications should choose their actual product model using measured device latency, memory, language/output quality, repair rate, model size, and supported-device budget. Use `--model-id` plus the matching `CoreAIModelProfile` to override the reference model without changing AICoreKit globally.

AICoreKit's reference model should change only for a compatibility/testing reason, not simply because a newer or larger model is released.
