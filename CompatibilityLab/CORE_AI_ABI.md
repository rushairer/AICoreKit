# Core AI weak ABI contract

This is the product-neutral C ABI between a lower-minimum host and the iOS/macOS 27-only Core AI runtime.

The host must not import `CoreAILanguageModels` or the higher-minimum Swift runtime module.

## Symbols

```c
int32_t AICKCoreAIIsAvailable(void);
int32_t AICKCoreAIIsPrepared(const char *modelPath);

void AICKCoreAIGenerate(
    const char *requestJSON,
    const char *modelPath,
    void *context,
    AICKCoreAIGenerateCompletion completion
);

void AICKCoreAIPrepare(
    const char *modelPath,
    void *context,
    AICKCoreAIStatusCompletion completion
);

void AICKCoreAILoad(
    const char *modelPath,
    void *context,
    AICKCoreAIStatusCompletion completion
);

void AICKCoreAIUnload(
    const char *modelPath,
    void *context,
    AICKCoreAIStatusCompletion completion
);

void AICKCoreAIClearPreparationCache(
    const char *modelPath,
    void *context,
    AICKCoreAIStatusCompletion completion
);
```

The root package's `WeakSymbolCoreAIBridge` resolves these symbols dynamically with `dlsym`. The host is still responsible for embedding the runtime framework with a weak load command so the higher-minimum image is optional on older OS releases.

## Request JSON

The host sends vendor-neutral chat data:

```json
{
  "messages": [
    {"role": "system", "content": "Be concise.", "name": null},
    {"role": "user", "content": "Hello", "name": null}
  ],
  "maxOutputTokens": 128,
  "temperature": 0.2,
  "metadata": {}
}
```

The runtime must copy `requestJSON` and `modelPath` before the exported C function returns. The host owns those C-string buffers only for the duration of the call.

## Response JSON

The runtime responds with:

```json
{
  "text": "Hello.",
  "finishReason": "completed",
  "inputTokens": null,
  "outputTokens": null
}
```

The callback's JSON C string is valid only during the callback. The host copies it immediately.

The ABI intentionally knows nothing about palettes, practice sessions, astrology, or other product domains.

## Status codes

| Code | Meaning |
| ---: | --- |
| 0 | success |
| 1 | invalid request |
| 2 | model load failed |
| 3 | generation failed |
| 4 | serialization failed |
| 5 | cancelled |
| 6 | runtime unavailable |
| -1 | unknown |


## Lifecycle semantics

The ABI deliberately distinguishes two kinds of local-model state:

1. **Persistent preparation** — Core AI specialization survives process termination and is queried with `AICKCoreAIIsPrepared`. `AICKCoreAIPrepare` may be expensive on first use.
2. **Current-process residency** — `AICKCoreAILoad` makes an already prepared model resident for the current process; `AICKCoreAIUnload` releases that resident engine without deleting the persistent preparation cache.

`AICKCoreAIClearPreparationCache` first unloads current-process state and then removes Core AI's persistent specialization cache while leaving installed model assets intact.

A lower-minimum host must never call `AICKCoreAIPrepare` automatically at application launch merely because model assets exist. It may call `AICKCoreAILoad` automatically only after `AICKCoreAIIsPrepared` confirms a persistent cache hit.
