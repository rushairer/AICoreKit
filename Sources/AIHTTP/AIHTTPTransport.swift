import Foundation

public struct AIHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(
        data: Data,
        statusCode: Int,
        headers: [String: String] = [:]
    ) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

public struct AIHTTPLineStreamResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let lines: AsyncThrowingStream<String, Error>

    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        lines: AsyncThrowingStream<String, Error>
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.lines = lines
    }
}

public enum AIHTTPTransportError: Error, Sendable, Equatable {
    case invalidResponse
}

public protocol AIHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> AIHTTPResponse
}

public protocol AIHTTPStreamingTransport: AIHTTPTransport {
    func lines(
        for request: URLRequest
    ) async throws -> AIHTTPLineStreamResponse
}

public struct URLSessionAIHTTPTransport:
    AIHTTPTransport,
    AIHTTPStreamingTransport
{
    public init() {}

    public func data(for request: URLRequest) async throws -> AIHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIHTTPTransportError.invalidResponse
        }

        return AIHTTPResponse(
            data: data,
            statusCode: httpResponse.statusCode,
            headers: headers(from: httpResponse)
        )
    }

    public func lines(
        for request: URLRequest
    ) async throws -> AIHTTPLineStreamResponse {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIHTTPTransportError.invalidResponse
        }

        let lineStream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        return AIHTTPLineStreamResponse(
            statusCode: httpResponse.statusCode,
            headers: headers(from: httpResponse),
            lines: lineStream
        )
    }

    private func headers(
        from response: HTTPURLResponse
    ) -> [String: String] {
        response.allHeaderFields.reduce(
            into: [String: String]()
        ) { result, pair in
            guard let key = pair.key as? String else {
                return
            }
            result[key] = String(describing: pair.value)
        }
    }
}
