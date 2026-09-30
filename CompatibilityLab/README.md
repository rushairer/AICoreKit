# Compatibility Lab

This directory records compatibility experiments that should not leak platform-specific constraints into AICore.

## iOS 26 host / iOS 27 Core AI runtime

ColorCamera proved the following packaging boundary with Xcode 27:

- The host app keeps an iOS 26 minimum deployment target.
- An internal framework keeps an iOS 27 minimum deployment target.
- The host weak-links the higher-minimum framework.
- The host does not import the higher-minimum Swift module.
- A narrow C ABI bridge is exposed from the iOS 27 framework.
- The framework uses an @rpath install name.
- The host gates calls with OS availability and a weak bridge probe.

The production AICoreKit Core AI provider should generalize this boundary without importing ColorCamera product types, prompts, or palette schemas.

Before 0.2, the compatibility lab must cover:

1. iOS 26 real-device launch with the weak framework absent/unavailable.
2. iOS 27 real-device bridge availability.
3. Release archive and distribution validation.
4. Model load and inference after the ABI boundary is proven.
5. Cancellation, repeated model load, and memory-pressure behavior.
