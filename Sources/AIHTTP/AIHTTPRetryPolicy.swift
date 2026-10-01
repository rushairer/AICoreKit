import Foundation

public protocol AIHTTPSleeping: Sendable {
    func sleep(
        for seconds: TimeInterval
    ) async throws
}

public struct TaskAIHTTPSleeper:
    AIHTTPSleeping
{
    public init() {}

    public func sleep(
        for seconds: TimeInterval
    ) async throws {
        guard seconds > 0 else {
            return
        }

        try await ContinuousClock().sleep(
            for: .seconds(seconds)
        )
    }
}

public struct AIHTTPRetryPolicy: Sendable {
    public let maximumAttempts: Int
    public let retryableStatusCodes: Set<Int>
    public let retryTransportErrors: Bool
    public let baseDelaySeconds: TimeInterval
    public let maximumDelaySeconds: TimeInterval
    public let respectsRetryAfter: Bool

    public init(
        maximumAttempts: Int = 3,
        retryableStatusCodes: Set<Int> = [
            429,
            502,
            503,
            504
        ],
        retryTransportErrors: Bool = false,
        baseDelaySeconds: TimeInterval = 0.5,
        maximumDelaySeconds: TimeInterval = 8,
        respectsRetryAfter: Bool = true
    ) {
        self.maximumAttempts =
            max(1, maximumAttempts)
        self.retryableStatusCodes =
            retryableStatusCodes
        self.retryTransportErrors =
            retryTransportErrors
        self.baseDelaySeconds =
            max(0, baseDelaySeconds)
        self.maximumDelaySeconds =
            max(0, maximumDelaySeconds)
        self.respectsRetryAfter =
            respectsRetryAfter
    }

    public func shouldRetry(
        statusCode: Int,
        failedAttempt: Int
    ) -> Bool {
        failedAttempt < maximumAttempts
            && retryableStatusCodes.contains(
                statusCode
            )
    }

    public func shouldRetryTransportError(
        failedAttempt: Int
    ) -> Bool {
        retryTransportErrors
            && failedAttempt < maximumAttempts
    }

    public func delaySeconds(
        afterFailedAttempt failedAttempt: Int,
        responseHeaders: [String: String] = [:]
    ) -> TimeInterval {
        if
            respectsRetryAfter,
            let retryAfter =
                retryAfterSeconds(
                    from: responseHeaders
                )
        {
            return min(
                maximumDelaySeconds,
                max(0, retryAfter)
            )
        }

        let exponent = max(
            0,
            failedAttempt - 1
        )
        let multiplier = Foundation.pow(
            2,
            Double(exponent)
        )
        let delay =
            baseDelaySeconds * multiplier

        return min(
            maximumDelaySeconds,
            max(0, delay)
        )
    }

    private func retryAfterSeconds(
        from headers: [String: String]
    ) -> TimeInterval? {
        guard
            let value = headers.first(
                where: {
                    $0.key.caseInsensitiveCompare(
                        "Retry-After"
                    ) == .orderedSame
                }
            )?.value
        else {
            return nil
        }

        return TimeInterval(
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
    }
}
