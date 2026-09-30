import AICore
import Foundation

public struct CoreAIProvider: AIProvider {
    public let id: AIProviderID
    public let displayName: String

    private let bridge: any CoreAIBridge
    private let resourceProvider: any CoreAIModelResourceProviding

    public init(
        id: AIProviderID = .coreAI,
        displayName: String = "Core AI Local Model",
        bridge: any CoreAIBridge,
        resourceProvider: any CoreAIModelResourceProviding
    ) {
        self.id = id
        self.displayName = displayName
        self.bridge = bridge
        self.resourceProvider = resourceProvider
    }

    public var capabilities: AICapabilities {
        [.textGeneration, .localExecution, .privacyPreferred]
    }

    public func availability() async -> AIAvailability {
        let bridgeAvailability = await bridge.availability()
        guard bridgeAvailability == .available else {
            return bridgeAvailability
        }

        do {
            guard let resource = try await resourceProvider.modelResource(),
                  resource.exists else {
                return .unavailable(.modelMissing)
            }
            return .available
        } catch {
            return .unavailable(.modelNotReady)
        }
    }

    public func generate(_ request: AIRequest) async throws -> AIResponse {
        guard capabilities.satisfies(request.requiredCapabilities) else {
            throw AIError.unsupportedCapability
        }

        let currentAvailability = await availability()
        guard currentAvailability == .available else {
            throw AIError.unavailable(unavailableReason(from: currentAvailability))
        }

        guard let resource = try await resourceProvider.modelResource(),
              resource.exists else {
            throw AIError.unavailable(.modelMissing)
        }

        let wireRequest = CoreAIWireRequest(
            messages: request.messages.map(CoreAIWireMessage.init),
            maxOutputTokens: request.maxOutputTokens,
            temperature: request.temperature,
            metadata: request.metadata
        )

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(wireRequest)
        } catch {
            throw AIError.invalidRequest("Failed to encode Core AI request")
        }

        let invocation = await bridge.generate(
            requestJSON: String(decoding: requestData, as: UTF8.self),
            modelPath: resource.path
        )

        switch invocation.status {
        case .success:
            break
        case .invalidRequest:
            throw AIError.invalidRequest("Core AI bridge rejected the request")
        case .modelLoadFailed:
            throw AIError.unavailable(.modelNotReady)
        case .generationFailed:
            throw AIError.providerFailure(providerID: id, message: "Core AI generation failed")
        case .serializationFailed:
            throw AIError.decodingFailure("Core AI bridge failed to serialize its response")
        case .cancelled:
            throw AIError.cancelled
        case .unavailable:
            throw AIError.unavailable(.frameworkUnavailable)
        case .unknown:
            throw AIError.providerFailure(providerID: id, message: "Unknown Core AI bridge failure")
        }

        guard let responseJSON = invocation.responseJSON,
              let responseData = responseJSON.data(using: .utf8) else {
            throw AIError.decodingFailure("Core AI bridge returned an empty response")
        }

        let wireResponse: CoreAIWireResponse
        do {
            wireResponse = try JSONDecoder().decode(CoreAIWireResponse.self, from: responseData)
        } catch {
            throw AIError.decodingFailure(error.localizedDescription)
        }

        return AIResponse(
            text: wireResponse.text,
            providerID: id,
            finishReason: wireResponse.normalizedFinishReason,
            usage: AIUsage(
                inputTokens: wireResponse.inputTokens,
                outputTokens: wireResponse.outputTokens
            )
        )
    }

    private func unavailableReason(from availability: AIAvailability) -> AIUnavailabilityReason {
        switch availability {
        case .available:
            return .unknown()
        case .unavailable(let reason):
            return reason
        }
    }
}
