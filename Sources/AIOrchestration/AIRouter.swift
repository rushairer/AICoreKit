public import AICore

struct AIRouterResolution: Sendable {
    let candidates: [any AIProvider]
    let firstUnavailableReason: AIUnavailabilityReason?
}

public struct AIRouter: Sendable {
    public init() {}

    public func candidates(
        from providers: [any AIProvider],
        requiredCapabilities: AICapabilities,
        preference: AIExecutionPreference
    ) async -> [any AIProvider] {
        await resolve(
            from: providers,
            requiredCapabilities: requiredCapabilities,
            preference: preference
        )
        .candidates
    }

    func resolve(
        from providers: [any AIProvider],
        requiredCapabilities: AICapabilities,
        preference: AIExecutionPreference
    ) async -> AIRouterResolution {
        var states: [ProviderState] = []

        for provider in providers
        where provider.capabilities.satisfies(
            requiredCapabilities
        ) {
            states.append(
                ProviderState(
                    provider: provider,
                    availability:
                        await provider.availability()
                )
            )
        }

        let ordered = orderedStates(
            states,
            preference: preference
        )

        let candidates =
            ordered.compactMap {
                state -> (any AIProvider)? in

                guard
                    state.availability == .available
                else {
                    return nil
                }

                return state.provider
            }

        let firstUnavailableReason =
            ordered.compactMap {
                state -> AIUnavailabilityReason? in

                guard
                    case .unavailable(
                        let reason
                    ) = state.availability
                else {
                    return nil
                }

                return reason
            }
            .first

        return AIRouterResolution(
            candidates: candidates,
            firstUnavailableReason:
                firstUnavailableReason
        )
    }

    private func orderedStates(
        _ states: [ProviderState],
        preference: AIExecutionPreference
    ) -> [ProviderState] {
        let local = states.filter {
            $0.provider.capabilities
                .contains(.localExecution)
        }
        let remote = states.filter {
            $0.provider.capabilities
                .contains(.remoteExecution)
        }
        let uncategorized = states.filter {
            !$0.provider.capabilities
                .contains(.localExecution)
            && !$0.provider.capabilities
                .contains(.remoteExecution)
        }

        switch preference {
        case .localOnly:
            return local
        case .remoteOnly:
            return remote
        case .localFirst:
            return local
                + remote
                + uncategorized
        case .remoteFirst:
            return remote
                + local
                + uncategorized
        case .automatic:
            let privacyPreferred =
                local.filter {
                    $0.provider.capabilities
                        .contains(.privacyPreferred)
                }
            let remainingLocal =
                local.filter {
                    !$0.provider.capabilities
                        .contains(.privacyPreferred)
                }

            return privacyPreferred
                + remainingLocal
                + remote
                + uncategorized
        }
    }
}

private struct ProviderState: Sendable {
    let provider: any AIProvider
    let availability: AIAvailability
}
