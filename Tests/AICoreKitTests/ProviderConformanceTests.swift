import AICore
import AIHTTP
import AIProviderAnthropic
import AIProviderApple
import AIProviderCoreAI
import AIProviderGemini
import AIProviderOpenAI
import AIProviderOpenAICompatible
import Foundation
import XCTest

private struct ConformanceCredentialProvider:
    AICredentialProviding
{
    func credential(
        for request: AICredentialRequest
    ) async throws -> String? {
        "fixture"
    }
}

private struct ConformanceHTTPTransport:
    AIHTTPTransport
{
    func data(
        for request: URLRequest
    ) async throws -> AIHTTPResponse {
        throw AIHTTPTransportError.invalidResponse
    }
}

private struct ConformanceStreamingHTTPTransport:
    AIHTTPStreamingTransport
{
    func data(
        for request: URLRequest
    ) async throws -> AIHTTPResponse {
        throw AIHTTPTransportError.invalidResponse
    }

    func lines(
        for request: URLRequest
    ) async throws -> AIHTTPLineStreamResponse {
        throw AIHTTPTransportError.invalidResponse
    }
}

final class ProviderConformanceTests: XCTestCase {
    private let credentialProvider =
        ConformanceCredentialProvider()

    func testBuiltInProviderIdentifiersAreStable() {
        XCTAssertEqual(
            AIProviderID.appleFoundationModels.rawValue,
            "apple.foundation-models"
        )
        XCTAssertEqual(
            AIProviderID.coreAI.rawValue,
            "apple.core-ai"
        )
        XCTAssertEqual(
            AIProviderID.openAI.rawValue,
            "openai"
        )
        XCTAssertEqual(
            AIProviderID.anthropic.rawValue,
            "anthropic"
        )
        XCTAssertEqual(
            AIProviderID.gemini.rawValue,
            "google.gemini"
        )
        XCTAssertEqual(
            AIProviderID.openAICompatible.rawValue,
            "openai-compatible"
        )
    }

    func testLocalProviderCapabilityContracts() {
        let apple = AppleFoundationModelsProvider()

        XCTAssertEqual(
            apple.capabilities,
            [
                .textGeneration,
                .localExecution,
                .privacyPreferred
            ]
        )

        let coreAI = CoreAIProvider(
            bridge: UnavailableCoreAIBridge(),
            resourceProvider:
                StaticCoreAIModelResourceProvider(
                    resource: nil
                )
        )

        XCTAssertEqual(
            coreAI.capabilities,
            [
                .textGeneration,
                .localExecution,
                .privacyPreferred
            ]
        )

        XCTAssertFalse(
            apple.capabilities.contains(.requiresNetwork)
        )
        XCTAssertFalse(
            coreAI.capabilities.contains(.remoteExecution)
        )
    }

    func testCloudProviderBaseCapabilityContracts() {
        let transport = ConformanceHTTPTransport()

        let openAICompatible =
            OpenAICompatibleProvider(
                configuration:
                    OpenAICompatibleProviderConfiguration(
                        baseURL: URL(
                            string:
                                "https://example.invalid/v1"
                        )!,
                        model: "fixture"
                    ),
                credentialProvider: credentialProvider,
                transport: transport
            )

        XCTAssertEqual(
            openAICompatible.capabilities,
            [
                .textGeneration,
                .remoteExecution,
                .requiresNetwork
            ]
        )

        let openAI = OpenAIProvider(
            configuration: OpenAIProviderConfiguration(
                model: "fixture"
            ),
            credentialProvider: credentialProvider,
            transport: transport
        )

        let anthropic = AnthropicProvider(
            configuration: AnthropicProviderConfiguration(
                model: "fixture"
            ),
            credentialProvider: credentialProvider,
            transport: transport
        )

        let gemini = GeminiProvider(
            configuration: GeminiProviderConfiguration(
                model: "fixture"
            ),
            credentialProvider: credentialProvider,
            transport: transport
        )

        let dedicatedExpected: AICapabilities = [
            .textGeneration,
            .structuredGeneration,
            .toolCalling,
            .remoteExecution,
            .requiresNetwork
        ]

        XCTAssertEqual(
            openAI.capabilities,
            dedicatedExpected
        )
        XCTAssertEqual(
            anthropic.capabilities,
            dedicatedExpected
        )
        XCTAssertEqual(
            gemini.capabilities,
            dedicatedExpected
        )
    }

    func testStreamingCapabilityRequiresStreamingTransport() {
        let transport =
            ConformanceStreamingHTTPTransport()

        let openAICompatible =
            OpenAICompatibleProvider(
                configuration:
                    OpenAICompatibleProviderConfiguration(
                        baseURL: URL(
                            string:
                                "https://example.invalid/v1"
                        )!,
                        model: "fixture"
                    ),
                credentialProvider: credentialProvider,
                transport: transport
            )

        let openAI = OpenAIProvider(
            configuration: OpenAIProviderConfiguration(
                model: "fixture"
            ),
            credentialProvider: credentialProvider,
            transport: transport
        )

        let anthropic = AnthropicProvider(
            configuration: AnthropicProviderConfiguration(
                model: "fixture"
            ),
            credentialProvider: credentialProvider,
            transport: transport
        )

        let gemini = GeminiProvider(
            configuration: GeminiProviderConfiguration(
                model: "fixture"
            ),
            credentialProvider: credentialProvider,
            transport: transport
        )

        XCTAssertTrue(
            openAICompatible.capabilities.contains(
                .streaming
            )
        )
        XCTAssertTrue(
            openAI.capabilities.contains(.streaming)
        )
        XCTAssertTrue(
            anthropic.capabilities.contains(.streaming)
        )
        XCTAssertTrue(
            gemini.capabilities.contains(.streaming)
        )
    }

    func testUnsupportedFutureModalitiesAreNotAdvertised() {
        let transport = ConformanceHTTPTransport()

        let providers: [any AIProvider] = [
            AppleFoundationModelsProvider(),
            CoreAIProvider(
                bridge: UnavailableCoreAIBridge(),
                resourceProvider:
                    StaticCoreAIModelResourceProvider(
                        resource: nil
                    )
            ),
            OpenAICompatibleProvider(
                configuration:
                    OpenAICompatibleProviderConfiguration(
                        baseURL: URL(
                            string:
                                "https://example.invalid/v1"
                        )!,
                        model: "fixture"
                    ),
                credentialProvider: credentialProvider,
                transport: transport
            ),
            OpenAIProvider(
                configuration:
                    OpenAIProviderConfiguration(
                        model: "fixture"
                    ),
                credentialProvider: credentialProvider,
                transport: transport
            ),
            AnthropicProvider(
                configuration:
                    AnthropicProviderConfiguration(
                        model: "fixture"
                    ),
                credentialProvider: credentialProvider,
                transport: transport
            ),
            GeminiProvider(
                configuration:
                    GeminiProviderConfiguration(
                        model: "fixture"
                    ),
                credentialProvider: credentialProvider,
                transport: transport
            )
        ]

        for provider in providers {
            XCTAssertFalse(
                provider.capabilities.contains(
                    .imageInput
                ),
                "\(provider.displayName) unexpectedly advertises image input"
            )
            XCTAssertFalse(
                provider.capabilities.contains(
                    .audioInput
                ),
                "\(provider.displayName) unexpectedly advertises audio input"
            )
            XCTAssertFalse(
                provider.capabilities.contains(
                    .embeddings
                ),
                "\(provider.displayName) unexpectedly advertises embeddings"
            )
        }
    }
}
