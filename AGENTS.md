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


## Local model integration

- Read `docs/CONSUMER_INTEGRATION.md` for any production consumer integration and `docs/LOCAL_MODELS.md` before changing any Core AI local-model consumer.
- A host build that succeeds without a real model resource proves graceful degradation only. Never report local inference as complete until the model is provisioned and a signed supported device executes a real generation.
- Use `Scripts/provision-coreai-model.sh` as the preferred export + install workflow. Product repositories may keep thin wrappers that choose destination/model names, but must not duplicate AICoreKit export/copy/validation logic.
- Keep generated model assets out of this repository. Host repositories must document their resource destination, git-ignore policy, and exact provisioning command.
- Preserve the distinction between installed model resource, persistent preparation, current-process load, generation readiness, unload, and preparation-cache clearing.
- Reuse `CoreAIModelProfile`, `CoreAIModelSettingsStore`, `CoreAIModelLifecycleController`, and `CoreAIDirectoryModelResourceProvider`; do not create product-specific parallel lifecycle state machines.
- Lower-minimum host targets must not import `CoreAILM` / `CoreAILanguageModels` directly. Keep the iOS/macOS 27 runtime behind the shared weak-link/ABI boundary.
- If the current agent environment cannot run Xcode 27 / `uv` / signed-device qualification, leave the exact provisioning command and mark the device-validation gate open. Do not substitute a no-model build and call the integration finished.

## Stabilization policy

- AICoreKit is in pre-1.0 stabilization. Prefer fixes, contract tests, documentation, and evidence from real consumers over adding new abstractions.
- Add a new public primitive only when at least one real consumer needs it and the behavior is product-neutral.
- Keep retry prompts, domain schemas, language policy, semantic validation, and product UX in the consuming application unless the contract is genuinely provider/runtime-wide.
- `AIResponse.validatedCompletedText()` is the shared completion boundary for plain-text responses; consumers still own schema, language, and domain validation after that boundary.
