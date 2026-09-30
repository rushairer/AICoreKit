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

public enum AIHTTPTransportError: Error, Sendable, Equatable {
    case invalidResponse
}

public protocol AIHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> AIHTTPResponse
}

public struct URLSessionAIHTTPTransport: AIHTTPTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> AIHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIHTTPTransportError.invalidResponse
        }

        let headers = httpResponse.allHeaderFields.reduce(
            into: [String: String]()
        ) { result, pair in
            guard
                let key = pair.key as? String,
                let value = pair.value as? String
            else {
                return
            }
            result[key] = value
        }

        return AIHTTPResponse(
            data: data,
            statusCode: httpResponse.statusCode,
            headers: headers
        )
    }
}
