public import AICore

public struct AIRouter: Sendable {
    public init() {}

    public func candidates(
        from providers: [any AIProvider],
        requiredCapabilities: AICapabilities,
        preference: AIExecutionPreference
    ) async -> [any AIProvider] {
        var available: [any AIProvider] = []

        for provider in providers where provider.capabilities.satisfies(requiredCapabilities) {
            if await provider.availability() == .available {
                available.append(provider)
            }
        }

        let local = available.filter { $0.capabilities.contains(.localExecution) }
        let remote = available.filter { $0.capabilities.contains(.remoteExecution) }
        let uncategorized = available.filter {
            !$0.capabilities.contains(.localExecution) && !$0.capabilities.contains(.remoteExecution)
        }

        switch preference {
        case .localOnly:
            return local
        case .remoteOnly:
            return remote
        case .localFirst:
            return local + remote + uncategorized
        case .remoteFirst:
            return remote + local + uncategorized
        case .automatic:
            let privacyPreferred = local.filter { $0.capabilities.contains(.privacyPreferred) }
            let remainingLocal = local.filter { !$0.capabilities.contains(.privacyPreferred) }
            return privacyPreferred + remainingLocal + remote + uncategorized
        }
    }
}
