import AICore
import AIOrchestration
import AIProviderCoreAI
import AITools
import Foundation
import XCTest

private struct StubProvider: AIProvider {
    let id: AIProviderID
    let capabilities: AICapabilities
    let text: String
    let shouldFail: Bool

    var displayName: String { id.rawValue }

    func availability() async -> AIAvailability { .available }

    func generate(_ request: AIRequest) async throws -> AIResponse {
        if shouldFail {
            throw AIError.providerFailure(providerID: id, message: "stub failure")
        }
        return AIResponse(text: text, providerID: id)
    }
}

private struct EchoTool: AITool {
    let definition = AIToolDefinition(
        name: "echo",
        description: "Echo input",
        inputSchemaJSON: "{\"type\":\"object\"}"
    )

    func execute(argumentsJSON: String) async throws -> AIToolResult {
        AIToolResult(toolName: definition.name, content: argumentsJSON)
    }
}

private struct StubCoreAIBridge: CoreAIBridge {
    let bridgeAvailability: AIAvailability
    let invocation: CoreAIBridgeInvocation

    func availability() async -> AIAvailability {
        bridgeAvailability
    }

    func generate(
        requestJSON: String,
        modelPath: String
    ) async -> CoreAIBridgeInvocation {
        invocation
    }
}

final class AICoreKitTests: XCTestCase {
    func testCapabilitiesSatisfyRequiredSet() {
        let capabilities: AICapabilities = [.textGeneration, .localExecution]
        XCTAssertTrue(capabilities.satisfies([.textGeneration]))
        XCTAssertFalse(capabilities.satisfies([.textGeneration, .toolCalling]))
    }

    func testRouterPrefersLocalProvider() async {
        let local = StubProvider(
            id: "local",
            capabilities: [.textGeneration, .localExecution],
            text: "local",
            shouldFail: false
        )
        let remote = StubProvider(
            id: "remote",
            capabilities: [.textGeneration, .remoteExecution],
            text: "remote",
            shouldFail: false
        )

        let candidates = await AIRouter().candidates(
            from: [remote, local],
            requiredCapabilities: [.textGeneration],
            preference: .localFirst
        )

        XCTAssertEqual(candidates.first?.id, local.id)
    }

    func testOrchestratorFallsBackAfterFailure() async throws {
        let first = StubProvider(
            id: "first",
            capabilities: [.textGeneration, .localExecution],
            text: "",
            shouldFail: true
        )
        let second = StubProvider(
            id: "second",
            capabilities: [.textGeneration, .remoteExecution],
            text: "fallback",
            shouldFail: false
        )
        let registry = AIProviderRegistry(providers: [first, second])
        let orchestrator = DefaultAIOrchestrator(registry: registry)

        let response = try await orchestrator.respond(
            to: AIRequest(messages: [.user("hello")], executionPreference: .localFirst)
        )

        XCTAssertEqual(response.text, "fallback")
        XCTAssertEqual(response.providerID, second.id)
    }

    func testToolRegistryStoresTools() async throws {
        let registry = AIToolRegistry()
        try await registry.register(EchoTool())
        let definitions = await registry.definitions()
        XCTAssertEqual(definitions.map(\.name), ["echo"])
    }

    func testCoreAIProviderReportsMissingModel() async {
        let provider = CoreAIProvider(
            bridge: StubCoreAIBridge(
                bridgeAvailability: .available,
                invocation: CoreAIBridgeInvocation(status: .success)
            ),
            resourceProvider: StaticCoreAIModelResourceProvider(resource: nil)
        )

        let availability = await provider.availability()
        XCTAssertEqual(
            availability,
            .unavailable(.modelMissing)
        )
    }

    func testCoreAIProviderDecodesGenericResponse() async throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let responseJSON = """
        {
          "text": "local response",
          "finishReason": "completed",
          "inputTokens": 12,
          "outputTokens": 4
        }
        """

