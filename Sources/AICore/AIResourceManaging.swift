public protocol AIResourceManaging: Sendable {
    func prepareResources() async throws
    func releaseResources() async throws
}
