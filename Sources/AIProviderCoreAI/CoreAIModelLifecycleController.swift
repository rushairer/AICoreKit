import AICore

public enum CoreAIModelLifecycleState:
    String,
    Sendable,
    Codable,
    Equatable
{
    case unavailable
    case missingModel
    case notPrepared
    case preparing
    case prepared
    case loading
    case ready
    case failed
}

public actor CoreAIModelLifecycleController {
    private let providerID: AIProviderID
    private let bridge: any CoreAIModelLifecycleBridge
    private let resourceProvider:
        any CoreAIModelResourceProviding

    private var state:
        CoreAIModelLifecycleState = .notPrepared
    private var stateObservers:
        [UInt64:
            AsyncStream<
                CoreAIModelLifecycleState
            >.Continuation] = [:]
    private var nextStateObserverID:
        UInt64 = 0

    private var readinessTask:
        Task<Void, Error>?
    private var readinessGeneration:
        UInt64?
    private var generation: UInt64 = 0

    public init(
        providerID: AIProviderID = .coreAI,
        bridge: any CoreAIModelLifecycleBridge,
        resourceProvider:
            any CoreAIModelResourceProviding
    ) {
        self.providerID = providerID
        self.bridge = bridge
        self.resourceProvider = resourceProvider
    }

    public func currentState()
        async -> CoreAIModelLifecycleState
    {
        await refreshState()
    }

    public func stateChanges(
        includeCurrentState: Bool = true
    ) -> AsyncStream<
        CoreAIModelLifecycleState
    > {
        let observerID =
            nextStateObserverID
        nextStateObserverID &+= 1

        let pair =
            AsyncStream<
                CoreAIModelLifecycleState
            >
            .makeStream(
                bufferingPolicy:
                    .bufferingNewest(16)
            )

        stateObservers[observerID] =
            pair.continuation

        if includeCurrentState {
            pair.continuation.yield(
                state
            )
        }

        pair.continuation.onTermination = {
            [weak self] _ in

            Task {
                await self?
                    .removeStateObserver(
                        observerID
                    )
            }
        }

        return pair.stream
    }

    public func isPersistentlyPrepared()
        async -> Bool
    {
        guard
            await bridge.availability() == .available,
            let resource =
                try? await resourceProvider.modelResource(),
            resource.exists
        else {
            return false
        }

        return await bridge.isPrepared(
            modelPath: resource.path
        )
    }

    @discardableResult
    public func refreshState()
        async -> CoreAIModelLifecycleState
    {
        switch state {
        case .preparing,
             .loading,
             .ready:
            return state
        case .unavailable,
             .missingModel,
             .notPrepared,
             .prepared,
             .failed:
            break
        }

        guard
            await bridge.availability() == .available
        else {
            transition(to: .unavailable)
            return state
        }

        guard
            let resource =
                try? await resourceProvider.modelResource(),
            resource.exists
        else {
            transition(to: .missingModel)
            return state
        }

        let refreshedState:
            CoreAIModelLifecycleState =
            await bridge.isPrepared(
                modelPath: resource.path
            )
            ? .prepared
            : .notPrepared
        transition(
            to: refreshedState
        )

        return state
    }

    public func preparePersistentResources()
        async throws
    {
        let resource =
            try await requiredResource()

        if await bridge.isPrepared(
            modelPath: resource.path
        ) {
            transition(to: .prepared)
            return
        }

        generation &+= 1
        let operationGeneration = generation
        transition(to: .preparing)

        let status = await bridge.prepare(
            modelPath: resource.path
        )

        guard operationGeneration == generation else {
            throw AIError.cancelled
        }

        do {
            try validate(
                status,
                operation: "prepare"
            )
            transition(to: .prepared)
        } catch {
            transition(to: .failed)
            throw error
        }
    }

    public func loadPreparedResources()
        async throws
    {
        if state == .ready {
            return
        }

        let resource =
            try await requiredResource()

        guard await bridge.isPrepared(
            modelPath: resource.path
        ) else {
            transition(to: .notPrepared)
            throw AIError.unavailable(
                .modelNotReady
            )
        }

        generation &+= 1
        let operationGeneration = generation
        transition(to: .loading)

        let status = await bridge.load(
            modelPath: resource.path
        )

        guard operationGeneration == generation else {
            throw AIError.cancelled
        }

        do {
            try validate(
                status,
                operation: "load"
            )
            transition(to: .ready)
        } catch {
            transition(to: .failed)
            throw error
        }
    }

    public func ensureReady() async throws {
        if state == .ready {
            return
        }

        if let readinessTask {
            return try await readinessTask.value
        }

        let operationGeneration =
            generation
        let task = Task {
            try await self.performEnsureReady(
                expectedGeneration:
                    operationGeneration
            )
        }
        readinessTask = task
        readinessGeneration =
            operationGeneration

        do {
            try await task.value
            clearReadinessTask(
                ifGeneration:
                    operationGeneration
            )
        } catch {
            clearReadinessTask(
                ifGeneration:
                    operationGeneration
            )
            throw error
        }
    }

    @discardableResult
    public func bootstrapIfPrepared()
        async throws -> Bool
    {
        if state == .ready {
            return true
        }

        if let readinessTask {
            try await readinessTask.value
            return state == .ready
        }

        let resource =
            try await requiredResource()

        guard await bridge.isPrepared(
            modelPath: resource.path
        ) else {
            transition(to: .notPrepared)
            return false
        }

        let operationGeneration =
            generation
        let task = Task {
            try await self.performLoadPrepared(
                resource: resource,
                expectedGeneration:
                    operationGeneration
            )
        }
        readinessTask = task
        readinessGeneration =
            operationGeneration

        do {
            try await task.value
            clearReadinessTask(
                ifGeneration:
                    operationGeneration
            )
            return true
        } catch {
            clearReadinessTask(
                ifGeneration:
                    operationGeneration
            )
            throw error
        }
    }

    public func unload() async throws {
        let pendingTask =
            invalidateReadinessTask()

        guard
            let resource =
                try await resourceProvider.modelResource()
        else {
            transition(to: .missingModel)
            return
        }

        let initialStatus =
            await bridge.unload(
                modelPath: resource.path
            )

        do {
            try validate(
                initialStatus,
                operation: "unload"
            )
        } catch {
            transition(to: .failed)
            throw error
        }

        if let pendingTask {
            _ = try? await pendingTask.value

            let finalStatus =
                await bridge.unload(
                    modelPath: resource.path
                )

            do {
                try validate(
                    finalStatus,
                    operation: "unload"
                )
            } catch {
                transition(to: .failed)
                throw error
            }
        }

        let postUnloadState:
            CoreAIModelLifecycleState =
            await bridge.isPrepared(
                modelPath: resource.path
            )
            ? .prepared
            : .notPrepared
        transition(
            to: postUnloadState
        )
    }

    public func clearPreparationCache()
        async throws
    {
        let pendingTask =
            invalidateReadinessTask()

        let resource =
            try await requiredResource()

        // Ask the runtime to cancel resident or in-flight work first.
        // Some bridges cannot synchronously abort preparation, so wait for
        // the invalidated operation to settle before the final cache clear.
        let unloadStatus =
            await bridge.unload(
                modelPath: resource.path
            )

        do {
            try validate(
                unloadStatus,
                operation: "unload"
            )
        } catch {
            transition(to: .failed)
            throw error
        }

        if let pendingTask {
            _ = try? await pendingTask.value
        }

        let status =
            await bridge.clearPreparationCache(
                modelPath: resource.path
            )

        do {
            try validate(
                status,
                operation:
                    "clear preparation cache"
            )
            transition(to: .notPrepared)
        } catch {
            transition(to: .failed)
            throw error
        }
    }

    private func performEnsureReady(
        expectedGeneration: UInt64
    ) async throws {
        try ensureCurrent(
            expectedGeneration
        )

        let resource =
            try await requiredResource()

        try ensureCurrent(
            expectedGeneration
        )

        let prepared =
            await bridge.isPrepared(
                modelPath: resource.path
            )

        try ensureCurrent(
            expectedGeneration
        )

        if !prepared {
            transition(to: .preparing)

            let prepareStatus =
                await bridge.prepare(
                    modelPath: resource.path
                )

            try ensureCurrent(
                expectedGeneration
            )

            do {
                try validate(
                    prepareStatus,
                    operation: "prepare"
                )
            } catch {
                transition(to: .failed)
                throw error
            }
        }

        try await performLoadPrepared(
            resource: resource,
            expectedGeneration:
                expectedGeneration
        )
    }

    private func performLoadPrepared(
        resource: CoreAIModelResource,
        expectedGeneration: UInt64
    ) async throws {
        try ensureCurrent(
            expectedGeneration
        )

        transition(to: .loading)

        let loadStatus =
            await bridge.load(
                modelPath: resource.path
            )

        try ensureCurrent(
            expectedGeneration
        )

        do {
            try validate(
                loadStatus,
                operation: "load"
            )
            transition(to: .ready)
        } catch {
            transition(to: .failed)
            throw error
        }
    }

    private func ensureCurrent(
        _ expectedGeneration: UInt64
    ) throws {
        guard
            expectedGeneration == generation
        else {
            throw AIError.cancelled
        }

        do {
            try Task.checkCancellation()
        } catch {
            throw AIError.cancelled
        }
    }

    @discardableResult
    private func invalidateReadinessTask()
        -> Task<Void, Error>?
    {
        generation &+= 1

        let pendingTask =
            readinessTask
        readinessTask?.cancel()
        readinessTask = nil
        readinessGeneration = nil

        return pendingTask
    }

    private func clearReadinessTask(
        ifGeneration operationGeneration:
            UInt64
    ) {
        guard
            readinessGeneration
                == operationGeneration
        else {
            return
        }

        readinessTask = nil
        readinessGeneration = nil
    }

    private func transition(
        to newState:
            CoreAIModelLifecycleState
    ) {
        guard state != newState else {
            return
        }

        state = newState

        for continuation
            in stateObservers.values
        {
            continuation.yield(
                newState
            )
        }
    }

    private func removeStateObserver(
        _ observerID: UInt64
    ) {
        stateObservers.removeValue(
            forKey: observerID
        )
    }

    private func requiredResource()
        async throws -> CoreAIModelResource
    {
        guard
            await bridge.availability() == .available
        else {
            transition(to: .unavailable)
            throw AIError.unavailable(
                .frameworkUnavailable
            )
        }

        guard
            let resource =
                try await resourceProvider.modelResource(),
            resource.exists
        else {
            transition(to: .missingModel)
            throw AIError.unavailable(
                .modelMissing
            )
        }

        return resource
    }

    private func validate(
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
                providerID: providerID,
                message:
                    "Core AI \(operation) failed"
            )
        case .serializationFailed:
            throw AIError.decodingFailure(
                "Core AI bridge failed during \(operation)"
            )
        case .cancelled:
            throw AIError.cancelled
        case .unavailable:
            throw AIError.unavailable(
                .frameworkUnavailable
            )
        case .unknown:
            throw AIError.providerFailure(
                providerID: providerID,
                message:
                    "Unknown Core AI \(operation) failure"
            )
        }
    }
}
