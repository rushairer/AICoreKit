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
    let initiallyPrepared: Bool
    let prepareStatus: CoreAIBridgeStatus
    let loadStatus: CoreAIBridgeStatus
    let unloadStatus: CoreAIBridgeStatus
    let clearStatus: CoreAIBridgeStatus

    init(
        initiallyPrepared: Bool = false,
        prepareStatus: CoreAIBridgeStatus = .success,
        loadStatus: CoreAIBridgeStatus = .success,
        unloadStatus: CoreAIBridgeStatus = .success,
        clearStatus: CoreAIBridgeStatus = .success
    ) {
        self.initiallyPrepared = initiallyPrepared
        self.prepareStatus = prepareStatus
        self.loadStatus = loadStatus
        self.unloadStatus = unloadStatus
        self.clearStatus = clearStatus
    }

    func availability() async -> AIAvailability {
        .available
    }

    func generate(
        requestJSON: String,
        modelPath: String
    ) async -> CoreAIBridgeInvocation {
        CoreAIBridgeInvocation(status: .unavailable)
    }

    func isPrepared(modelPath: String) async -> Bool {
        initiallyPrepared
    }

    func prepare(modelPath: String) async -> CoreAIBridgeStatus {
        prepareStatus
    }

    func load(modelPath: String) async -> CoreAIBridgeStatus {
        loadStatus
    }

    func unload(modelPath: String) async -> CoreAIBridgeStatus {
        unloadStatus
    }

    func clearPreparationCache(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        clearStatus
    }
}

extension AICoreKitTests {
    func testCoreAIProviderPreparesAndReleasesResources() async throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let provider = CoreAIProvider(
            bridge: LifecycleStubCoreAIBridge(),
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
import AIDiagnostics
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


private actor SequencedRecordingHTTPTransport:
    AIHTTPTransport
{
    private var responses: [AIHTTPResponse]
    private var requests: [URLRequest] = []

    init(responses: [AIHTTPResponse]) {
        self.responses = responses
    }

    func data(
        for request: URLRequest
    ) async throws -> AIHTTPResponse {
        requests.append(request)

        guard !responses.isEmpty else {
            throw AIError.transportFailure(
                "No fixture response remaining"
            )
        }

        return responses.removeFirst()
    }

    func capturedRequests() -> [URLRequest] {
        requests
    }
}

private struct WeatherFixtureTool: AITool {
    let definition = AIToolDefinition(
        name: "get_weather",
        description: "Get current weather.",
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

    func execute(
        argumentsJSON: String
    ) async throws -> AIToolResult {
        AIToolResult(
            toolName: definition.name,
            content: #"{"temperature":21,"unit":"C"}"#
        )
    }
}

extension AICoreKitTests {
    func testOpenAIProviderContinuesToolLoopStatelessly() async throws {
        let firstResponse = """
        {
          "status": "completed",
          "output": [
            {
              "id": "rs_1",
              "type": "reasoning",
              "summary": []
            },
            {
              "id": "fc_1",
              "call_id": "call_weather",
              "type": "function_call",
              "name": "get_weather",
              "arguments": "{\\\"location\\\":\\\"Paris\\\"}"
            }
          ],
          "usage": {
            "input_tokens": 10,
            "output_tokens": 5
          }
        }
        """.data(using: .utf8)!

        let secondResponse = """
        {
          "status": "completed",
          "output": [
            {
              "id": "msg_2",
              "type": "message",
              "role": "assistant",
              "content": [
                {
                  "type": "output_text",
                  "text": "Paris is 21 C."
                }
              ]
            }
          ],
          "usage": {
            "input_tokens": 22,
            "output_tokens": 6
          }
        }
        """.data(using: .utf8)!

        let transport = SequencedRecordingHTTPTransport(
            responses: [
                AIHTTPResponse(
                    data: firstResponse,
                    statusCode: 200
                ),
                AIHTTPResponse(
                    data: secondResponse,
                    statusCode: 200
                )
            ]
        )

        let provider = OpenAIProvider(
            configuration: OpenAIProviderConfiguration(
                model: "fixture-openai",
                baseURL: URL(
                    string: "https://openai.example/v1"
                )!,
                storeResponses: false
            ),
            credentialProvider: TestCredentialProvider(
                value: "openai-token"
            ),
            transport: transport
        )

        let providerRegistry = AIProviderRegistry(
            providers: [provider]
        )
        let orchestrator = DefaultAIOrchestrator(
            registry: providerRegistry
        )
        let tool = WeatherFixtureTool()
        let toolRegistry = AIToolRegistry(
            tools: [tool]
        )

        let response = try await orchestrator.respondWithTools(
            to: AIRequest(
                messages: [
                    .user("What is the weather in Paris?")
                ],
                tools: [tool.definition]
            ),
            toolRegistry: toolRegistry
        )

        XCTAssertEqual(
            response.text,
            "Paris is 21 C."
        )
        XCTAssertEqual(
            response.providerID,
            .openAI
        )
        XCTAssertNil(response.continuation)

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)

        let secondBodyData = try XCTUnwrap(
            requests.last?.httpBody
        )
        let secondBody = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: secondBodyData
            ) as? [String: Any]
        )

        XCTAssertEqual(
            secondBody["store"] as? Bool,
            false
        )

        let input = try XCTUnwrap(
            secondBody["input"] as? [[String: Any]]
        )

        XCTAssertEqual(input.count, 4)
        XCTAssertEqual(
            input[1]["type"] as? String,
            "reasoning"
        )
        XCTAssertEqual(
            input[2]["type"] as? String,
            "function_call"
        )
        XCTAssertEqual(
            input[3]["type"] as? String,
            "function_call_output"
        )
        XCTAssertEqual(
            input[3]["call_id"] as? String,
            "call_weather"
        )
        XCTAssertEqual(
            input[3]["output"] as? String,
            #"{"temperature":21,"unit":"C"}"#
        )
    }
}


