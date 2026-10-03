import AICore
import AIProviderCoreAI
import Foundation

public struct WeakLinkedCoreAIBridge:
    CoreAIModelLifecycleBridge
{
    private let dynamicBridge:
        WeakSymbolCoreAIBridge

    public init(
        availabilitySymbol: String =
            "AICKCoreAIIsAvailable",
        generateSymbol: String =
            "AICKCoreAIGenerate",
        isPreparedSymbol: String =
            "AICKCoreAIIsPrepared",
        prepareSymbol: String =
            "AICKCoreAIPrepare",
        loadSymbol: String =
            "AICKCoreAILoad",
        unloadSymbol: String =
            "AICKCoreAIUnload",
        clearPreparationCacheSymbol:
            String =
            "AICKCoreAIClearPreparationCache",
        runtimeFrameworkName:
            String =
            "AICoreKitCoreAIRuntime"
    ) {
        let runtimeExecutablePath =
            Self.runtimeExecutablePath(
                frameworkName:
                    runtimeFrameworkName
            )

        dynamicBridge =
            WeakSymbolCoreAIBridge(
                availabilitySymbol:
                    availabilitySymbol,
                generateSymbol:
                    generateSymbol,
                isPreparedSymbol:
                    isPreparedSymbol,
                prepareSymbol:
                    prepareSymbol,
                loadSymbol:
                    loadSymbol,
                unloadSymbol:
                    unloadSymbol,
                clearPreparationCacheSymbol:
                    clearPreparationCacheSymbol,
                runtimeLibraryPath:
                    runtimeExecutablePath
            )
    }

    private static func runtimeExecutablePath(
        frameworkName: String
    ) -> String? {
        guard
            let frameworksURL =
                Bundle.main
                .privateFrameworksURL
        else {
            return nil
        }

        let executableURL =
            frameworksURL
            .appendingPathComponent(
                "\(frameworkName).framework",
                isDirectory:
                    true
            )
            .appendingPathComponent(
                frameworkName,
                isDirectory:
                    false
            )

        return
            FileManager.default
            .fileExists(
                atPath:
                    executableURL.path
            )
            ? executableURL.path
            : nil
    }

    public func availability()
        async -> AIAvailability
    {
        await dynamicBridge
            .availability()
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

    public func isPrepared(
        modelPath: String
    ) async -> Bool {
        await dynamicBridge.isPrepared(
            modelPath: modelPath
        )
    }

    public func prepare(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        await dynamicBridge.prepare(
            modelPath: modelPath
        )
    }

    public func load(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        await dynamicBridge.load(
            modelPath: modelPath
        )
    }

    public func unload(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        await dynamicBridge.unload(
            modelPath: modelPath
        )
    }

    public func clearPreparationCache(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        await dynamicBridge
            .clearPreparationCache(
                modelPath: modelPath
            )
    }
}
