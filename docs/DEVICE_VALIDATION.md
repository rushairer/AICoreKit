# Signed-device validation

AICoreKit's remaining 1.0 local-runtime gate requires evidence from signed applications on real devices. Archive and weak-link fixtures prove packaging topology, but they cannot prove launch, inference, memory, cancellation, or thermal behavior on hardware.

Before running this matrix, provision the real host model resource according to `LOCAL_MODELS.md`. A no-model build is not device inference evidence.

ColorCamera has already provided real iOS 27 Qwen3-0.6B inference evidence for one production integration. That closes the basic "can the shared runtime execute this model in a real app?" question, but it does not replace the lower-OS, signed-distribution, repeated memory/cancellation, or thermal matrix below.

## Required device matrix

At minimum, validate:

1. a supported lower-OS host device where the Core AI runtime is unavailable;
2. an iOS 27 device that supports the Core AI runtime and can execute the target local model;
3. at least one representative lower-memory device tier if the product ships a large local model.

## Lower-OS host run

The signed application must:

- launch without attempting to load the iOS 27 runtime;
- report the local provider unavailable without crashing;
- continue through its documented fallback path;
- avoid first-use model preparation.

Record an `AIDeviceValidationReport` for the provider availability probe and preserve the signed build/archive identifier used for the run.

## iOS 27 local-model run

Run diagnostics twice.

### Cold preparation

Start from a cleared preparation cache and record:

- availability;
- persistent preparation duration;
- process/runtime load duration;
- generation duration;
- before/after physical footprint and resident memory;
- thermal state;
- explicit cancellation probe;
- release behavior.

### Warm launch

Terminate and relaunch the app without clearing persistent preparation. The app must use launch-safe bootstrap/load and must not repeat expensive first preparation.

Record the second report separately so cold preparation and warm load can be compared directly.

## Thermal run

Exercise the product's realistic foreground workload together with local inference for long enough to observe thermal transitions. For ColorCamera this means camera capture plus representative AI requests rather than an isolated text loop.

Do not encode a universal thermal threshold in AICoreKit. Record the observed state and product behavior. The product should degrade deliberately when its own thermal/resource policy requires it.

## Cancellation

The cancellation probe is successful only when the provider surfaces cancellation. A generation that finishes before cancellation is applied is not counted as proof of cancellation behavior; rerun with a request/model workload that remains active long enough to cancel.

## Distribution evidence

For the 1.0 gate, retain:

- signed archive/build identity;
- App Store/TestFlight or equivalent signed-distribution evidence;
- device + OS version;
- cold and warm diagnostic JSON reports;
- notes for fallback, memory, cancellation, and thermal observations.

The Roadmap item remains open until those real-device and signed-distribution artifacts exist.


When the provider implements `AIPersistentResourceManaging`, the JSON report contains separate `preparePersistentResources` and `loadPreparedResources` steps. Do not collapse these measurements: the former represents first-use persistent specialization, while the latter represents ordinary process startup residency.
