import AICore
import AIHTTP
import Foundation

public struct OpenAICompatibleProvider: AIProvider {
    public let configuration: OpenAICompatibleProviderConfiguration

    private let credentialProvider: any AICredentialProviding
    private let transport: any AIHTTPTransport

    public init(
        configuration: OpenAICompatibleProviderConfiguration,
        credentialProvider: any AICredentialProviding,
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport()
    ) {
        self.configuration = configuration
        self.credentialProvider = credentialProvider
        self.transport = transport
    }

    public var id: AIProviderID {
        configuration.providerID
    }

    public var displayName: String {
        configuration.displayName
    }

    public var capabilities: AICapabilities {
        var capabilities: AICapabilities = [
            .textGeneration,
            .remoteExecution,
            .requiresNetwork
        ]

        if transport is any AIHTTPStreamingTransport {
            capabilities.insert(.streaming)
        }

        return capabilities
    }

    public func availability() async -> AIAvailability {
        guard endpointURL != nil else {
            return .unavailable(.serviceUnavailable)
        }

        do {
            guard
                let credential = try await credentialProvider.credential(
                    for: credentialRequest
                )?.trimmingCharacters(in: .whitespacesAndNewlines),
                !credential.isEmpty
            else {
                return .unavailable(.authenticationMissing)
            }
            return .available
        } catch {
            return .unavailable(.unknown(error.localizedDescription))
        }
    }

    public func generate(_ request: AIRequest) async throws -> AIResponse {
        guard capabilities.satisfies(request.requiredCapabilities) else {
            throw AIError.unsupportedCapability
        }

        guard request.tools.isEmpty else {
            throw AIError.unsupportedCapability
        }

        let urlRequest = try await makeURLRequest(
            for: request,
            stream: false
        )

        let response: AIHTTPResponse
        do {
            response = try await transport.data(for: urlRequest)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.transportFailure(error.localizedDescription)
        }

        try validateHTTPResponse(response)

        let decoded: OpenAICompatibleChatResponse
        do {
            decoded = try JSONDecoder().decode(
                OpenAICompatibleChatResponse.self,
                from: response.data
            )
        } catch {
            throw AIError.decodingFailure(error.localizedDescription)
        }

        guard
            let choice = decoded.choices.first,
            let text = choice.message.content
        else {
            throw AIError.decodingFailure(
                "OpenAI-compatible response did not contain message content"
            )
        }

        return AIResponse(
            text: text,
            providerID: id,
            finishReason: finishReason(from: choice.finishReason),
            usage: usage(from: decoded.usage)
        )
    }