        let provider = CoreAIProvider(
            bridge: StubCoreAIBridge(
                bridgeAvailability: .available,
                invocation: CoreAIBridgeInvocation(
                    status: .success,
                    responseJSON: responseJSON
                )
            ),
            resourceProvider: StaticCoreAIModelResourceProvider(
                resource: CoreAIModelResource(
                    identifier: "fixture",
                    path: temporaryURL.path
                )
            )
        )

        let response = try await provider.generate(
            AIRequest(messages: [.user("hello")])
        )

        XCTAssertEqual(response.text, "local response")
        XCTAssertEqual(response.providerID, .coreAI)
        XCTAssertEqual(response.usage?.inputTokens, 12)
        XCTAssertEqual(response.usage?.outputTokens, 4)
    }

    func testCoreAIProviderRejectsUnsupportedCapability() async throws {
        let provider = CoreAIProvider(
            bridge: UnavailableCoreAIBridge(),
            resourceProvider: StaticCoreAIModelResourceProvider(resource: nil)
        )

        do {
            _ = try await provider.generate(
                AIRequest(
                    messages: [.user("hello")],
                    requiredCapabilities: [.textGeneration, .toolCalling]
                )
            )
            XCTFail("Expected unsupported capability")
        } catch let error as AIError {
            XCTAssertEqual(error, .unsupportedCapability)
        }
    }
}


extension AICoreKitTests {
    func testWeakSymbolBridgeIsUnavailableWithoutRuntimeImage() async {
        let bridge = WeakSymbolCoreAIBridge(
            availabilitySymbol: "AICKDefinitelyMissingAvailability",
            generateSymbol: "AICKDefinitelyMissingGenerate"
        )

        let availability = await bridge.availability()
        XCTAssertNotEqual(availability, .available)

        let invocation = await bridge.generate(
            requestJSON: "{}",
            modelPath: "/missing"
        )
        XCTAssertEqual(invocation.status, .unavailable)
    }
}


private struct LifecycleStubCoreAIBridge: CoreAIModelLifecycleBridge {
    let prepareStatus: CoreAIBridgeStatus
    let unloadStatus: CoreAIBridgeStatus

    func availability() async -> AIAvailability {
        .available
    }

    func generate(
        requestJSON: String,
        modelPath: String
    ) async -> CoreAIBridgeInvocation {
        CoreAIBridgeInvocation(status: .unavailable)
    }

    func prepare(modelPath: String) async -> CoreAIBridgeStatus {
        prepareStatus
    }

    func unload(modelPath: String) async -> CoreAIBridgeStatus {
        unloadStatus
    }
}

extension AICoreKitTests {
    func testCoreAIProviderPreparesAndReleasesResources() async throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let provider = CoreAIProvider(
            bridge: LifecycleStubCoreAIBridge(
                prepareStatus: .success,
                unloadStatus: .success
            ),
            resourceProvider: StaticCoreAIModelResourceProvider(
                resource: CoreAIModelResource(
                    identifier: "fixture",
                    path: temporaryURL.path
                )
            )
        )

        try await provider.prepareResources()
        try await provider.releaseResources()
    }
}


import AIHTTP
import AIProviderOpenAICompatible

private struct TestCredentialProvider: AICredentialProviding {
    let value: String?

    func credential(
        for request: AICredentialRequest
    ) async throws -> String? {
        value
    }
}

private actor RecordingHTTPTransport: AIHTTPTransport {
    private let response: AIHTTPResponse
    private var capturedRequest: URLRequest?

    init(response: AIHTTPResponse) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> AIHTTPResponse {
        capturedRequest = request
        return response
    }

    func lastRequest() -> URLRequest? {
        capturedRequest
    }
}

