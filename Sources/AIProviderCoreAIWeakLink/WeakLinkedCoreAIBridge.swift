import AICore
import AICoreWeakBridgeShim
import AIProviderCoreAI

public struct WeakLinkedCoreAIBridge: CoreAIModelLifecycleBridge {
    private let dynamicBridge: WeakSymbolCoreAIBridge

    public init(
        generateSymbol: String = "AICKCoreAIGenerate",
        prepareSymbol: String = "AICKCoreAIPrepare",
        unloadSymbol: String = "AICKCoreAIUnload"
    ) {
        dynamicBridge = WeakSymbolCoreAIBridge(
            generateSymbol: generateSymbol,
            prepareSymbol: prepareSymbol,
            unloadSymbol: unloadSymbol
        )
    }

    public func availability() async -> AIAvailability {
        guard Self.runtimeOSAvailable else {
            return .unavailable(.unsupportedPlatform)
        }

        guard AICKCoreAIWeakSymbolPresent() != 0 else {
            return .unavailable(.frameworkUnavailable)
        }

        return AICKCoreAIWeakIsAvailable() != 0
            ? .available
            : .unavailable(.serviceUnavailable)
    }

    public func generate(
        requestJSON: String,
        modelPath: String
    ) async -> CoreAIBridgeInvocation {
        await dynamicBridge.generate(
            requestJSON: requestJSON,
            modelPath: modelPath
        )
    }

    public func prepare(modelPath: String) async -> CoreAIBridgeStatus {
        await dynamicBridge.prepare(modelPath: modelPath)
    }

    public func unload(modelPath: String) async -> CoreAIBridgeStatus {
        await dynamicBridge.unload(modelPath: modelPath)
    }

    private static var runtimeOSAvailable: Bool {
        if #available(iOS 27.0, macOS 27.0, *) {
            return true
        }
        return false
    }
}
