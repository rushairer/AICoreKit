import Foundation

public struct CoreAIModelResource: Hashable, Sendable, Codable {
    public let identifier: String
    public let path: String

    public init(identifier: String, path: String) {
        self.identifier = identifier
        self.path = path
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

public protocol CoreAIModelResourceProviding: Sendable {
    func modelResource() async throws -> CoreAIModelResource?
}

public struct StaticCoreAIModelResourceProvider: CoreAIModelResourceProviding {
    public let resource: CoreAIModelResource?

    public init(resource: CoreAIModelResource?) {
        self.resource = resource
    }

    public func modelResource() async throws -> CoreAIModelResource? {
        resource
    }
}
