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
public func AICKCoreAIIsAvailableExport() -> Int32 {
    1
}

@_cdecl("AICKCoreAIGenerate")
public func AICKCoreAIGenerateExport(
    _ requestJSON: UnsafePointer<CChar>?,
    _ modelPath: UnsafePointer<CChar>?,
    _ context: UnsafeMutableRawPointer?,
    _ completion: AICKCoreAIGenerateCompletion
) {
    guard let requestJSON, let modelPath else {
        completion(context, nil, RuntimeStatus.invalidRequest.rawValue)
        return
    }

    let requestString = String(cString: requestJSON)
    let modelPathString = String(cString: modelPath)
    let callback = RuntimeCallback(
        context: context,
        completion: completion
    )

    Task {
        do {
            guard let requestData = requestString.data(using: .utf8) else {
                throw RuntimeFailure.invalidRequest
            }

            let request = try JSONDecoder().decode(
                RuntimeRequest.self,
                from: requestData
            )

            let response = try await CoreAIRuntime.shared.generate(
                request: request,
                modelPath: modelPathString
            )

            let responseData = try JSONEncoder().encode(response)
            let responseString = String(decoding: responseData, as: UTF8.self)

            callback.complete(
                json: responseString,
                status: .success
            )
        } catch let failure as RuntimeFailure {
            callback.complete(json: nil, status: failure.status)
        } catch is CancellationError {
            callback.complete(json: nil, status: .cancelled)
        } catch {
            callback.complete(json: nil, status: .generationFailed)
        }
    }
}

@_cdecl("AICKCoreAIPrepare")
public func AICKCoreAIPrepareExport(
    _ modelPath: UnsafePointer<CChar>?,
    _ context: UnsafeMutableRawPointer?,
    _ completion: AICKCoreAIStatusCompletion
) {
    guard let modelPath else {
        completion(context, RuntimeStatus.invalidRequest.rawValue)
        return
    }

    let modelPathString = String(cString: modelPath)
    let callback = RuntimeStatusCallback(
        context: context,
        completion: completion
    )

    Task {
        do {
            try await CoreAIRuntime.shared.prepare(modelPath: modelPathString)
            callback.complete(status: .success)
        } catch let failure as RuntimeFailure {
            callback.complete(status: failure.status)
        } catch is CancellationError {
            callback.complete(status: .cancelled)
        } catch {
            callback.complete(status: .modelLoadFailed)
        }
    }
}

@_cdecl("AICKCoreAIUnload")
public func AICKCoreAIUnloadExport(
    _ modelPath: UnsafePointer<CChar>?,
    _ context: UnsafeMutableRawPointer?,
    _ completion: AICKCoreAIStatusCompletion
) {
    guard let modelPath else {
        completion(context, RuntimeStatus.invalidRequest.rawValue)
        return
    }

    let modelPathString = String(cString: modelPath)
    let callback = RuntimeStatusCallback(
        context: context,
        completion: completion
    )

    Task {
        await CoreAIRuntime.shared.unload(modelPath: modelPathString)
        callback.complete(status: .success)
    }
}

private actor CoreAIRuntime {
    static let shared = CoreAIRuntime()

    private var cachedModel: CoreAILanguageModel?
    private var cachedModelPath: String?

    func prepare(modelPath: String) async throws {
        let model = try await model(at: modelPath)

        do {
            try await model.load()
        } catch is CancellationError {
            throw RuntimeFailure.cancelled
        } catch {
            throw RuntimeFailure.modelLoadFailed
        }
    }

    func unload(modelPath: String) {
        guard cachedModelPath == modelPath else {
            return
        }

        cachedModel?.unload()
        cachedModel = nil
        cachedModelPath = nil
    }

    func generate(
        request: RuntimeRequest,
        modelPath: String
    ) async throws -> RuntimeResponse {
        let model = try await model(at: modelPath)

        let systemInstructions = request.messages
            .filter { $0.role == "system" }
            .map(\.content)
            .joined(separator: "\n\n")

        let session = LanguageModelSession(
            model: model,
            instructions: systemInstructions.isEmpty
                ? "Respond accurately and concisely."
                : systemInstructions
        )

        let prompt = request.messages
            .filter { $0.role != "system" }
            .map { message in
                let label: String
                switch message.role {
                case "assistant":
                    label = "Assistant"
                case "tool":
                    label = "Tool"
                default:
                    label = "User"
                }
                return "\(label): \(message.content)"
            }
            .joined(separator: "\n\n")

        do {
            let response = try await session.respond(
                to: prompt.isEmpty ? "User: Hello" : prompt,
                options: GenerationOptions(
                    temperature: request.temperature.map {
                        min(max($0, 0), 1)
                    },
                    maximumResponseTokens: request.maxOutputTokens
                )
            )

            return RuntimeResponse(
                text: response.content,
                finishReason: "completed",
                inputTokens: nil,
                outputTokens: nil
            )
        } catch is CancellationError {
            throw RuntimeFailure.cancelled
        } catch {
            throw RuntimeFailure.generationFailed
        }
    }

    private func model(at path: String) async throws -> CoreAILanguageModel {
        if cachedModelPath == path, let cachedModel {
            return cachedModel
        }

        if let cachedModel {
            cachedModel.unload()
            self.cachedModel = nil
            cachedModelPath = nil
        }

        do {
            let model = try await CoreAILanguageModel(
                resourcesAt: URL(fileURLWithPath: path, isDirectory: true)
            )
            cachedModel = model
            cachedModelPath = path
            return model
        } catch {
            throw RuntimeFailure.modelLoadFailed
        }
    }
}

private struct RuntimeRequest: Decodable, Sendable {
    let messages: [RuntimeMessage]
    let maxOutputTokens: Int?
    let temperature: Double?
    let metadata: [String: String]
}

private struct RuntimeMessage: Decodable, Sendable {
    let role: String
    let content: String
    let name: String?
}

private struct RuntimeResponse: Encodable, Sendable {
    let text: String
    let finishReason: String?
    let inputTokens: Int?
    let outputTokens: Int?
}

private struct RuntimeCallback: @unchecked Sendable {
    let context: UnsafeMutableRawPointer?
    let completion: AICKCoreAIGenerateCompletion

    func complete(
        json: String?,
        status: RuntimeStatus
    ) {
        guard let json else {
            completion(context, nil, status.rawValue)
            return
        }

        json.withCString {
            completion(context, $0, status.rawValue)
        }
    }
}

private struct RuntimeStatusCallback: @unchecked Sendable {
    let context: UnsafeMutableRawPointer?
    let completion: AICKCoreAIStatusCompletion

    func complete(status: RuntimeStatus) {
        completion(context, status.rawValue)
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
