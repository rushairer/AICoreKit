import AICore
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct AppleFoundationModelsProvider: AIProvider {
    public let id: AIProviderID = .appleFoundationModels
    public let displayName: String

    public init(displayName: String = "Apple Foundation Models") {
        self.displayName = displayName
    }

    public var capabilities: AICapabilities {
        [.textGeneration, .localExecution, .privacyPreferred]
    }

    public func availability() async -> AIAvailability {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return .unavailable(.unsupportedPlatform)
        }

        let model = SystemLanguageModel.default
        guard model.supportsLocale() else {
            return .unavailable(.localeUnsupported)
        }

        switch model.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceUnsupported)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.featureDisabled)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        case .unavailable:
            return .unavailable(.unknown())
        }
        #else
        return .unavailable(.frameworkUnavailable)
        #endif
    }

    public func generate(_ request: AIRequest) async throws -> AIResponse {
        let currentAvailability = await availability()
        guard currentAvailability == .available else {
            throw AIError.unavailable(unavailableReason(from: currentAvailability))
        }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw AIError.unavailable(.unsupportedPlatform)
        }

        let session = LanguageModelSession(instructions: instructions(from: request.messages))
        let response = try await session.respond(
            to: prompt(from: request.messages),
            options: generationOptions(request)
        )

        return AIResponse(text: response.content, providerID: id)
        #else
        throw AIError.unavailable(.frameworkUnavailable)
        #endif
    }

    private func unavailableReason(from availability: AIAvailability) -> AIUnavailabilityReason {
        switch availability {
        case .available:
            return .unknown()
        case .unavailable(let reason):
            return reason
        }
    }

    private func instructions(from messages: [AIMessage]) -> String {
        let systemMessages = messages.filter { $0.role == .system }.map(\.content)
        return systemMessages.isEmpty
            ? "Respond helpfully, accurately, and concisely."
            : systemMessages.joined(separator: "\n\n")
    }

    private func prompt(from messages: [AIMessage]) -> String {
        let lines = messages.compactMap { message -> String? in
            switch message.role {
            case .system:
                return nil
            case .user:
                return "User: \(message.content)"
            case .assistant:
                return "Assistant: \(message.content)"
            case .tool:
                return "Tool: \(message.content)"
            }
        }
        return lines.isEmpty ? "User: Hello" : lines.joined(separator: "\n\n")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func generationOptions(_ request: AIRequest) -> GenerationOptions {
        GenerationOptions(
            temperature: request.temperature.map { min(max($0, 0), 1) },
            maximumResponseTokens: request.maxOutputTokens
        )
    }
    #endif
}
