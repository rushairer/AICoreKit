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

        let task = Task {
            try await self.performEnsureReady()
        }
        readinessTask = task

        do {
            try await task.value
            if readinessTask != nil {
                readinessTask = nil
            }
        } catch {
            if readinessTask != nil {
                readinessTask = nil
            }
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

        let task = Task {
            try await self.performLoadPrepared(
                resource: resource
            )
        }
        readinessTask = task

        do {
            try await task.value
            readinessTask = nil
            return true
        } catch {
            readinessTask = nil
            throw error
        }
    }

    public func unload() async throws {
        generation &+= 1
        readinessTask?.cancel()
        readinessTask = nil

        guard
            let resource =
                try await resourceProvider.modelResource()
        else {
            state = .missingModel
            return
        }

        let status = await bridge.unload(
            modelPath: resource.path
        )
        try validate(
            status,
            operation: "unload"
        )

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
        generation &+= 1
        readinessTask?.cancel()
        readinessTask = nil

        let resource =
            try await requiredResource()

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

    private func performEnsureReady()
        async throws
    {
        let resource =
            try await requiredResource()
        let prepared =
            await bridge.isPrepared(
                modelPath: resource.path
            )

        if !prepared {
            state = .preparing

            let prepareStatus =
                await bridge.prepare(
                    modelPath: resource.path
                )
            try validate(
                prepareStatus,
                operation: "prepare"
            )
        }

        try await performLoadPrepared(
            resource: resource
        )
    }

    private func performLoadPrepared(
        resource: CoreAIModelResource
    ) async throws {
        state = .loading

        let loadStatus =
            await bridge.load(
                modelPath: resource.path
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
