import Foundation

struct OpenAIToolContinuationState:
    Codable,
    Sendable
{
    let requestJSON: String
    let responseJSON: String
}