extension AICoreKitTests {
    func testAnthropicProviderContinuesToolLoopStatelessly() async throws {
        let firstResponse = """
        {
          "content": [
            {
              "type": "text",
              "text": "I will check."
            },
            {
              "type": "tool_use",
              "id": "toolu_weather",
              "name": "get_weather",
              "input": {"location": "Paris"}
            }
          ],
          "stop_reason": "tool_use",
          "usage": {
            "input_tokens": 9,
            "output_tokens": 5
          }
        }
        """.data(using: .utf8)!

        let secondResponse = """
        {
          "content": [
            {
              "type": "text",
              "text": "Paris is 21 C."
            }
          ],
          "stop_reason": "end_turn",
          "usage": {
            "input_tokens": 18,
            "output_tokens": 6
          }
        }
        """.data(using: .utf8)!

        let transport = SequencedRecordingHTTPTransport(
            responses: [
                AIHTTPResponse(
                    data: firstResponse,
                    statusCode: 200
                ),
                AIHTTPResponse(
                    data: secondResponse,
                    statusCode: 200
                )
            ]
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

        let providerRegistry = AIProviderRegistry(
            providers: [provider]
        )
        let orchestrator = DefaultAIOrchestrator(
            registry: providerRegistry
        )
        let tool = WeatherFixtureTool()
        let toolRegistry = AIToolRegistry(
            tools: [tool]
        )

        let response = try await orchestrator.respondWithTools(
            to: AIRequest(
                messages: [
                    .user("What is the weather in Paris?")
                ],
                tools: [tool.definition]
            ),
            toolRegistry: toolRegistry
        )

        XCTAssertEqual(
            response.text,
            "Paris is 21 C."
        )
        XCTAssertEqual(
            response.providerID,
            .anthropic
        )
        XCTAssertNil(response.continuation)

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)

        let secondBodyData = try XCTUnwrap(
            requests.last?.httpBody
        )
        let secondBody = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: secondBodyData
            ) as? [String: Any]
        )

        let messages = try XCTUnwrap(
            secondBody["messages"] as? [[String: Any]]
        )
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(
            messages[1]["role"] as? String,
            "assistant"
        )
        XCTAssertEqual(
            messages[2]["role"] as? String,
            "user"
        )

        let assistantContent = try XCTUnwrap(
            messages[1]["content"] as? [[String: Any]]
        )
        XCTAssertEqual(
            assistantContent.last?["type"] as? String,
            "tool_use"
        )

        let toolResults = try XCTUnwrap(
            messages[2]["content"] as? [[String: Any]]
        )
        XCTAssertEqual(
            toolResults.first?["type"] as? String,
            "tool_result"
        )
        XCTAssertEqual(
            toolResults.first?["tool_use_id"] as? String,
            "toolu_weather"
        )
        XCTAssertEqual(
            toolResults.first?["is_error"] as? Bool,
            false
        )
        XCTAssertEqual(
            toolResults.first?["content"] as? String,
            #"{"temperature":21,"unit":"C"}"#
        )
    }
}


