public protocol AIProvider: Sendable {
    var id: AIProviderID { get }
    var displayName: String { get }
    var capabilities: AICapabilities { get }

    func availability() async -> AIAvailability
    func generate(_ request: AIRequest) async throws -> AIResponse
    func stream(_ request: AIRequest) -> AIResponseStream
    func generateStructured<Output: Decodable & Sendable>(
        _ request: AIStructuredRequest<Output>
    ) async throws -> Output
}

public extension AIProvider {
    func stream(_ request: AIRequest) -> AIResponseStream {
        AIResponseStream { continuation in
            Task {
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
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generateStructured<Output: Decodable & Sendable>(
        _ request: AIStructuredRequest<Output>
    ) async throws -> Output {
        throw AIError.unsupportedCapability
    }
}
