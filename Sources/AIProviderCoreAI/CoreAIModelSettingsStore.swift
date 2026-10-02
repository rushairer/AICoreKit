import Combine

@MainActor
public final class CoreAIModelSettingsStore:
    ObservableObject
{
    public let profile:
        CoreAIModelProfile

    @Published
    public private(set) var state:
        CoreAIModelLifecycleState

    private let lifecycleController:
        CoreAIModelLifecycleController

    private var observationTask:
        Task<Void, Never>?

    public init(
        profile:
            CoreAIModelProfile,
        lifecycleController:
            CoreAIModelLifecycleController,
        initialState:
            CoreAIModelLifecycleState =
                .notPrepared
    ) {
        self.profile =
            profile
        self.lifecycleController =
            lifecycleController
        self.state =
            initialState

        observationTask =
            Task { [weak self] in
                let changes =
                    await lifecycleController
                    .stateChanges()

                for await lifecycleState
                    in changes
                {
                    guard
                        !Task.isCancelled,
                        let self
                    else {
                        return
                    }

                    self.state =
                        lifecycleState
                }
            }
    }

    deinit {
        observationTask?
            .cancel()
    }

    @discardableResult
    public func refreshState()
        async -> CoreAIModelLifecycleState
    {
        let refreshed =
            await lifecycleController
            .currentState()

        state =
            refreshed

        return refreshed
    }

    @discardableResult
    public func bootstrapIfPrepared()
        async throws -> Bool
    {
        try await lifecycleController
            .bootstrapIfPrepared()
    }

    public func preparePersistentResources()
        async throws
    {
        try await lifecycleController
            .preparePersistentResources()
    }

    public func loadPreparedResources()
        async throws
    {
        try await lifecycleController
            .loadPreparedResources()
    }

    public func ensureReady()
        async throws
    {
        try await lifecycleController
            .ensureReady()
    }

    public func unload()
        async throws
    {
        try await lifecycleController
            .unload()
    }

    public func clearPreparationCache()
        async throws
    {
        try await lifecycleController
            .clearPreparationCache()
    }
}
