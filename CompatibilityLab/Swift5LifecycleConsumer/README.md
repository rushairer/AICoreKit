# Swift 5 Lifecycle Consumer Fixture

This fixture compiles AICoreKit's Core AI lifecycle API from a Swift 5 language-mode consumer.

It protects the compatibility path used by lower-minimum iOS applications such as ColorCamera while the AICoreKit package itself is authored in Swift 6.

The fixture intentionally exercises:

- `CoreAIModelResourceProviding`
- `CoreAIModelLifecycleBridge`
- `CoreAIModelLifecycleController`
- actor calls for state/readiness/reset/cache clearing
- exhaustive `AIError` mapping from a consumer module

CI builds this package on every AICoreKit change.
