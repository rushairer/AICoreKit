import AICore
import AIProviderCoreAI
import Foundation

private struct FixtureResourceProvider:
    CoreAIModelResourceProviding
{
    func modelResource()
        async throws -> CoreAIModelResource?
    {
        CoreAIModelResource(
            identifier: "fixture",
            path: "/tmp/aicorekit-fixture-model"
        )
    }
}

private struct FixtureLifecycleBridge:
    CoreAIModelLifecycleBridge
{
    func availability()
        async -> AIAvailability
    {
        .available
    }

    func generate(
        requestJSON: String,
        modelPath: String
    ) async -> CoreAIBridgeInvocation {
        CoreAIBridgeInvocation(
            status: .unavailable
        )
    }

    func isPrepared(
        modelPath: String
    ) async -> Bool {
        false
    }

    func prepare(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        .success
    }

    func load(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        .success
    }

    func unload(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        .success
    }

    func clearPreparationCache(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        .success
    }
}

private enum LegacyStatus {
    case invalidRequest
    case serializationFailed
    case cancelled
    case modelLoadFailed
}

private func legacyStatus(
    from error: Error
) -> LegacyStatus {
    guard let aiError = error as? AIError else {
        return .modelLoadFailed
    }

    switch aiError {
    case .invalidRequest:
        return .invalidRequest

    case .decodingFailure:
        return .serializationFailed

    case .cancelled:
        return .cancelled

    case .unavailable,
         .unsupportedCapability,
         .authenticationFailed,
         .rateLimited,
         .transportFailure,
         .toolExecutionFailed,
         .toolConfirmationRequired,
         .toolConfirmationDenied,
         .exhaustedProviders,
         .providerFailure:
        return .modelLoadFailed
    }
}

@main
private struct Swift5LifecycleConsumer {
    static func main() async {
        let controller =
            CoreAIModelLifecycleController(
                bridge: FixtureLifecycleBridge(),
                resourceProvider:
                    FixtureResourceProvider()
            )

        _ = await controller.currentState()
        _ = await controller
            .isPersistentlyPrepared()

        do {
            _ = try await controller
                .bootstrapIfPrepared()
            try await controller
                .ensureReady()
            try await controller
                .unload()
            try await controller
                .clearPreparationCache()
        } catch {
            _ = legacyStatus(
                from: error
            )
        }
    }
}
