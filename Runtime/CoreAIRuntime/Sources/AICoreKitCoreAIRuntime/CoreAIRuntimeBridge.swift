import CoreAILanguageModels
import Foundation
import FoundationModels

public typealias AICKCoreAIGenerateCompletion =
    @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        Int32
    ) -> Void

public typealias AICKCoreAIStatusCompletion =
    @convention(c) (
        UnsafeMutableRawPointer?,
        Int32
    ) -> Void

@_cdecl("AICKCoreAIIsAvailable")
public func AICKCoreAIIsAvailableExport()
    -> Int32
{
    1
}

@_cdecl("AICKCoreAIIsPrepared")
public func AICKCoreAIIsPreparedExport(
    _ modelPath: UnsafePointer<CChar>?
) -> Int32 {
    guard let modelPath else {
        return 0
    }

    return coreAIModelIsPrepared(
        at: String(cString: modelPath)
    )
    ? 1
    : 0
}

@_cdecl("AICKCoreAIGenerate")
public func AICKCoreAIGenerateExport(
    _ requestJSON:
        UnsafePointer<CChar>?,
    _ modelPath:
        UnsafePointer<CChar>?,
    _ context:
        UnsafeMutableRawPointer?,
    _ completion:
        AICKCoreAIGenerateCompletion
) {
    guard
        let requestJSON,
        let modelPath
    else {
        completion(
            context,
            nil,
            RuntimeStatus
                .invalidRequest
                .rawValue
        )
        return
    }

    let requestString =
        String(cString: requestJSON)
    let modelPathString =
        String(cString: modelPath)
    let callback =
        RuntimeCallback(
            context: context,
            completion: completion
        )

    Task {
        do {
            guard
                let requestData =
                    requestString.data(
                        using: .utf8
                    )
            else {
                throw RuntimeFailure
                    .invalidRequest
            }

            let request =
                try JSONDecoder()
                .decode(
                    RuntimeRequest.self,
                    from: requestData
                )

            let response =
                try await CoreAIRuntime
                .shared
                .generate(
                    request: request,
                    modelPath:
                        modelPathString
                )

            let responseData =
                try JSONEncoder()
                .encode(response)
            let responseString =
                String(
                    decoding:
                        responseData,
                    as: UTF8.self
                )

            callback.complete(
                json: responseString,
                status: .success
            )
        } catch let failure as
            RuntimeFailure {
            callback.complete(
                json: nil,
                status:
                    failure.status
            )
        } catch is CancellationError {
            callback.complete(
                json: nil,
                status: .cancelled
            )
        } catch {
            callback.complete(
                json: nil,
                status:
                    .generationFailed
            )
        }
    }
}

@_cdecl("AICKCoreAIPrepare")
public func AICKCoreAIPrepareExport(
    _ modelPath:
        UnsafePointer<CChar>?,
    _ context:
        UnsafeMutableRawPointer?,
    _ completion:
        AICKCoreAIStatusCompletion
) {
    runLifecycleOperation(
        modelPath,
        context: context,
        completion: completion
    ) {
        try await CoreAIRuntime
            .shared
            .prepare(
                modelPath: $0
            )
    }
}

@_cdecl("AICKCoreAILoad")
public func AICKCoreAILoadExport(
    _ modelPath:
        UnsafePointer<CChar>?,
    _ context:
        UnsafeMutableRawPointer?,
    _ completion:
        AICKCoreAIStatusCompletion
) {
    runLifecycleOperation(
        modelPath,
        context: context,
        completion: completion
    ) {
        try await CoreAIRuntime
            .shared
            .load(
                modelPath: $0
            )
    }
}

@_cdecl("AICKCoreAIUnload")
public func AICKCoreAIUnloadExport(
    _ modelPath:
        UnsafePointer<CChar>?,
    _ context:
        UnsafeMutableRawPointer?,
    _ completion:
        AICKCoreAIStatusCompletion
) {
    runLifecycleOperation(
        modelPath,
        context: context,
        completion: completion
    ) {
        await CoreAIRuntime
            .shared
            .unload(
                modelPath: $0
            )
    }
}

@_cdecl("AICKCoreAIClearPreparationCache")
public func AICKCoreAIClearPreparationCacheExport(
    _ modelPath:
        UnsafePointer<CChar>?,
    _ context:
        UnsafeMutableRawPointer?,
    _ completion:
        AICKCoreAIStatusCompletion
) {
    runLifecycleOperation(
        modelPath,
        context: context,
        completion: completion
    ) {
        try await CoreAIRuntime
            .shared
            .clearPreparationCache(
                modelPath: $0
            )
    }
}

