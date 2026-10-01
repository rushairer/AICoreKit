import AICore
import AIHTTP
import Foundation

public struct AnthropicProvider: AIProvider {
    public let configuration: AnthropicProviderConfiguration

    private let credentialProvider: any AICredentialProviding
    private let transport: any AIHTTPTransport

    public init(
        configuration: AnthropicProviderConfiguration,
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
            .structuredGeneration,
            .toolCalling,
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
            return .unavailable(
                .unknown(error.localizedDescription)
            )
        }
    }

    public func generate(_ request: AIRequest) async throws -> AIResponse {
        try validate(request)

        let urlRequest = try await makeURLRequest(
            for: request,
            stream: false,
            structuredSchema: nil
        )

        let response: AIHTTPResponse
        do {
            response = try await transport.data(for: urlRequest)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.transportFailure(
                error.localizedDescription
            )
        }

        try validateHTTPStatus(
            response.statusCode,
            data: response.data
        )

        let decoded: AnthropicMessageResponse
        do {
            decoded = try JSONDecoder().decode(
                AnthropicMessageResponse.self,
                from: response.data
            )
        } catch {
            throw AIError.decodingFailure(
                error.localizedDescription
            )
        }

        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()

        var toolCalls: [AIToolCall] = []
        for block in decoded.content where block.type == "tool_use" {
            guard
                let callID = block.id,
                let name = block.name,
                let input = block.input
            else {
                throw AIError.decodingFailure(
                    "Anthropic tool_use block omitted id, name, or input"
                )
            }

            toolCalls.append(
                AIToolCall(
                    id: callID,
                    name: name,
                    argumentsJSON: try input.jsonString()
                )
            )
        }

        guard !text.isEmpty || !toolCalls.isEmpty else {
            throw AIError.decodingFailure(
                "Anthropic response did not contain text or tool calls"
            )
        }

        return AIResponse(
            text: text,
            toolCalls: toolCalls,
            providerID: id,
            finishReason:
                toolCalls.isEmpty
                ? finishReason(from: decoded.stopReason)
                : .toolCallRequested,
            usage: usage(from: decoded.usage)
        )
    }

    public func stream(_ request: AIRequest) -> AIResponseStream {
        if !request.tools.isEmpty {
            return fallbackStream(request)
        }

        guard
            let streamingTransport =
                transport as? any AIHTTPStreamingTransport
        else {
            return fallbackStream(request)
        }

        return AIResponseStream { continuation in
            let task = Task {
                do {
                    try validate(request)

                    let urlRequest = try await makeURLRequest(
                        for: request,
                        stream: true,
                        structuredSchema: nil
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
                    var inputTokens: Int?
                    var outputTokens: Int?
                    var reachedMessageStop = false

                    func currentUsage() -> AIUsage? {
                        guard
                            inputTokens != nil
                            || outputTokens != nil
                        else {
                            return nil
                        }

                        return AIUsage(
                            inputTokens: inputTokens,
                            outputTokens: outputTokens
                        )
                    }

                    func emitUsageIfAvailable() {
                        if let usage = currentUsage() {
                            continuation.yield(.usage(usage))
                        }
                    }

                    func consumeEvent(
                        _ event: AIServerSentEvent
                    ) throws -> Bool {
                        guard
                            let data = event.data.data(using: .utf8)
                        else {
                            throw AIError.decodingFailure(
                                "Anthropic SSE payload was not UTF-8"
                            )
                        }

                        let envelope: AnthropicStreamEnvelope
                        do {
                            envelope = try JSONDecoder().decode(
                                AnthropicStreamEnvelope.self,
                                from: data
                            )
                        } catch {
                            throw AIError.decodingFailure(
                                error.localizedDescription
                            )
                        }

                        switch envelope.type {
                        case "message_start":
                            if let usage = envelope.message?.usage {
                                if let value = usage.inputTokens {
                                    inputTokens = value
                                }
                                if let value = usage.outputTokens {
                                    outputTokens = value
                                }
                                emitUsageIfAvailable()
                            }

                        case "content_block_delta":
                            guard
                                envelope.delta?.type == "text_delta",
                                let delta = envelope.delta?.text,
                                !delta.isEmpty
                            else {
                                return false
                            }

                            accumulatedText += delta
                            continuation.yield(.textDelta(delta))

                        case "message_delta":
                            if
                                let rawStopReason =
                                    envelope.delta?.stopReason
                            {
                                finalFinishReason = finishReason(
                                    from: rawStopReason
                                )
                            }

                            if let usage = envelope.usage {
                                if let value = usage.inputTokens {
                                    inputTokens = value
                                }
                                if let value = usage.outputTokens {
                                    outputTokens = value
                                }
                                emitUsageIfAvailable()
                            }

                        case "message_stop":
                            return true

                        case "error":
                            if let apiError = envelope.error {
                                throw mapAPIError(apiError)
                            }

                            throw AIError.providerFailure(
                                providerID: id,
                                message: "Anthropic streaming error"
                            )

                        default:
                            break
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

                        if try consumeEvent(event) {
                            reachedMessageStop = true
                            break
                        }
                    }

                    if
                        !reachedMessageStop,
                        let event = sseDecoder.finish()
                    {
                        _ = try consumeEvent(event)
                    }

                    let completedResponse = AIResponse(
                        text: accumulatedText,
                        providerID: id,
                        finishReason: finalFinishReason,
                        usage: currentUsage()
                    )

                    continuation.yield(
                        .completed(completedResponse)
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(
                        throwing: AIError.cancelled
                    )
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    if Task.isCancelled {
                        continuation.finish(
                            throwing: AIError.cancelled
                        )
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
            kind: .apiKey
        )
    }

    private var endpointURL: URL? {
        let base = configuration.baseURL.absoluteString
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
        let path = configuration.messagesPath
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )

        guard !base.isEmpty, !path.isEmpty else {
            return nil
        }

        return URL(string: "\(base)/\(path)")
    }

    private func validate(
        _ request: AIRequest
    ) throws {
        guard capabilities.satisfies(
            request.requiredCapabilities
        ) else {
            throw AIError.unsupportedCapability
        }

    }

    public func generateStructured<Output: Decodable & Sendable>(
        _ request: AIStructuredRequest<Output>
    ) async throws -> Output {
        guard capabilities.satisfies(
            request.requiredCapabilities
        ) else {
            throw AIError.unsupportedCapability
        }

        guard let schema = request.schema else {
            throw AIError.invalidRequest(
                "Anthropic structured generation requires a JSON schema"
            )
        }

        let baseRequest = AIRequest(
            messages: [
                .system(request.instructions),
                .user(request.input)
            ],
            requiredCapabilities: [.textGeneration],
            executionPreference: request.executionPreference,
            metadata: request.metadata,
            maxOutputTokens: request.maxOutputTokens,
            temperature: request.temperature
        )

        let urlRequest = try await makeURLRequest(
            for: baseRequest,
            stream: false,
            structuredSchema: schema
        )

        let response: AIHTTPResponse
        do {
            response = try await transport.data(
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
            data: response.data
        )

        let decoded: AnthropicMessageResponse
        do {
            decoded = try JSONDecoder().decode(
                AnthropicMessageResponse.self,
                from: response.data
            )
        } catch {
            throw AIError.decodingFailure(
                error.localizedDescription
            )
        }

        guard
            finishReason(from: decoded.stopReason) == .completed
        else {
            throw AIError.providerFailure(
                providerID: id,
                message: "Anthropic structured response did not complete"
            )
        }

        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()

        guard let data = text.data(using: .utf8) else {
            throw AIError.decodingFailure(
                "Anthropic structured response was not UTF-8"
            )
        }

        do {
            return try JSONDecoder().decode(
                Output.self,
                from: data
            )
        } catch {
            throw AIError.decodingFailure(
                error.localizedDescription
            )
        }
    }

    private func makeURLRequest(
        for request: AIRequest,
        stream: Bool,
        structuredSchema: AIStructuredOutputSchema?
    ) async throws -> URLRequest {
        guard let endpointURL else {
            throw AIError.invalidRequest(
                "Invalid Anthropic endpoint URL"
            )
        }

        let credential = try await requiredCredential()

        let system = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")

        let messages = try request.messages.compactMap {
            message -> AnthropicMessage? in

            if message.role == .system {
                return nil
            }

            return try AnthropicMessage(message)
        }

        guard !messages.isEmpty else {
            throw AIError.invalidRequest(
                "Anthropic Messages API requires at least one user or assistant message"
            )
        }

        let body = AnthropicMessageRequest(
            model: configuration.model,
            maxTokens:
                request.maxOutputTokens
                ?? configuration.defaultMaxOutputTokens,
            messages: messages,
            system: system.isEmpty ? nil : system,
            temperature:
                request.temperature
                ?? configuration.defaultTemperature,
            stream: stream,
            outputConfig: structuredSchema.map {
                AnthropicMessageRequest.OutputConfiguration(
                    schema: $0
                )
            },
            tools:
                request.tools.isEmpty
                ? nil
                : try request.tools.map {
                    try AnthropicMessageRequest.Tool($0)
                }
        )

        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue(
            credential,
            forHTTPHeaderField: configuration.apiKeyHeaderName
        )
        urlRequest.setValue(
            configuration.apiVersion,
            forHTTPHeaderField:
                configuration.apiVersionHeaderName
        )

        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw AIError.invalidRequest(
                "Failed to encode Anthropic request"
            )
        }

        return urlRequest
    }

    private func requiredCredential() async throws -> String {
        let credential: String
        do {
            guard
                let value = try await credentialProvider.credential(
                    for: credentialRequest
                )
            else {
                throw AIError.unavailable(
                    .authenticationMissing
                )
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
            throw AIError.unavailable(
                .authenticationMissing
            )
        }

        return credential
    }

    private func validateHTTPStatus(
        _ statusCode: Int,
        data: Data?
    ) throws {
        guard !(200...299).contains(statusCode) else {
            return
        }

        let apiError =
            data.flatMap {
                try? JSONDecoder().decode(
                    AnthropicErrorEnvelope.self,
                    from: $0
                ).error
            }

        if let apiError {
            throw mapAPIError(apiError)
        }

        let message =
            "Anthropic HTTP request failed with status "
            + String(statusCode)

        switch statusCode {
        case 401, 403:
            throw AIError.authenticationFailed
        case 408, 504:
            throw AIError.transportFailure(message)
        case 429:
            throw AIError.rateLimited
        case 400, 404, 409, 413, 422:
            throw AIError.invalidRequest(message)
        case 500...599:
            throw AIError.unavailable(
                .serviceUnavailable
            )
        default:
            throw AIError.providerFailure(
                providerID: id,
                message: message
            )
        }
    }

    private func mapAPIError(
        _ error: AnthropicAPIError
    ) -> AIError {
        let message =
            error.message
            ?? "Anthropic API request failed"

        switch error.type {
        case "authentication_error",
             "permission_error":
            return .authenticationFailed

        case "rate_limit_error":
            return .rateLimited

        case "invalid_request_error",
             "not_found_error",
             "conflict_error",
             "request_too_large":
            return .invalidRequest(message)

        case "timeout_error":
            return .transportFailure(message)

        case "api_error",
             "overloaded_error":
            return .unavailable(.serviceUnavailable)

        default:
            return .providerFailure(
                providerID: id,
                message: message
            )
        }
    }

    private func finishReason(
        from rawValue: String?
    ) -> AIFinishReason {
        switch rawValue {
        case nil, "end_turn", "stop_sequence":
            return .completed

        case "max_tokens",
             "model_context_window_exceeded":
            return .maxOutputReached

        case "tool_use":
            return .toolCallRequested

        case "refusal":
            return .blocked

        case "pause_turn":
            return .failed

        default:
            return .completed
        }
    }

    private func usage(
        from usage: AnthropicUsage?
    ) -> AIUsage? {
        guard let usage else {
            return nil
        }

        return AIUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens
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
                        continuation.yield(
                            .textDelta(response.text)
                        )
                    }

                    for toolCall in response.toolCalls {
                        continuation.yield(.toolCall(toolCall))
                    }

                    if let usage = response.usage {
                        continuation.yield(.usage(usage))
                    }

                    continuation.yield(
                        .completed(response)
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(
                        throwing: AIError.cancelled
                    )
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
