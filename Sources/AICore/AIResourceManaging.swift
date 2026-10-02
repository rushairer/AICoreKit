public protocol AIResourceManaging: Sendable {
    func prepareResources() async throws
    func releaseResources() async throws
}


public protocol AIPersistentResourceManaging:
    AIResourceManaging
{
    func isPersistentlyPrepared()
        async -> Bool
    func preparePersistentResources()
        async throws
    func loadPreparedResources()
        async throws
}
