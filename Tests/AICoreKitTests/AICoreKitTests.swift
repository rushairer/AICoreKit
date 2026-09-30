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
