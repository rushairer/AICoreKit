import AICore
import AIHTTP
import Foundation

public struct OpenAIProvider: AIProvider {
    public let configuration: OpenAIProviderConfiguration

    private let credentialProvider: any AICredentialProviding
    private let transport: any AIHTTPTransport

    public init(
        configuration: OpenAIProviderConfiguration,
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

        let httpResponse: AIHTTPResponse
        do {
            httpResponse = try await transport.data(
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
            httpResponse.statusCode,
            data: httpResponse.data
        )

        let response: OpenAIResponseObject
        do {
            response = try JSONDecoder().decode(
                OpenAIResponseObject.self,
                from: httpResponse.data
            )
        } catch {
            throw AIError.decodingFailure(
                error.localizedDescription
            )
        }

        return try makeAIResponse(from: response)
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
                    try validate(request)

                    let urlRequest = try await makeURLRequest(
                        for: request,
                        stream: true,
                        structuredSchema: nil
                    )

                    let httpResponse: AIHTTPLineStreamResponse
                    do {
                        httpResponse =
                            try await streamingTransport.lines(
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
                        httpResponse.statusCode,
                        data: nil
                    )

                    var decoder = AIServerSentEventDecoder()
                    var accumulatedText = ""
                    var accumulatedRefusal = ""
                    var finalResponse: AIResponse?
                    var sawTerminalEvent = false

                    func consume(
                        _ event: AIServerSentEvent
                    ) throws {
                        guard
                            let data = event.data.data(using: .utf8)
                        else {
                            throw AIError.decodingFailure(
                                "OpenAI SSE payload was not UTF-8"
                            )
                        }

                        let payload: OpenAIResponsesStreamEvent
                        do {
                            payload = try JSONDecoder().decode(
                                OpenAIResponsesStreamEvent.self,
                                from: data
                            )
                        } catch {
                            throw AIError.decodingFailure(
                                error.localizedDescription
                            )
                        }

                        switch payload.type {
                        case "response.output_text.delta":
                            guard
                                let delta = payload.delta,
                                !delta.isEmpty
                            else {
                                return
                            }

                            accumulatedText += delta
                            continuation.yield(.textDelta(delta))

                        case "response.refusal.delta":
                            if let delta = payload.delta {
                                accumulatedRefusal += delta
                            }

                        case "response.completed",
                             "response.incomplete",
                             "response.failed":
                            guard let response = payload.response else {
                                throw AIError.decodingFailure(
                                    "OpenAI terminal stream event omitted the response object"
                                )
                            }

                            let normalized = try makeAIResponse(
                                from: response,
                                fallbackText: accumulatedText,
                                fallbackRefusal: accumulatedRefusal
                            )

                            for toolCall in normalized.toolCalls {
                                continuation.yield(
                                    .toolCall(toolCall)
                                )
                            }

                            if let usage = normalized.usage {
                                continuation.yield(.usage(usage))
                            }

                            finalResponse = normalized
                            sawTerminalEvent = true

                        case "error":
                            let message =
                                payload.error?.message
                                ?? "OpenAI streaming error"
                            throw AIError.providerFailure(
                                providerID: id,
                                message: message
                            )

                        default:
                            break
                        }
                    }

                    for try await rawLine in httpResponse.lines {
                        try Task.checkCancellation()

                        guard let event = decoder.consume(rawLine) else {
                            continue
                        }

                        try consume(event)

                        if sawTerminalEvent {
                            break
                        }
                    }

                    if
                        !sawTerminalEvent,
                        let event = decoder.finish()
                    {
                        try consume(event)
                    }

                    guard let finalResponse else {
                        throw AIError.decodingFailure(
                            "OpenAI response stream ended without a terminal response event"
                        )
                    }

                    continuation.yield(.completed(finalResponse))
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
            kind: .bearerToken
        )
    }

    private var endpointURL: URL? {
        let base = configuration.baseURL.absoluteString
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
        let path = configuration.responsesPath
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )

        guard !base.isEmpty, !path.isEmpty else {
            return nil
        }

        return URL(string: "\(base)/\(path)")
    }

    private func validate(_ request: AIRequest) throws {
        guard capabilities.satisfies(
            request.requiredCapabilities
        ) else {
            throw AIError.unsupportedCapability
        }

        guard !request.messages.contains(
            where: { $0.role == .tool }
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
                "OpenAI structured generation requires a JSON schema"
            )
        }

        let messages: [AIMessage] = [
            .system(request.instructions),
            .user(request.input)
        ]

