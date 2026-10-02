import AICore
import AIHTTP
import AIProviderAnthropic
import AIProviderGemini
import AIProviderOpenAI
import AIProviderOpenAICompatible
import Foundation

public enum AIProviderProfileKind:
    String,
    CaseIterable,
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    case openAI
    case anthropic
    case gemini
    case openAICompatible
}


public enum AIProviderPreset:
    String,
    CaseIterable,
    Codable,
    Sendable,
    Equatable,
    Hashable,
    Identifiable
{
    case openAI
    case anthropic
    case gemini
    case deepSeek
    case customOpenAICompatible

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Gemini"
        case .deepSeek:
            return "DeepSeek"
        case .customOpenAICompatible:
            return "OpenAI Compatible"
        }
    }

    public var kind:
        AIProviderProfileKind
    {
        switch self {
        case .openAI:
            return .openAI
        case .anthropic:
            return .anthropic
        case .gemini:
            return .gemini
        case .deepSeek,
             .customOpenAICompatible:
            return .openAICompatible
        }
    }

    public var providerID:
        AIProviderID
    {
        switch self {
        case .openAI:
            return .openAI
        case .anthropic:
            return .anthropic
        case .gemini:
            return .gemini
        case .deepSeek:
            return AIProviderID(
                rawValue: "deepseek"
            )
        case .customOpenAICompatible:
            return .openAICompatible
        }
    }

    public var defaultBaseURL: URL? {
        switch self {
        case .openAI:
            return URL(
                string:
                    "https://api.openai.com/v1"
            )
        case .anthropic:
            return URL(
                string:
                    "https://api.anthropic.com/v1"
            )
        case .gemini:
            return URL(
                string:
                    "https://generativelanguage.googleapis.com"
            )
        case .deepSeek:
            return URL(
                string:
                    "https://api.deepseek.com/v1"
            )
        case .customOpenAICompatible:
            return nil
        }
    }

    public var credentialKind:
        AICredentialKind
    {
        switch self {
        case .anthropic,
             .gemini:
            return .apiKey
        case .openAI,
             .deepSeek,
             .customOpenAICompatible:
            return .bearerToken
        }
    }

    public func profile(
        id: String,
        model: String,
        baseURL: URL? = nil,
        displayName:
            String? = nil,
        providerID:
            AIProviderID? = nil
    ) throws -> AIProviderProfile {
        guard
            let resolvedBaseURL =
                baseURL
                ?? defaultBaseURL
        else {
            throw AIProviderProfileValidationError
                .missingHost
        }

        let profile =
            AIProviderProfile(
                id: id,
                kind: kind,
                providerID:
                    providerID
                    ?? self.providerID,
                displayName:
                    displayName
                    ?? self.displayName,
                model: model,
                baseURL:
                    resolvedBaseURL,
                credentialKind:
                    credentialKind
            )

        try AIProviderProfileValidator
            .validate(profile)

        return profile
    }
}

public struct AIProviderProfile:
    Identifiable,
    Codable,
    Sendable,
    Equatable
{
    public let id: String
    public var kind: AIProviderProfileKind
    public var providerID: AIProviderID
    public var displayName: String
    public var model: String
    public var baseURL: URL
    public var credentialKind: AICredentialKind

    public init(
        id: String,
        kind: AIProviderProfileKind,
        providerID: AIProviderID,
        displayName: String,
        model: String,
        baseURL: URL,
        credentialKind: AICredentialKind
    ) {
        self.id = id
        self.kind = kind
        self.providerID = providerID
        self.displayName = displayName
        self.model = model
        self.baseURL = baseURL
        self.credentialKind = credentialKind
    }
}

public extension AIProviderProfile {
    static func openAI(
        model: String,
        id: String = "openai"
    ) -> Self {
        Self(
            id: id,
            kind: .openAI,
            providerID: .openAI,
            displayName: "OpenAI",
            model: model,
            baseURL: URL(
                string: "https://api.openai.com/v1"
            )!,
            credentialKind: .bearerToken
        )
    }

    static func anthropic(
        model: String,
        id: String = "anthropic"
    ) -> Self {
        Self(
            id: id,
            kind: .anthropic,
            providerID: .anthropic,
            displayName: "Anthropic",
            model: model,
            baseURL: URL(
                string: "https://api.anthropic.com/v1"
            )!,
            credentialKind: .apiKey
        )
    }

    static func gemini(
        model: String,
        id: String = "gemini"
    ) -> Self {
        Self(
            id: id,
            kind: .gemini,
            providerID: .gemini,
            displayName: "Gemini",
            model: model,
            baseURL: URL(
                string:
                    "https://generativelanguage.googleapis.com"
            )!,
            credentialKind: .apiKey
        )
    }

    static func deepSeek(
        model: String,
        id: String = "deepseek"
    ) -> Self {
        Self(
            id: id,
            kind: .openAICompatible,
            providerID: AIProviderID(
                rawValue: "deepseek"
            ),
            displayName: "DeepSeek",
            model: model,
            baseURL: URL(
                string: "https://api.deepseek.com/v1"
            )!,
            credentialKind: .bearerToken
        )
    }

