# Core AI weak ABI contract

This is the proposed product-neutral C ABI between an iOS 26 host and an iOS 27-only Core AI runtime framework.

The host must not import `CoreAILanguageModels` or the higher-minimum Swift framework module.

## Symbols

```c
int32_t AICKCoreAIIsAvailable(void);

void AICKCoreAIGenerate(
    const char *requestJSON,
    const char *modelPath,
    void *context,
    AICKCoreAIGenerateCompletion completion
);
```

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

The ABI intentionally knows nothing about palettes, practice sessions, astrology, or other host product domains.

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

The production iOS 27 framework implementation will map Core AI runtime failures to this contract.
