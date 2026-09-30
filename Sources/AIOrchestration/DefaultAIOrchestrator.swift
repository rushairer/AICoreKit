public import AICore

public actor DefaultAIOrchestrator {
    private let registry: AIProviderRegistry
    private let router: AIRouter

    public init(registry: AIProviderRegistry, router: AIRouter = AIRouter()) {
        self.registry = registry
        self.router = router
    }

    public func respond(
        to request: AIRequest,
        fallbackPolicy: AIFallbackPolicy = .enabled
    ) async throws -> AIResponse {
        let providers = await registry.allProviders()
        var candidates = await router.candidates(
            from: providers,
            requiredCapabilities: request.requiredCapabilities,
            preference: request.executionPreference
        )

        if !fallbackPolicy.allowsFallback {
            candidates = Array(candidates.prefix(1))
        } else if let limit = fallbackPolicy.maximumProviderAttempts {
            candidates = Array(candidates.prefix(max(0, limit)))
        }

        guard !candidates.isEmpty else {
            throw AIError.exhaustedProviders
        }

        var lastError: Error?
        for provider in candidates {
            do {
                return try await provider.generate(request)
            } catch is CancellationError {
                throw AIError.cancelled
            } catch {
                lastError = error
            }
        }

        if let error = lastError {
            throw error
        }
        throw AIError.exhaustedProviders
    }

    public func stream(
        _ request: AIRequest,
        fallbackPolicy: AIFallbackPolicy = .enabled
    ) async throws -> AIResponseStream {
        let providers = await registry.allProviders()
        var candidates = await router.candidates(
            from: providers,
            requiredCapabilities: request.requiredCapabilities,
            preference: request.executionPreference
        )

        if !fallbackPolicy.allowsFallback {
            candidates = Array(candidates.prefix(1))
        } else if let limit = fallbackPolicy.maximumProviderAttempts {
            candidates = Array(candidates.prefix(max(0, limit)))
        }

        guard let provider = candidates.first else {
            throw AIError.exhaustedProviders
        }
        return provider.stream(request)
    }
}
