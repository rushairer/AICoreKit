# Core AI runtime packaging contract

AICoreKit keeps the host-facing package compatible with lower deployment targets while the Core AI runtime is isolated in an iOS 27+ dynamic framework.

## Required topology

```text
Host application
  minimum iOS <= 26
        |
        | imports AIProviderCoreAI only
        v
WeakSymbolCoreAIBridge
        |
        | dlsym C ABI
        v
AICoreKitCoreAIRuntime.framework
  minimum iOS 27
  install name @rpath/AICoreKitCoreAIRuntime.framework/AICoreKitCoreAIRuntime
        |
        v
CoreAILM / Core AI
```

The lower-minimum host must not import the `AICoreKitCoreAIRuntime` Swift module.

## Runtime framework requirements

The produced framework must satisfy all of these conditions:

- dynamic framework binary exists;
- minimum iOS version is 27 or newer;
- Mach-O install name is `@rpath/AICoreKitCoreAIRuntime.framework/AICoreKitCoreAIRuntime`;
- the following C ABI symbols are exported:
  - `AICKCoreAIIsAvailable`
  - `AICKCoreAIGenerate`
  - `AICKCoreAIPrepare`
  - `AICKCoreAIUnload`

`Scripts/verify-coreai-runtime-framework.sh` enforces these invariants in CI.

## Host embedding requirements

A production host must:

1. Embed `AICoreKitCoreAIRuntime.framework` in the app's Frameworks directory.
2. Sign the embedded framework as part of normal app signing.
3. Keep `@executable_path/Frameworks` in `LD_RUNPATH_SEARCH_PATHS`.
4. Link the runtime framework weakly, not strongly.
5. Keep all host calls behind `WeakSymbolCoreAIBridge` and runtime availability checks.

For an Xcode application target, the effective linker invocation must produce `LC_LOAD_WEAK_DYLIB` for the runtime framework. A typical linker flag is:

```text
-weak_framework AICoreKitCoreAIRuntime
```

Do not treat the flag alone as proof. Release validation must inspect the final host Mach-O load commands.

## Release validation

Before declaring the compatibility boundary production-ready, a host application build must prove:

- host application minimum OS remains its intended lower target;
- runtime framework minimum OS is iOS 27+;
- the final host executable contains `LC_LOAD_WEAK_DYLIB`, not `LC_LOAD_DYLIB`, for the runtime;
- runtime install name uses `@rpath`;
- host launches successfully on the lower supported OS when the runtime cannot load;
- the four C ABI symbols resolve and inference succeeds on iOS 27+.

ColorCamera previously demonstrated this topology. AICoreKit's Compatibility Lab is extracting those checks into product-neutral validation.
