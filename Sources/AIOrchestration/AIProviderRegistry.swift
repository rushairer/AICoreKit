public import AICore

public actor AIProviderRegistry {
    private var providersByID: [AIProviderID: any AIProvider] = [:]
    private var registrationOrder: [AIProviderID] = []

    public init(providers: [any AIProvider] = []) {
        for provider in providers {
            providersByID[provider.id] = provider
            registrationOrder.append(provider.id)
        }
    }

    public func register(_ provider: any AIProvider) {
        if providersByID[provider.id] == nil {
            registrationOrder.append(provider.id)
        }
        providersByID[provider.id] = provider
    }

    public func unregister(_ id: AIProviderID) {
        providersByID[id] = nil
        registrationOrder.removeAll { $0 == id }
    }

    public func provider(id: AIProviderID) -> (any AIProvider)? {
        providersByID[id]
    }

    public func allProviders() -> [any AIProvider] {
        registrationOrder.compactMap { providersByID[$0] }
    }
}
