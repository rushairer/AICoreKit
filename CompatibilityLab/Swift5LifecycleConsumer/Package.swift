// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swift5LifecycleConsumer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "Swift5LifecycleConsumer",
            dependencies: [
                .product(
                    name: "AICore",
                    package: "AICoreKit"
                ),
                .product(
                    name: "AIProviderCoreAI",
                    package: "AICoreKit"
                )
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
