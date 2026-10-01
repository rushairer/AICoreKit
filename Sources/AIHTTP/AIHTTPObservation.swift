import Foundation

public enum AIHTTPOperation:
    String,
    Hashable,
    Sendable
{
    case data
    case stream
}

public struct AIHTTPRequestObservation:
    Hashable,
    Sendable
{
    public let requestID: UUID
    public let operation: AIHTTPOperation
    public let method: String?
    public let scheme: String?
    public let host: String?
    public let path: String

    public init(
        requestID: UUID = UUID(),
        operation: AIHTTPOperation,
        method: String?,
        scheme: String?,
        host: String?,
        path: String
    ) {
        self.requestID = requestID
        self.operation = operation
        self.method = method
        self.scheme = scheme
        self.host = host
        self.path = path
    }

    public init(
        requestID: UUID = UUID(),
        operation: AIHTTPOperation,
        request: URLRequest
    ) {
        self.init(
            requestID: requestID,
            operation: operation,
            method: request.httpMethod,
            scheme: request.url?.scheme,
            host: request.url?.host,
            path: request.url?.path ?? ""
        )
    }
}

public struct AIHTTPResponseObservation:
    Sendable
{
    public let request: AIHTTPRequestObservation
    public let statusCode: Int
    public let durationSeconds: TimeInterval

    public init(
        request: AIHTTPRequestObservation,
        statusCode: Int,
        durationSeconds: TimeInterval
    ) {
        self.request = request
        self.statusCode = statusCode
        self.durationSeconds = durationSeconds
    }
}

public struct AIHTTPFailureObservation:
    Sendable
{
    public let request: AIHTTPRequestObservation
    public let durationSeconds: TimeInterval
    public let errorDescription: String

    public init(
        request: AIHTTPRequestObservation,
        durationSeconds: TimeInterval,
        errorDescription: String
    ) {
        self.request = request
        self.durationSeconds = durationSeconds
        self.errorDescription = errorDescription
    }
}

public enum AIHTTPObservationEvent:
    Sendable
{
    case started(AIHTTPRequestObservation)
    case response(AIHTTPResponseObservation)
    case failed(AIHTTPFailureObservation)
}

public protocol AIHTTPObserver: Sendable {
    func record(
        _ event: AIHTTPObservationEvent
    ) async
}

public struct ClosureAIHTTPObserver:
    AIHTTPObserver
{
    public typealias Handler =
        @Sendable (
            AIHTTPObservationEvent
        ) async -> Void

    private let handler: Handler

    public init(
        handler: @escaping Handler
    ) {
        self.handler = handler
    }

    public func record(
        _ event: AIHTTPObservationEvent
    ) async {
        await handler(event)
    }
}
