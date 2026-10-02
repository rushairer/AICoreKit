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
    private enum ReadinessRequirement {
        case prepared
        case ready
    }

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
    private var readinessTaskID:
        UInt64?
    private var nextReadinessTaskID:
        UInt64 = 0
    private var generation: UInt64 = 0
    private var resetInProgress = false

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
        try rejectIfResetting()

        if stateSatisfies(.prepared) {
            return
        }

        try await awaitInFlightReadiness(
            until: .prepared
        )

        if stateSatisfies(.prepared) {
            return
        }

        let operationGeneration =
            generation
        let taskID =
            allocateReadinessTaskID()
        let task = Task {
            try await self
                .performPreparePersistent(
                    expectedGeneration:
                        operationGeneration
                )
        }
        readinessTask = task
        readinessTaskID = taskID

        do {
            try await task.value
            clearReadinessTask(
                ifID: taskID
            )
        } catch {
            clearReadinessTask(
                ifID: taskID
            )
            throw error
        }
    }

    public func loadPreparedResources()
        async throws
    {
        try rejectIfResetting()

        if stateSatisfies(.ready) {
            return
        }

        try await awaitInFlightReadiness(
            until: .ready
        )

        if stateSatisfies(.ready) {
            return
        }

        let operationGeneration =
            generation
        let taskID =
            allocateReadinessTaskID()
        let task = Task {
            try await self
                .performLoadPreparedResources(
                    expectedGeneration:
                        operationGeneration
                )
        }
        readinessTask = task
        readinessTaskID = taskID

        do {
            try await task.value
            clearReadinessTask(
                ifID: taskID
            )
        } catch {
            clearReadinessTask(
                ifID: taskID
            )
            throw error
        }
    }

    public func ensureReady() async throws {
        try rejectIfResetting()

        if stateSatisfies(.ready) {
            return
        }

        try await awaitInFlightReadiness(
            until: .ready
        )

        if stateSatisfies(.ready) {
            return
        }

        let operationGeneration =
            generation
        let taskID =
            allocateReadinessTaskID()
        let task = Task {
            try await self.performEnsureReady(
                expectedGeneration:
                    operationGeneration
            )
        }
        readinessTask = task
        readinessTaskID = taskID

        do {
            try await task.value
            clearReadinessTask(
                ifID: taskID
            )
        } catch {
            clearReadinessTask(
                ifID: taskID
            )
            throw error
        }
    }

    @discardableResult
    public func bootstrapIfPrepared()
        async throws -> Bool
    {
        try rejectIfResetting()

        if stateSatisfies(.ready) {
            return true
        }

        try await awaitInFlightReadiness(
            until: .ready
        )

        if stateSatisfies(.ready) {
            return true
        }

        let operationGeneration =
            generation
        let taskID =
            allocateReadinessTaskID()
        let task = Task {
            try await self
                .performBootstrapIfPrepared(
                    expectedGeneration:
                        operationGeneration
                )
        }
        readinessTask = task
        readinessTaskID = taskID

        do {
            try await task.value
            clearReadinessTask(
                ifID: taskID
            )
            return stateSatisfies(
                .ready
            )
        } catch {
            clearReadinessTask(
                ifID: taskID
            )
            throw error
        }
    }

    public func unload() async throws {
        try beginReset()
        defer {
            endReset()
        }

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
        try beginReset()
        defer {
            endReset()
        }

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

    private func performPreparePersistent(
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

        if await bridge.isPrepared(
            modelPath: resource.path
        ) {
            try ensureCurrent(
                expectedGeneration
            )
            transition(to: .prepared)
            return
        }

        transition(to: .preparing)

        let status =
            await bridge.prepare(
                modelPath: resource.path
            )

        try ensureCurrent(
            expectedGeneration
        )

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

    private func performLoadPreparedResources(
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

        guard await bridge.isPrepared(
            modelPath: resource.path
        ) else {
            try ensureCurrent(
                expectedGeneration
            )
            transition(to: .notPrepared)
            throw AIError.unavailable(
                .modelNotReady
            )
        }

        try ensureCurrent(
            expectedGeneration
        )

        try await performLoadPrepared(
            resource: resource,
            expectedGeneration:
                expectedGeneration
        )
    }

    private func performBootstrapIfPrepared(
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

        guard await bridge.isPrepared(
            modelPath: resource.path
        ) else {
            try ensureCurrent(
                expectedGeneration
            )
            transition(to: .notPrepared)
            return
        }

        try ensureCurrent(
            expectedGeneration
        )

        try await performLoadPrepared(
            resource: resource,
            expectedGeneration:
                expectedGeneration
        )
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

    private func rejectIfResetting()
        throws
    {
        guard !resetInProgress else {
            throw AIError.cancelled
        }
    }

    private func beginReset()
        throws
    {
        guard !resetInProgress else {
            throw AIError.cancelled
        }

        resetInProgress = true
    }

    private func endReset() {
        resetInProgress = false
    }

    private func stateSatisfies(
        _ requirement:
            ReadinessRequirement
    ) -> Bool {
        switch requirement {
        case .prepared:
            return
                state == .prepared
                || state == .ready
        case .ready:
            return state == .ready
        }
    }

    private func awaitInFlightReadiness(
        until requirement:
            ReadinessRequirement
    ) async throws {
        while !stateSatisfies(
            requirement
        ) {
            guard
                let task = readinessTask,
                let taskID =
                    readinessTaskID
            else {
                return
            }

            do {
                try await task.value
            } catch {
                clearReadinessTask(
                    ifID: taskID
                )
                throw error
            }

            clearReadinessTask(
                ifID: taskID
            )
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
        readinessTaskID = nil

        return pendingTask
    }

    private func allocateReadinessTaskID()
        -> UInt64
    {
        let taskID =
            nextReadinessTaskID
        nextReadinessTaskID &+= 1
        return taskID
    }

    private func clearReadinessTask(
        ifID taskID: UInt64
    ) {
        guard
            readinessTaskID == taskID
        else {
            return
        }

        readinessTask = nil
        readinessTaskID = nil
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
