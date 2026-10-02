import AICore
import Darwin

public struct WeakSymbolCoreAIBridge: CoreAIModelLifecycleBridge {
    public let availabilitySymbol: String
    public let generateSymbol: String
    public let isPreparedSymbol: String
    public let prepareSymbol: String
    public let loadSymbol: String
    public let unloadSymbol: String
    public let clearPreparationCacheSymbol: String

    public init(
        availabilitySymbol: String = "AICKCoreAIIsAvailable",
        generateSymbol: String = "AICKCoreAIGenerate",
        isPreparedSymbol: String = "AICKCoreAIIsPrepared",
        prepareSymbol: String = "AICKCoreAIPrepare",
        loadSymbol: String = "AICKCoreAILoad",
        unloadSymbol: String = "AICKCoreAIUnload",
        clearPreparationCacheSymbol: String =
            "AICKCoreAIClearPreparationCache"
    ) {
        self.availabilitySymbol = availabilitySymbol
        self.generateSymbol = generateSymbol
        self.isPreparedSymbol = isPreparedSymbol
        self.prepareSymbol = prepareSymbol
        self.loadSymbol = loadSymbol
        self.unloadSymbol = unloadSymbol
        self.clearPreparationCacheSymbol =
            clearPreparationCacheSymbol
    }

    public func availability() async -> AIAvailability {
        guard Self.runtimeOSAvailable else {
            return .unavailable(.unsupportedPlatform)
        }

        guard let function = resolveAvailabilityFunction() else {
            return .unavailable(.frameworkUnavailable)
        }

        return function() != 0
            ? .available
            : .unavailable(.serviceUnavailable)
    }

    public func generate(
        requestJSON: String,
        modelPath: String
    ) async -> CoreAIBridgeInvocation {
        guard Self.runtimeOSAvailable else {
            return CoreAIBridgeInvocation(
                status: .unavailable
            )
        }

        guard let function = resolveGenerateFunction() else {
            return CoreAIBridgeInvocation(
                status: .unavailable
            )
        }

        return await withCheckedContinuation {
            (
                continuation:
                    CheckedContinuation<
                        CoreAIBridgeInvocation,
                        Never
                    >
            ) in

            let pending =
                PendingCoreAIInvocation(
                    continuation:
                        continuation
                )
            let context =
                Unmanaged
                .passRetained(pending)
                .toOpaque()

            requestJSON.withCString {
                requestPointer in

                modelPath.withCString {
                    modelPathPointer in

                    function(
                        requestPointer,
                        modelPathPointer,
                        context,
                        coreAIGenerateCompletion
                    )
                }
            }
        }
    }

    public func isPrepared(
        modelPath: String
    ) async -> Bool {
        guard Self.runtimeOSAvailable else {
            return false
        }

        guard
            let function = resolveSymbol(
                named: isPreparedSymbol,
                as:
                    CoreAIModelProbeFunction
                    .self
            )
        else {
            return false
        }

        return modelPath.withCString {
            function($0) != 0
        }
    }

    public func prepare(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        await invokeLifecycle(
            symbol: prepareSymbol,
            modelPath: modelPath
        )
    }

    public func load(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        await invokeLifecycle(
            symbol: loadSymbol,
            modelPath: modelPath
        )
    }

    public func unload(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        await invokeLifecycle(
            symbol: unloadSymbol,
            modelPath: modelPath
        )
    }

    public func clearPreparationCache(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        await invokeLifecycle(
            symbol:
                clearPreparationCacheSymbol,
            modelPath: modelPath
        )
    }

    private func invokeLifecycle(
        symbol: String,
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        guard Self.runtimeOSAvailable else {
            return .unavailable
        }

        guard
            let function = resolveSymbol(
                named: symbol,
                as:
                    CoreAIModelLifecycleFunction
                    .self
            )
        else {
            return .unavailable
        }

        return await withCheckedContinuation {
            (
                continuation:
                    CheckedContinuation<
                        CoreAIBridgeStatus,
                        Never
                    >
            ) in

            let pending =
                PendingCoreAIStatus(
                    continuation:
                        continuation
                )
            let context =
                Unmanaged
                .passRetained(pending)
                .toOpaque()

            modelPath.withCString {
                modelPathPointer in

                function(
                    modelPathPointer,
                    context,
                    coreAIStatusCompletion
                )
            }
        }
    }

