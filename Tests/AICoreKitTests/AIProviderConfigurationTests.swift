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
                .missingHost
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