extension AICoreKitTests {
    func testOpenAICompatibleProviderGeneratesTextAndUsage() async throws {
        let responseData = """
        {
          "choices": [
            {
              "message": {"content": "hello from cloud"},
              "finish_reason": "stop"
            }
          ],
          "usage": {
            "prompt_tokens": 7,
            "completion_tokens": 3
          }
        }
        """.data(using: .utf8)!

        let transport = RecordingHTTPTransport(
            response: AIHTTPResponse(
                data: responseData,
                statusCode: 200
            )
        )

        let provider = OpenAICompatibleProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                providerID: "fixture.openai-compatible",
                displayName: "Fixture",
                baseURL: URL(string: "https://example.com/v1")!,
                model: "fixture-model",
                defaultMaxOutputTokens: 64,
                defaultTemperature: 0.25
            ),
            credentialProvider: TestCredentialProvider(
                value: "test-token"
            ),
            transport: transport
        )

        let response = try await provider.generate(
            AIRequest(messages: [.user("hello")])
        )

        XCTAssertEqual(response.text, "hello from cloud")
        XCTAssertEqual(response.providerID, "fixture.openai-compatible")
        XCTAssertEqual(response.usage?.inputTokens, 7)
        XCTAssertEqual(response.usage?.outputTokens, 3)

        let capturedRequest = await transport.lastRequest()
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://example.com/v1/chat/completions"
        )
        XCTAssertEqual(
            capturedRequest?.value(
                forHTTPHeaderField: "Authorization"
            ),
            "Bearer test-token"
        )

        let bodyData = try XCTUnwrap(capturedRequest?.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )
        XCTAssertEqual(body["model"] as? String, "fixture-model")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["max_tokens"] as? Int, 64)
    }

    func testOpenAICompatibleProviderDoesNotOverstateCapabilities() {
        let provider = OpenAICompatibleProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                baseURL: URL(string: "https://example.com/v1")!,
                model: "fixture-model"
            ),
            credentialProvider: TestCredentialProvider(
                value: "test-token"
            ),
            transport: RecordingHTTPTransport(
                response: AIHTTPResponse(
                    data: Data(),
                    statusCode: 200
                )
            )
        )

        XCTAssertTrue(
            provider.capabilities.contains(.textGeneration)
        )
        XCTAssertTrue(
            provider.capabilities.contains(.remoteExecution)
        )
        XCTAssertTrue(
            provider.capabilities.contains(.requiresNetwork)
        )
        XCTAssertFalse(
            provider.capabilities.contains(.streaming)
        )
        XCTAssertFalse(
            provider.capabilities.contains(.structuredGeneration)
        )
        XCTAssertFalse(
            provider.capabilities.contains(.toolCalling)
        )
    }

    func testOpenAICompatibleProviderReportsMissingCredential() async {
        let provider = OpenAICompatibleProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                baseURL: URL(string: "https://example.com/v1")!,
                model: "fixture-model"
            ),
            credentialProvider: TestCredentialProvider(value: nil),
            transport: RecordingHTTPTransport(
                response: AIHTTPResponse(
                    data: Data(),
                    statusCode: 200
                )
            )
        )

        let availability = await provider.availability()
        XCTAssertEqual(
            availability,
            .unavailable(.authenticationMissing)
        )
    }

    func testOpenAICompatibleProviderMapsAuthenticationFailure() async {
        let errorData = """
        {"error":{"message":"invalid credential"}}
        """.data(using: .utf8)!

        let provider = OpenAICompatibleProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                baseURL: URL(string: "https://example.com/v1")!,
                model: "fixture-model"
            ),
            credentialProvider: TestCredentialProvider(
                value: "bad-token"
            ),
            transport: RecordingHTTPTransport(
                response: AIHTTPResponse(
                    data: errorData,
                    statusCode: 401
                )
            )
        )

        do {
            _ = try await provider.generate(
                AIRequest(messages: [.user("hello")])
            )
            XCTFail("Expected authentication failure")
        } catch let error as AIError {
            XCTAssertEqual(error, .authenticationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOpenAICompatibleProviderRejectsToolsUntilNormalized() async {
        let provider = OpenAICompatibleProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                baseURL: URL(string: "https://example.com/v1")!,
                model: "fixture-model"
            ),
            credentialProvider: TestCredentialProvider(
                value: "test-token"
            ),
            transport: RecordingHTTPTransport(
                response: AIHTTPResponse(
                    data: Data(),
                    statusCode: 200
                )
            )
        )

        do {
            _ = try await provider.generate(
                AIRequest(
                    messages: [.user("hello")],
                    tools: [
                        AIToolDefinition(
                            name: "fixture",
                            description: "fixture",
                            inputSchemaJSON: "{}"
                        )
                    ]
                )
            )
            XCTFail("Expected unsupported capability")
        } catch let error as AIError {
            XCTAssertEqual(error, .unsupportedCapability)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}


private actor RecordingStreamingHTTPTransport: AIHTTPStreamingTransport {
    private let statusCode: Int
    private let streamLines: [String]
    private var capturedRequest: URLRequest?

    init(
        statusCode: Int = 200,
        streamLines: [String]
    ) {
        self.statusCode = statusCode
        self.streamLines = streamLines
    }

    func data(for request: URLRequest) async throws -> AIHTTPResponse {
        capturedRequest = request
        return AIHTTPResponse(
            data: Data(),
            statusCode: statusCode
        )
    }

    func lines(
        for request: URLRequest
    ) async throws -> AIHTTPLineStreamResponse {
        capturedRequest = request
        let values = streamLines

        let lines = AsyncThrowingStream<String, Error> {
            continuation in

            for value in values {
                continuation.yield(value)
            }
            continuation.finish()
        }

        return AIHTTPLineStreamResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "text/event-stream"],
            lines: lines
        )
    }

    func lastRequest() -> URLRequest? {
        capturedRequest
    }
}

