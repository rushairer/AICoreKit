import AICore

public enum CoreAIBridgeStatus: Int32, Sendable, Codable, Equatable {
    case success = 0
    case invalidRequest = 1
    case modelLoadFailed = 2
    case generationFailed = 3
    case serializationFailed = 4
    case cancelled = 5
    case unavailable = 6
    case unknown = -1
}

public struct CoreAIBridgeInvocation: Sendable, Equatable {
    public let status: CoreAIBridgeStatus
    public let responseJSON: String?

    public init(
        status: CoreAIBridgeStatus,
        responseJSON: String? = nil
    ) {
        self.status = status
        self.responseJSON = responseJSON
    }
}

public protocol CoreAIBridge: Sendable {
    func availability() async -> AIAvailability

    func generate(
        requestJSON: String,
        modelPath: String
    ) async -> CoreAIBridgeInvocation
}

public protocol CoreAIModelLifecycleBridge: CoreAIBridge {
    func prepare(modelPath: String) async -> CoreAIBridgeStatus
    func unload(modelPath: String) async -> CoreAIBridgeStatus
}

public struct UnavailableCoreAIBridge: CoreAIModelLifecycleBridge {
    public init() {}

    public func availability() async -> AIAvailability {
        .unavailable(.frameworkUnavailable)
    }

    public func generate(
        requestJSON: String,
        modelPath: String
    ) async -> CoreAIBridgeInvocation {
        CoreAIBridgeInvocation(status: .unavailable)
    }

    public func prepare(modelPath: String) async -> CoreAIBridgeStatus {
        .unavailable
    }

    public func unload(modelPath: String) async -> CoreAIBridgeStatus {
        .unavailable
    }
}
