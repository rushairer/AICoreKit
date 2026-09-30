// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AICoreKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AICore", targets: ["AICore"]),
        .library(name: "AIOrchestration", targets: ["AIOrchestration"]),
        .library(name: "AITools", targets: ["AITools"]),
        .library(name: "AIProviderApple", targets: ["AIProviderApple"]),
        .library(name: "AIProviderCoreAI", targets: ["AIProviderCoreAI"]),
        .library(name: "AICoreKit", targets: ["AICoreKit"])
    ],
    targets: [
        .target(name: "AICore"),
        .target(name: "AIOrchestration", dependencies: ["AICore"]),
        .target(name: "AITools", dependencies: ["AICore"]),
        .target(name: "AIProviderApple", dependencies: ["AICore"]),
        .target(name: "AIProviderCoreAI", dependencies: ["AICore"]),
        .target(
            name: "AICoreKit",
            dependencies: [
                "AICore",
                "AIOrchestration",
                "AITools",
                "AIProviderApple",
                "AIProviderCoreAI"
            ]
        ),
        .testTarget(
            name: "AICoreKitTests",
            dependencies: [
                "AICore",
                "AIOrchestration",
                "AITools",
                "AIProviderApple",
                "AIProviderCoreAI"
            ]
        )
    ]
)
