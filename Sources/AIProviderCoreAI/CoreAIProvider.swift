import AICore
import Foundation

public struct CoreAIProvider:
    AIProvider,
    AIPersistentResourceManaging
{
    public let id: AIProviderID
    public let displayName: String

    private let bridge: any CoreAIBridge
    private let resourceProvider:
        any CoreAIModelResourceProviding
    private let lifecycleController:
        CoreAIModelLifecycleController?

    public init(
        id: AIProviderID = .coreAI,
        displayName: String =
            "Core AI Local Model",
        bridge: any CoreAIBridge,
        resourceProvider:
            any CoreAIModelResourceProviding,
        lifecycleController:
            CoreAIModelLifecycleController? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bridge = bridge
        self.resourceProvider =
            resourceProvider

        if let lifecycleBridge =
            bridge
            as? any CoreAIModelLifecycleBridge
        {
            self.lifecycleController =
                lifecycleController
                ?? CoreAIModelLifecycleController(
                    providerID: id,
                    bridge: lifecycleBridge,
                    resourceProvider:
                        resourceProvider
                )
        } else {
            self.lifecycleController =
                lifecycleController
        }
    }

    public var capabilities: AICapabilities {
        [
            .textGeneration,
            .localExecution,
            .privacyPreferred
        ]
    }

    public func availability()
        async -> AIAvailability
    {
        let bridgeAvailability =
            await bridge.availability()
        guard
            bridgeAvailability == .available
        else {
            return bridgeAvailability
        }

        do {
            guard
                let resource =
                    try await resourceProvider
                    .modelResource(),
                resource.exists
            else {
                return .unavailable(
                    .modelMissing
                )
            }
            return .available
        } catch {
            return .unavailable(
                .modelNotReady
            )
        }
    }

    public func modelLifecycleState()
        async -> CoreAIModelLifecycleState?
    {
        guard let lifecycleController else {
            return nil
        }

        return await lifecycleController
            .currentState()
    }

    public func isPersistentlyPrepared()
        async -> Bool
    {
        guard let lifecycleController else {
            return false
        }

        return await lifecycleController
            .isPersistentlyPrepared()
    }

    @discardableResult
    public func bootstrapIfPrepared()
        async throws -> Bool
    {
        guard let lifecycleController else {
            throw AIError
                .unsupportedCapability
        }

        return try await lifecycleController
            .bootstrapIfPrepared()
    }

    public func preparePersistentResources()
        async throws
    {
        guard let lifecycleController else {
            throw AIError
                .unsupportedCapability
        }

        try await lifecycleController
            .preparePersistentResources()
    }

    public func loadPreparedResources()
        async throws
    {
        guard let lifecycleController else {
            throw AIError
                .unsupportedCapability
        }

        try await lifecycleController
            .loadPreparedResources()
    }

    public func clearPreparationCache()
        async throws
    {
        guard let lifecycleController else {
            throw AIError
                .unsupportedCapability
        }

        try await lifecycleController
            .clearPreparationCache()
    }

    public func prepareResources()
        async throws
    {
        guard let lifecycleController else {
            throw AIError
                .unsupportedCapability
        }

        try await lifecycleController
            .ensureReady()
    }

    public func releaseResources()
        async throws
    {
        guard let lifecycleController else {
            throw AIError
                .unsupportedCapability
        }

        try await lifecycleController
            .unload()
    }

    public func generate(
        _ request: AIRequest
    ) async throws -> AIResponse {
        guard
            capabilities.satisfies(
                request
                    .requiredCapabilities
            )
        else {
            throw AIError
                .unsupportedCapability
        }

        let currentAvailability =
            await availability()
        guard
            currentAvailability
                == .available
        else {
            throw AIError.unavailable(
                unavailableReason(
                    from:
                        currentAvailability
                )
            )
        }

        if let lifecycleController {
            try await lifecycleController
                .ensureReady()
        }

        let resource =
            try await requiredModelResource(
                requireExistingFile: true
            )

        let wireRequest =
            CoreAIWireRequest(
                messages:
                    request.messages.map(
                        CoreAIWireMessage.init
                    ),
                maxOutputTokens:
                    request.maxOutputTokens,
                temperature:
                    request.temperature,
                metadata:
                    request.metadata
            )

        let requestData: Data
        do {
            requestData =
                try JSONEncoder()
                .encode(wireRequest)
        } catch {
            throw AIError.invalidRequest(
                "Failed to encode Core AI request"
            )
        }

        let invocation =
            await bridge.generate(
                requestJSON:
                    String(
                        decoding:
                            requestData,
                        as: UTF8.self
                    ),
                modelPath:
                    resource.path
            )

        try throwIfNeeded(
            invocation.status,
            operation: "generate"
        )

        guard
            let responseJSON =
                invocation.responseJSON,
            let responseData =
                responseJSON.data(
                    using: .utf8
                )
        else {
            throw AIError.decodingFailure(
                "Core AI bridge returned an empty response"
            )
        }

        let wireResponse:
            CoreAIWireResponse
        do {
            wireResponse =
                try JSONDecoder()
                .decode(
                    CoreAIWireResponse.self,
                    from: responseData
                )
        } catch {
            throw AIError.decodingFailure(
                error.localizedDescription
            )
        }

        return AIResponse(
            text: wireResponse.text,
            providerID: id,
            finishReason:
                wireResponse
                .normalizedFinishReason,
            usage:
                AIUsage(
                    inputTokens:
                        wireResponse
                        .inputTokens,
                    outputTokens:
                        wireResponse
                        .outputTokens
                )
        )
    }

    private func requiredModelResource(
        requireExistingFile: Bool
    ) async throws -> CoreAIModelResource {
        guard
            let resource =
                try await resourceProvider
                .modelResource()
        else {
            throw AIError.unavailable(
                .modelMissing
            )
        }

        if
            requireExistingFile
            && !resource.exists
        {
            throw AIError.unavailable(
                .modelMissing
            )
        }

        return resource
    }

    private func throwIfNeeded(
        _ status: CoreAIBridgeStatus,
        operation: String
    ) throws {
        switch status {
        case .success:
            return
        case .invalidRequest:
            throw AIError.invalidRequest(
                "Core AI bridge rejected the \(operation) request"
            )
        case .modelLoadFailed:
            throw AIError.unavailable(
                .modelNotReady
            )
        case .generationFailed:
            throw AIError.providerFailure(
                providerID: id,
                message:
                    "Core AI \(operation) failed"
            )
        case .serializationFailed:
            throw AIError.decodingFailure(
                "Core AI bridge failed to serialize the \(operation) response"
            )
        case .cancelled:
            throw AIError.cancelled
        case .unavailable:
            throw AIError.unavailable(
                .frameworkUnavailable
            )
        case .unknown:
            throw AIError.providerFailure(
                providerID: id,
                message:
                    "Unknown Core AI \(operation) failure"
            )
        }
    }

    private func unavailableReason(
        from availability: AIAvailability
    ) -> AIUnavailabilityReason {
        switch availability {
        case .available:
            return .unknown()
        case .unavailable(let reason):
            return reason
        }
    }
}