private func runLifecycleOperation(
    _ modelPath:
        UnsafePointer<CChar>?,
    context:
        UnsafeMutableRawPointer?,
    completion:
        @escaping AICKCoreAIStatusCompletion,
    operation:
        @escaping @Sendable (
            String
        ) async throws -> Void
) {
    guard let modelPath else {
        completion(
            context,
            RuntimeStatus
                .invalidRequest
                .rawValue
        )
        return
    }

    let modelPathString =
        String(cString: modelPath)
    let callback =
        RuntimeStatusCallback(
            context: context,
            completion: completion
        )

    Task {
        do {
            try await operation(
                modelPathString
            )
            callback.complete(
                status: .success
            )
        } catch let failure as
            RuntimeFailure {
            callback.complete(
                status:
                    failure.status
            )
        } catch is CancellationError {
            callback.complete(
                status: .cancelled
            )
        } catch {
            callback.complete(
                status:
                    .modelLoadFailed
            )
        }
    }
}

private actor CoreAIRuntime {
    static let shared =
        CoreAIRuntime()

    private var cachedModel:
        CoreAILanguageModel?
    private var cachedModelPath:
        String?

    private var modelLoadTask:
        Task<
            CoreAILanguageModel,
            Error
        >?
    private var modelLoadPath:
        String?

    private var preparationTask:
        Task<Void, Error>?
    private var preparationPath:
        String?

    func prepare(
        modelPath: String
    ) async throws {
        if coreAIModelIsPrepared(
            at: modelPath
        ) {
            return
        }

        let task =
            preparationTaskForPath(
                modelPath
            )

        do {
            try await task.value
            clearPreparationTask(
                for: modelPath
            )
        } catch is CancellationError {
            clearPreparationTask(
                for: modelPath
            )
            throw RuntimeFailure
                .cancelled
        } catch {
            clearPreparationTask(
                for: modelPath
            )
            throw RuntimeFailure
                .modelLoadFailed
        }
    }

    func load(
        modelPath: String
    ) async throws {
        if
            cachedModelPath == modelPath,
            cachedModel != nil
        {
            return
        }

        guard coreAIModelIsPrepared(
            at: modelPath
        ) else {
            throw RuntimeFailure
                .modelLoadFailed
        }

        let task =
            modelLoadTaskForPath(
                modelPath
            )

        do {
            let model =
                try await task.value

            cacheLoadedModel(
                model,
                for: modelPath
            )
        } catch is CancellationError {
            clearFailedLoadTask(
                for: modelPath
            )
            throw RuntimeFailure
                .cancelled
        } catch {
            clearFailedLoadTask(
                for: modelPath
            )
            throw RuntimeFailure
                .modelLoadFailed
        }
    }

    func unload(
        modelPath: String
    ) {
        guard
            cachedModelPath == modelPath
            || modelLoadPath == modelPath
            || preparationPath == modelPath
        else {
            return
        }

        let cached = cachedModel
        let pendingLoad =
            modelLoadTask

        cachedModel = nil
        cachedModelPath = nil

        modelLoadTask?.cancel()
        modelLoadTask = nil
        modelLoadPath = nil

        preparationTask?.cancel()
        preparationTask = nil
        preparationPath = nil

        cached?.unload()

        if let pendingLoad {
            Task {
                if
                    let loadedModel =
                        try? await
                            pendingLoad.value
                {
                    loadedModel.unload()
                }
            }
        }
    }

    func clearPreparationCache(
        modelPath: String
    ) async throws {
        unload(
            modelPath: modelPath
        )

        do {
            _ = try PreparedModel
                .clearCache(
                    at:
                        URL(
                            fileURLWithPath:
                                modelPath,
                            isDirectory:
                                true
                        )
                )
        } catch {
            throw RuntimeFailure
                .modelLoadFailed
        }
    }

    func generate(
        request: RuntimeRequest,
        modelPath: String
    ) async throws
        -> RuntimeResponse
    {
        if !coreAIModelIsPrepared(
            at: modelPath
        ) {
            try await prepare(
                modelPath: modelPath
            )
        }

        try await load(
            modelPath: modelPath
        )

        guard
            cachedModelPath == modelPath,
            let model = cachedModel
        else {
            throw RuntimeFailure
                .modelLoadFailed
        }

        let systemInstructions =
            request.messages
            .filter {
                $0.role == "system"
            }
            .map(\.content)
            .joined(
                separator: "\n\n"
            )

        let session =
            LanguageModelSession(
                model: model,
                instructions:
                    systemInstructions
                    .isEmpty
                    ? "Respond accurately and concisely."
                    : systemInstructions
            )

        let prompt =
            request.messages
            .filter {
                $0.role != "system"
            }
            .map {
                message in

                let label: String
                switch message.role {
                case "assistant":
                    label =
                        "Assistant"
                case "tool":
                    label = "Tool"
                default:
                    label = "User"
                }

                return
                    "\(label): "
                    + message.content
            }
            .joined(
                separator: "\n\n"
            )

        do {
            let response =
                try await session.respond(
                    to:
                        prompt.isEmpty
                        ? "User: Hello"
                        : prompt,
                    options:
                        GenerationOptions(
                            temperature:
                                request
                                .temperature
                                .map {
                                    min(
                                        max(
                                            $0,
                                            0
                                        ),
                                        1
                                    )
                                },
                            maximumResponseTokens:
                                request
                                .maxOutputTokens
                        )
                )

            return RuntimeResponse(
                text:
                    response.content,
                finishReason:
                    "completed",
                inputTokens: nil,
                outputTokens: nil
            )
        } catch is CancellationError {
            throw RuntimeFailure
                .cancelled
        } catch {
            throw RuntimeFailure
                .generationFailed
        }
    }

    private func preparationTaskForPath(
        _ path: String
    ) -> Task<Void, Error> {
        if
            preparationPath == path,
            let preparationTask
        {
            return preparationTask
        }

        let task = Task {
            let url =
                URL(
                    fileURLWithPath:
                        path,
                    isDirectory: true
                )

            let assets =
                try PreparedModel
                .modelAssetURLs(
                    at: url
                )

            guard !assets.isEmpty else {
                throw RuntimeFailure
                    .modelLoadFailed
            }

            for asset in assets {
                try Task
                    .checkCancellation()
                _ = try await
                    PreparedModel
                    .prepare(
                        at: asset
                    )
            }
        }

        preparationPath = path
        preparationTask = task
        return task
    }

    private func modelLoadTaskForPath(
        _ path: String
    ) -> Task<
        CoreAILanguageModel,
        Error
    > {
        if
            modelLoadPath == path,
            let modelLoadTask
        {
            return modelLoadTask
        }

        let url =
            URL(
                fileURLWithPath:
                    path,
                isDirectory: true
            )

        let task = Task {
            try Task
                .checkCancellation()

            return try await
                CoreAILanguageModel(
                    resourcesAt: url,
                    mode: .eager
                )
        }

        modelLoadPath = path
        modelLoadTask = task
        return task
    }

    private func cacheLoadedModel(
        _ model:
            CoreAILanguageModel,
        for path: String
    ) {
        cachedModelPath = path
        cachedModel = model

        guard modelLoadPath == path else {
            return
        }

        modelLoadPath = nil
        modelLoadTask = nil
    }

    private func clearFailedLoadTask(
        for path: String
    ) {
        guard modelLoadPath == path else {
            return
        }

        modelLoadPath = nil
        modelLoadTask = nil
    }

    private func clearPreparationTask(
        for path: String
    ) {
        guard
            preparationPath == path
        else {
            return
        }

        preparationPath = nil
        preparationTask = nil
    }
}

