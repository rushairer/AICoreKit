import AICore
import AIProviderConfiguration
import Foundation
import XCTest

final class AIProviderConfigurationTests:
    XCTestCase
{
    func testSharedPresetBuildsDeepSeekProfile()
        throws
    {
        let profile =
            try AIProviderPreset
            .deepSeek
            .profile(
                id: "consumer.deepseek",
                model: "deepseek-chat"
            )

        XCTAssertEqual(
            profile.kind,
            .openAICompatible
        )
        XCTAssertEqual(
            profile.providerID,
            AIProviderID(
                rawValue: "deepseek"
            )
        )
        XCTAssertEqual(
            profile.baseURL
                .absoluteString,
            "https://api.deepseek.com/v1"
        )
        XCTAssertEqual(
            profile.credentialKind,
            .bearerToken
        )
    }

    func testCustomPresetRequiresBaseURL()
    {
        XCTAssertThrowsError(
            try AIProviderPreset
                .customOpenAICompatible
                .profile(
                    id: "consumer.custom",
                    model: "model"
                )
        ) {
            error in

            XCTAssertEqual(
                error
                    as? AIProviderProfileValidationError,
                .missingBaseURL
            )
        }
    }

    func testRejectsEmptyProviderIdentifier()
    {
        let profile =
            AIProviderProfile(
                id: "custom",
                kind:
                    .openAICompatible,
                providerID:
                    AIProviderID(
                        rawValue: "   "
                    ),
                displayName:
                    "Custom",
                model:
                    "model",
                baseURL:
                    URL(
                        string:
                            "https://example.com/v1"
                    )!,
                credentialKind:
                    .bearerToken
            )

        XCTAssertThrowsError(
            try AIProviderProfileValidator
                .validate(profile)
        ) {
            error in

            XCTAssertEqual(
                error
                    as? AIProviderProfileValidationError,
                .emptyProviderID
            )
        }
    }

    func testRejectsCredentialKindThatDoesNotMatchDedicatedProvider()
    {
        let profile =
            AIProviderProfile(
                id: "openai",
                kind:
                    .openAI,
                providerID:
                    .openAI,
                displayName:
                    "OpenAI",
                model:
                    "model",
                baseURL:
                    URL(
                        string:
                            "https://api.openai.com/v1"
                    )!,
                credentialKind:
                    .apiKey
            )

        XCTAssertThrowsError(
            try AIProviderProfileValidator
                .validate(profile)
        ) {
            error in

            XCTAssertEqual(
                error
                    as? AIProviderProfileValidationError,
                .incompatibleCredentialKind
            )
        }
    }

    func testBuiltInProfilesValidate()
        throws
    {
        let profiles: [AIProviderProfile] = [
            .openAI(model: "gpt-5"),
            .anthropic(model: "claude-sonnet-5"),
            .gemini(model: "gemini-3.8-flash"),
            .deepSeek(model: "deepseek-chat")
        ]

        for profile in profiles {
            XCTAssertNoThrow(
                try AIProviderProfileValidator
                    .validate(profile)
            )
        }
    }

    func testPresetPreservesExecutionDefaults()
        throws
    {
        let profile =
            try AIProviderPreset
            .openAI
            .profile(
                id: "consumer.openai",
                model: "gpt-5",
                timeout: 12,
                defaultMaxOutputTokens:
                    321,
                defaultTemperature:
                    0.4
            )

        XCTAssertEqual(
            profile.timeout,
            12
        )
        XCTAssertEqual(
            profile.defaultMaxOutputTokens,
            321
        )
        XCTAssertEqual(
            profile.defaultTemperature,
            0.4
        )
    }

    func testLegacyProfileJSONDecodesWithExecutionDefaults()
        throws
    {
        let json =
            """
            {
              "id": "legacy",
              "kind": "openAI",
              "providerID": "openai",
              "displayName": "OpenAI",
              "model": "gpt-5",
              "baseURL": "https://api.openai.com/v1",
              "credentialKind": {
                "bearerToken": {}
              }
            }
            """

        let profile =
            try JSONDecoder().decode(
                AIProviderProfile.self,
                from:
                    Data(
                        json.utf8
                    )
            )

        XCTAssertEqual(
            profile.timeout,
            60
        )
        XCTAssertNil(
            profile.defaultMaxOutputTokens
        )
        XCTAssertNil(
            profile.defaultTemperature
        )
    }

    func testRejectsInvalidExecutionDefaults()
    {
        let invalidTimeout =
            AIProviderProfile(
                id: "custom",
                kind:
                    .openAICompatible,
                providerID:
                    "custom",
                displayName:
                    "Custom",
                model:
                    "model",
                baseURL:
                    URL(
                        string:
                            "https://example.com/v1"
                    )!,
                credentialKind:
                    .bearerToken,
                timeout:
                    0
            )

        XCTAssertThrowsError(
            try AIProviderProfileValidator
                .validate(
                    invalidTimeout
                )
        ) {
            error in

            XCTAssertEqual(
                error
                    as? AIProviderProfileValidationError,
                .invalidTimeout
            )
        }

        let invalidTokens =
            AIProviderProfile(
                id: "custom",
                kind:
                    .openAICompatible,
                providerID:
                    "custom",
                displayName:
                    "Custom",
                model:
                    "model",
                baseURL:
                    URL(
                        string:
                            "https://example.com/v1"
                    )!,
                credentialKind:
                    .bearerToken,
                defaultMaxOutputTokens:
                    0
            )

        XCTAssertThrowsError(
            try AIProviderProfileValidator
                .validate(
                    invalidTokens
                )
        ) {
            error in

            XCTAssertEqual(
                error
                    as? AIProviderProfileValidationError,
                .invalidMaxOutputTokens
            )
        }
    }

    func testProfileRoundTripsThroughCodable()
        throws
    {
        let profile =
            AIProviderProfile
            .openAICompatible(
                id: "custom",
                providerID:
                    AIProviderID(
                        rawValue:
                            "example.custom"
                    ),
                displayName: "Custom",
                baseURL:
                    URL(
                        string:
                            "https://example.com/v1"
                    )!,
                model: "example-model"
            )

        let data =
            try JSONEncoder().encode(
                profile
            )
        let decoded =
            try JSONDecoder().decode(
                AIProviderProfile.self,
                from: data
            )

        XCTAssertEqual(
            decoded,
            profile
        )
    }

    func testFactoryPreservesProfileIdentity()
        throws
    {
        let profile =
            AIProviderProfile
            .deepSeek(
                model: "deepseek-chat"
            )

        let credentials =
            ClosureAICredentialProvider {
                _ in
                "fixture"
            }
        let factory =
            AIConfiguredProviderFactory(
                credentialProvider:
                    credentials
            )
        let provider =
            try factory.makeProvider(
                from: profile
            )

        XCTAssertEqual(
            provider.id,
            profile.providerID
        )
        XCTAssertEqual(
            provider.displayName,
            profile.displayName
        )
    }

    func testRejectsEmptyModel()
    {
        let profile =
            AIProviderProfile(
                id: "custom",
                kind:
                    .openAICompatible,
                providerID:
                    "example.custom",
                displayName:
                    "Custom",
                model: "",
                baseURL:
                    URL(
                        string:
                            "https://example.com/v1"
                    )!,
                credentialKind:
                    .bearerToken
            )

        XCTAssertThrowsError(
            try AIProviderProfileValidator
                .validate(profile)
        ) {
            error in

            XCTAssertEqual(
                error
                    as? AIProviderProfileValidationError,
                .emptyModel
            )
        }
    }
}
