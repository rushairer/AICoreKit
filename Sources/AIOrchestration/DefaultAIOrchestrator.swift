public import AICore
public import AITools

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
        let resolution = await router.resolve(
            from: providers,
            requiredCapabilities: request.requiredCapabilities,
            preference: request.executionPreference
        )
        var candidates = resolution.candidates

        if !fallbackPolicy.allowsFallback {
            candidates = Array(candidates.prefix(1))
        } else if let limit = fallbackPolicy.maximumProviderAttempts {
            candidates = Array(candidates.prefix(max(0, limit)))
        }

        guard !candidates.isEmpty else {
            if let reason = resolution.firstUnavailableReason {
                throw AIError.unavailable(reason)
            }
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

    public func respondWithTools(
        to request: AIRequest,
        toolRegistry: AIToolRegistry,
        executionPolicy: any AIToolExecutionPolicy =
            ReadOnlyAIToolExecutionPolicy(),
        confirmationProvider:
            (any AIToolConfirmationProviding)? = nil,
        configuration: AIToolLoopConfiguration =
            AIToolLoopConfiguration(),
        fallbackPolicy: AIFallbackPolicy = .enabled
    ) async throws -> AIResponse {
        let providers = await registry.allProviders()

        var requiredCapabilities =
            request.requiredCapabilities
        if !request.tools.isEmpty {
            requiredCapabilities.insert(.toolCalling)
        }

        let resolution = await router.resolve(
            from: providers,
            requiredCapabilities: requiredCapabilities,
            preference: request.executionPreference
        )
        var candidates = resolution.candidates

        if !fallbackPolicy.allowsFallback {
            candidates = Array(candidates.prefix(1))
        } else if let limit =
            fallbackPolicy.maximumProviderAttempts
        {
            candidates = Array(
                candidates.prefix(max(0, limit))
            )
        }

        guard !candidates.isEmpty else {
            throw AIError.exhaustedProviders
        }

        var selectedProvider: (any AIProvider)?
        var response: AIResponse?
        var lastError: Error?

        for provider in candidates {
            do {
                response = try await provider.generate(
                    request
                )
                selectedProvider = provider
                break
            } catch is CancellationError {
                throw AIError.cancelled
            } catch {
                lastError = error
            }
        }

        guard
            let provider = selectedProvider,
            var currentResponse = response
        else {
            if let lastError {
                throw lastError
            }
            throw AIError.exhaustedProviders
        }

        var round = 0

        while !currentResponse.toolCalls.isEmpty {
            guard round < configuration.maximumRounds else {
                throw AIError.toolExecutionFailed(
                    "Tool loop exceeded the maximum of "
                    + String(configuration.maximumRounds)
                    + " rounds"
                )
            }

            guard
                let continuingProvider =
                    provider as? any AIToolContinuingProvider
            else {
                throw AIError.providerFailure(
                    providerID: provider.id,
                    message:
                        "Provider returned tool calls but does not support continuation"
                )
            }

            guard
                let continuation =
                    currentResponse.continuation
            else {
                throw AIError.providerFailure(
                    providerID: provider.id,
                    message:
                        "Provider returned tool calls without continuation state"
                )
            }

            guard continuation.providerID == provider.id else {
                throw AIError.providerFailure(
                    providerID: provider.id,
                    message:
                        "Tool continuation belongs to a different provider"
                )
            }

            let outputs = try await toolRegistry.execute(
                currentResponse.toolCalls,
                policy: executionPolicy,
                confirmationProvider:
                    confirmationProvider
            )

            currentResponse =
                try await continuingProvider
                    .continueToolCalls(
                        continuation,
                        outputs: outputs
                    )

            round += 1
        }

        return currentResponse
    }

    public func stream(
        _ request: AIRequest,
        fallbackPolicy: AIFallbackPolicy = .enabled
    ) async throws -> AIResponseStream {
        let providers = await registry.allProviders()
        let resolution = await router.resolve(
            from: providers,
            requiredCapabilities: request.requiredCapabilities,
            preference: request.executionPreference
        )
        var candidates = resolution.candidates

        if !fallbackPolicy.allowsFallback {
            candidates = Array(candidates.prefix(1))
        } else if let limit = fallbackPolicy.maximumProviderAttempts {
            candidates = Array(candidates.prefix(max(0, limit)))
        }

        guard let provider = candidates.first else {
            if let reason = resolution.firstUnavailableReason {
                throw AIError.unavailable(reason)
            }
            throw AIError.exhaustedProviders
        }
        return provider.stream(request)
    }
}