private func coreAIModelIsPrepared(
    at path: String
) -> Bool {
    let url =
        URL(
            fileURLWithPath: path,
            isDirectory: true
        )

    do {
        let assets =
            try PreparedModel
            .modelAssetURLs(
                at: url
            )

        guard !assets.isEmpty else {
            return false
        }

        return assets.allSatisfy {
            PreparedModel.isCached(
                at: $0
            )
        }
    } catch {
        return false
    }
}

private struct RuntimeRequest:
    Decodable,
    Sendable
{
    let messages:
        [RuntimeMessage]
    let maxOutputTokens:
        Int?
    let temperature:
        Double?
    let metadata:
        [String: String]
}

private struct RuntimeMessage:
    Decodable,
    Sendable
{
    let role: String
    let content: String
    let name: String?
}

private struct RuntimeResponse:
    Encodable,
    Sendable
{
    let text: String
    let finishReason: String?
    let inputTokens: Int?
    let outputTokens: Int?
}

private struct RuntimeCallback:
    @unchecked Sendable
{
    let context:
        UnsafeMutableRawPointer?
    let completion:
        AICKCoreAIGenerateCompletion

    func complete(
        json: String?,
        status: RuntimeStatus
    ) {
        guard let json else {
            completion(
                context,
                nil,
                status.rawValue
            )
            return
        }

        json.withCString {
            completion(
                context,
                $0,
                status.rawValue
            )
        }
    }
}

private struct RuntimeStatusCallback:
    @unchecked Sendable
{
    let context:
        UnsafeMutableRawPointer?
    let completion:
        AICKCoreAIStatusCompletion

    func complete(
        status: RuntimeStatus
    ) {
        completion(
            context,
            status.rawValue
        )
    }
}

private enum RuntimeStatus: Int32 {
    case success = 0
    case invalidRequest = 1
    case modelLoadFailed = 2
    case generationFailed = 3
    case serializationFailed = 4
    case cancelled = 5
    case unavailable = 6
}

private enum RuntimeFailure: Error {
    case invalidRequest
    case modelLoadFailed
    case generationFailed
    case serializationFailed
    case cancelled

    var status: RuntimeStatus {
        switch self {
        case .invalidRequest:
            return .invalidRequest
        case .modelLoadFailed:
            return .modelLoadFailed
        case .generationFailed:
            return .generationFailed
        case .serializationFailed:
            return .serializationFailed
        case .cancelled:
            return .cancelled
        }
    }
}