extension AICoreKitTests {
    func testOpenAICompatibleProviderStreamsSSE() async throws {
        let transport = RecordingStreamingHTTPTransport(
            streamLines: [
                ": keepalive",
                "data: {\"choices\":[{\"delta\":{\"content\":\"hel\"},\"finish_reason\":null}]}",
                "",
                "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":2}}",
                "",
                "data: [DONE]",
                ""
            ]
        )

        let provider = OpenAICompatibleProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                providerID: "fixture.streaming",
                displayName: "Streaming Fixture",
                baseURL: URL(string: "https://example.com/v1")!,
                model: "fixture-model"
            ),
            credentialProvider: TestCredentialProvider(
                value: "test-token"
            ),
            transport: transport
        )

        XCTAssertTrue(
            provider.capabilities.contains(.streaming)
        )

        var deltas: [String] = []
        var observedUsage: AIUsage?
        var completedResponse: AIResponse?

        let stream = provider.stream(
            AIRequest(
                messages: [.user("hello")],
                requiredCapabilities: [
                    .textGeneration,
                    .streaming
                ]
            )
        )

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                deltas.append(delta)
            case .usage(let usage):
                observedUsage = usage
            case .completed(let response):
                completedResponse = response
            case .toolCall:
                XCTFail("Unexpected tool call")
            }
        }

        XCTAssertEqual(deltas, ["hel", "lo"])
        XCTAssertEqual(completedResponse?.text, "hello")
        XCTAssertEqual(
            completedResponse?.finishReason,
            .completed
        )
        XCTAssertEqual(observedUsage?.inputTokens, 7)
        XCTAssertEqual(observedUsage?.outputTokens, 2)
        XCTAssertEqual(
            completedResponse?.usage?.inputTokens,
            7
        )
        XCTAssertEqual(
            completedResponse?.usage?.outputTokens,
            2
        )

        let capturedRequest = await transport.lastRequest()
        let bodyData = try XCTUnwrap(capturedRequest?.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testOpenAICompatibleStreamingMapsRateLimit() async {
        let transport = RecordingStreamingHTTPTransport(
            statusCode: 429,
            streamLines: []
        )

        let provider = OpenAICompatibleProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                baseURL: URL(string: "https://example.com/v1")!,
                model: "fixture-model"
            ),
            credentialProvider: TestCredentialProvider(
                value: "test-token"
            ),
            transport: transport
        )

        do {
            for try await _ in provider.stream(
                AIRequest(messages: [.user("hello")])
            ) {}
            XCTFail("Expected rate limit")
        } catch let error as AIError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}


