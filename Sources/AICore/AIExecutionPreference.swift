public enum AIExecutionPreference: String, Sendable, Codable, Equatable {
    case automatic
    case localFirst
    case remoteFirst
    case localOnly
    case remoteOnly
}
