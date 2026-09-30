import AICore
import AIHTTP
import Foundation

public struct GeminiProvider: AIProvider {
    public let configuration: GeminiProviderConfiguration

    private let credentialProvider: any AICredentialProviding
    private let transport: any AIHTTPTransport

    public init(
        configuration: GeminiProviderConfiguration,
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
            .remoteExecution,
            .requiresNetwork
        ]

        if transport is any AIHTTPStreamingTransport {
            capabilities.insert(.streaming)
        }

        return capabilities
    }

    public func availability() async -> AIAvailability {
        guard endpointURL(stream: false) != nil else {
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
            stream: false
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

        let decoded: GeminiGenerateContentResponse
        do {
            decoded = try JSONDecoder().decode(
                GeminiGenerateContentResponse.self,
                from: response.data
            )
        } catch {
            throw AIError.decodingFailure(
                error.localizedDescription
            )
        }

        if let blockReason = decoded.promptFeedback?.blockReason {
            return AIResponse(
                text: "",
                providerID: id,
                finishReason: finishReason(
                    fromPromptBlockReason: blockReason
                ),
                usage: usage(from: decoded.usageMetadata)
            )
        }

        guard let candidate = decoded.candidates?.first else {
            throw AIError.decodingFailure(
                "Gemini response did not contain a candidate"
            )
        }

        let text = text(from: candidate.content)

        if text.isEmpty,
           candidate.finishReason == nil
        {
            throw AIError.decodingFailure(
                "Gemini response did not contain text content"
            )
        }

        return AIResponse(
            text: text,
            providerID: id,
            finishReason: finishReason(
                from: candidate.finishReason
            ),
            usage: usage(from: decoded.usageMetadata)
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
                    try validate(request)

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

                    var decoder = AIServerSentEventDecoder()
                    var accumulatedText = ""
                    var finalFinishReason: AIFinishReason = .completed
                    var finalUsage: AIUsage?

                    func consume(
                        _ event: AIServerSentEvent
                    ) throws {
                        guard
                            let data = event.data.data(using: .utf8)
                        else {
                            throw AIError.decodingFailure(
                                "Gemini SSE payload was not UTF-8"
                            )
                        }

                        let chunk: GeminiGenerateContentResponse
                        do {
                            chunk = try JSONDecoder().decode(
                                GeminiGenerateContentResponse.self,
                                from: data
                            )
                        } catch {
                            throw AIError.decodingFailure(
                                error.localizedDescription
                            )
                        }

                        if let metadata = chunk.usageMetadata {
                            let chunkUsage = usage(from: metadata)
                            finalUsage = chunkUsage
                            if let chunkUsage {
                                continuation.yield(.usage(chunkUsage))
                            }
                        }

                        if let blockReason = chunk.promptFeedback?.blockReason {
                            finalFinishReason = finishReason(
                                fromPromptBlockReason: blockReason
                            )
                        }

                        guard let candidate = chunk.candidates?.first else {
                            return
                        }

                        let delta = text(from: candidate.content)
                        if !delta.isEmpty {
                            accumulatedText += delta
                            continuation.yield(.textDelta(delta))
                        }

                        if let rawFinishReason = candidate.finishReason {
                            finalFinishReason = finishReason(
                                from: rawFinishReason
                            )
                        }
                    }

                    for try await rawLine in response.lines {
                        try Task.checkCancellation()

                        guard let event = decoder.consume(rawLine) else {
                            continue
                        }

                        try consume(event)
                    }

                    if let event = decoder.finish() {
                        try consume(event)
                    }

                    let completed = AIResponse(
                        text: accumulatedText,
                        providerID: id,
                        finishReason: finalFinishReason,
                        usage: finalUsage
                    )

                    continuation.yield(.completed(completed))
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
                "Gemini structured generation requires a JSON schema"
            )
        }

        guard let url = interactionsURL else {
            throw AIError.invalidRequest(
                "Invalid Gemini Interactions endpoint URL"
            )
        }

        let input = request.input.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !input.isEmpty else {
            throw AIError.invalidRequest(
                "Gemini Interactions API requires non-empty input"
            )
        }

        let credential = try await requiredCredential()

        let generationConfig =
            GeminiInteractionRequest.GenerationConfiguration(
                maxOutputTokens:
                    request.maxOutputTokens
                    ?? configuration.defaultMaxOutputTokens,
                temperature:
                    request.temperature
                    ?? configuration.defaultTemperature
            )

        let body = GeminiInteractionRequest(
            model: normalizedModel,
            input: request.input,
            systemInstruction:
                request.instructions.isEmpty
                ? nil
                : request.instructions,
            responseFormat:
                GeminiInteractionRequest.ResponseFormat(
                    schema: schema
                ),
            store: configuration.storeInteractions,
            generationConfig:
                generationConfig.isEmpty
                ? nil
                : generationConfig
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue(
            credential,
            forHTTPHeaderField:
                configuration.apiKeyHeaderName
        )

        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw AIError.invalidRequest(
                "Failed to encode Gemini Interactions request"
            )
        }

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

        let interaction: GeminiInteractionResponse
        do {
            interaction = try JSONDecoder().decode(
                GeminiInteractionResponse.self,
                from: response.data
            )
        } catch {
            throw AIError.decodingFailure(
                error.localizedDescription
            )
        }

        switch interaction.status {
        case "completed":
            break
        case "cancelled":
            throw AIError.cancelled
        case "incomplete":
            throw AIError.providerFailure(
                providerID: id,
                message: "Gemini structured interaction was incomplete"
            )
        case "failed":
            throw AIError.providerFailure(
                providerID: id,
                message: "Gemini structured interaction failed"
            )
        case "requires_action":
            throw AIError.unsupportedCapability
        default:
            throw AIError.providerFailure(
                providerID: id,
                message:
                    "Unexpected Gemini interaction status: "
                    + interaction.status
            )
        }

        var text = ""

        for step in interaction.steps ?? [] {
            guard step.type == "model_output" else {
                continue
            }

            for content in step.content ?? [] {
                guard
                    content.type == "text",
                    let value = content.text
                else {
                    continue
                }

                text += value
            }
        }

        guard !text.isEmpty else {
            throw AIError.decodingFailure(
                "Gemini structured interaction did not contain text output"
            )
        }

        guard
            let data = text.data(
                using: String.Encoding.utf8
            )
        else {
            throw AIError.decodingFailure(
                "Gemini structured response was not UTF-8"
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

    private var credentialRequest: AICredentialRequest {
        AICredentialRequest(
            providerID: id,
            kind: .apiKey
        )
    }

    private var normalizedModel: String {
        configuration.model
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .replacingOccurrences(
                of: "models/",
                with: ""
            )
    }

    private var interactionsURL: URL? {
        let base = configuration.baseURL.absoluteString
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
        let version = configuration.apiVersion
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
        let path = configuration.interactionsPath
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )

        guard
            !base.isEmpty,
            !version.isEmpty,
            !path.isEmpty,
            !normalizedModel.isEmpty
        else {
            return nil
        }

        return URL(
            string: "\(base)/\(version)/\(path)"
        )
    }

    private func endpointURL(stream: Bool) -> URL? {
        let base = configuration.baseURL.absoluteString
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
        let version = configuration.apiVersion
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
        let model = normalizedModel

        guard
            !base.isEmpty,
            !version.isEmpty,
            !model.isEmpty
        else {
            return nil
        }

        let method =
            stream
            ? "streamGenerateContent"
            : "generateContent"

        var components = URLComponents(
            string: "\(base)/\(version)/models/\(model):\(method)"
        )

        if stream {
            components?.queryItems = [
                URLQueryItem(name: "alt", value: "sse")
            ]
        }

        return components?.url
    }

    private func validate(
        _ request: AIRequest
    ) throws {
        guard capabilities.satisfies(
            request.requiredCapabilities
        ) else {
            throw AIError.unsupportedCapability
        }

        guard request.tools.isEmpty else {
            throw AIError.unsupportedCapability
        }

        guard !request.messages.contains(
            where: { $0.role == .tool }
        ) else {
            throw AIError.unsupportedCapability
        }
    }

    private func makeURLRequest(
        for request: AIRequest,
        stream: Bool
    ) async throws -> URLRequest {
        guard let url = endpointURL(stream: stream) else {
            throw AIError.invalidRequest(
                "Invalid Gemini endpoint URL or model"
            )
        }

        let credential = try await requiredCredential()

        let system = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")

        let contents = try request.messages.compactMap {
            message -> GeminiContent? in

            if message.role == .system {
                return nil
            }

            return try GeminiContent(message)
        }

        guard !contents.isEmpty else {
            throw AIError.invalidRequest(
                "Gemini generateContent requires at least one user or model message"
            )
        }

        let generationConfig = GeminiGenerationConfig(
            maxOutputTokens:
                request.maxOutputTokens
                ?? configuration.defaultMaxOutputTokens,
            temperature:
                request.temperature
                ?? configuration.defaultTemperature
        )

        let body = GeminiGenerateContentRequest(
            contents: contents,
            systemInstruction:
                system.isEmpty
                ? nil
                : GeminiContent(
                    role: nil,
                    text: system
                ),
            generationConfig:
                generationConfig.isEmpty
                ? nil
                : generationConfig
        )

        var urlRequest = URLRequest(url: url)
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

        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw AIError.invalidRequest(
                "Failed to encode Gemini request"
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

        let envelope = data.flatMap {
            try? JSONDecoder().decode(
                GeminiErrorEnvelope.self,
                from: $0
            )
        }
        let message =
            envelope?.error?.message
            ?? "Gemini HTTP request failed with status "
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

    private func text(
        from content: GeminiContent?
    ) -> String {
        content?.parts
            .compactMap(\.text)
            .joined()
            ?? ""
    }

    private func usage(
        from metadata:
            GeminiGenerateContentResponse.UsageMetadata?
    ) -> AIUsage? {
        guard let metadata else {
            return nil
        }

        return AIUsage(
            inputTokens: metadata.promptTokenCount,
            outputTokens: metadata.candidatesTokenCount
        )
    }

    private func finishReason(
        from rawValue: String?
    ) -> AIFinishReason {
        switch rawValue {
        case nil,
             "FINISH_REASON_UNSPECIFIED",
             "STOP":
            return .completed

        case "MAX_TOKENS":
            return .maxOutputReached

        case "SAFETY",
             "RECITATION",
             "LANGUAGE",
             "BLOCKLIST",
             "PROHIBITED_CONTENT",
             "SPII",
             "IMAGE_SAFETY",
             "IMAGE_PROHIBITED_CONTENT",
             "IMAGE_RECITATION",
             "ESCALATION":
            return .blocked

        case "MALFORMED_FUNCTION_CALL",
             "UNEXPECTED_TOOL_CALL",
             "TOO_MANY_TOOL_CALLS",
             "MISSING_THOUGHT_SIGNATURE",
             "MALFORMED_RESPONSE",
             "IMAGE_OTHER",
             "NO_IMAGE",
             "OTHER":
            return .failed

        default:
            return .failed
        }
    }

    private func finishReason(
        fromPromptBlockReason rawValue: String
    ) -> AIFinishReason {
        switch rawValue {
        case "SAFETY",
             "BLOCKLIST",
             "PROHIBITED_CONTENT",
             "IMAGE_SAFETY":
            return .blocked

        default:
            return .failed
        }
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