    private static var runtimeOSAvailable: Bool {
        if #available(
            iOS 27.0,
            macOS 27.0,
            *
        ) {
            return true
        }
        return false
    }

    private func resolveAvailabilityFunction()
        -> CoreAIAvailabilityFunction?
    {
        resolveSymbol(
            named: availabilitySymbol,
            as:
                CoreAIAvailabilityFunction
                .self
        )
    }

    private func resolveGenerateFunction()
        -> CoreAIGenerateFunction?
    {
        resolveSymbol(
            named: generateSymbol,
            as:
                CoreAIGenerateFunction
                .self
        )
    }

    private func resolveSymbol<T>(
        named name: String,
        as type: T.Type
    ) -> T? {
        guard
            let handle =
                dlopen(nil, RTLD_LAZY)
        else {
            return nil
        }
        defer {
            dlclose(handle)
        }

        guard
            let symbol =
                dlsym(handle, name)
        else {
            return nil
        }

        return unsafeBitCast(
            symbol,
            to: type
        )
    }
}

private typealias CoreAIAvailabilityFunction =
    @convention(c) () -> Int32

private typealias CoreAIModelProbeFunction =
    @convention(c) (
        UnsafePointer<CChar>?
    ) -> Int32

private typealias CoreAIGenerateCompletion =
    @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        Int32
    ) -> Void

private typealias CoreAIGenerateFunction =
    @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafeMutableRawPointer?,
        CoreAIGenerateCompletion
    ) -> Void

private typealias CoreAIStatusCompletion =
    @convention(c) (
        UnsafeMutableRawPointer?,
        Int32
    ) -> Void

private typealias CoreAIModelLifecycleFunction =
    @convention(c) (
        UnsafePointer<CChar>?,
        UnsafeMutableRawPointer?,
        CoreAIStatusCompletion
    ) -> Void

private final class PendingCoreAIInvocation:
    @unchecked Sendable
{
    let continuation:
        CheckedContinuation<
            CoreAIBridgeInvocation,
            Never
        >

    init(
        continuation:
            CheckedContinuation<
                CoreAIBridgeInvocation,
                Never
            >
    ) {
        self.continuation = continuation
    }
}

private final class PendingCoreAIStatus:
    @unchecked Sendable
{
    let continuation:
        CheckedContinuation<
            CoreAIBridgeStatus,
            Never
        >

    init(
        continuation:
            CheckedContinuation<
                CoreAIBridgeStatus,
                Never
            >
    ) {
        self.continuation = continuation
    }
}

private let coreAIGenerateCompletion:
    CoreAIGenerateCompletion = {
        context,
        responseJSON,
        rawStatus in

        guard let context else {
            return
        }

        let pending =
            Unmanaged<
                PendingCoreAIInvocation
            >
            .fromOpaque(context)
            .takeRetainedValue()

        let response =
            responseJSON.map {
                String(cString: $0)
            }

        pending.continuation.resume(
            returning:
                CoreAIBridgeInvocation(
                    status:
                        CoreAIBridgeStatus(
                            rawValue:
                                rawStatus
                        )
                        ?? .unknown,
                    responseJSON:
                        response
                )
        )
    }

private let coreAIStatusCompletion:
    CoreAIStatusCompletion = {
        context,
        rawStatus in

        guard let context else {
            return
        }

        let pending =
            Unmanaged<
                PendingCoreAIStatus
            >
            .fromOpaque(context)
            .takeRetainedValue()

        pending.continuation.resume(
            returning:
                CoreAIBridgeStatus(
                    rawValue: rawStatus
                )
                ?? .unknown
        )
    }
