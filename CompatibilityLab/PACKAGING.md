# Core AI runtime packaging contract

AICoreKit keeps the host-facing package compatible with lower deployment targets while the Core AI runtime is isolated in an iOS 27+ dynamic framework.

## Required topology

```text
Host application
  minimum iOS <= 26
        |
        | imports AIProviderCoreAI only
        v
AICoreWeakBridgeShim
  weak C symbol reference
        |
        v
WeakSymbolCoreAIBridge
  availability probe + dlsym C ABI
        |
        v
AICoreKitCoreAIRuntime.framework
  minimum iOS 27
  install name @rpath/AICoreKitCoreAIRuntime.framework/AICoreKitCoreAIRuntime
        |
        v
CoreAILM / Core AI
```

The lower-minimum host must not import the `AICoreKitCoreAIRuntime` Swift module.

## Why the C shim exists

A pure `dlsym` implementation does not create a link-time reference to the runtime framework. When dead stripping of unused dynamic libraries is enabled, the final host binary can lose the weak framework load command entirely.

`AICoreWeakBridgeShim` therefore carries one deliberately tiny weak import of `AICKCoreAIIsAvailable`. This preserves the weak framework relationship in the final Mach-O while keeping all higher-level Runtime Swift types out of the lower-minimum host.

Generation and lifecycle operations still resolve through the stable C ABI.

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

## Automated lower-minimum fixture

`CompatibilityLab/HostFixture` is compiled directly against the iPhoneOS SDK with a lower deployment target and the same C shim used by the Swift package.

`Scripts/build-verify-coreai-host-fixture.sh` verifies that the resulting host Mach-O contains:

- the requested lower minimum OS;
- `LC_LOAD_WEAK_DYLIB` for the iOS 27 runtime;
- a weak external reference to `AICKCoreAIIsAvailable`.

This checks the linker boundary independently from any product application.

## Release validation

Before declaring the compatibility boundary production-ready, a real host application build must additionally prove:

- the runtime framework is embedded and code signed;
- the final app launches successfully on the lower supported OS when the runtime cannot load;
- the four C ABI symbols resolve and inference succeeds on iOS 27+;
- Release/archive behavior matches Debug compatibility behavior.

ColorCamera previously demonstrated this topology. AICoreKit's Compatibility Lab extracts those checks into product-neutral validation.
