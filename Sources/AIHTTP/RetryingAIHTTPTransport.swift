import Foundation

public struct RetryingAIHTTPTransport:
    AIHTTPTransport
{
    private let base: any AIHTTPTransport
    public let policy: AIHTTPRetryPolicy
    private let sleeper: any AIHTTPSleeping

    public init(
        base: any AIHTTPTransport,
        policy: AIHTTPRetryPolicy =
            AIHTTPRetryPolicy(),
        sleeper: any AIHTTPSleeping =
            TaskAIHTTPSleeper()
    ) {
        self.base = base
        self.policy = policy
        self.sleeper = sleeper
    }

    public func data(
        for request: URLRequest
    ) async throws -> AIHTTPResponse {
        var attempt = 1

        while true {
            try Task.checkCancellation()

            do {
                let response = try await base.data(
                    for: request
                )

                guard
                    policy.shouldRetry(
                        statusCode:
                            response.statusCode,
                        failedAttempt: attempt
                    )
                else {
                    return response
                }

                try await sleeper.sleep(
                    for: policy.delaySeconds(
                        afterFailedAttempt:
                            attempt,
                        responseHeaders:
                            response.headers
                    )
                )

                attempt += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard
                    policy
                        .shouldRetryTransportError(
                            failedAttempt: attempt
                        )
                else {
                    throw error
                }

                try await sleeper.sleep(
                    for: policy.delaySeconds(
                        afterFailedAttempt:
                            attempt
                    )
                )

                attempt += 1
            }
        }
    }
}

public struct RetryingAIHTTPStreamingTransport:
    AIHTTPStreamingTransport
{
    private let base:
        any AIHTTPStreamingTransport
    public let policy: AIHTTPRetryPolicy
    private let sleeper: any AIHTTPSleeping

    public init(
        base: any AIHTTPStreamingTransport,
        policy: AIHTTPRetryPolicy =
            AIHTTPRetryPolicy(),
        sleeper: any AIHTTPSleeping =
            TaskAIHTTPSleeper()
    ) {
        self.base = base
        self.policy = policy
        self.sleeper = sleeper
    }

    public func data(
        for request: URLRequest
    ) async throws -> AIHTTPResponse {
        try await RetryingAIHTTPTransport(
            base: base,
            policy: policy,
            sleeper: sleeper
        ).data(for: request)
    }

    public func lines(
        for request: URLRequest
    ) async throws -> AIHTTPLineStreamResponse {
        var attempt = 1

        while true {
            try Task.checkCancellation()

            do {
                return try await base.lines(
                    for: request
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard
                    policy
                        .shouldRetryTransportError(
                            failedAttempt: attempt
                        )
                else {
                    throw error
                }

                try await sleeper.sleep(
                    for: policy.delaySeconds(
                        afterFailedAttempt:
                            attempt
                    )
                )

                attempt += 1
            }
        }
    }
}
