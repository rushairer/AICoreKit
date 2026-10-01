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
        XCTAssertTrue(
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
        XCTAssertTrue(
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


import AIProviderOpenAI

extension AICoreKitTests {
    func testOpenAIProviderGeneratesResponsesAPIText() async throws {
        let responseData = """
        {
          "status": "completed",
          "output": [
            {
              "type": "message",
              "role": "assistant",
              "content": [
                {
                  "type": "output_text",
                  "text": "hello from OpenAI"
                }
              ]
            }
          ],
          "usage": {
            "input_tokens": 10,
            "output_tokens": 5,
            "total_tokens": 15
          },
          "incomplete_details": null,
          "error": null
        }
        """.data(using: .utf8)!

        let transport = RecordingHTTPTransport(
            response: AIHTTPResponse(
                data: responseData,
                statusCode: 200
            )
        )

        let provider = OpenAIProvider(
            configuration: OpenAIProviderConfiguration(
                model: "fixture-openai",
                baseURL: URL(
                    string: "https://openai.example/v1"
                )!,
                defaultMaxOutputTokens: 128
            ),
            credentialProvider: TestCredentialProvider(
                value: "openai-token"
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

        XCTAssertEqual(response.text, "hello from OpenAI")
        XCTAssertEqual(response.providerID, .openAI)
        XCTAssertEqual(response.usage?.inputTokens, 10)
        XCTAssertEqual(response.usage?.outputTokens, 5)

        let capturedRequest = await transport.lastRequest()
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://openai.example/v1/responses"
        )
        XCTAssertEqual(
            capturedRequest?.value(
                forHTTPHeaderField: "Authorization"
            ),
            "Bearer openai-token"
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
            "fixture-openai"
        )
        XCTAssertEqual(
            body["max_output_tokens"] as? Int,
            128
        )
        XCTAssertEqual(
            body["stream"] as? Bool,
            false
        )
        XCTAssertEqual(
            body["store"] as? Bool,
            false
        )
        XCTAssertNil(body["temperature"])

        let input = try XCTUnwrap(
            body["input"] as? [[String: Any]]
        )
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(
            input.first?["role"] as? String,
            "system"
        )
    }

    func testOpenAIProviderStreamsResponsesAPIEvents() async throws {
        let terminalResponse = """
        {"type":"response.completed","response":{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hello"}]}],"usage":{"input_tokens":7,"output_tokens":2},"incomplete_details":null,"error":null}}
        """

        let transport = RecordingStreamingHTTPTransport(
            streamLines: [
                "event: response.output_text.delta",
                "data: {\"type\":\"response.output_text.delta\",\"delta\":\"hel\"}",
                "",
                "event: response.output_text.delta",
                "data: {\"type\":\"response.output_text.delta\",\"delta\":\"lo\"}",
                "",
                "event: response.completed",
                "data: \(terminalResponse)",
                ""
            ]
        )

        let provider = OpenAIProvider(
            configuration: OpenAIProviderConfiguration(
                model: "fixture-openai",
                baseURL: URL(
                    string: "https://openai.example/v1"
                )!
            ),
            credentialProvider: TestCredentialProvider(
                value: "openai-token"
            ),
            transport: transport
        )

        XCTAssertTrue(
            provider.capabilities.contains(.streaming)
        )
        XCTAssertTrue(
            provider.capabilities.contains(.toolCalling)
        )
        XCTAssertTrue(
            provider.capabilities.contains(.structuredGeneration)
        )

        var deltas: [String] = []
        var usage: AIUsage?
        var completed: AIResponse?

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
            case .usage(let value):
                usage = value
            case .completed(let response):
                completed = response
            case .toolCall:
                XCTFail("Unexpected tool call")
            }
        }

        XCTAssertEqual(deltas, ["hel", "lo"])
        XCTAssertEqual(completed?.text, "hello")
        XCTAssertEqual(completed?.finishReason, .completed)
        XCTAssertEqual(usage?.inputTokens, 7)
        XCTAssertEqual(usage?.outputTokens, 2)

        let capturedRequest = await transport.lastRequest()
        let bodyData = try XCTUnwrap(
            capturedRequest?.httpBody
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["store"] as? Bool, false)
    }

    func testOpenAIProviderMapsIncompleteMaxOutput() async throws {
        let responseData = """
        {
          "status": "incomplete",
          "output": [
            {
              "type": "message",
              "role": "assistant",
              "content": [
                {
                  "type": "output_text",
                  "text": "partial"
                }
              ]
            }
          ],
          "usage": {
            "input_tokens": 3,
            "output_tokens": 8
          },
          "incomplete_details": {
            "reason": "max_output_tokens"
          },
          "error": null
        }
        """.data(using: .utf8)!

        let provider = OpenAIProvider(
            configuration: OpenAIProviderConfiguration(
                model: "fixture-openai",
                baseURL: URL(
                    string: "https://openai.example/v1"
                )!
            ),
            credentialProvider: TestCredentialProvider(
                value: "openai-token"
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

        XCTAssertEqual(response.text, "partial")
        XCTAssertEqual(
            response.finishReason,
            .maxOutputReached
        )
    }
}


private struct StructuredContactFixture:
    Decodable,
    Equatable,
    Sendable
{
    let name: String
    let age: Int
}

extension AICoreKitTests {
    func testStructuredOutputSchemaRejectsNonObjectJSON() {
        XCTAssertThrowsError(
            try AIStructuredOutputSchema(
                name: "invalid",
                schemaJSON: "[1, 2, 3]"
            )
        )
    }

    func testOpenAIProviderGeneratesNativeStructuredOutput() async throws {
        let responseData = """
        {
          "status": "completed",
          "output": [
            {
              "type": "message",
              "role": "assistant",
              "content": [
                {
                  "type": "output_text",
                  "text": "{\\\"name\\\":\\\"Ada\\\",\\\"age\\\":36}"
                }
              ]
            }
          ],
          "usage": {
            "input_tokens": 12,
            "output_tokens": 8
          },
          "incomplete_details": null,
          "error": null
        }
        """.data(using: .utf8)!

        let transport = RecordingHTTPTransport(
            response: AIHTTPResponse(
                data: responseData,
                statusCode: 200
            )
        )

        let provider = OpenAIProvider(
            configuration: OpenAIProviderConfiguration(
                model: "fixture-openai",
                baseURL: URL(
                    string: "https://openai.example/v1"
                )!
            ),
            credentialProvider: TestCredentialProvider(
                value: "openai-token"
            ),
            transport: transport
        )

        XCTAssertTrue(
            provider.capabilities.contains(
                .structuredGeneration
            )
        )

        let schema = try AIStructuredOutputSchema(
            name: "contact",
            description: "A contact record",
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "name": {"type": "string"},
                "age": {"type": "integer"}
              },
              "required": ["name", "age"],
              "additionalProperties": false
            }
            """
        )

        let value: StructuredContactFixture =
            try await provider.generateStructured(
                AIStructuredRequest(
                    instructions: "Extract the contact.",
                    input: "Ada is 36.",
                    schema: schema,
                    outputType: StructuredContactFixture.self
                )
            )

        XCTAssertEqual(
            value,
            StructuredContactFixture(
                name: "Ada",
                age: 36
            )
        )

        let capturedRequest = await transport.lastRequest()
        let bodyData = try XCTUnwrap(
            capturedRequest?.httpBody
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )
        let textConfig = try XCTUnwrap(
            body["text"] as? [String: Any]
        )
        let format = try XCTUnwrap(
            textConfig["format"] as? [String: Any]
        )

        XCTAssertEqual(
            format["type"] as? String,
            "json_schema"
        )
        XCTAssertEqual(
            format["name"] as? String,
            "contact"
        )
        XCTAssertEqual(
            format["strict"] as? Bool,
            true
        )
        XCTAssertNotNil(
            format["schema"] as? [String: Any]
        )
    }
}


extension AICoreKitTests {
    func testAnthropicProviderGeneratesNativeStructuredOutput() async throws {
        let responseData = """
        {
          "content": [
            {
              "type": "text",
              "text": "{\\\"name\\\":\\\"Ada\\\",\\\"age\\\":36}"
            }
          ],
          "stop_reason": "end_turn",
          "usage": {
            "input_tokens": 11,
            "output_tokens": 8
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
                    string: "https://anthropic.example/v1"
                )!
            ),
            credentialProvider: TestCredentialProvider(
                value: "anthropic-key"
            ),
            transport: transport
        )

        XCTAssertTrue(
            provider.capabilities.contains(
                .structuredGeneration
            )
        )

        let schema = try AIStructuredOutputSchema(
            name: "contact",
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "name": {"type": "string"},
                "age": {"type": "integer"}
              },
              "required": ["name", "age"],
              "additionalProperties": false
            }
            """
        )

        let value: StructuredContactFixture =
            try await provider.generateStructured(
                AIStructuredRequest(
                    instructions: "Extract the contact.",
                    input: "Ada is 36.",
                    schema: schema,
                    outputType: StructuredContactFixture.self
                )
            )

        XCTAssertEqual(
            value,
            StructuredContactFixture(
                name: "Ada",
                age: 36
            )
        )

        let capturedRequest = await transport.lastRequest()
        let bodyData = try XCTUnwrap(
            capturedRequest?.httpBody
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )
        let outputConfig = try XCTUnwrap(
            body["output_config"] as? [String: Any]
        )
        let format = try XCTUnwrap(
            outputConfig["format"] as? [String: Any]
        )

        XCTAssertEqual(
            format["type"] as? String,
            "json_schema"
        )
        XCTAssertNotNil(
            format["schema"] as? [String: Any]
        )
    }
}


extension AICoreKitTests {
    func testGeminiProviderGeneratesNativeStructuredOutput() async throws {
        let responseData = """
        {
          "status": "completed",
          "steps": [
            {
              "type": "model_output",
              "content": [
                {
                  "type": "text",
                  "text": "{\\\"name\\\":\\\"Ada\\\",\\\"age\\\":36}"
                }
              ]
            }
          ],
          "usage": {
            "total_input_tokens": 10,
            "total_output_tokens": 8,
            "total_tokens": 18
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
                defaultMaxOutputTokens: 192
            ),
            credentialProvider: TestCredentialProvider(
                value: "gemini-key"
            ),
            transport: transport
        )

        XCTAssertTrue(
            provider.capabilities.contains(
                .structuredGeneration
            )
        )

        let schema = try AIStructuredOutputSchema(
            name: "contact",
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "name": {"type": "string"},
                "age": {"type": "integer"}
              },
              "required": ["name", "age"],
              "additionalProperties": false
            }
            """
        )

        let value: StructuredContactFixture =
            try await provider.generateStructured(
                AIStructuredRequest(
                    instructions: "Extract the contact.",
                    input: "Ada is 36.",
                    schema: schema,
                    temperature: 0.2,
                    outputType: StructuredContactFixture.self
                )
            )

        XCTAssertEqual(
            value,
            StructuredContactFixture(
                name: "Ada",
                age: 36
            )
        )

        let capturedRequest = await transport.lastRequest()

        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://gemini.example/v1beta/interactions"
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

        XCTAssertEqual(
            body["model"] as? String,
            "fixture-gemini"
        )
        XCTAssertEqual(
            body["input"] as? String,
            "Ada is 36."
        )
        XCTAssertEqual(
            body["system_instruction"] as? String,
            "Extract the contact."
        )
        XCTAssertEqual(
            body["store"] as? Bool,
            false
        )

        let responseFormat = try XCTUnwrap(
            body["response_format"] as? [String: Any]
        )
        XCTAssertEqual(
            responseFormat["type"] as? String,
            "text"
        )
        XCTAssertEqual(
            responseFormat["mime_type"] as? String,
            "application/json"
        )
        XCTAssertNotNil(
            responseFormat["schema"] as? [String: Any]
        )

        let generationConfig = try XCTUnwrap(
            body["generation_config"] as? [String: Any]
        )
        XCTAssertEqual(
            generationConfig["max_output_tokens"] as? Int,
            192
        )
        XCTAssertEqual(
            generationConfig["temperature"] as? Double,
            0.2
        )
    }
}


extension AICoreKitTests {
    private var weatherToolDefinition: AIToolDefinition {
        AIToolDefinition(
            name: "get_weather",
            description: "Get current weather for a location.",
            inputSchemaJSON: """
            {
              "type": "object",
              "properties": {
                "location": {"type": "string"}
              },
              "required": ["location"],
              "additionalProperties": false
            }
            """
        )
    }

    func testToolDefinitionRejectsNonObjectSchema() {
        let definition = AIToolDefinition(
            name: "invalid",
            description: "Invalid fixture",
            inputSchemaJSON: "[1, 2, 3]"
        )

        XCTAssertThrowsError(
            try definition.parsedInputSchema()
        )
    }

    func testOpenAIProviderNormalizesFunctionCalls() async throws {
        let responseData = """
        {
          "status": "completed",
          "output": [
            {
              "id": "fc_123",
              "call_id": "call_123",
              "type": "function_call",
              "name": "get_weather",
              "arguments": "{\\\"location\\\":\\\"Paris\\\"}"
            }
          ],
          "usage": {
            "input_tokens": 12,
            "output_tokens": 7
          }
        }
        """.data(using: .utf8)!

        let transport = RecordingHTTPTransport(
            response: AIHTTPResponse(
                data: responseData,
                statusCode: 200
            )
        )

        let provider = OpenAIProvider(
            configuration: OpenAIProviderConfiguration(
                model: "fixture-openai",
                baseURL: URL(
                    string: "https://openai.example/v1"
                )!
            ),
            credentialProvider: TestCredentialProvider(
                value: "openai-token"
            ),
            transport: transport
        )

        XCTAssertTrue(
            provider.capabilities.contains(.toolCalling)
        )

        let response = try await provider.generate(
            AIRequest(
                messages: [.user("Weather in Paris?")],
                requiredCapabilities: [
                    .textGeneration,
                    .toolCalling
                ],
                tools: [weatherToolDefinition]
            )
        )

        XCTAssertEqual(
            response.finishReason,
            .toolCallRequested
        )
        XCTAssertEqual(response.toolCalls.count, 1)
        XCTAssertEqual(
            response.toolCalls.first?.id,
            "call_123"
        )
        XCTAssertEqual(
            response.toolCalls.first?.name,
            "get_weather"
        )
        XCTAssertEqual(
            response.toolCalls.first?.argumentsJSON,
            #"{"location":"Paris"}"#
        )

        let request = await transport.lastRequest()
        let bodyData = try XCTUnwrap(request?.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )
        let tools = try XCTUnwrap(
            body["tools"] as? [[String: Any]]
        )
        XCTAssertEqual(
            tools.first?["type"] as? String,
            "function"
        )
        XCTAssertEqual(
            tools.first?["name"] as? String,
            "get_weather"
        )
        XCTAssertNotNil(
            tools.first?["parameters"] as? [String: Any]
        )
    }

    func testAnthropicProviderNormalizesToolUse() async throws {
        let responseData = """
        {
          "content": [
            {
              "type": "tool_use",
              "id": "toolu_123",
              "name": "get_weather",
              "input": {"location": "Paris"}
            }
          ],
          "stop_reason": "tool_use",
          "usage": {
            "input_tokens": 10,
            "output_tokens": 6
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
                    string: "https://anthropic.example/v1"
                )!
            ),
            credentialProvider: TestCredentialProvider(
                value: "anthropic-key"
            ),
            transport: transport
        )

        XCTAssertTrue(
            provider.capabilities.contains(.toolCalling)
        )

        let response = try await provider.generate(
            AIRequest(
                messages: [.user("Weather in Paris?")],
                requiredCapabilities: [
                    .textGeneration,
                    .toolCalling
                ],
                tools: [weatherToolDefinition]
            )
        )

        XCTAssertEqual(
            response.finishReason,
            .toolCallRequested
        )
        XCTAssertEqual(
            response.toolCalls.first?.id,
            "toolu_123"
        )
        XCTAssertEqual(
            response.toolCalls.first?.name,
            "get_weather"
        )
        XCTAssertEqual(
            response.toolCalls.first?.argumentsJSON,
            #"{"location":"Paris"}"#
        )

        let request = await transport.lastRequest()
        let bodyData = try XCTUnwrap(request?.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )
        let tools = try XCTUnwrap(
            body["tools"] as? [[String: Any]]
        )
        XCTAssertEqual(
            tools.first?["name"] as? String,
            "get_weather"
        )
        XCTAssertNotNil(
            tools.first?["input_schema"] as? [String: Any]
        )
    }

    func testGeminiProviderNormalizesFunctionCallSteps() async throws {
        let responseData = """
        {
          "status": "completed",
          "steps": [
            {
              "type": "function_call",
              "id": "call_123",
              "name": "get_weather",
              "arguments": {"location": "Paris"}
            }
          ],
          "usage": {
            "total_input_tokens": 9,
            "total_output_tokens": 5
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
                )!
            ),
            credentialProvider: TestCredentialProvider(
                value: "gemini-key"
            ),
            transport: transport
        )

        XCTAssertTrue(
            provider.capabilities.contains(.toolCalling)
        )

        let response = try await provider.generate(
            AIRequest(
                messages: [.user("Weather in Paris?")],
                requiredCapabilities: [
                    .textGeneration,
                    .toolCalling
                ],
                tools: [weatherToolDefinition]
            )
        )

        XCTAssertEqual(
            response.finishReason,
            .toolCallRequested
        )
        XCTAssertEqual(
            response.toolCalls.first?.id,
            "call_123"
        )
        XCTAssertEqual(
            response.toolCalls.first?.name,
            "get_weather"
        )
        XCTAssertEqual(
            response.toolCalls.first?.argumentsJSON,
            #"{"location":"Paris"}"#
        )

        let request = await transport.lastRequest()
        XCTAssertEqual(
            request?.url?.absoluteString,
            "https://gemini.example/v1beta/interactions"
        )
        let bodyData = try XCTUnwrap(request?.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData)
                as? [String: Any]
        )
        let tools = try XCTUnwrap(
            body["tools"] as? [[String: Any]]
        )
        XCTAssertEqual(
            tools.first?["type"] as? String,
            "function"
        )
        XCTAssertEqual(
            tools.first?["name"] as? String,
            "get_weather"
        )
        XCTAssertNotNil(
            tools.first?["parameters"] as? [String: Any]
        )
        XCTAssertEqual(
            body["store"] as? Bool,
            false
        )
    }
}


private struct ToolLoopStubProvider:
    AIToolContinuingProvider
{
    let id: AIProviderID = "fixture.tool-loop"
    let displayName = "Tool Loop Fixture"
    let capabilities: AICapabilities = [
        .textGeneration,
        .toolCalling,
        .localExecution
    ]

    func availability() async -> AIAvailability {
        .available
    }

    func generate(
        _ request: AIRequest
    ) async throws -> AIResponse {
        AIResponse(
            text: "",
            toolCalls: [
                AIToolCall(
                    id: "call-1",
                    name: "echo",
                    argumentsJSON: #"{"value":"hello"}"#
                )
            ],
            providerID: id,
            finishReason: .toolCallRequested,
            continuation: AIToolContinuation(
                providerID: id,
                opaqueState: "round-1"
            )
        )
    }

    func continueToolCalls(
        _ continuation: AIToolContinuation,
        outputs: [AIToolOutput]
    ) async throws -> AIResponse {
        guard
            continuation.providerID == id,
            continuation.opaqueState == "round-1",
            let output = outputs.first
        else {
            throw AIError.providerFailure(
                providerID: id,
                message: "Invalid fixture continuation"
            )
        }

        return AIResponse(
            text: output.content,
            providerID: id
        )
    }
}

private struct MutatingFixtureTool: AITool {
    let definition = AIToolDefinition(
        name: "mutate",
        description: "Mutating fixture",
        inputSchemaJSON: #"{"type":"object"}"#,
        sideEffectLevel: .localMutation
    )

    func execute(
        argumentsJSON: String
    ) async throws -> AIToolResult {
        AIToolResult(
            toolName: definition.name,
            content: "mutated"
        )
    }
}

private struct MutatingToolLoopStubProvider:
    AIToolContinuingProvider
{
    let id: AIProviderID = "fixture.mutating-loop"
    let displayName = "Mutating Tool Loop Fixture"
    let capabilities: AICapabilities = [
        .textGeneration,
        .toolCalling,
        .localExecution
    ]

    func availability() async -> AIAvailability {
        .available
    }

    func generate(
        _ request: AIRequest
    ) async throws -> AIResponse {
        AIResponse(
            text: "",
            toolCalls: [
                AIToolCall(
                    id: "call-mutate",
                    name: "mutate",
                    argumentsJSON: "{}"
                )
            ],
            providerID: id,
            finishReason: .toolCallRequested,
            continuation: AIToolContinuation(
                providerID: id,
                opaqueState: "round-1"
            )
        )
    }

    func continueToolCalls(
        _ continuation: AIToolContinuation,
        outputs: [AIToolOutput]
    ) async throws -> AIResponse {
        AIResponse(
            text: "unexpected",
            providerID: id
        )
    }
}

extension AICoreKitTests {
    func testOrchestratorRunsReadOnlyToolLoop() async throws {
        let provider = ToolLoopStubProvider()
        let providerRegistry = AIProviderRegistry(
            providers: [provider]
        )
        let orchestrator = DefaultAIOrchestrator(
            registry: providerRegistry
        )

        let toolRegistry = AIToolRegistry(
            tools: [EchoTool()]
        )

        let response = try await orchestrator.respondWithTools(
            to: AIRequest(
                messages: [.user("echo hello")],
                tools: [EchoTool().definition]
            ),
            toolRegistry: toolRegistry
        )

        XCTAssertEqual(
            response.text,
            #"{"value":"hello"}"#
        )
        XCTAssertEqual(
            response.providerID,
            provider.id
        )
    }

    func testOrchestratorBlocksMutatingToolByDefault() async throws {
        let provider = MutatingToolLoopStubProvider()
        let providerRegistry = AIProviderRegistry(
            providers: [provider]
        )
        let orchestrator = DefaultAIOrchestrator(
            registry: providerRegistry
        )
        let toolRegistry = AIToolRegistry(
            tools: [MutatingFixtureTool()]
        )

        do {
            _ = try await orchestrator.respondWithTools(
                to: AIRequest(
                    messages: [.user("mutate")],
                    tools: [
                        MutatingFixtureTool().definition
                    ]
                ),
                toolRegistry: toolRegistry
            )
            XCTFail("Expected execution policy rejection")
        } catch let error as AIError {
            guard
                case .toolExecutionFailed(let message) =
                    error
            else {
                XCTFail("Unexpected AIError: \(error)")
                return
            }

            XCTAssertTrue(
                message.contains("blocked")
            )
        }
    }
}