        let baseRequest = AIRequest(
            messages: messages,
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

        let httpResponse: AIHTTPResponse
        do {
            httpResponse = try await transport.data(
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
            httpResponse.statusCode,
            data: httpResponse.data
        )

        let response: OpenAIResponseObject
        do {
            response = try JSONDecoder().decode(
                OpenAIResponseObject.self,
                from: httpResponse.data
            )
        } catch {
            throw AIError.decodingFailure(
                error.localizedDescription
            )
        }

        let normalized = try makeAIResponse(
            from: response
        )

        guard normalized.finishReason == .completed else {
            throw AIError.providerFailure(
                providerID: id,
                message: "OpenAI structured response did not complete"
            )
        }

        guard let data = normalized.text.data(using: .utf8) else {
            throw AIError.decodingFailure(
                "OpenAI structured response was not UTF-8"
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
                "Invalid OpenAI Responses endpoint URL"
            )
        }

        let model = configuration.model
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !model.isEmpty else {
            throw AIError.invalidRequest(
                "OpenAI model must not be empty"
            )
        }

        let credential = try await requiredCredential()
        let input = try request.messages.map(
            OpenAIResponsesRequest.InputMessage.init
        )

        guard !input.isEmpty else {
            throw AIError.invalidRequest(
                "OpenAI Responses API requires at least one input message"
            )
        }

        let body = OpenAIResponsesRequest(
            model: model,
            input: input,
            maxOutputTokens:
                request.maxOutputTokens
                ?? configuration.defaultMaxOutputTokens,
            temperature:
                request.temperature
                ?? configuration.defaultTemperature,
            stream: stream,
            store: configuration.storeResponses,
            text: structuredSchema.map {
                OpenAIResponsesRequest.TextConfiguration(
                    schema: $0
                )
            },
            tools:
                request.tools.isEmpty
                ? nil
                : try request.tools.map {
                    try OpenAIResponsesRequest.Tool($0)
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
            authorizationValue(credential),
            forHTTPHeaderField:
                configuration.authorizationHeaderName
        )

        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw AIError.invalidRequest(
                "Failed to encode OpenAI Responses request"
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

    private func authorizationValue(
        _ credential: String
    ) -> String {
        let prefix = configuration.authorizationPrefix
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !prefix.isEmpty else {
            return credential
        }

        return "\(prefix) \(credential)"
    }

    private func validateHTTPStatus(
        _ statusCode: Int,
        data: Data?
    ) throws {
        guard !(200...299).contains(statusCode) else {
            return
        }

        let envelope = data.flatMap {
            try? JSONDecoder().decode(
                OpenAIErrorEnvelope.self,
                from: $0
            )
        }
        let message =
            envelope?.error?.message
            ?? "OpenAI HTTP request failed with status "
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
            throw AIError.unavailable(.serviceUnavailable)
        default:
            throw AIError.providerFailure(
                providerID: id,
                message: message
            )
        }
    }

    private func makeAIResponse(
        from response: OpenAIResponseObject,
        fallbackText: String = "",
        fallbackRefusal: String = ""
    ) throws -> AIResponse {
        var text = ""
        var refusal = ""
        var toolCalls: [AIToolCall] = []

        for item in response.output ?? [] {
            switch item.type {
            case "message":
                for content in item.content ?? [] {
                    switch content.type {
                    case "output_text":
                        text += content.text ?? ""
                    case "refusal":
                        refusal += content.refusal ?? ""
                    default:
                        break
                    }
                }

            case "function_call":
                guard
                    let callID = item.callID ?? item.id,
                    let name = item.name,
                    let arguments = item.arguments
                else {
                    throw AIError.decodingFailure(
                        "OpenAI function call omitted id, name, or arguments"
                    )
                }

                toolCalls.append(
                    AIToolCall(
                        id: callID,
                        name: name,
                        argumentsJSON: arguments
                    )
                )

            default:
                break
            }
        }

        if text.isEmpty {
            text = fallbackText
        }
        if refusal.isEmpty {
            refusal = fallbackRefusal
        }

        let finish = finishReason(
            status: response.status,
            incompleteReason:
                response.incompleteDetails?.reason,
            hasRefusal: !refusal.isEmpty
        )

        if text.isEmpty && !refusal.isEmpty {
            text = refusal
        }

        if text.isEmpty,
           toolCalls.isEmpty,
           response.status == "completed"
        {
            throw AIError.decodingFailure(
                "OpenAI response did not contain output text or tool calls"
            )
        }

        if response.status == "failed" {
            throw AIError.providerFailure(
                providerID: id,
                message:
                    response.error?.message
                    ?? "OpenAI response failed"
            )
        }

        return AIResponse(
            text: text,
            toolCalls: toolCalls,
            providerID: id,
            finishReason:
                toolCalls.isEmpty
                ? finish
                : .toolCallRequested,
            usage: usage(from: response.usage)
        )
    }

    private func finishReason(
        status: String?,
        incompleteReason: String?,
        hasRefusal: Bool
    ) -> AIFinishReason {
        if hasRefusal {
            return .blocked
        }

        switch status {
        case nil, "completed":
            return .completed

        case "incomplete":
            switch incompleteReason {
            case "max_output_tokens":
                return .maxOutputReached
            case "content_filter":
                return .blocked
            default:
                return .failed
            }

        case "cancelled":
            return .cancelled

        case "failed":
            return .failed

        default:
            return .failed
        }
    }

    private func usage(
        from usage: OpenAIResponseObject.Usage?
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

                    continuation.yield(.completed(response))
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
