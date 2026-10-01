import Foundation

struct AnthropicToolContinuationState:
    Codable,
    Sendable
{
    let requestJSON: String
    let responseJSON: String
}
