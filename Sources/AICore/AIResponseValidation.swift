import Foundation

public enum AICompletedTextValidationError:
    Error,
    Sendable,
    Equatable
{
    case empty
    case toolCallRequested
    case outputTruncated
    case blocked
    case cancelled
    case failed
}

public extension AIResponse {
    /// Returns normalized display text only when the provider explicitly
    /// reports a completed generation.
    ///
    /// A non-empty partial response is not considered successful. Product
    /// layers can catch the typed failure, decide whether to retry, and then
    /// apply domain-specific validation such as language or schema checks.
    func validatedCompletedText() throws -> String {
        switch finishReason {
        case .completed:
            break
        case .toolCallRequested:
            throw AICompletedTextValidationError
                .toolCallRequested
        case .maxOutputReached:
            throw AICompletedTextValidationError
                .outputTruncated
        case .blocked:
            throw AICompletedTextValidationError
                .blocked
        case .cancelled:
            throw AICompletedTextValidationError
                .cancelled
        case .failed:
            throw AICompletedTextValidationError
                .failed
        }

        let normalized =
            text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !normalized.isEmpty else {
            throw AICompletedTextValidationError
                .empty
        }

        return normalized
    }
}
