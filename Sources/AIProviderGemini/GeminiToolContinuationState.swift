import Foundation

struct GeminiToolContinuationState:
    Codable,
    Sendable
{
    let requestJSON: String
    let responseJSON: String
}