extension AICoreKitTests {
    func testServerSentEventDecoderHandlesMultilineDataAndIDs() {
        var decoder = AIServerSentEventDecoder()

        XCTAssertNil(decoder.consume(": keepalive"))
        XCTAssertNil(decoder.consume("id: event-1"))
        XCTAssertNil(decoder.consume("event: message"))
        XCTAssertNil(decoder.consume("data: first"))
        XCTAssertNil(decoder.consume("data: second"))

        let event = decoder.consume("")

        XCTAssertEqual(event?.event, "message")
        XCTAssertEqual(event?.data, "first\nsecond")
        XCTAssertEqual(event?.id, "event-1")

        XCTAssertNil(decoder.consume("data: tail"))
        let tail = decoder.finish()

        XCTAssertEqual(tail?.event, nil)
        XCTAssertEqual(tail?.data, "tail")
        XCTAssertEqual(tail?.id, "event-1")
    }
}


import AIProviderAnthropic

extension AICoreKitTests {
    func testAnthropicProviderGeneratesTextAndHeaders() async throws {
        let responseData = """
        {
          "content": [
            {"type": "text", "text": "hello from Claude"}
          ],
          "stop_reason": "end_turn",
          "usage": {
            "input_tokens": 8,
            "output_tokens": 4
          }
        }
        """.data(using: .utf8)!

        let transport = RecordingHTTPTransport(
            response: AIHTTPResponse(
                data: responseData,
                statusCode: 200
            )
        )

        let provider = AnthropicProvider(
            configuration: AnthropicProviderConfiguration(
                model: "fixture-claude",
                baseURL: URL(
                    string: "https://api.anthropic.example/v1"
                )!,
                defaultMaxOutputTokens: 256
            ),
            credentialProvider: TestCredentialProvider(
                value: "anthropic-key"
            ),
            transport: transport
        )

        let response = try await provider.generate(
            AIRequest(
                messages: [
                    .system("Be concise."),
                    .user("hello")
                ]
            )
        )

        XCTAssertEqual(response.text, "hello from Claude")
        XCTAssertEqual(response.providerID, .anthropic)
        XCTAssertEqual(response.usage?.inputTokens, 8)
        XCTAssertEqual(response.usage?.outputTokens, 4)

        let capturedRequest = await transport.lastRequest()

        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://api.anthropic.example/v1/messages"
        )
        XCTAssertEqual(
            capturedRequest?.value(
                forHTTPHeaderField: "x-api-key"
            ),
            "anthropic-key"
        )
        XCTAssertEqual(
            capturedRequest?.value(
                forHTTPHeaderField: "anthropic-version"
            ),
            "2023-06-01"
        )

        let bodyData = try XCTUnwrap(
            capturedRequest?.httpBody
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )

        XCTAssertEqual(
            body["model"] as? String,
            "fixture-claude"
        )
        XCTAssertEqual(
            body["max_tokens"] as? Int,
            256
        )
        XCTAssertEqual(
            body["stream"] as? Bool,
            false
        )
        XCTAssertEqual(
            body["system"] as? String,
            "Be concise."
        )
        XCTAssertNil(body["temperature"])