    static func openAICompatible(
        id: String,
        providerID: AIProviderID,
        displayName: String,
        baseURL: URL,
        model: String,
        credentialKind:
            AICredentialKind = .bearerToken
    ) -> Self {
        Self(
            id: id,
            kind: .openAICompatible,
            providerID: providerID,
            displayName: displayName,
            model: model,
            baseURL: baseURL,
            credentialKind: credentialKind
        )
    }
}

public enum AIProviderProfileValidationError:
    Error,
    Sendable,
    Equatable,
    LocalizedError
{
    case emptyIdentifier
    case emptyDisplayName
    case emptyModel
    case unsupportedURLScheme
    case missingHost

    public var errorDescription:
        String?
    {
        switch self {
        case .emptyIdentifier:
            return "Provider identifier is required."
        case .emptyDisplayName:
            return "Provider display name is required."
        case .emptyModel:
            return "Model name is required."
        case .unsupportedURLScheme:
            return "Provider URL must use HTTP or HTTPS."
        case .missingHost:
            return "Provider URL must include a valid host."
        }
    }
}

public enum AIProviderProfileValidator {
    public static func validate(
        _ profile: AIProviderProfile
    ) throws {
        guard
            !profile.id
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        else {
            throw AIProviderProfileValidationError
                .emptyIdentifier
        }

        guard
            !profile.displayName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        else {
            throw AIProviderProfileValidationError
                .emptyDisplayName
        }

        guard
            !profile.model
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        else {
            throw AIProviderProfileValidationError
                .emptyModel
        }

        guard
            let scheme =
                profile.baseURL.scheme?
                .lowercased(),
            scheme == "https"
                || scheme == "http"
        else {
            throw AIProviderProfileValidationError
                .unsupportedURLScheme
        }

        guard
            let host = profile.baseURL.host,
            !host.isEmpty
        else {
            throw AIProviderProfileValidationError
                .missingHost
        }
    }
}

public struct AIConfiguredProviderFactory:
    Sendable
{
    private let credentialProvider:
        any AICredentialProviding
    private let transport:
        any AIHTTPTransport

    public init(
        credentialProvider:
            any AICredentialProviding,
        transport:
            any AIHTTPTransport =
                URLSessionAIHTTPTransport()
    ) {
        self.credentialProvider =
            credentialProvider
        self.transport = transport
    }

    public func makeProvider(
        from profile: AIProviderProfile
    ) throws -> any AIProvider {
        try AIProviderProfileValidator
            .validate(profile)

        switch profile.kind {
        case .openAI:
            return OpenAIProvider(
                configuration:
                    OpenAIProviderConfiguration(
                        providerID:
                            profile.providerID,
                        displayName:
                            profile.displayName,
                        model:
                            profile.model,
                        baseURL:
                            profile.baseURL
                    ),
                credentialProvider:
                    credentialProvider,
                transport:
                    transport
            )

        case .anthropic:
            return AnthropicProvider(
                configuration:
                    AnthropicProviderConfiguration(
                        providerID:
                            profile.providerID,
                        displayName:
                            profile.displayName,
                        model:
                            profile.model,
                        baseURL:
                            profile.baseURL
                    ),
                credentialProvider:
                    credentialProvider,
                transport:
                    transport
            )

        case .gemini:
            return GeminiProvider(
                configuration:
                    GeminiProviderConfiguration(
                        providerID:
                            profile.providerID,
                        displayName:
                            profile.displayName,
                        model:
                            profile.model,
                        baseURL:
                            profile.baseURL
                    ),
                credentialProvider:
                    credentialProvider,
                transport:
                    transport
            )

        case .openAICompatible:
            return OpenAICompatibleProvider(
                configuration:
                    OpenAICompatibleProviderConfiguration(
                        providerID:
                            profile.providerID,
                        displayName:
                            profile.displayName,
                        baseURL:
                            profile.baseURL,
                        model:
                            profile.model,
                        credentialKind:
                            profile.credentialKind
                    ),
                credentialProvider:
                    credentialProvider,
                transport:
                    transport
            )
        }
    }
}

public struct AIProviderConnectionResult:
    Sendable,
    Equatable
{
    public let providerID: AIProviderID
    public let availability: AIAvailability

    public init(
        providerID: AIProviderID,
        availability: AIAvailability
    ) {
        self.providerID = providerID
        self.availability = availability
    }
}

public struct AIProviderConnectionTester:
    Sendable
{
    private let factory:
        AIConfiguredProviderFactory

    public init(
        factory: AIConfiguredProviderFactory
    ) {
        self.factory = factory
    }

    public func checkAvailability(
        profile: AIProviderProfile
    ) async throws
        -> AIProviderConnectionResult
    {
        let provider =
            try factory.makeProvider(
                from: profile
            )

        return AIProviderConnectionResult(
            providerID: provider.id,
            availability:
                await provider.availability()
        )
    }

    public func probeTextGeneration(
        profile: AIProviderProfile,
        prompt: String = "Reply with OK.",
        maxOutputTokens: Int = 8
    ) async throws -> AIResponse {
        let provider =
            try factory.makeProvider(
                from: profile
            )

        return try await provider.generate(
            AIRequest(
                messages: [
                    .user(prompt)
                ],
                requiredCapabilities: [
                    .textGeneration
                ],
                executionPreference:
                    .remoteOnly,
                maxOutputTokens:
                    maxOutputTokens,
                temperature: 0
            )
        )
    }
}
