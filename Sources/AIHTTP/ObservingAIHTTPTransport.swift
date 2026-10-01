import Foundation

public struct ObservingAIHTTPTransport:
    AIHTTPTransport
{
    private let base: any AIHTTPTransport
    private let observer: any AIHTTPObserver

    public init(
        base: any AIHTTPTransport,
        observer: any AIHTTPObserver
    ) {
        self.base = base
        self.observer = observer
    }

    public func data(
        for request: URLRequest
    ) async throws -> AIHTTPResponse {
        let observation = AIHTTPRequestObservation(
            operation: .data,
            request: request
        )
        let startedAt = Date()

        await observer.record(
            .started(observation)
        )

        do {
            let response = try await base.data(
                for: request
            )

            await observer.record(
                .response(
                    AIHTTPResponseObservation(
                        request: observation,
                        statusCode: response.statusCode,
                        durationSeconds:
                            Date().timeIntervalSince(
                                startedAt
                            )
                    )
                )
            )

            return response
        } catch {
            await observer.record(
                .failed(
                    AIHTTPFailureObservation(
                        request: observation,
                        durationSeconds:
                            Date().timeIntervalSince(
                                startedAt
                            ),
                        errorDescription:
                            error.localizedDescription
                    )
                )
            )
            throw error
        }
    }
}

public struct ObservingAIHTTPStreamingTransport:
    AIHTTPStreamingTransport
{
    private let base:
        any AIHTTPStreamingTransport
    private let observer: any AIHTTPObserver

    public init(
        base: any AIHTTPStreamingTransport,
        observer: any AIHTTPObserver
    ) {
        self.base = base
        self.observer = observer
    }

    public func data(
        for request: URLRequest
    ) async throws -> AIHTTPResponse {
        try await ObservingAIHTTPTransport(
            base: base,
            observer: observer
        ).data(for: request)
    }

    public func lines(
        for request: URLRequest
    ) async throws -> AIHTTPLineStreamResponse {
        let observation = AIHTTPRequestObservation(
            operation: .stream,
            request: request
        )
        let startedAt = Date()

        await observer.record(
            .started(observation)
        )

        do {
            let response = try await base.lines(
                for: request
            )

            await observer.record(
                .response(
                    AIHTTPResponseObservation(
                        request: observation,
                        statusCode: response.statusCode,
                        durationSeconds:
                            Date().timeIntervalSince(
                                startedAt
                            )
                    )
                )
            )

            return response
        } catch {
            await observer.record(
                .failed(
                    AIHTTPFailureObservation(
                        request: observation,
                        durationSeconds:
                            Date().timeIntervalSince(
                                startedAt
                            ),
                        errorDescription:
                            error.localizedDescription
                    )
                )
            )
            throw error
        }
    }
}
