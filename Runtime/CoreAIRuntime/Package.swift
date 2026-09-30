// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AICoreKitCoreAIRuntime",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0")
    ],
    products: [
        .library(
            name: "AICoreKitCoreAIRuntime",
            type: .dynamic,
            targets: ["AICoreKitCoreAIRuntime"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/coreai-models",
            revision: "3efa838ebf1a1e816ef4c17eb5022fe22cda2cb9"
        )
    ],
    targets: [
        .target(
            name: "AICoreKitCoreAIRuntime",
            dependencies: [
                .product(
                    name: "CoreAILM",
                    package: "coreai-models"
                )
            ]
        )
    ]
)