    public func stream(_ request: AIRequest) -> AIResponseStream {
        guard
            let streamingTransport =
                transport as? any AIHTTPStreamingTransport
        else {
            return fallbackStream(request)
        }

        return AIResponseStream { continuation in
            let task = Task {
                do {
                    guard capabilities.satisfies(
                        request.requiredCapabilities
                    ) else {
                        throw AIError.unsupportedCapability
                    }

                    guard request.tools.isEmpty else {
                        throw AIError.unsupportedCapability
                    }

                    let urlRequest = try await makeURLRequest(
                        for: request,
                        stream: true
                    )

                    let response: AIHTTPLineStreamResponse
                    do {
                        response = try await streamingTransport.lines(
                            for: urlRequest
                        )
                    } catch is CancellationError {
                        throw AIError.cancelled
                    } catch {
                        throw AIError.transportFailure(
                            error.localizedDescription
                        )
                    }

                    try validateHTTPStatus(
                        response.statusCode,
                        data: nil
                    )

                    var sseDecoder = AIServerSentEventDecoder()
                    var accumulatedText = ""
                    var finalFinishReason: AIFinishReason = .completed
                    var finalUsage: AIUsage?
                    var reachedDone = false

                    func consumePayload(
                        _ payload: String
                    ) throws -> Bool {
                        let normalized = payload.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                        guard !normalized.isEmpty else {
                            return false
                        }

                        if normalized == "[DONE]" {
                            return true
                        }

                        guard let data = normalized.data(using: .utf8) else {
                            throw AIError.decodingFailure(
                                "OpenAI-compatible SSE payload was not UTF-8"
                            )
                        }

                        let chunk: OpenAICompatibleChatChunk
                        do {
                            chunk = try JSONDecoder().decode(
                                OpenAICompatibleChatChunk.self,
                                from: data
                            )
                        } catch {
                            throw AIError.decodingFailure(
                                error.localizedDescription
                            )
                        }

                        if let chunkUsage = usage(from: chunk.usage) {
                            finalUsage = chunkUsage
                            continuation.yield(.usage(chunkUsage))
                        }

                        if let choice = chunk.choices.first {
                            if
                                let delta = choice.delta.content,
                                !delta.isEmpty
                            {
                                accumulatedText += delta
                                continuation.yield(.textDelta(delta))
                            }

                            if let rawFinishReason = choice.finishReason {
                                finalFinishReason = finishReason(
                                    from: rawFinishReason
                                )
                            }
                        }

                        return false
                    }

                    for try await rawLine in response.lines {
                        try Task.checkCancellation()

                        guard
                            let event = sseDecoder.consume(rawLine)
                        else {
                            continue
                        }

                        if try consumePayload(event.data) {
                            reachedDone = true
                            break
                        }
                    }

                    if
                        !reachedDone,
                        let event = sseDecoder.finish()
                    {
                        _ = try consumePayload(event.data)
                    }

                    let completedResponse = AIResponse(
                        text: accumulatedText,
                        providerID: id,
                        finishReason: finalFinishReason,
                        usage: finalUsage
                    )

                    continuation.yield(.completed(completedResponse))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIError.cancelled)
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: AIError.cancelled)
                    } else {
                        continuation.finish(
                            throwing: AIError.transportFailure(
                                error.localizedDescription
                            )
                        )
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private var credentialRequest: AICredentialRequest {
        AICredentialRequest(
            providerID: id,
            kind: configuration.credentialKind
        )
    }

    private var endpointURL: URL? {
        let base = configuration.baseURL.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = configuration.chatCompletionsPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !base.isEmpty, !path.isEmpty else {
            return nil
        }

        return URL(string: "\(base)/\(path)")
    }

    private func makeURLRequest(
        for request: AIRequest,
        stream: Bool
    ) async throws -> URLRequest {
        guard let endpointURL else {
            throw AIError.invalidRequest(
                "Invalid OpenAI-compatible endpoint URL"
            )
        }

        let credential = try await requiredCredential()
        let messages = try request.messages.map(
            OpenAICompatibleMessage.init
        )

        let body = OpenAICompatibleChatRequest(
            model: configuration.model,
            messages: messages,
            maxTokens:
                request.maxOutputTokens
                ?? configuration.defaultMaxOutputTokens,
            temperature:
                request.temperature
                ?? configuration.defaultTemperature,
            stream: stream
        )

        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue(
            authorizationValue(credential: credential),
            forHTTPHeaderField: configuration.authorizationHeaderName
        )

        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw AIError.invalidRequest(
                "Failed to encode OpenAI-compatible request"
            )
        }

        return urlRequest
    }

    private func requiredCredential() async throws -> String {
        let credential: String
        do {
            guard let value = try await credentialProvider.credential(
                for: credentialRequest
            ) else {
                throw AIError.unavailable(.authenticationMissing)
            }
            credential = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        } catch let error as AIError {
            throw error
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.authenticationFailed
        }

        guard !credential.isEmpty else {
            throw AIError.unavailable(.authenticationMissing)
        }

        return credential
    }

    private func authorizationValue(credential: String) -> String {
        guard
            let prefix = configuration.authorizationPrefix?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !prefix.isEmpty
        else {
            return credential
        }

        return "\(prefix) \(credential)"
    }

    private func validateHTTPResponse(
        _ response: AIHTTPResponse
    ) throws {
        try validateHTTPStatus(
            response.statusCode,
            data: response.data
        )
    }

    private func validateHTTPStatus(
        _ statusCode: Int,
        data: Data?
    ) throws {
        guard !(200...299).contains(statusCode) else {
            return
        }

        let message: String
        if let data {
            message = errorMessage(from: data)
        } else {
            message =
                "OpenAI-compatible HTTP request failed with status " +
                String(statusCode)
        }

        switch statusCode {
        case 401, 403:
            throw AIError.authenticationFailed
        case 408:
            throw AIError.transportFailure(message)
        case 429:
            throw AIError.rateLimited
        case 400, 404, 409, 422:
            throw AIError.invalidRequest(message)
        case 500...599:
            throw AIError.unavailable(.serviceUnavailable)
        default:
            throw AIError.providerFailure(
                providerID: id,
                message: message
            )
        }
    }

    private func errorMessage(from data: Data) -> String {
        if
            let envelope = try? JSONDecoder().decode(
                OpenAICompatibleErrorEnvelope.self,
                from: data
            ),
            let message = envelope.error?.message,
            !message.isEmpty
        {
            return String(message.prefix(1024))
        }

        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return String(raw.prefix(1024))
        }

        return "OpenAI-compatible HTTP request failed"
    }

    private func finishReason(from rawValue: String?) -> AIFinishReason {
        switch rawValue {
        case nil, "stop":
            return .completed
        case "length":
            return .maxOutputReached
        case "content_filter":
            return .blocked
        case "tool_calls":
            return .toolCallRequested
        case "cancelled", "aborted":
            return .cancelled
        default:
            return .completed
        }
    }

    private func usage(
        from usage: OpenAICompatibleChatResponse.Usage?
    ) -> AIUsage? {
        guard let usage else {
            return nil
        }

        return AIUsage(
            inputTokens: usage.promptTokens,
            outputTokens: usage.completionTokens
        )
    }

    private func fallbackStream(
        _ request: AIRequest
    ) -> AIResponseStream {
        AIResponseStream { continuation in
            let task = Task {
                do {
                    let response = try await generate(request)

                    if !response.text.isEmpty {
                        continuation.yield(.textDelta(response.text))
                    }

                    for toolCall in response.toolCalls {
                        continuation.yield(.toolCall(toolCall))
                    }

                    if let usage = response.usage {
                        continuation.yield(.usage(usage))
                    }

                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIError.cancelled)
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