        let messages = try XCTUnwrap(
            body["messages"] as? [[String: Any]]
        )
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(
            messages.first?["role"] as? String,
            "user"
        )
        XCTAssertEqual(
            messages.first?["content"] as? String,
            "hello"
        )
    }

    func testAnthropicProviderStreamsMessagesAPIEvents() async throws {
        let transport = RecordingStreamingHTTPTransport(
            streamLines: [
                "event: message_start",
                "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}",
                "",
                "event: content_block_delta",
                "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"hel\"}}",
                "",
                "event: content_block_delta",
                "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}",
                "",
                "event: message_delta",
                "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":2}}",
                "",
                "event: message_stop",
                "data: {\"type\":\"message_stop\"}",
                ""
            ]
        )

        let provider = AnthropicProvider(
            configuration: AnthropicProviderConfiguration(
                model: "fixture-claude",
                baseURL: URL(
                    string: "https://api.anthropic.example/v1"
                )!
            ),
            credentialProvider: TestCredentialProvider(
                value: "anthropic-key"
            ),
            transport: transport
        )

        XCTAssertTrue(
            provider.capabilities.contains(.streaming)
        )
        XCTAssertFalse(
            provider.capabilities.contains(.toolCalling)
        )

        var deltas: [String] = []
        var observedUsage: AIUsage?
        var completedResponse: AIResponse?

        for try await event in provider.stream(
            AIRequest(
                messages: [.user("hello")],
                requiredCapabilities: [
                    .textGeneration,
                    .streaming
                ]
            )
        ) {
            switch event {
            case .textDelta(let delta):
                deltas.append(delta)

            case .usage(let usage):
                observedUsage = usage

            case .completed(let response):
                completedResponse = response

            case .toolCall:
                XCTFail("Unexpected tool call")
            }
        }

        XCTAssertEqual(deltas, ["hel", "lo"])
        XCTAssertEqual(
            completedResponse?.text,
            "hello"
        )
        XCTAssertEqual(
            completedResponse?.finishReason,
            .completed
        )
        XCTAssertEqual(
            observedUsage?.inputTokens,
            5
        )
        XCTAssertEqual(
            observedUsage?.outputTokens,
            2
        )
        XCTAssertEqual(
            completedResponse?.usage?.inputTokens,
            5
        )
        XCTAssertEqual(
            completedResponse?.usage?.outputTokens,
            2
        )

        let capturedRequest = await transport.lastRequest()
        let bodyData = try XCTUnwrap(
            capturedRequest?.httpBody
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )

        XCTAssertEqual(
            body["stream"] as? Bool,
            true
        )
    }
}


import AIProviderGemini

extension AICoreKitTests {
    func testGeminiProviderGeneratesTextAndHeaders() async throws {
        let responseData = """
        {
          "candidates": [
            {
              "content": {
                "role": "model",
                "parts": [
                  {"text": "hello from Gemini"}
                ]
              },
              "finishReason": "STOP"
            }
          ],
          "usageMetadata": {
            "promptTokenCount": 9,
            "candidatesTokenCount": 4,
            "totalTokenCount": 13
          }
        }
        """.data(using: .utf8)!

        let transport = RecordingHTTPTransport(
            response: AIHTTPResponse(
                data: responseData,
                statusCode: 200
            )
        )

        let provider = GeminiProvider(
            configuration: GeminiProviderConfiguration(
                model: "fixture-gemini",
                baseURL: URL(
                    string: "https://gemini.example"
                )!,
                defaultMaxOutputTokens: 256
            ),
            credentialProvider: TestCredentialProvider(
                value: "gemini-key"
            ),
            transport: transport
        )

        let response = try await provider.generate(
            AIRequest(
                messages: [
                    .system("Be concise."),
                    .user("hello")
                ]
            )
        )

        XCTAssertEqual(response.text, "hello from Gemini")
        XCTAssertEqual(response.providerID, .gemini)
        XCTAssertEqual(response.usage?.inputTokens, 9)
        XCTAssertEqual(response.usage?.outputTokens, 4)

        let capturedRequest = await transport.lastRequest()

        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://gemini.example/v1beta/models/fixture-gemini:generateContent"
        )
        XCTAssertEqual(
            capturedRequest?.value(
                forHTTPHeaderField: "x-goog-api-key"
            ),
            "gemini-key"
        )

        let bodyData = try XCTUnwrap(
            capturedRequest?.httpBody
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )

        let generationConfig = try XCTUnwrap(
            body["generationConfig"] as? [String: Any]
        )
        XCTAssertEqual(
            generationConfig["maxOutputTokens"] as? Int,
            256
        )
        XCTAssertNil(generationConfig["temperature"])

        let systemInstruction = try XCTUnwrap(
            body["systemInstruction"] as? [String: Any]
        )
        let systemParts = try XCTUnwrap(
            systemInstruction["parts"] as? [[String: Any]]
        )
        XCTAssertEqual(
            systemParts.first?["text"] as? String,
            "Be concise."
        )

        let contents = try XCTUnwrap(
            body["contents"] as? [[String: Any]]
        )
        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(
            contents.first?["role"] as? String,
            "user"
        )
    }

    func testGeminiProviderStreamsGenerateContentSSE() async throws {
        let transport = RecordingStreamingHTTPTransport(
            streamLines: [
                "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"hel\"}]}}],\"usageMetadata\":{\"promptTokenCount\":6,\"candidatesTokenCount\":1}}",
                "",
                "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"lo\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":6,\"candidatesTokenCount\":2}}",
                ""
            ]
        )

        let provider = GeminiProvider(
            configuration: GeminiProviderConfiguration(
                model: "fixture-gemini",
                baseURL: URL(
                    string: "https://gemini.example"
                )!
            ),
            credentialProvider: TestCredentialProvider(
                value: "gemini-key"
            ),
            transport: transport
        )

        XCTAssertTrue(
            provider.capabilities.contains(.streaming)
        )
        XCTAssertFalse(
            provider.capabilities.contains(.toolCalling)
        )
        XCTAssertFalse(
            provider.capabilities.contains(.imageInput)
        )
        XCTAssertFalse(
            provider.capabilities.contains(.audioInput)
        )

        var deltas: [String] = []
        var observedUsage: AIUsage?
        var completedResponse: AIResponse?

        for try await event in provider.stream(
            AIRequest(
                messages: [.user("hello")],
                requiredCapabilities: [
                    .textGeneration,
                    .streaming
                ]
            )
        ) {
            switch event {
            case .textDelta(let delta):
                deltas.append(delta)

            case .usage(let usage):
                observedUsage = usage

            case .completed(let response):
                completedResponse = response

            case .toolCall:
                XCTFail("Unexpected tool call")
            }
        }

        XCTAssertEqual(deltas, ["hel", "lo"])
        XCTAssertEqual(
            completedResponse?.text,
            "hello"
        )
        XCTAssertEqual(
            completedResponse?.finishReason,
            .completed
        )
        XCTAssertEqual(
            observedUsage?.inputTokens,
            6
        )
        XCTAssertEqual(
            observedUsage?.outputTokens,
            2
        )

        let capturedRequest = await transport.lastRequest()
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://gemini.example/v1beta/models/fixture-gemini:streamGenerateContent?alt=sse"
        )
    }

    func testGeminiProviderMapsBlockedPromptToBlockedResponse() async throws {
        let responseData = """
        {
          "promptFeedback": {
            "blockReason": "SAFETY"
          },
          "usageMetadata": {
            "promptTokenCount": 3,
            "totalTokenCount": 3
          }
        }
        """.data(using: .utf8)!

        let provider = GeminiProvider(
            configuration: GeminiProviderConfiguration(
                model: "fixture-gemini",
                baseURL: URL(
                    string: "https://gemini.example"
                )!
            ),
            credentialProvider: TestCredentialProvider(
                value: "gemini-key"
            ),
            transport: RecordingHTTPTransport(
                response: AIHTTPResponse(
                    data: responseData,
                    statusCode: 200
                )
            )
        )

        let response = try await provider.generate(
            AIRequest(messages: [.user("hello")])
        )

        XCTAssertEqual(response.text, "")
        XCTAssertEqual(response.finishReason, .blocked)
        XCTAssertEqual(response.usage?.inputTokens, 3)
    }
}
