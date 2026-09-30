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
        [.textGeneration, .remoteExecution, .requiresNetwork]
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

        guard let endpointURL else {
            throw AIError.invalidRequest("Invalid OpenAI-compatible endpoint URL")
        }

        let credential = try await requiredCredential()
        let messages = try request.messages.map(OpenAICompatibleMessage.init)

        let body = OpenAICompatibleChatRequest(
            model: configuration.model,
            messages: messages,
            maxTokens: request.maxOutputTokens ?? configuration.defaultMaxOutputTokens,
            temperature: request.temperature ?? configuration.defaultTemperature,
            stream: false
        )

        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            usage: AIUsage(
                inputTokens: decoded.usage?.promptTokens,
                outputTokens: decoded.usage?.completionTokens
            )
        )
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

    private func requiredCredential() async throws -> String {
        let credential: String
        do {
            guard let value = try await credentialProvider.credential(
                for: credentialRequest
            ) else {
                throw AIError.unavailable(.authenticationMissing)
            }
            credential = value.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard !(200...299).contains(response.statusCode) else {
            return
        }

        let message = errorMessage(from: response.data)

        switch response.statusCode {
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
}
