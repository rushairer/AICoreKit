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
            state = .unavailable
            return state
        }

        guard
            let resource =
                try? await resourceProvider.modelResource(),
            resource.exists
        else {
            state = .missingModel
            return state
        }

        state =
            await bridge.isPrepared(
                modelPath: resource.path
            )
            ? .prepared
            : .notPrepared

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
            state = .prepared
            return
        }

        generation &+= 1
        let operationGeneration = generation
        state = .preparing

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
            state = .prepared
        } catch {
            state = .failed
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
            state = .notPrepared
            throw AIError.unavailable(
                .modelNotReady
            )
        }

        generation &+= 1
        let operationGeneration = generation
        state = .loading

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
            state = .ready
        } catch {
            state = .failed
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
            state = .notPrepared
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
            state = .missingModel
            return
        }

        let initialStatus =
            await bridge.unload(
                modelPath: resource.path
            )
        try validate(
            initialStatus,
            operation: "unload"
        )

        if let pendingTask {
            _ = try? await pendingTask.value

            let finalStatus =
                await bridge.unload(
                    modelPath: resource.path
                )
            try validate(
                finalStatus,
                operation: "unload"
            )
        }

        state =
            await bridge.isPrepared(
                modelPath: resource.path
            )
            ? .prepared
            : .notPrepared
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
        try validate(
            unloadStatus,
            operation: "unload"
        )

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
            state = .notPrepared
        } catch {
            state = .failed
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
            state = .preparing

            let prepareStatus =
                await bridge.prepare(
                    modelPath: resource.path
                )

            try ensureCurrent(
                expectedGeneration
            )

            try validate(
                prepareStatus,
                operation: "prepare"
            )
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

        state = .loading

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
            state = .ready
        } catch {
            state = .failed
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

    private func requiredResource()
        async throws -> CoreAIModelResource
    {
        guard
            await bridge.availability() == .available
        else {
            state = .unavailable
            throw AIError.unavailable(
                .frameworkUnavailable
            )
        }

        guard
            let resource =
                try await resourceProvider.modelResource(),
            resource.exists
        else {
            state = .missingModel
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
