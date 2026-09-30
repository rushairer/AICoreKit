import AICore
import Darwin

public struct WeakSymbolCoreAIBridge: CoreAIBridge {
    public let availabilitySymbol: String
    public let generateSymbol: String

    public init(
        availabilitySymbol: String = "AICKCoreAIIsAvailable",
        generateSymbol: String = "AICKCoreAIGenerate"
    ) {
        self.availabilitySymbol = availabilitySymbol
        self.generateSymbol = generateSymbol
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
            return CoreAIBridgeInvocation(status: .unavailable)
        }

        guard let function = resolveGenerateFunction() else {
            return CoreAIBridgeInvocation(status: .unavailable)
        }

        return await withCheckedContinuation {
            (continuation: CheckedContinuation<CoreAIBridgeInvocation, Never>) in

            let pending = PendingCoreAIInvocation(continuation: continuation)
            let context = Unmanaged.passRetained(pending).toOpaque()

            requestJSON.withCString { requestPointer in
                modelPath.withCString { modelPathPointer in
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

    private static var runtimeOSAvailable: Bool {
        if #available(iOS 27.0, macOS 27.0, *) {
            return true
        }
        return false
    }

    private func resolveAvailabilityFunction() -> CoreAIAvailabilityFunction? {
        resolveSymbol(named: availabilitySymbol, as: CoreAIAvailabilityFunction.self)
    }

    private func resolveGenerateFunction() -> CoreAIGenerateFunction? {
        resolveSymbol(named: generateSymbol, as: CoreAIGenerateFunction.self)
    }

    private func resolveSymbol<T>(
        named name: String,
        as type: T.Type
    ) -> T? {
        guard let handle = dlopen(nil, RTLD_LAZY) else {
            return nil
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, name) else {
            return nil
        }

        return unsafeBitCast(symbol, to: type)
    }
}

private typealias CoreAIAvailabilityFunction =
    @convention(c) () -> Int32

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

private final class PendingCoreAIInvocation:
    @unchecked Sendable
{
    let continuation: CheckedContinuation<CoreAIBridgeInvocation, Never>

    init(
        continuation: CheckedContinuation<CoreAIBridgeInvocation, Never>
    ) {
        self.continuation = continuation
    }
}

private let coreAIGenerateCompletion: CoreAIGenerateCompletion = {
    context,
    responseJSON,
    rawStatus in

    guard let context else {
        return
    }

    let pending =
        Unmanaged<PendingCoreAIInvocation>
        .fromOpaque(context)
        .takeRetainedValue()

    let response =
        responseJSON.map { String(cString: $0) }

    pending.continuation.resume(
        returning: CoreAIBridgeInvocation(
            status: CoreAIBridgeStatus(rawValue: rawStatus) ?? .unknown,
            responseJSON: response
        )
    )
}
