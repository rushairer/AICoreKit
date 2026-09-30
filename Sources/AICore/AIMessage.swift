import Foundation

public enum AIMessageRole: String, Hashable, Sendable, Codable {
    case system
    case user
    case assistant
    case tool
}

public struct AIMessage: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let role: AIMessageRole
    public let content: String
    public let name: String?

    public init(
        id: UUID = UUID(),
        role: AIMessageRole,
        content: String,
        name: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.name = name
    }

    public static func system(_ content: String) -> Self {
        Self(role: .system, content: content)
    }

    public static func user(_ content: String) -> Self {
        Self(role: .user, content: content)
    }

    public static func assistant(_ content: String) -> Self {
        Self(role: .assistant, content: content)
    }
}