extension AICoreKitTests {
    func testGeminiProviderContinuesToolLoopStatelessly() async throws {
        let firstResponse = """
        {
          "status": "completed",
          "steps": [
            {
              "type": "thought",
              "signature": "thought-signature",
              "summary": [
                {
                  "type": "text",
                  "text": "Need weather data."
                }
              ]
            },
            {
              "type": "function_call",
              "id": "call_weather",
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

        let secondResponse = """
        {
          "status": "completed",
          "steps": [
            {
              "type": "model_output",
              "content": [
                {
                  "type": "text",
                  "text": "Paris is 21 C."
                }
              ]
            }
          ],
          "usage": {
            "total_input_tokens": 20,
            "total_output_tokens": 6
          }
        }
        """.data(using: .utf8)!

        let transport = SequencedRecordingHTTPTransport(
            responses: [
                AIHTTPResponse(
                    data: firstResponse,
                    statusCode: 200
                ),
                AIHTTPResponse(
                    data: secondResponse,
                    statusCode: 200
                )
            ]
        )

        let provider = GeminiProvider(
            configuration: GeminiProviderConfiguration(
                model: "fixture-gemini",
                baseURL: URL(
                    string: "https://gemini.example"
                )!,
                storeInteractions: false
            ),
            credentialProvider: TestCredentialProvider(
                value: "gemini-key"
            ),
            transport: transport
        )

        let providerRegistry = AIProviderRegistry(
            providers: [provider]
        )
        let orchestrator = DefaultAIOrchestrator(
            registry: providerRegistry
        )
        let tool = WeatherFixtureTool()
        let toolRegistry = AIToolRegistry(
            tools: [tool]
        )

        let response = try await orchestrator.respondWithTools(
            to: AIRequest(
                messages: [
                    .user("What is the weather in Paris?")
                ],
                tools: [tool.definition]
            ),
            toolRegistry: toolRegistry
        )

        XCTAssertEqual(
            response.text,
            "Paris is 21 C."
        )
        XCTAssertEqual(
            response.providerID,
            .gemini
        )
        XCTAssertNil(response.continuation)

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)

        let secondBodyData = try XCTUnwrap(
            requests.last?.httpBody
        )
        let secondBody = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: secondBodyData
            ) as? [String: Any]
        )

        XCTAssertEqual(
            secondBody["store"] as? Bool,
            false
        )
        XCTAssertNotNil(
            secondBody["tools"] as? [[String: Any]]
        )

        let input = try XCTUnwrap(
            secondBody["input"] as? [[String: Any]]
        )

        XCTAssertEqual(input.count, 4)
        XCTAssertEqual(
            input[0]["type"] as? String,
            "user_input"
        )
        XCTAssertEqual(
            input[1]["type"] as? String,
            "thought"
        )
        XCTAssertEqual(
            input[1]["signature"] as? String,
            "thought-signature"
        )
        XCTAssertEqual(
            input[2]["type"] as? String,
            "function_call"
        )
        XCTAssertEqual(
            input[2]["id"] as? String,
            "call_weather"
        )
        XCTAssertEqual(
            input[3]["type"] as? String,
            "function_result"
        )
        XCTAssertEqual(
            input[3]["call_id"] as? String,
            "call_weather"
        )
        XCTAssertEqual(
            input[3]["name"] as? String,
            "get_weather"
        )
        XCTAssertEqual(
            input[3]["is_error"] as? Bool,
            false
        )

        let result = try XCTUnwrap(
            input[3]["result"] as? [[String: Any]]
        )
        XCTAssertEqual(
            result.first?["type"] as? String,
            "text"
        )
        XCTAssertEqual(
            result.first?["text"] as? String,
            #"{"temperature":21,"unit":"C"}"#
        )
    }
}


private actor RecordingToolConfirmationProvider:
    AIToolConfirmationProviding
{
    private let decision:
        AIToolConfirmationDecision
    private var requests:
        [AIToolExecutionRequest] = []

    init(
        decision: AIToolConfirmationDecision
    ) {
        self.decision = decision
    }

    func confirm(
        _ request: AIToolExecutionRequest
    ) async throws -> AIToolConfirmationDecision {
        requests.append(request)
        return decision
    }

    func capturedRequests()
        -> [AIToolExecutionRequest]
    {
        requests
    }
}

extension AICoreKitTests {
    func testConfirmingPolicyExecutesApprovedMutation() async throws {
        let provider =
            MutatingToolLoopStubProvider()
        let providerRegistry = AIProviderRegistry(
            providers: [provider]
        )
        let orchestrator = DefaultAIOrchestrator(
            registry: providerRegistry
        )
        let tool = MutatingFixtureTool()
        let toolRegistry = AIToolRegistry(
            tools: [tool]
        )
        let confirmation =
            RecordingToolConfirmationProvider(
                decision: .approved
            )

        let response = try await orchestrator.respondWithTools(
            to: AIRequest(
                messages: [.user("mutate")],
                tools: [tool.definition]
            ),
            toolRegistry: toolRegistry,
            executionPolicy:
                UserConfirmationAIToolExecutionPolicy(),
            confirmationProvider: confirmation
        )

        XCTAssertEqual(
            response.text,
            "unexpected"
        )

        let requests =
            await confirmation.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests.first?.call.id,
            "call-mutate"
        )
        XCTAssertEqual(
            requests.first?.definition.sideEffectLevel,
            .localMutation
        )
    }

    func testConfirmingPolicyRejectsDeniedMutation() async throws {
        let provider =
            MutatingToolLoopStubProvider()
        let providerRegistry = AIProviderRegistry(
            providers: [provider]
        )
        let orchestrator = DefaultAIOrchestrator(
            registry: providerRegistry
        )
        let tool = MutatingFixtureTool()
        let toolRegistry = AIToolRegistry(
            tools: [tool]
        )
        let confirmation =
            RecordingToolConfirmationProvider(
                decision: .denied
            )

        do {
            _ = try await orchestrator.respondWithTools(
                to: AIRequest(
                    messages: [.user("mutate")],
                    tools: [tool.definition]
                ),
                toolRegistry: toolRegistry,
                executionPolicy:
                    UserConfirmationAIToolExecutionPolicy(),
                confirmationProvider: confirmation
            )
            XCTFail(
                "Expected confirmation denial"
            )
        } catch let error as AIError {
            XCTAssertEqual(
                error,
                .toolConfirmationDenied(
                    toolName: "mutate",
                    callID: "call-mutate"
                )
            )
        }
    }

    func testConfirmingPolicyReportsMissingConfirmationProvider() async throws {
        let provider =
            MutatingToolLoopStubProvider()
        let providerRegistry = AIProviderRegistry(
            providers: [provider]
        )
        let orchestrator = DefaultAIOrchestrator(
            registry: providerRegistry
        )
        let tool = MutatingFixtureTool()
        let toolRegistry = AIToolRegistry(
            tools: [tool]
        )

        do {
            _ = try await orchestrator.respondWithTools(
                to: AIRequest(
                    messages: [.user("mutate")],
                    tools: [tool.definition]
                ),
                toolRegistry: toolRegistry,
                executionPolicy:
                    UserConfirmationAIToolExecutionPolicy()
            )
            XCTFail(
                "Expected confirmation requirement"
            )
        } catch let error as AIError {
            XCTAssertEqual(
                error,
                .toolConfirmationRequired(
                    toolName: "mutate",
                    callID: "call-mutate"
                )
            )
        }
    }

    func testConfirmingPolicyDoesNotPromptForReadOnlyTool() async throws {
        let provider = ToolLoopStubProvider()
        let providerRegistry = AIProviderRegistry(
            providers: [provider]
        )
        let orchestrator = DefaultAIOrchestrator(
            registry: providerRegistry
        )
        let tool = EchoTool()
        let toolRegistry = AIToolRegistry(
            tools: [tool]
        )
        let confirmation =
            RecordingToolConfirmationProvider(
                decision: .denied
            )

        let response = try await orchestrator.respondWithTools(
            to: AIRequest(
                messages: [.user("echo hello")],
                tools: [tool.definition]
            ),
            toolRegistry: toolRegistry,
            executionPolicy:
                UserConfirmationAIToolExecutionPolicy(),
            confirmationProvider: confirmation
        )

        XCTAssertEqual(
            response.text,
            #"{"value":"hello"}"#
        )

        let requests =
            await confirmation.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }
}


private actor RecordingAIHTTPObserver:
    AIHTTPObserver
{
    private var events:
        [AIHTTPObservationEvent] = []

    func record(
        _ event: AIHTTPObservationEvent
    ) async {
        events.append(event)
    }

    func capturedEvents()
        -> [AIHTTPObservationEvent]
    {
        events
    }
}

extension AICoreKitTests {
    func testClosureCredentialProviderCanResolveGatewayToken() async throws {
        let credentials =
            ClosureAICredentialProvider {
                request in

                XCTAssertEqual(
                    request.providerID,
                    "fixture.gateway"
                )
                XCTAssertEqual(
                    request.kind,
                    .bearerToken
                )
                return "short-lived-token"
            }

        let value = try await credentials.credential(
            for: AICredentialRequest(
                providerID: "fixture.gateway",
                kind: .bearerToken
            )
        )

        XCTAssertEqual(
            value,
            "short-lived-token"
        )
    }

    func testObservingHTTPTransportEmitsSanitizedMetadata() async throws {
        let base = RecordingHTTPTransport(
            response: AIHTTPResponse(
                data: Data("ok".utf8),
                statusCode: 200
            )
        )
        let observer =
            RecordingAIHTTPObserver()
        let transport = ObservingAIHTTPTransport(
            base: base,
            observer: observer
        )

        var request = URLRequest(
            url: URL(
                string:
                    "https://gateway.example/v1/ai?secret=hidden"
            )!
        )
        request.httpMethod = "POST"
        request.setValue(
            "Bearer secret-token",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = Data(
            #"{"private":"payload"}"#.utf8
        )

        _ = try await transport.data(
            for: request
        )

        let events =
            await observer.capturedEvents()
        XCTAssertEqual(events.count, 2)

        guard
            case .started(let started) =
                events[0]
        else {
            XCTFail("Expected start event")
            return
        }

        XCTAssertEqual(
            started.operation,
            .data
        )
        XCTAssertEqual(
            started.method,
            "POST"
        )
        XCTAssertEqual(
            started.scheme,
            "https"
        )
        XCTAssertEqual(
            started.host,
            "gateway.example"
        )
        XCTAssertEqual(
            started.path,
            "/v1/ai"
        )

        guard
            case .response(let completed) =
                events[1]
        else {
            XCTFail("Expected response event")
            return
        }

        XCTAssertEqual(
            completed.request.requestID,
            started.requestID
        )
        XCTAssertEqual(
            completed.statusCode,
            200
        )
        XCTAssertGreaterThanOrEqual(
            completed.durationSeconds,
            0
        )
    }
}


private enum RetryFixtureOutcome:
    Sendable
{
    case response(AIHTTPResponse)
    case failure(AIHTTPTransportError)
}

private actor SequencedRetryHTTPTransport:
    AIHTTPTransport
{
    private var outcomes:
        [RetryFixtureOutcome]
    private var count = 0

    init(
        outcomes: [RetryFixtureOutcome]
    ) {
        self.outcomes = outcomes
    }

    func data(
        for request: URLRequest
    ) async throws -> AIHTTPResponse {
        count += 1

        guard !outcomes.isEmpty else {
            throw AIHTTPTransportError
                .invalidResponse
        }

        switch outcomes.removeFirst() {
        case .response(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    func requestCount() -> Int {
        count
    }
}

private actor RecordingAIHTTPSleeper:
    AIHTTPSleeping
{
    private var delays:
        [TimeInterval] = []

    func sleep(
        for seconds: TimeInterval
    ) async throws {
        delays.append(seconds)
    }

    func capturedDelays()
        -> [TimeInterval]
    {
        delays
    }
}

extension AICoreKitTests {
    func testRetryingHTTPTransportRetriesTransientStatusAndHonorsRetryAfter() async throws {
        let base = SequencedRetryHTTPTransport(
            outcomes: [
                .response(
                    AIHTTPResponse(
                        data: Data(),
                        statusCode: 503,
                        headers: [
                            "Retry-After": "2"
                        ]
                    )
                ),
                .response(
                    AIHTTPResponse(
                        data: Data("ok".utf8),
                        statusCode: 200
                    )
                )
            ]
        )
        let sleeper =
            RecordingAIHTTPSleeper()
        let transport =
            RetryingAIHTTPTransport(
                base: base,
                policy: AIHTTPRetryPolicy(
                    maximumAttempts: 3,
                    baseDelaySeconds: 0.1,
                    maximumDelaySeconds: 5
                ),
                sleeper: sleeper
            )

        let response = try await transport.data(
            for: URLRequest(
                url: URL(
                    string:
                        "https://gateway.example/v1/ai"
                )!
            )
        )

        XCTAssertEqual(
            response.statusCode,
            200
        )
        let requestCount =
            await base.requestCount()
        let delays =
            await sleeper.capturedDelays()

        XCTAssertEqual(
            requestCount,
            2
        )
        XCTAssertEqual(
            delays,
            [2]
        )
    }

    func testRetryingHTTPTransportDoesNotRetryAmbiguousTransportErrorsByDefault() async throws {
        let base = SequencedRetryHTTPTransport(
            outcomes: [
                .failure(.invalidResponse),
                .response(
                    AIHTTPResponse(
                        data: Data(),
                        statusCode: 200
                    )
                )
            ]
        )
        let transport =
            RetryingAIHTTPTransport(
                base: base,
                policy: AIHTTPRetryPolicy(
                    maximumAttempts: 3,
                    baseDelaySeconds: 0
                ),
                sleeper:
                    RecordingAIHTTPSleeper()
            )

        do {
            _ = try await transport.data(
                for: URLRequest(
                    url: URL(
                        string:
                            "https://gateway.example/v1/ai"
                    )!
                )
            )
            XCTFail(
                "Expected transport error"
            )
        } catch let error as AIHTTPTransportError {
            XCTAssertEqual(
                error,
                .invalidResponse
            )
        }

        let requestCount =
            await base.requestCount()

        XCTAssertEqual(
            requestCount,
            1
        )
    }

    func testRetryingHTTPTransportCanExplicitlyRetryTransportErrors() async throws {
        let base = SequencedRetryHTTPTransport(
            outcomes: [
                .failure(.invalidResponse),
                .response(
                    AIHTTPResponse(
                        data: Data("ok".utf8),
                        statusCode: 200
                    )
                )
            ]
        )
        let sleeper =
            RecordingAIHTTPSleeper()
        let transport =
            RetryingAIHTTPTransport(
                base: base,
                policy: AIHTTPRetryPolicy(
                    maximumAttempts: 2,
                    retryTransportErrors: true,
                    baseDelaySeconds: 0
                ),
                sleeper: sleeper
            )

        let response = try await transport.data(
            for: URLRequest(
                url: URL(
                    string:
                        "https://gateway.example/v1/ai"
                )!
            )
        )

        XCTAssertEqual(
            response.statusCode,
            200
        )
        let requestCount =
            await base.requestCount()
        let delays =
            await sleeper.capturedDelays()

        XCTAssertEqual(
            requestCount,
            2
        )
        XCTAssertEqual(
            delays,
            [0]
        )
    }
}


private actor RecordingCoreAILifecycleBridge:
    CoreAIModelLifecycleBridge
{
    private var prepared: Bool
    private(set) var prepareCount = 0
    private(set) var loadCount = 0
    private(set) var unloadCount = 0
    private(set) var clearCount = 0

    init(prepared: Bool) {
        self.prepared = prepared
    }

    func availability() async -> AIAvailability {
        .available
    }

    func generate(
        requestJSON: String,
        modelPath: String
    ) async -> CoreAIBridgeInvocation {
        CoreAIBridgeInvocation(
            status: .unavailable
        )
    }

    func isPrepared(
        modelPath: String
    ) async -> Bool {
        prepared
    }

    func prepare(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        prepareCount += 1
        try? await Task.sleep(
            nanoseconds: 20_000_000
        )
        prepared = true
        return .success
    }

    func load(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        loadCount += 1
        try? await Task.sleep(
            nanoseconds: 20_000_000
        )
        return .success
    }

    func unload(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        unloadCount += 1
        return .success
    }

    func clearPreparationCache(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        clearCount += 1
        prepared = false
        return .success
    }

    func counts()
        -> (
            prepare: Int,
            load: Int,
            unload: Int,
            clear: Int
        )
    {
        (
            prepareCount,
            loadCount,
            unloadCount,
            clearCount
        )
    }
}

extension AICoreKitTests {
    func testCoreAILifecycleDistinguishesPreparedFromReady() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let bridge =
            RecordingCoreAILifecycleBridge(
                prepared: true
            )
        let controller =
            CoreAIModelLifecycleController(
                bridge: bridge,
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        let initial =
            await controller.currentState()
        XCTAssertEqual(
            initial,
            .prepared
        )

        let bootstrapped =
            try await controller
                .bootstrapIfPrepared()
        XCTAssertTrue(bootstrapped)
        let readyState =
            await controller.currentState()
        XCTAssertEqual(
            readyState,
            .ready
        )

        let counts =
            await bridge.counts()
        XCTAssertEqual(
            counts.prepare,
            0
        )
        XCTAssertEqual(
            counts.load,
            1
        )
    }

    func testCoreAIBootstrapNeverTriggersFirstPreparation() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let bridge =
            RecordingCoreAILifecycleBridge(
                prepared: false
            )
        let controller =
            CoreAIModelLifecycleController(
                bridge: bridge,
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        let bootstrapped =
            try await controller
                .bootstrapIfPrepared()

        XCTAssertFalse(bootstrapped)
        let bootstrapState =
            await controller.currentState()
        XCTAssertEqual(
            bootstrapState,
            .notPrepared
        )

        let counts =
            await bridge.counts()
        XCTAssertEqual(
            counts.prepare,
            0
        )
        XCTAssertEqual(
            counts.load,
            0
        )
    }

    func testCoreAILifecycleCoalescesConcurrentFirstUse() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let bridge =
            RecordingCoreAILifecycleBridge(
                prepared: false
            )
        let controller =
            CoreAIModelLifecycleController(
                bridge: bridge,
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        async let first: Void =
            controller.ensureReady()
        async let second: Void =
            controller.ensureReady()

        _ = try await (
            first,
            second
        )

        let counts =
            await bridge.counts()
        XCTAssertEqual(
            counts.prepare,
            1
        )
        XCTAssertEqual(
            counts.load,
            1
        )
        let coalescedState =
            await controller.currentState()
        XCTAssertEqual(
            coalescedState,
            .ready
        )
    }

    func testCoreAIExplicitPreparationCoalescesConcurrentRequests() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let bridge =
            RecordingCoreAILifecycleBridge(
                prepared: false
            )
        let controller =
            CoreAIModelLifecycleController(
                bridge: bridge,
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        async let first: Void =
            controller
            .preparePersistentResources()
        async let second: Void =
            controller
            .preparePersistentResources()

        _ = try await (
            first,
            second
        )

        let counts =
            await bridge.counts()
        XCTAssertEqual(
            counts.prepare,
            1
        )
        XCTAssertEqual(
            counts.load,
            0
        )

        let state =
            await controller.currentState()
        XCTAssertEqual(
            state,
            .prepared
        )
    }

    func testCoreAIEnsureReadyJoinsExplicitPreparationThenLoadsOnce() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let bridge =
            RecordingCoreAILifecycleBridge(
                prepared: false
            )
        let controller =
            CoreAIModelLifecycleController(
                bridge: bridge,
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        let preparation =
            Task {
                try await controller
                    .preparePersistentResources()
            }

        try await Task.sleep(
            nanoseconds: 5_000_000
        )

        let readiness =
            Task {
                try await controller
                    .ensureReady()
            }

        try await preparation.value
        try await readiness.value

        let counts =
            await bridge.counts()
        XCTAssertEqual(
            counts.prepare,
            1
        )
        XCTAssertEqual(
            counts.load,
            1
        )

        let state =
            await controller.currentState()
        XCTAssertEqual(
            state,
            .ready
        )
    }

    func testCoreAIExplicitLoadCoalescesConcurrentRequests() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let bridge =
            RecordingCoreAILifecycleBridge(
                prepared: true
            )
        let controller =
            CoreAIModelLifecycleController(
                bridge: bridge,
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        async let first: Void =
            controller
            .loadPreparedResources()
        async let second: Void =
            controller
            .loadPreparedResources()

        _ = try await (
            first,
            second
        )

        let counts =
            await bridge.counts()
        XCTAssertEqual(
            counts.prepare,
            0
        )
        XCTAssertEqual(
            counts.load,
            1
        )

        let state =
            await controller.currentState()
        XCTAssertEqual(
            state,
            .ready
        )
    }

    func testCoreAIClearPreparationCacheKeepsLifecycleDistinct() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let bridge =
            RecordingCoreAILifecycleBridge(
                prepared: true
            )
        let controller =
            CoreAIModelLifecycleController(
                bridge: bridge,
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        _ = try await controller
            .bootstrapIfPrepared()
        try await controller
            .clearPreparationCache()

        let clearedState =
            await controller.currentState()
        let isPrepared =
            await controller
                .isPersistentlyPrepared()
        XCTAssertEqual(
            clearedState,
            .notPrepared
        )
        XCTAssertFalse(
            isPrepared
        )

        let counts =
            await bridge.counts()
        XCTAssertEqual(
            counts.load,
            1
        )
        XCTAssertEqual(
            counts.clear,
            1
        )
    }
}


private actor SlowNonCancellingCoreAILifecycleBridge:
    CoreAIModelLifecycleBridge
{
    private var prepared = false
    private(set) var prepareCount = 0
    private(set) var loadCount = 0
    private(set) var unloadCount = 0
    private(set) var clearCount = 0

    func availability() async -> AIAvailability {
        .available
    }

    func generate(
        requestJSON: String,
        modelPath: String
    ) async -> CoreAIBridgeInvocation {
        CoreAIBridgeInvocation(
            status: .unavailable
        )
    }

    func isPrepared(
        modelPath: String
    ) async -> Bool {
        prepared
    }

    func prepare(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        prepareCount += 1

        // Intentionally ignore cancellation to model a bridge operation
        // whose native callback arrives after reset was requested.
        try? await Task.sleep(
            nanoseconds: 80_000_000
        )

        prepared = true
        return .success
    }

    func load(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        loadCount += 1
        return .success
    }

    func unload(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        unloadCount += 1
        return .success
    }

    func clearPreparationCache(
        modelPath: String
    ) async -> CoreAIBridgeStatus {
        clearCount += 1
        prepared = false
        return .success
    }

    func snapshot()
        -> (
            prepared: Bool,
            prepare: Int,
            load: Int,
            unload: Int,
            clear: Int
        )
    {
        (
            prepared,
            prepareCount,
            loadCount,
            unloadCount,
            clearCount
        )
    }
}

extension AICoreKitTests {
    func testCoreAIClearInvalidatesLatePreparationCompletion() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let bridge =
            SlowNonCancellingCoreAILifecycleBridge()
        let controller =
            CoreAIModelLifecycleController(
                bridge: bridge,
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        let readiness = Task {
            try await controller.ensureReady()
        }

        try await Task.sleep(
            nanoseconds: 10_000_000
        )

        try await controller
            .clearPreparationCache()

        do {
            try await readiness.value
            XCTFail(
                "Expected invalidated readiness to be cancelled"
            )
        } catch let error as AIError {
            XCTAssertEqual(
                error,
                .cancelled
            )
        }

        let lifecycleState =
            await controller.currentState()
        XCTAssertEqual(
            lifecycleState,
            .notPrepared
        )

        let snapshot =
            await bridge.snapshot()
        XCTAssertFalse(
            snapshot.prepared
        )
        XCTAssertEqual(
            snapshot.prepare,
            1
        )
        XCTAssertEqual(
            snapshot.load,
            0
        )
        XCTAssertEqual(
            snapshot.clear,
            1
        )
    }
}


extension AICoreKitTests {
    func testCoreAILifecycleStateChangesReachMultipleSubscribers() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let bridge =
            RecordingCoreAILifecycleBridge(
                prepared: true
            )
        let controller =
            CoreAIModelLifecycleController(
                bridge: bridge,
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        let preparedState =
            await controller.currentState()
        XCTAssertEqual(
            preparedState,
            .prepared
        )

        let firstStream =
            await controller.stateChanges()
        let secondStream =
            await controller.stateChanges()

        let bootstrapped =
            try await controller
                .bootstrapIfPrepared()
        XCTAssertTrue(bootstrapped)

        var firstIterator =
            firstStream.makeAsyncIterator()
        var secondIterator =
            secondStream.makeAsyncIterator()

        var firstStates:
            [CoreAIModelLifecycleState] = []
        var secondStates:
            [CoreAIModelLifecycleState] = []

        for _ in 0..<3 {
            if let first =
                await firstIterator.next()
            {
                firstStates.append(first)
            }

            if let second =
                await secondIterator.next()
            {
                secondStates.append(second)
            }
        }

        XCTAssertEqual(
            firstStates,
            [
                .prepared,
                .loading,
                .ready
            ]
        )
        XCTAssertEqual(
            secondStates,
            firstStates
        )
    }
}


extension AICoreKitTests {
    func testCoreAIEnsureReadyPublishesFailedWhenFirstPreparationFails() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let controller =
            CoreAIModelLifecycleController(
                bridge:
                    LifecycleStubCoreAIBridge(
                        initiallyPrepared:
                            false,
                        prepareStatus:
                            .modelLoadFailed
                    ),
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        let stream =
            await controller.stateChanges()

        do {
            try await controller
                .ensureReady()
            XCTFail(
                "Expected first preparation to fail"
            )
        } catch let error as AIError {
            switch error {
            case .unavailable(
                .modelNotReady
            ):
                break
            default:
                XCTFail(
                    "Unexpected error: \(error)"
                )
            }
        }

        var iterator =
            stream.makeAsyncIterator()
        var states:
            [CoreAIModelLifecycleState] = []

        for _ in 0..<3 {
            if let value =
                await iterator.next()
            {
                states.append(value)
            }
        }

        XCTAssertEqual(
            states,
            [
                .notPrepared,
                .preparing,
                .failed
            ]
        )
    }
}


extension AICoreKitTests {
    func testCoreAIUnloadFailurePublishesFailedState() async throws {
        let temporaryURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )
        try Data().write(
            to: temporaryURL
        )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryURL
                )
        }

        let controller =
            CoreAIModelLifecycleController(
                bridge:
                    LifecycleStubCoreAIBridge(
                        initiallyPrepared:
                            true,
                        unloadStatus:
                            .modelLoadFailed
                    ),
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource:
                            CoreAIModelResource(
                                identifier:
                                    "fixture",
                                path:
                                    temporaryURL.path
                            )
                    )
            )

        _ = try await controller
            .bootstrapIfPrepared()

        let stream =
            await controller.stateChanges()

        do {
            try await controller.unload()
            XCTFail(
                "Expected unload to fail"
            )
        } catch let error as AIError {
            switch error {
            case .unavailable(
                .modelNotReady
            ):
                break
            default:
                XCTFail(
                    "Unexpected error: \(error)"
                )
            }
        }

        var iterator =
            stream.makeAsyncIterator()
        var states:
            [CoreAIModelLifecycleState] = []

        for _ in 0..<2 {
            if let value =
                await iterator.next()
            {
                states.append(value)
            }
        }

        XCTAssertEqual(
            states,
            [
                .ready,
                .failed
            ]
        )

        // A later explicit refresh may recover to the still-persistently
        // prepared state. The important contract is that the failed
        // operation itself is observable.
        let refreshedState =
            await controller.currentState()
        XCTAssertEqual(
            refreshedState,
            .prepared
        )
    }
}


private actor DiagnosticFixtureState {
    private(set) var prepareCount = 0
    private(set) var releaseCount = 0

    func prepared() {
        prepareCount += 1
    }

    func released() {
        releaseCount += 1
    }

    func counts() -> (Int, Int) {
        (
            prepareCount,
            releaseCount
        )
    }
}

private struct DiagnosticFixtureProvider:
    AIProvider,
    AIResourceManaging
{
    let state:
        DiagnosticFixtureState
    let generationDelayNanoseconds:
        UInt64

    let id:
        AIProviderID =
            "fixture.diagnostics"
    let displayName =
        "Diagnostics Fixture"
    let capabilities:
        AICapabilities = [
            .textGeneration,
            .localExecution
        ]

    func availability()
        async -> AIAvailability
    {
        .available
    }

    func prepareResources()
        async throws
    {
        await state.prepared()
    }

    func releaseResources()
        async throws
    {
        await state.released()
    }

    func generate(
        _ request: AIRequest
    ) async throws -> AIResponse {
        if generationDelayNanoseconds > 0 {
            try await Task.sleep(
                nanoseconds:
                    generationDelayNanoseconds
            )
        }

        try Task.checkCancellation()

        return AIResponse(
            text: "ok",
            providerID: id
        )
    }
}

extension AICoreKitTests {
    func testDeviceValidationRunnerCapturesLifecycleAndCancellation() async throws {
        let state =
            DiagnosticFixtureState()
        let provider =
            DiagnosticFixtureProvider(
                state: state,
                generationDelayNanoseconds:
                    100_000_000
            )

        let report =
            await AIDeviceValidationRunner()
                .run(
                    provider: provider,
                    request:
                        AIRequest(
                            messages: [
                                .user("hello")
                            ]
                        ),
                    cancellationProbe:
                        AICancellationProbe(
                            request:
                                AIRequest(
                                    messages: [
                                        .user(
                                            "cancel me"
                                        )
                                    ]
                                ),
                            delayMilliseconds: 5
                        )
                )

        XCTAssertEqual(
            report.providerID,
            provider.id
        )

        XCTAssertEqual(
            report.steps.map(\.operation),
            [
                .availability,
                .prepareResources,
                .generate,
                .cancellationProbe,
                .releaseResources
            ]
        )

        XCTAssertEqual(
            report.steps.map(\.status),
            [
                .succeeded,
                .succeeded,
                .succeeded,
                .cancelled,
                .succeeded
            ]
        )

        let counts =
            await state.counts()
        XCTAssertEqual(
            counts.0,
            1
        )
        XCTAssertEqual(
            counts.1,
            1
        )

        let json =
            try report.jsonString()
        XCTAssertTrue(
            json.contains(
                "fixture.diagnostics"
            )
        )
    }

    func testDeviceValidationRunnerStopsAfterUnavailableProvider() async {
        let provider =
            StubProvider(
                id:
                    "fixture.unavailable",
                capabilities: [
                    .textGeneration
                ],
                text: "",
                shouldFail: false
            )

        let unavailable =
            UnavailableDiagnosticProvider(
                base: provider
            )

        let report =
            await AIDeviceValidationRunner()
                .run(
                    provider: unavailable,
                    request:
                        AIRequest(
                            messages: [
                                .user("hello")
                            ]
                        )
                )

        XCTAssertEqual(
            report.steps.count,
            1
        )
        XCTAssertEqual(
            report.steps.first?
                .operation,
            .availability
        )
        XCTAssertEqual(
            report.steps.first?
                .status,
            .unavailable
        )
    }
}

private struct UnavailableDiagnosticProvider:
    AIProvider
{
    let base: StubProvider

    var id: AIProviderID {
        base.id
    }

    var displayName: String {
        base.displayName
    }

    var capabilities:
        AICapabilities
    {
        base.capabilities
    }

    func availability()
        async -> AIAvailability
    {
        .unavailable(
            .unsupportedPlatform
        )
    }

    func generate(
        _ request: AIRequest
    ) async throws -> AIResponse {
        try await base.generate(
            request
        )
    }
}


extension AICoreKitTests {
    func testDirectoryModelResourceProviderRequiresModelAsset() async throws {
        let root =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: root,
                withIntermediateDirectories:
                    true
            )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }

        let provider =
            CoreAIDirectoryModelResourceProvider(
                identifier: "fixture",
                directoryURL: root
            )

        let missing =
            try await provider
                .modelResource()
        XCTAssertNil(missing)

        let asset =
            root
            .appendingPathComponent(
                "fixture.aimodel"
            )
        try Data()
            .write(to: asset)

        let resource =
            try await provider
                .modelResource()

        XCTAssertEqual(
            resource?.identifier,
            "fixture"
        )
        XCTAssertEqual(
            resource?.path,
            root.path
        )
    }

    func testDirectoryModelResourceProviderCanSkipExtensionValidation() async throws {
        let root =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: root,
                withIntermediateDirectories:
                    true
            )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }

        let provider =
            CoreAIDirectoryModelResourceProvider(
                identifier: "fixture",
                directoryURL: root,
                requiredFileExtension: nil
            )

        let resource =
            try await provider
                .modelResource()

        XCTAssertEqual(
            resource?.path,
            root.path
        )
    }
}


private actor PersistentDiagnosticFixtureState {
    private var isPrepared: Bool
    private(set) var prepareCount = 0
    private(set) var loadCount = 0
    private(set) var releaseCount = 0

    init(initiallyPrepared: Bool = false) {
        isPrepared = initiallyPrepared
    }

    func prepared() {
        prepareCount += 1
        isPrepared = true
    }

    func loaded() {
        loadCount += 1
    }

    func released() {
        releaseCount += 1
    }

    func preparedState() -> Bool {
        isPrepared
    }

    func counts()
        -> (
            prepare: Int,
            load: Int,
            release: Int
        )
    {
        (
            prepareCount,
            loadCount,
            releaseCount
        )
    }
}

private struct PersistentDiagnosticFixtureProvider:
    AIProvider,
    AIPersistentResourceManaging
{
    let state:
        PersistentDiagnosticFixtureState

    let id:
        AIProviderID =
            "fixture.persistent-diagnostics"
    let displayName =
        "Persistent Diagnostics Fixture"
    let capabilities:
        AICapabilities = [
            .textGeneration,
            .localExecution
        ]

    func availability()
        async -> AIAvailability
    {
        .available
    }

    func isPersistentlyPrepared()
        async -> Bool
    {
        await state.preparedState()
    }

    func preparePersistentResources()
        async throws
    {
        await state.prepared()
    }

    func loadPreparedResources()
        async throws
    {
        await state.loaded()
    }

    func prepareResources()
        async throws
    {
        try await
            preparePersistentResources()
        try await
            loadPreparedResources()
    }

    func releaseResources()
        async throws
    {
        await state.released()
    }

    func generate(
        _ request: AIRequest
    ) async throws -> AIResponse {
        AIResponse(
            text: "ok",
            providerID: id
        )
    }
}

extension AICoreKitTests {
    func testDeviceValidationRunnerSeparatesPersistentPreparationFromRuntimeLoad() async {
        let state =
            PersistentDiagnosticFixtureState()
        let provider =
            PersistentDiagnosticFixtureProvider(
                state: state
            )

        let report =
            await AIDeviceValidationRunner()
                .run(
                    provider: provider,
                    request:
                        AIRequest(
                            messages: [
                                .user("hello")
                            ]
                        )
                )

        XCTAssertEqual(
            report.steps.map(\.operation),
            [
                .availability,
                .preparePersistentResources,
                .loadPreparedResources,
                .generate,
                .releaseResources
            ]
        )

        XCTAssertEqual(
            report.steps.map(\.status),
            [
                .succeeded,
                .succeeded,
                .succeeded,
                .succeeded,
                .succeeded
            ]
        )

        let evidence =
            report.persistentPreparation
        XCTAssertEqual(
            evidence?.preparedBeforeRun,
            false
        )
        XCTAssertEqual(
            evidence?.preparedAfterPrepare,
            true
        )
        XCTAssertEqual(
            evidence?.preparedAfterRelease,
            true
        )
        XCTAssertEqual(
            evidence?.coldPreparationPerformed,
            true
        )

        let counts =
            await state.counts()
        XCTAssertEqual(
            counts.prepare,
            1
        )
        XCTAssertEqual(
            counts.load,
            1
        )
        XCTAssertEqual(
            counts.release,
            1
        )
    }
}


extension AICoreKitTests {
    func testDeviceValidationRunnerMarksWarmPersistentPreparation() async {
        let state =
            PersistentDiagnosticFixtureState(
                initiallyPrepared: true
            )
        let provider =
            PersistentDiagnosticFixtureProvider(
                state: state
            )

        let report =
            await AIDeviceValidationRunner()
                .run(
                    provider: provider,
                    request:
                        AIRequest(
                            messages: [
                                .user("hello")
                            ]
                        )
                )

        let evidence =
            report.persistentPreparation
        XCTAssertEqual(
            evidence?.preparedBeforeRun,
            true
        )
        XCTAssertEqual(
            evidence?.preparedAfterPrepare,
            true
        )
        XCTAssertEqual(
            evidence?.preparedAfterRelease,
            true
        )
        XCTAssertEqual(
            evidence?.coldPreparationPerformed,
            false
        )

        let counts =
            await state.counts()
        XCTAssertEqual(
            counts.prepare,
            1
        )
        XCTAssertEqual(
            counts.load,
            1
        )
        XCTAssertEqual(
            counts.release,
            1
        )
    }
}


extension AICoreKitTests {
    func testDeviceValidationReportCarriesEnvironmentAndCallerMetadata() async {
        let provider =
            StubProvider(
                id: "fixture.environment",
                capabilities: [
                    .textGeneration
                ],
                text: "ok",
                shouldFail: false
            )

        let report =
            await AIDeviceValidationRunner()
                .run(
                    provider: provider,
                    request:
                        AIRequest(
                            messages: [
                                .user("hello")
                            ]
                        ),
                    metadata: [
                        "application.version":
                            "3.2.0",
                        "application.build":
                            "42",
                        "model.identifier":
                            "Qwen3-0.6B"
                    ]
                )

        XCTAssertFalse(
            report.environment
                .architecture
                .isEmpty
        )
        XCTAssertFalse(
            report.environment
                .operatingSystemVersion
                .isEmpty
        )
        XCTAssertEqual(
            report.metadata[
                "application.version"
            ],
            "3.2.0"
        )
        XCTAssertEqual(
            report.metadata[
                "application.build"
            ],
            "42"
        )
        XCTAssertEqual(
            report.metadata[
                "model.identifier"
            ],
            "Qwen3-0.6B"
        )
    }
}
