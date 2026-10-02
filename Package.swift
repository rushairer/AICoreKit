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
        .library(name: "AIHTTP", targets: ["AIHTTP"]),
        .library(name: "AIOrchestration", targets: ["AIOrchestration"]),
        .library(name: "AITools", targets: ["AITools"]),
        .library(name: "AIDiagnostics", targets: ["AIDiagnostics"]),
        .library(name: "AIProviderApple", targets: ["AIProviderApple"]),
        .library(name: "AIProviderCoreAI", targets: ["AIProviderCoreAI"]),
        .library(name: "AIProviderCoreAIWeakLink", targets: ["AIProviderCoreAIWeakLink"]),
        .library(name: "AIProviderOpenAICompatible", targets: ["AIProviderOpenAICompatible"]),
        .library(name: "AIProviderAnthropic", targets: ["AIProviderAnthropic"]),
        .library(name: "AIProviderGemini", targets: ["AIProviderGemini"]),
        .library(name: "AIProviderOpenAI", targets: ["AIProviderOpenAI"]),
        .library(name: "AIProviderConfiguration", targets: ["AIProviderConfiguration"]),
        .library(name: "AICoreKit", targets: ["AICoreKit"])
    ],
    targets: [
        .target(name: "AICore"),
        .target(name: "AIHTTP"),
        .target(
            name: "AIOrchestration",
            dependencies: [
                "AICore",
                "AITools"
            ]
        ),
        .target(name: "AITools", dependencies: ["AICore"]),
        .target(name: "AIDiagnostics", dependencies: ["AICore"]),
        .target(name: "AIProviderApple", dependencies: ["AICore"]),
        .target(
            name: "AICoreWeakBridgeShim",
            publicHeadersPath: "include"
        ),
        .target(name: "AIProviderCoreAI", dependencies: ["AICore"]),
        .target(
            name: "AIProviderCoreAIWeakLink",
            dependencies: [
                "AIProviderCoreAI",
                "AICoreWeakBridgeShim"
            ]
        ),
        .target(
            name: "AIProviderOpenAICompatible",
            dependencies: [
                "AICore",
                "AIHTTP"
            ]
        ),
        .target(
            name: "AIProviderAnthropic",
            dependencies: [
                "AICore",
                "AIHTTP"
            ]
        ),
        .target(
            name: "AIProviderGemini",
            dependencies: [
                "AICore",
                "AIHTTP"
            ]
        ),
        .target(
            name: "AIProviderOpenAI",
            dependencies: [
                "AICore",
                "AIHTTP"
            ]
        ),
        .target(
            name: "AIProviderConfiguration",
            dependencies: [
                "AICore",
                "AIHTTP",
                "AIProviderOpenAICompatible",
                "AIProviderAnthropic",
                "AIProviderGemini",
                "AIProviderOpenAI"
            ]
        ),
        .target(
            name: "AICoreKit",
            dependencies: [
                "AICore",
                "AIOrchestration",
                "AITools",
                "AIDiagnostics",
                "AIProviderApple",
                "AIProviderCoreAI"
            ]
        ),
        .testTarget(
            name: "AICoreKitTests",
            dependencies: [
                "AICore",
                "AIHTTP",
                "AIOrchestration",
                "AITools",
                "AIDiagnostics",
                "AIProviderApple",
                "AIProviderCoreAI",
                "AIProviderOpenAICompatible",
                "AIProviderAnthropic",
                "AIProviderGemini",
                "AIProviderOpenAI",
                "AIProviderConfiguration"
            ]
        )
    ]
)
